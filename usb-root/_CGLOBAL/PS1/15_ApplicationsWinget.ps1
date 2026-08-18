#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

$InstallersRoot = "C:\_CGLOBAL\installers"

$script:RebootRequired      = $false
$script:OnlineSourceAvailable = $false

if (-not (Test-Path $InstallersRoot)) {
    New-Item -Path $InstallersRoot -ItemType Directory -Force | Out-Null
}

function Get-UsbCGlobalPath {

    $UsbDrives = Get-CimInstance Win32_LogicalDisk |
        Where-Object {
            $_.DriveType -eq 2
        }

    foreach ($Drive in $UsbDrives) {

        $Candidate = Join-Path $Drive.DeviceID "_CGLOBAL"

        if (Test-Path $Candidate) {

            Write-Log "Cle USB detectee : $Candidate" "OK"

            return $Candidate
        }
    }

    Write-Log "Cle USB _CGLOBAL introuvable" "WARN"

    return $null
}

function Invoke-LoggedCommand {

    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    Write-Log ("Commande : {0} {1}" -f $FilePath, ($Arguments -join " "))

    $Output = & $FilePath @Arguments 2>&1
    $ExitCode = $LASTEXITCODE

    foreach ($Line in $Output) {
        if ($null -ne $Line -and $Line.ToString().Trim() -ne "") {
            Write-Log $Line.ToString()
        }
    }

    return [PSCustomObject]@{
        ExitCode    = $ExitCode
        OutputLines = $Output
        OutputText  = ($Output -join "`n")
    }
}

