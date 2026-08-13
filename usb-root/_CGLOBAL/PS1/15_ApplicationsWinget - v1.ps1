#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$LogFolder      = "C:\_CGLOBAL\Logs"
$LogFile        = "$LogFolder\Log15_ApplicationsWinget.txt"
$InstallersRoot = "C:\_CGLOBAL\installers"

$script:RebootRequired = $false

if (-not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}

if (-not (Test-Path $InstallersRoot)) {
    New-Item -Path $InstallersRoot -ItemType Directory -Force | Out-Null
}

function Write-Log {

    param(
        [string]$Message,

        [ValidateSet('INFO','OK','WARN','ERROR')]
        [string]$Level = 'INFO'
    )

    $Line = "[{0}] [{1,-5}] {2}" -f `
        (Get-Date -Format "HH:mm:ss"), `
        $Level, `
        $Message

    Add-Content -Path $LogFile -Value $Line -Encoding UTF8

    $Color = @{
        INFO  = 'Cyan'
        OK    = 'Green'
        WARN  = 'Yellow'
        ERROR = 'Red'
    }

    Write-Host $Line -ForegroundColor $Color[$Level]
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

        $FoundItems += [PSCustomObject]@{
            Version      = $DetectedVersion
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

    return ($FoundItems | Sort-Object LastWrite -Descending | Select-Object -First 1)
}

function Get-LocalInstallerFile {

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

function Download-WingetPackage {

    param(
        [string]$PackageId
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

    $Result = Invoke-LoggedCommand `
        -FilePath "winget.exe" `
        -Arguments @(
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

    if ($Result.ExitCode -ne 0) {
        throw "Echec du telechargement de $PackageId"
    }

    Write-Log "Telechargement OK : $PackageId" "OK"

    #
    # Conservation uniquement de la version téléchargée
    #
    $YamlFiles = Get-ChildItem `
        -Path $PackageFolder `
        -Filter *.yaml `
        -File `
        -ErrorAction SilentlyContinue

    if ($YamlFiles.Count -gt 1) {

        $NewestYaml = $YamlFiles |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        $NewestBaseName = [System.IO.Path]::GetFileNameWithoutExtension(
            $NewestYaml.Name
        )

        Write-Log "Nettoyage des anciennes versions"

        Get-ChildItem `
            -Path $PackageFolder `
            -File `
            -ErrorAction SilentlyContinue |
            Where-Object {

                $_.BaseName -ne $NewestBaseName

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

        if ($Cache.Version -ne "" -and $InstalledInfo.Version -eq $Cache.Version) {

            Write-Log "$PackageId deja installe dans la bonne version : aucune action" "OK"
            return
        }

        Write-Log "$PackageId deja installe mais version differente : mise a niveau depuis le cache local" "WARN"
    }
    else {
        Write-Log "$PackageId non installe : installation depuis le cache local"
    }

    $InstallerPath = Get-LocalInstallerFile -Cache $Cache

    if ($null -eq $InstallerPath -or -not (Test-Path $InstallerPath)) {
        throw "Installeur local introuvable pour $PackageId"
    }

    Write-Log "Installeur local : $InstallerPath"

    $Extension = [System.IO.Path]::GetExtension($InstallerPath).ToLowerInvariant()

    if ($Extension -eq ".msi") {

        Write-Log "Installation MSI silencieuse"

        $MsiArgs = @(
            "/i",
            "`"$InstallerPath`"",
            "/qn",
            "/norestart"
        )

        $Process = Start-Process `
            -FilePath "msiexec.exe" `
            -ArgumentList $MsiArgs `
            -Wait `
            -PassThru
    }
    elseif ($Extension -eq ".exe") {

        Write-Log "Installation EXE silencieuse"
        Write-Log ("Arguments : {0}" -f $App.SilentArgs)

        $Process = Start-Process `
            -FilePath $InstallerPath `
            -ArgumentList $App.SilentArgs `
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
        else {
            Write-Log "$PackageId installe depuis le cache local" "OK"
        }

        return
    }

    Write-Log "Echec installation locale pour $PackageId, tentative en ligne" "WARN"

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

    $SourceUpdate = Invoke-LoggedCommand `
        -FilePath "winget.exe" `
        -Arguments @(
            "source",
            "update",
            "--disable-interactivity"
        )

    if ($SourceUpdate.ExitCode -ne 0) {
        Write-Log "Mise a jour des sources Winget non terminee correctement" "WARN"
    }
    else {
        Write-Log "Sources Winget mises a jour" "OK"
    }

    $Apps = @(
        @{
            Name       = "7-Zip"
            Id         = "7zip.7zip"
            SilentArgs = "/S"
        },
        @{
            Name       = "Adobe Acrobat Reader"
            Id         = "Adobe.Acrobat.Reader.64-bit"
            SilentArgs = "/sAll /rs /rps /msi EULA_ACCEPT=YES"
        },
        @{
            Name       = "Google Chrome"
            Id         = "Google.Chrome"
            SilentArgs = "/silent /install"
        },
        @{
            Name       = "Mozilla Firefox"
            Id         = "Mozilla.Firefox.fr"
            SilentArgs = "-ms"
        }
    )

    $DownloadedUpdates = $false

    foreach ($App in $Apps) {

        Write-Log "----------------------------------------"
        Write-Log ("Traitement : {0} ({1})" -f $App.Name, $App.Id)

        $OnlineVersion = Get-WingetLatestVersion -PackageId $App.Id

        $LocalCache = Get-LocalWingetCache `
            -PackageId $App.Id `
            -PreferredVersion $OnlineVersion

        if ($null -eq $LocalCache) {

            Write-Log "Aucun cache local trouve pour $($App.Name)" "WARN"

            if ($null -eq $OnlineVersion -or $OnlineVersion -eq "") {
                throw "Impossible de continuer sans cache ni version en ligne pour $($App.Name)"
            }

            Download-WingetPackage -PackageId $App.Id
            $DownloadedUpdates = $true

            $LocalCache = Get-LocalWingetCache `
                -PackageId $App.Id `
                -PreferredVersion $OnlineVersion
        }
        else {

            Write-Log ("Version locale : {0}" -f $LocalCache.Version)

            if ($null -ne $OnlineVersion -and $OnlineVersion -ne "") {

                Write-Log ("Version en ligne : {0}" -f $OnlineVersion)

                if ($LocalCache.Version -ne $OnlineVersion) {

                    Write-Log "Cache local non a jour pour $($App.Name)" "WARN"

                    Download-WingetPackage -PackageId $App.Id
                    $DownloadedUpdates = $true

                    $LocalCache = Get-LocalWingetCache `
                        -PackageId $App.Id `
                        -PreferredVersion $OnlineVersion
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