function Test-InternetConnectivity {

    # Test rapide et informatif de connectivite generale.
    # Best effort uniquement : sert a enrichir les logs et a distinguer
    # "pas d'Internet du tout" de "Internet ok mais source Winget injoignable".
	# Le résultat de "winget source update" détermine si les opérations
	# Winget en ligne peuvent être tentées. Chaque commande conserve
	# néanmoins sa propre vérification de code retour.
    #
    # Adapter la liste d'hotes ou ajouter la gestion d'un proxy explicite
    # si l'environnement le necessite.

    param(
        [string[]]$ProbeHosts = @("www.microsoft.com", "download.microsoft.com")
    )

    foreach ($ProbeHost in $ProbeHosts) {

        try {

            $TestResult = Test-NetConnection `
                -ComputerName $ProbeHost `
                -Port 443 `
                -InformationLevel Quiet `
                -WarningAction SilentlyContinue `
                -ErrorAction Stop

            if ($TestResult) {
                return $true
            }
        }
        catch {
            continue
        }
    }

    return $false
}

function Get-NormalizedVersion {

    # Extrait la partie numerique exploitable d'une chaine de version
    # (ex: "23.001.20693-beta" -> "23.001.20693")
    # Retourne $null si aucune partie numerique n'est trouvee

    param(
        [string]$Raw
    )

    if ([string]::IsNullOrWhiteSpace($Raw)) {
        return $null
    }

    if ($Raw -match "^\s*(\d+(\.\d+){0,3})") {
        return $Matches[1]
    }

    return $null
}

function Compare-WingetVersion {

    # Compare deux versions de facon ordinale (pas seulement une egalite de chaine)
    #
    # Retour :
    #    1  -> VersionA > VersionB
    #   -1  -> VersionA < VersionB
    #    0  -> versions egales (ou equivalentes)
    #
    # Si le parsing numerique echoue pour l'une des deux versions,
    # fallback sur une comparaison lexicographique de chaine.

    param(
        [string]$VersionA,
        [string]$VersionB
    )

    if ($VersionA -eq $VersionB) {
        return 0
    }

    if ([string]::IsNullOrWhiteSpace($VersionA) -and [string]::IsNullOrWhiteSpace($VersionB)) {
        return 0
    }

    if ([string]::IsNullOrWhiteSpace($VersionA)) {
        return -1
    }

    if ([string]::IsNullOrWhiteSpace($VersionB)) {
        return 1
    }

    $NormA = Get-NormalizedVersion -Raw $VersionA
    $NormB = Get-NormalizedVersion -Raw $VersionB

    if ($null -ne $NormA -and $null -ne $NormB) {

        try {

            $PartsA = $NormA.Split('.')
            while ($PartsA.Count -lt 4) { $PartsA += "0" }

            $PartsB = $NormB.Split('.')
            while ($PartsB.Count -lt 4) { $PartsB += "0" }

            $ParsedA = [version]($PartsA -join '.')
            $ParsedB = [version]($PartsB -join '.')

            return $ParsedA.CompareTo($ParsedB)
        }
        catch {
            # Parsing numerique impossible malgre la normalisation -> fallback texte
        }
    }

    # Fallback : comparaison lexicographique simple (best effort)
    $LexResult = [string]::Compare(
        $VersionA,
        $VersionB,
        [System.StringComparison]::OrdinalIgnoreCase
    )

    if ($LexResult -gt 0) { return 1 }
    if ($LexResult -lt 0) { return -1 }
    return 0
}

function Test-InstallerHash {

    # Verifie que le hash SHA256 du fichier local correspond au hash
    # attendu (issu du manifest winget telecharge).
    #
    # Retourne $true si le hash correspond ou si aucun hash attendu
    # n'est disponible (auquel cas la verification est ignoree avec un WARN).
    # Retourne $false si le fichier est absent ou si le hash ne correspond pas.

    param(
        [string]$FilePath,
        [string]$ExpectedSha256
    )

    if ([string]::IsNullOrWhiteSpace($ExpectedSha256)) {
        Write-Log "Aucun hash SHA256 attendu dans le manifest local : verification ignoree" "WARN"
        return $true
    }

    if (-not (Test-Path $FilePath)) {
        Write-Log "Impossible de verifier le hash : fichier introuvable ($FilePath)" "ERROR"
        return $false
    }

    Write-Log "Verification du hash SHA256 de l'installeur local"

    $ActualHash = (Get-FileHash -Path $FilePath -Algorithm SHA256 -ErrorAction Stop).Hash

    if ($ActualHash -ieq $ExpectedSha256) {
        Write-Log "Hash SHA256 verifie avec succes" "OK"
        return $true
    }

    Write-Log ("Hash SHA256 invalide pour {0} : attendu {1}, obtenu {2}" -f (Split-Path $FilePath -Leaf), $ExpectedSha256, $ActualHash) "ERROR"

    return $false
}

function Get-WingetLatestVersion {

    param(
        [string]$PackageId
    )

    $Result = Invoke-LoggedCommand `
        -FilePath "winget.exe" `
        -Arguments @(
            "show",
            "--id", $PackageId,
            "-e",
            "--source", "winget",
            "--accept-source-agreements",
            "--disable-interactivity"
        )

    if ($Result.ExitCode -ne 0) {
        Write-Log "Impossible de recuperer la version en ligne pour $PackageId" "WARN"
        return $null
    }

    foreach ($Line in $Result.OutputLines) {
        if ($Line -match "^\s*Version\s*:\s*(.+?)\s*$") {
            return $Matches[1].Trim()
        }
    }

    Write-Log "Version en ligne non detectee pour $PackageId" "WARN"
    return $null
}

function Get-WingetInstalledInfo {

    param(
        [string]$PackageId
    )

    $Result = Invoke-LoggedCommand `
        -FilePath "winget.exe" `
        -Arguments @(
            "list",
            "--id", $PackageId,
            "-e",
            "--source", "winget",
            "--accept-source-agreements",
            "--disable-interactivity"
        )

    $Info = [PSCustomObject]@{
        Installed = $false
        Version   = ""
    }

    $EscapedId = [System.Text.RegularExpressions.Regex]::Escape($PackageId)

    foreach ($Line in $Result.OutputLines) {

        $Text = $Line.ToString().Trim()

        if ($Text -eq "") {
            continue
        }

        if ($Text -match "^-+$") {
            continue
        }

        if ($Text -match ("^(?<Name>.+?)\s+$EscapedId\s+(?<Version>\S+)(\s|$)")) {

            return [PSCustomObject]@{
                Installed = $true
                Version   = $Matches["Version"].Trim()
            }
        }
    }

    return $Info
}

function Get-LocalWingetCache {

    param(
        [string]$PackageId,
        [string]$PreferredVersion = ""
    )

    $PackageFolder = Join-Path $InstallersRoot $PackageId

    if (-not (Test-Path $PackageFolder)) {
        return $null
    }

    $EscapedId = [System.Text.RegularExpressions.Regex]::Escape($PackageId)

    $YamlFiles = Get-ChildItem `
        -Path $PackageFolder `
        -File `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Extension -eq ".yaml" -or $_.Extension -eq ".yml"
        }

    $FoundItems = @()

    foreach ($Yaml in $YamlFiles) {

        $Content = Get-Content `
            -Path $Yaml.FullName `
            -Raw `
            -ErrorAction SilentlyContinue

        if ($null -eq $Content) {
            continue
        }

        if ($Content -notmatch "(?m)^\s*PackageIdentifier\s*:\s*$EscapedId\s*$") {
            continue
        }

        $DetectedVersion = ""

        if ($Content -match "(?m)^\s*PackageVersion\s*:\s*(.+?)\s*$") {
            $DetectedVersion = $Matches[1].Trim()
        }

        $DetectedSha256 = ""

        if ($Content -match "(?m)^\s*InstallerSha256\s*:\s*(.+?)\s*$") {
            $DetectedSha256 = $Matches[1].Trim()
        }

        $FoundItems += [PSCustomObject]@{
            Version      = $DetectedVersion
            Sha256       = $DetectedSha256
            ManifestPath = $Yaml.FullName
            RootPath     = Split-Path -Path $Yaml.FullName -Parent
            LastWrite    = $Yaml.LastWriteTime
        }
    }

    if ($FoundItems.Count -eq 0) {
        return $null
    }

    if ($PreferredVersion -ne "") {

        $Preferred = $FoundItems |
            Where-Object { $_.Version -eq $PreferredVersion } |
            Sort-Object LastWrite -Descending |
            Select-Object -First 1

        if ($null -ne $Preferred) {
            return $Preferred
        }
    }

    #
    # Aucun match exact avec la version preferee : on prend la version
    # la plus elevee disponible localement (comparaison ordinale),
    # et non plus simplement la plus recente par date de fichier.
    #
    $BestItem = $null

    foreach ($Item in $FoundItems) {

        if ($null -eq $BestItem) {
            $BestItem = $Item
            continue
        }

        $Comparison = Compare-WingetVersion `
            -VersionA $Item.Version `
            -VersionB $BestItem.Version

        if ($Comparison -gt 0) {
            $BestItem = $Item
        }
        elseif ($Comparison -eq 0 -and $Item.LastWrite -gt $BestItem.LastWrite) {
            $BestItem = $Item
        }
    }

    return $BestItem
}

function Get-LocalInstallerFile {

    # Recupere le fichier installeur associe a un manifest local.
    #
    # Hypothese : winget download nomme l'installeur avec le meme nom de
    # base que le manifest .yaml genere. C'est le comportement observe de
    # winget, mais si un jour ce n'est plus le cas, le fallback ci-dessous
    # (recherche par extension dans le dossier) prend le relais.

    param(
        [object]$Cache
    )

    if ($null -eq $Cache) {
        return $null
    }

    if (-not (Test-Path $Cache.ManifestPath)) {
        return $null
    }

    $ManifestBaseName = [System.IO.Path]::GetFileNameWithoutExtension($Cache.ManifestPath)
    $ManifestFolder   = Split-Path -Path $Cache.ManifestPath -Parent

    $PossibleExtensions = @(
        ".exe",
        ".msi",
        ".msix",
        ".appx",
        ".msixbundle",
        ".appxbundle"
    )

    foreach ($Extension in $PossibleExtensions) {

        $Candidate = Join-Path $ManifestFolder ($ManifestBaseName + $Extension)

        if (Test-Path $Candidate) {
            return $Candidate
        }
    }

    $InstallerFiles = Get-ChildItem `
        -Path $ManifestFolder `
        -File `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Extension -in $PossibleExtensions
        } |
        Sort-Object LastWriteTime -Descending

    if ($InstallerFiles.Count -gt 0) {
        return $InstallerFiles[0].FullName
    }

    return $null
}

function Invoke-WingetPackageDownload {

    param(
        [string]$PackageId,
        [string]$TargetVersion = ""
    )

    $PackageFolder = Join-Path $InstallersRoot $PackageId

    if (-not (Test-Path $PackageFolder)) {

        New-Item `
            -Path $PackageFolder `
            -ItemType Directory `
            -Force | Out-Null
    }

    Write-Log "Telechargement du package $PackageId"
    Write-Log "Dossier cible : $PackageFolder"

    $DownloadArgs = @(
        "download",
        "--id", $PackageId,
        "-e",
        "--source", "winget",
        "--download-directory", $PackageFolder,
        "--architecture", "x64",
        "--skip-license",
        "--accept-package-agreements",
        "--accept-source-agreements",
        "--disable-interactivity"
    )

    #
    # Fige la version demandee pour eviter une race condition entre
    # la version detectee par "winget show" et celle effectivement
    # telechargee si une nouvelle version sort entre-temps.
    #
    if ($TargetVersion -ne "") {
        $DownloadArgs += @("--version", $TargetVersion)
    }

    $Result = Invoke-LoggedCommand `
        -FilePath "winget.exe" `
        -Arguments $DownloadArgs

    if ($Result.ExitCode -ne 0) {
        throw "Echec du telechargement de $PackageId"
    }

    Write-Log "Telechargement OK : $PackageId" "OK"

    #
    # Conservation uniquement de la version telechargee.
    # Selection basee sur la version (PackageVersion dans le yaml),
    # et non plus uniquement sur la date de derniere ecriture des fichiers,
    # afin d'eviter de conserver par erreur un ancien manifest si les
    # dates ne refletent pas fidelement l'ordre chronologique reel
    # (copie via cle USB, horodatage preserve par robocopy, etc).
    #
    $YamlFiles = Get-ChildItem `
        -Path $PackageFolder `
        -Filter *.yaml `
        -File `
        -ErrorAction SilentlyContinue

    if ($YamlFiles.Count -gt 1) {

        Write-Log "Nettoyage des anciennes versions"

        $KeepYaml = $null

        #
        # 1) Priorite : le manifest correspondant exactement a la version
        #    qui vient d'etre telechargee.
        #
        if ($TargetVersion -ne "") {

            foreach ($Yaml in $YamlFiles) {

                $Content = Get-Content `
                    -Path $Yaml.FullName `
                    -Raw `
                    -ErrorAction SilentlyContinue

                if ($null -eq $Content) {
                    continue
                }

                if ($Content -match "(?m)^\s*PackageVersion\s*:\s*(.+?)\s*$") {

                    $ThisVersion = $Matches[1].Trim()

                    if ($ThisVersion -eq $TargetVersion) {
                        $KeepYaml = $Yaml
                        break
                    }
                }
            }
        }

        #
        # 2) A defaut : la version la plus elevee detectee parmi les
        #    manifests presents (comparaison ordinale, pas la date fichier).
        #
        if ($null -eq $KeepYaml) {

            $BestVersion = $null
            $BestYaml    = $null

            foreach ($Yaml in $YamlFiles) {

                $Content = Get-Content `
                    -Path $Yaml.FullName `
                    -Raw `
                    -ErrorAction SilentlyContinue

                if ($null -eq $Content) {
                    continue
                }

                $ThisVersion = ""

                if ($Content -match "(?m)^\s*PackageVersion\s*:\s*(.+?)\s*$") {
                    $ThisVersion = $Matches[1].Trim()
                }

                if ($null -eq $BestYaml) {
                    $BestYaml    = $Yaml
                    $BestVersion = $ThisVersion
                    continue
                }

                $Comparison = Compare-WingetVersion `
                    -VersionA $ThisVersion `
                    -VersionB $BestVersion

                if ($Comparison -gt 0) {
                    $BestYaml    = $Yaml
                    $BestVersion = $ThisVersion
                }
            }

            $KeepYaml = $BestYaml
        }

        #
        # 3) Dernier recours : le plus recent par date de fichier
        #    (comportement d'origine, utilise seulement si aucune
        #    version n'a pu etre extraite d'aucun manifest).
        #
        if ($null -eq $KeepYaml) {

            $KeepYaml = $YamlFiles |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
        }

        $KeepBaseName = [System.IO.Path]::GetFileNameWithoutExtension($KeepYaml.Name)

        Get-ChildItem `
            -Path $PackageFolder `
            -File `
            -ErrorAction SilentlyContinue |
            Where-Object {

                $_.BaseName -ne $KeepBaseName

            } |
            ForEach-Object {

                Write-Log "Suppression : $($_.Name)"

                Remove-Item `
                    -Path $_.FullName `
                    -Force `
                    -ErrorAction SilentlyContinue
            }

        Write-Log "Nettoyage termine" "OK"
    }
}

function Install-Or-UpgradeFromCache {

    param(
        [hashtable]$App,
        [object]$Cache
    )

    $PackageId = $App.Id

    $InstalledInfo = Get-WingetInstalledInfo -PackageId $PackageId

    if ($InstalledInfo.Installed) {

        Write-Log ("Version installee : {0}" -f $InstalledInfo.Version)

        if ($Cache.Version -ne "") {

            $InstallComparison = Compare-WingetVersion `
                -VersionA $Cache.Version `
                -VersionB $InstalledInfo.Version

            if ($InstallComparison -le 0) {

                Write-Log "$PackageId deja installe dans une version egale ou superieure au cache local : aucune action" "OK"
                return
            }

            Write-Log ("$PackageId version cache ({0}) plus recente que la version installee ({1}) : mise a niveau depuis le cache local" -f $Cache.Version, $InstalledInfo.Version) "WARN"
        }
        else {
            Write-Log "$PackageId deja installe mais version du cache inconnue : mise a niveau depuis le cache local par prudence" "WARN"
        }
    }
    else {
        Write-Log "$PackageId non installe : installation depuis le cache local"
    }

    $InstallerPath = Get-LocalInstallerFile -Cache $Cache

    if ($null -eq $InstallerPath -or -not (Test-Path $InstallerPath)) {
        throw "Installeur local introuvable pour $PackageId"
    }

    Write-Log "Installeur local : $InstallerPath"

    #
    # Verification d'integrite avant toute execution de l'installeur local.
    # Le fichier transite potentiellement par une cle USB reutilisee sur
    # plusieurs postes : on ne l'execute jamais sans confirmer son hash.
    #
    $HashValid = Test-InstallerHash `
        -FilePath $InstallerPath `
        -ExpectedSha256 $Cache.Sha256

    $LocalInstallSucceeded = $false

    if ($HashValid) {

        $Extension = [System.IO.Path]::GetExtension($InstallerPath).ToLowerInvariant()

        if ($Extension -eq ".msi") {

            $MsiArgs = @(
                "/i",
                "`"$InstallerPath`"",
                "/qn",
                "/norestart"
            )

            if ($App.ContainsKey("MsiArgs") -and $App.MsiArgs -ne "") {

                Write-Log "Installation MSI silencieuse (arguments specifiques a l'appli)"
                Write-Log ("Arguments additionnels : {0}" -f $App.MsiArgs)

                $MsiArgs += $App.MsiArgs.Split(" ") | Where-Object { $_ -ne "" }
            }
            else {
                Write-Log "Installation MSI silencieuse (aucun argument specifique defini, /qn /norestart uniquement)" "WARN"
            }

            $Process = Start-Process `
                -FilePath "msiexec.exe" `
                -ArgumentList $MsiArgs `
                -Wait `
                -PassThru
        }
        elseif ($Extension -eq ".exe") {

            if (-not $App.ContainsKey("ExeArgs") -or $App.ExeArgs -eq "") {
                throw "Aucun argument d'installation silencieuse EXE defini pour $PackageId"
            }

            Write-Log "Installation EXE silencieuse"
            Write-Log ("Arguments : {0}" -f $App.ExeArgs)

            $Process = Start-Process `
                -FilePath $InstallerPath `
                -ArgumentList $App.ExeArgs `
                -Wait `
                -PassThru
        }
        else {
            throw "Type d'installeur non gere : $Extension"
        }

        $ExitCode = $Process.ExitCode

        Write-Log "Code retour installateur : $ExitCode"

        if ($ExitCode -eq 0 -or $ExitCode -eq 3010) {

            if ($ExitCode -eq 3010) {
                $script:RebootRequired = $true
                Write-Log "$PackageId installe depuis le cache local, redemarrage requis" "WARN"
            }

            $LocalInstallSucceeded = $true
        }
        else {
            Write-Log "Echec installation locale (code $ExitCode) pour $PackageId, tentative en ligne" "WARN"
        }
    }
    else {

        Write-Log "$PackageId : fichier local rejete suite a l'echec de verification du hash, tentative en ligne" "ERROR"

        #
        # Le fichier est corrompu ou suspect : on le supprime avec son
        # manifest pour forcer un retelechargement propre au prochain
        # passage plutot que de le laisser trainer dans le cache.
        #
        Remove-Item -Path $InstallerPath -Force -ErrorAction SilentlyContinue

        if (Test-Path $Cache.ManifestPath) {
            Remove-Item -Path $Cache.ManifestPath -Force -ErrorAction SilentlyContinue
        }
    }

    if ($LocalInstallSucceeded) {
        Write-Log "$PackageId installe depuis le cache local" "OK"
        return
    }

    if (-not $script:OnlineSourceAvailable) {
        throw "Echec de l'installation locale de $PackageId et aucun acces aux sources en ligne pour tenter un fallback"
    }

    if ($InstalledInfo.Installed) {
        $FallbackAction = "upgrade"
    }
    else {
        $FallbackAction = "install"
    }

    $Fallback = Invoke-LoggedCommand `
        -FilePath "winget.exe" `
        -Arguments @(
            $FallbackAction,
            "--id", $PackageId,
            "-e",
            "--source", "winget",
            "--silent",
            "--accept-package-agreements",
            "--accept-source-agreements",
            "--disable-interactivity"
        )

    if ($Fallback.ExitCode -ne 0) {
        throw "Echec installation ou mise a niveau de $PackageId"
    }

    Write-Log "$PackageId traite en ligne" "OK"
}

try {

    $UsbCGlobalPath = Get-UsbCGlobalPath
	
	Write-Log "Installation des applications via Winget"

    if (-not (Get-Command "winget.exe" -ErrorAction SilentlyContinue)) {
        throw "winget.exe introuvable"
    }

    Write-Log "Winget detecte" "OK"

    #
    # Test de connectivite generique (informatif uniquement, non bloquant).
    #
    $InternetOk = Test-InternetConnectivity

    if ($InternetOk) {
        Write-Log "Connectivite Internet detectee" "OK"
    }
    else {
        Write-Log "Aucune connectivite Internet detectee : les sources Winget seront probablement injoignables" "WARN"
    }

    #
    # Test reel de l'acces aux sources Winget. Cette etape ne doit JAMAIS
    # interrompre le script (pas de throw) : en cas d'echec, on bascule en
    # mode "cache local uniquement" pour toute l'execution.
    #
    $SourceUpdate = Invoke-LoggedCommand `
        -FilePath "winget.exe" `
        -Arguments @(
            "source",
            "update",
            "--disable-interactivity"
        )

    if ($SourceUpdate.ExitCode -ne 0) {
        Write-Log "Acces aux sources Winget indisponible (pas d'Internet ou site de telechargement injoignable) : bascule en mode cache local uniquement pour cette execution" "WARN"
        $script:OnlineSourceAvailable = $false
    }
    else {
        Write-Log "Sources Winget mises a jour" "OK"
        $script:OnlineSourceAvailable = $true
    }

    #
    # ExeArgs  : arguments utilises si le fichier telecharge est un .exe
    # MsiArgs  : arguments ADDITIONNELS (proprietes/switches) ajoutes a
    #            "/i <fichier> /qn /norestart" si le fichier telecharge
    #            est un .msi. Laisser vide si /qn /norestart suffit.
    #
    # Important : le type reel d'installeur telecharge par winget peut
    # changer d'une version a l'autre pour un meme paquet (ex: Firefox
    # est passe de .msi a .exe selon les versions, Chrome telecharge
    # actuellement un .msi). Les deux jeux d'arguments sont donc definis
    # pour chaque appli afin qu'aucun ne soit silencieusement ignore.
    #
    $Apps = @(
        @{
            Name       = "7-Zip"
            Id         = "7zip.7zip"
            ExeArgs    = "/S"
            MsiArgs    = ""
        },
        @{
            Name       = "Adobe Acrobat Reader"
            Id         = "Adobe.Acrobat.Reader.64-bit"
            ExeArgs    = "/sAll /rs /rps /msi EULA_ACCEPT=YES"
            MsiArgs    = "EULA_ACCEPT=YES"
        },
        @{
            Name       = "Google Chrome"
            Id         = "Google.Chrome"
            ExeArgs    = "/silent /install"
            MsiArgs    = ""
        },
        @{
            Name       = "Mozilla Firefox"
            Id         = "Mozilla.Firefox.fr"
            ExeArgs    = "/S /PreventRebootRequired=true"
            MsiArgs    = ""
        }
    )

    $DownloadedUpdates = $false

    foreach ($App in $Apps) {

        Write-Log "----------------------------------------"
        Write-Log ("Traitement : {0} ({1})" -f $App.Name, $App.Id)

        if ($script:OnlineSourceAvailable) {
            $OnlineVersion = Get-WingetLatestVersion -PackageId $App.Id
        }
        else {
            Write-Log "Sources en ligne indisponibles : utilisation directe du cache local pour $($App.Name)" "WARN"
            $OnlineVersion = $null
        }

        $LocalCache = Get-LocalWingetCache `
            -PackageId $App.Id `
            -PreferredVersion $OnlineVersion

        if ($null -eq $LocalCache) {

            Write-Log "Aucun cache local trouve pour $($App.Name)" "WARN"

            if ($null -eq $OnlineVersion -or $OnlineVersion -eq "") {
                throw "Impossible de continuer sans cache ni version en ligne pour $($App.Name)"
            }

            Invoke-WingetPackageDownload -PackageId $App.Id -TargetVersion $OnlineVersion
            $DownloadedUpdates = $true

            $LocalCache = Get-LocalWingetCache `
                -PackageId $App.Id `
                -PreferredVersion $OnlineVersion
        }
        else {

            Write-Log ("Version locale : {0}" -f $LocalCache.Version)

            if ($null -ne $OnlineVersion -and $OnlineVersion -ne "") {

                Write-Log ("Version en ligne : {0}" -f $OnlineVersion)

                $VersionComparison = Compare-WingetVersion `
                    -VersionA $OnlineVersion `
                    -VersionB $LocalCache.Version

                if ($VersionComparison -gt 0) {

                    Write-Log ("Version en ligne plus recente pour $($App.Name) ({0} > {1})" -f $OnlineVersion, $LocalCache.Version) "WARN"

                    Invoke-WingetPackageDownload -PackageId $App.Id -TargetVersion $OnlineVersion
                    $DownloadedUpdates = $true

                    $LocalCache = Get-LocalWingetCache `
                        -PackageId $App.Id `
                        -PreferredVersion $OnlineVersion
                }
                elseif ($VersionComparison -lt 0) {

                    Write-Log ("Version locale ({0}) plus recente ou non comparable a la version en ligne ({1}) : cache conserve" -f $LocalCache.Version, $OnlineVersion) "WARN"
                }
                else {
                    Write-Log "Cache local a jour" "OK"
                }
            }
            else {
                Write-Log "Comparaison en ligne impossible, utilisation du cache local" "WARN"
            }
        }

        if ($null -eq $LocalCache) {
            throw "Cache local introuvable pour $($App.Name)"
        }

        if (-not (Test-Path $LocalCache.ManifestPath)) {
            throw "Manifest local introuvable pour $($App.Name)"
        }

        Write-Log ("Manifest detecte : {0}" -f $LocalCache.ManifestPath)
        Write-Log ("Dossier cache     : {0}" -f $LocalCache.RootPath)

        Install-Or-UpgradeFromCache `
            -App $App `
            -Cache $LocalCache
    }

    Write-Log "----------------------------------------"

    if ($DownloadedUpdates) {

        Write-Log "Des mises a jour ont ete telechargees localement"

        if ($UsbCGlobalPath -ne "" -and (Test-Path $UsbCGlobalPath)) {

            $UsbInstallersPath = Join-Path $UsbCGlobalPath "installers"

            if (-not (Test-Path $UsbInstallersPath)) {
                New-Item -Path $UsbInstallersPath -ItemType Directory -Force | Out-Null
            }

            Write-Log "Synchronisation retour vers la cle USB"

            $RoboCopyResult = Invoke-LoggedCommand `
                -FilePath "robocopy.exe" `
                -Arguments @(
                    $InstallersRoot,
                    $UsbInstallersPath,
                    "/MIR",
                    "/R:1",
                    "/W:1",
                    "/NFL",
                    "/NDL",
                    "/NJH",
                    "/NJS"
                )

            if ($RoboCopyResult.ExitCode -ge 8) {
                throw "Erreur Robocopy retour vers cle USB"
            }

            Write-Log "Synchronisation retour terminee" "OK"
        }
        else {
            Write-Log "Chemin USB non fourni ou introuvable : pas de synchronisation retour" "WARN"
        }
    }
    else {
        Write-Log "Aucune mise a jour telechargee : pas de synchronisation retour"
    }

    if ($script:RebootRequired) {
        Write-Log "Un redemarrage est recommande par au moins un installateur" "WARN"
    }

    Write-Log "Installation des applications terminee" "OK"
}
catch {

    Write-Log $_.Exception.Message "ERROR"
    exit 1
}