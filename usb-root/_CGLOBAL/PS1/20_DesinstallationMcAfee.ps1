#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
 Désinstalle complètement McAfee de manière totalement silencieuse,
 sans aucune interaction utilisateur ni popup du désinstalleur.

.DESCRIPTION
 Stratégie en 3 étapes :
   1. Désinstallation silencieuse classique (QuietUninstallString / UninstallString)
   2. Si des composants restent : utilisation de MCPR.exe (outil officiel McAfee)
   3. En dernier recours : suppression manuelle forcée (services, fichiers, registre)

 Le fichier MCPR.exe est recherché dans cet ordre :
   1. Sur la clé USB (_CGLOBAL/tools/MCPR.exe)
   2. Sur le disque dur (C:\_CGLOBAL\tools\MCPR.exe)
   3. Téléchargement depuis Internet si nécessaire

 Le fichier est considéré valide si :
   - Il a moins de 90 jours (3 mois)
   - Sa taille est > 5 MB
   - Si le fichier est téléchargé, il est copié sur la clé USB pour les prochaines utilisations.

.NOTES
 A executer en tant qu'administrateur (elevation requise).

 VERSION CORRIGEE : Support du mode Prevalidé / Silencieux + cache MCPR 3 mois
#>

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

# ============================================================
# 20 - DESINSTALLATION MCAFEE (VERSION FORCEE)
# ============================================================

# ============================================================
# Configuration du cache MCPR.exe
# ============================================================

# Durée de validité du cache : 3 mois (90 jours)
$script:MCPR_CacheMaxAgeDays = 90

# Taille minimale d'un fichier MCPR.exe valide (5 MB)
$script:MCPR_MinValidSizeBytes = 5242880

# URL de téléchargement de MCPR (outil officiel McAfee)
# Note : Cette URL peut changer. Si elle ne fonctionne plus,
# télécharger manuellement depuis https://www.mcafee.com/support/
# et placer le fichier dans usb-root/_CGLOBAL/tools/MCPR.exe
$script:MCPR_Url = "https://download.mcafee.com/products/licensed/cust_support_patches/MCPR.exe"

# ------------------------------------------------------------------
# Détection de la clé USB
# ------------------------------------------------------------------

function Get-UsbCGlobalPath {
    $UsbDrives = Get-CimInstance Win32_LogicalDisk |
        Where-Object {
            $_.DriveType -eq 2
        }

    foreach ($Drive in $UsbDrives) {
        $Candidate = Join-Path $Drive.DeviceID "_CGLOBAL"

        if (Test-Path $Candidate) {
            Write-Log "Clé USB détectée : $Candidate" "OK"
            return $Candidate
        }
    }

    Write-Log "Clé USB _CGLOBAL introuvable" "WARN"
    return $null
}

# ------------------------------------------------------------------
# Vérification de validité d'un fichier MCPR.exe
# ------------------------------------------------------------------

function Test-MCPRFileValid {
    param(
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath)) {
        return $false
    }

    $File = Get-Item $FilePath
    $FileAge = (Get-Date) - $File.LastWriteTime

    Write-Log "Fichier MCPR détecté : $FilePath"
    Write-Log "Date dernière modification: $($File.LastWriteTime)"
    Write-Log "Age: $($FileAge.Days) jours"

    # Vérifier l'âge (90 jours = 3 mois)
    if ($FileAge.TotalDays -gt $script:MCPR_CacheMaxAgeDays) {
        Write-Log "Fichier trop ancien (plus de $($script:MCPR_CacheMaxAgeDays) jours)" "WARN"
        return $false
    }

    # Vérifier la taille
    if ($File.Length -lt $script:MCPR_MinValidSizeBytes) {
        Write-Log "Fichier trop petit (< 5 MB)" "WARN"
        return $false
    }

    return $true
}

# ------------------------------------------------------------------
# Copie de MCPR.exe vers la clé USB
# ------------------------------------------------------------------

function Copy-MCPRToUsb {
    param(
        [string]$UsbCGlobalPath,
        [string]$SourceFile
    )

    Write-Log "Copie de MCPR.exe vers la clé USB..."

    # Créer le dossier tools s'il n'existe pas
    $ToolsFolder = Join-Path $UsbCGlobalPath "tools"
    if (-not (Test-Path $ToolsFolder)) {
        New-Item -Path $ToolsFolder -ItemType Directory -Force | Out-Null
        Write-Log "Dossier tools créé : $ToolsFolder" "INFO"
    }

    $UsbFile = Join-Path $ToolsFolder "MCPR.exe"

    try {
        Copy-Item -Path $SourceFile -Destination $UsbFile -Force
        Write-Log "MCPR.exe copié vers $UsbFile" "OK"
    }
    catch {
        Write-Log "Échec de la copie vers USB: $($_.Exception.Message)" "WARN"
    }
}

# ------------------------------------------------------------------
# Recherche et préparation de MCPR.exe
# ------------------------------------------------------------------

function Find-MCPR {
    <#
    .SYNOPSIS
        Recherche MCPR.exe avec validation de cache (3 mois).
    .DESCRIPTION
        Cherche dans l'ordre :
        1. Clé USB (_CGLOBAL/tools/MCPR.exe)
        2. Disque dur (C:\_CGLOBAL\tools\MCPR.exe)
        3. Télécharge depuis Internet si nécessaire
    .RETURNS
        Chemin vers MCPR.exe si trouvé, $null sinon.
    #>

    # Détecter la clé USB
    $UsbCGlobalPath = Get-UsbCGlobalPath

    # 1. Chercher sur la clé USB
    if ($UsbCGlobalPath) {
        $UsbToolsFolder = Join-Path $UsbCGlobalPath "tools"
        $UsbFile = Join-Path $UsbToolsFolder "MCPR.exe"

        if (Test-MCPRFileValid -FilePath $UsbFile) {
            Write-Log "MCPR.exe valide trouvé sur la clé USB" "OK"

            # Copier sur le disque dur si nécessaire
            $LocalFile = "C:\_CGLOBAL\tools\MCPR.exe"
            if (-not (Test-Path $LocalFile) -or (Get-Item $LocalFile).LastWriteTime -lt (Get-Item $UsbFile).LastWriteTime) {
                Write-Log "Copie de MCPR.exe de la clé USB vers le disque dur..." "INFO"
                $LocalToolsFolder = "C:\_CGLOBAL\tools"
                if (-not (Test-Path $LocalToolsFolder)) {
                    New-Item -Path $LocalToolsFolder -ItemType Directory -Force | Out-Null
                }
                Copy-Item -Path $UsbFile -Destination $LocalFile -Force
                Write-Log "MCPR.exe copié vers $LocalFile" "OK"
            }
            else {
                Write-Log "Le fichier local est déjà à jour" "OK"
            }

            return $LocalFile
        }
    }

    # 2. Chercher sur le disque dur
    $LocalFile = "C:\_CGLOBAL\tools\MCPR.exe"
    if (Test-MCPRFileValid -FilePath $LocalFile) {
        Write-Log "MCPR.exe valide trouvé sur le disque dur" "OK"
        return $LocalFile
    }

    # 3. Télécharger depuis Internet
    Write-Log "Aucun fichier MCPR.exe valide trouvé (ou trop ancien), téléchargement requis" "WARN"
    Write-Log "Téléchargement de MCPR.exe depuis Internet..." "INFO"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        # Créer le dossier local si nécessaire
        $LocalToolsFolder = "C:\_CGLOBAL\tools"
        if (-not (Test-Path $LocalToolsFolder)) {
            New-Item -Path $LocalToolsFolder -ItemType Directory -Force | Out-Null
        }

        # Télécharger directement dans le dossier local
        Invoke-WebRequest -Uri $script:MCPR_Url -OutFile $LocalFile -UseBasicParsing

        # Vérifier le fichier téléchargé
        if (-not (Test-Path $LocalFile)) {
            throw "Le fichier n'a pas été téléchargé"
        }

        $File = Get-Item $LocalFile
        Write-Log "Taille fichier téléchargé : $($File.Length) octets"

        if ($File.Length -lt $script:MCPR_MinValidSizeBytes) {
            throw "Fichier téléchargé invalide : taille anormalement faible"
        }

        $SizeMB = [Math]::Round($File.Length / 1MB, 2)
        Write-Log "MCPR.exe téléchargé : $SizeMB Mo" "OK"

        # Copier vers la clé USB (si détectée)
        if ($UsbCGlobalPath) {
            Copy-MCPRToUsb -UsbCGlobalPath $UsbCGlobalPath -SourceFile $LocalFile
        }
        else {
            Write-Log "Impossible de copier vers USB (non détectée)" "WARN"
        }

        return $LocalFile
    }
    catch {
        Write-Log "Échec du téléchargement de MCPR.exe : $($_.Exception.Message)" "ERROR"

        # Nettoyer le fichier corrompu si existant
        if (Test-Path $LocalFile) {
            Remove-Item -Path $LocalFile -Force -ErrorAction SilentlyContinue
        }

        return $null
    }
}

function Get-McAfeeUninstallEntries {

    $Entries = @()

    $RegistryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($RegistryPath in $RegistryPaths) {

        if (-not (Test-Path $RegistryPath)) {
            continue
        }

        try {
            $Keys = Get-ChildItem -Path $RegistryPath -ErrorAction SilentlyContinue
        }
        catch {
            Write-Log "Impossible d'interroger $RegistryPath : $($_.Exception.Message)" "WARN"
            continue
        }

        foreach ($Key in $Keys) {

            try {
                $Properties = Get-ItemProperty `
                    -Path $Key.PSPath `
                    -ErrorAction SilentlyContinue

                if ($null -eq $Properties) {
                    continue
                }

                $DisplayName = [string]$Properties.DisplayName

                if ([string]::IsNullOrWhiteSpace($DisplayName)) {
                    continue
                }

                # Détection volontairement ciblée sur McAfee.
                if ($DisplayName -notmatch '(?i)\bMcAfee\b') {
                    continue
                }

                $Entry = [PSCustomObject]@{
                    DisplayName          = $DisplayName
                    DisplayVersion       = [string]$Properties.DisplayVersion
                    Publisher            = [string]$Properties.Publisher
                    UninstallString      = [string]$Properties.UninstallString
                    QuietUninstallString = [string]$Properties.QuietUninstallString
                    RegistryPath         = $Key.PSPath
                    WindowsInstaller     = [int]$Properties.WindowsInstaller
                    ProductCode          = [string]$Properties.PSChildName
                }

                $Entries += $Entry
            }
            catch {
                continue
            }
        }
    }

    return @(
        $Entries |
            Sort-Object RegistryPath -Unique
    )
}


function Stop-McAfeeProcesses {

    Write-Log "Recherche des processus McAfee en cours..." "INFO"

    $Processes = @(
        Get-Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.ProcessName -match '(?i)^McAfee|^mf|^mfe'
            }
    )

    if ($Processes.Count -eq 0) {
        Write-Log "Aucun processus McAfee à arrêter" "INFO"
        return
    }

    foreach ($Process in $Processes) {

        try {
            Write-Log "Arrêt du processus McAfee : $($Process.ProcessName) (PID $($Process.Id))" "INFO"

            Stop-Process `
                -Id $Process.Id `
                -Force `
                -ErrorAction SilentlyContinue

        }
        catch {
            Write-Log "Impossible d'arrêter $($Process.ProcessName) : $($_.Exception.Message)" "WARN"
        }
    }

    Start-Sleep -Seconds 2
}


function Stop-McAfeeServices {

    Write-Log "Arrêt des services McAfee..." "INFO"

    $Services = @(
        Get-Service -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -match '(?i)McAfee' -or
                $_.Name -match '(?i)^McAfee|^mfe|^macmnsvc|^mfewsp'
            }
    )

    if ($Services.Count -eq 0) {
        Write-Log "Aucun service McAfee à arrêter" "INFO"
        return
    }

    foreach ($Service in $Services) {

        try {
            Write-Log "Arrêt du service : $($Service.Name) ($($Service.DisplayName))" "INFO"

            # Désactiver le service pour éviter qu'il redémarre
            Set-Service -Name $Service.Name -StartupType Disabled -ErrorAction SilentlyContinue

            # Arrêter le service
            if ($Service.Status -eq 'Running') {
                Stop-Service -Name $Service.Name -Force -ErrorAction Stop
                Write-Log "Service arrêté : $($Service.Name)" "OK"
            }
        }
        catch {
            Write-Log "Impossible d'arrêter le service $($Service.Name) : $($_.Exception.Message)" "WARN"

            # Tenter avec sc.exe en dernier recours
            try {
                & sc.exe stop $Service.Name 2>&1 | Out-Null
                & sc.exe config $Service.Name start= disabled 2>&1 | Out-Null
                Write-Log "Service désactivé via sc.exe : $($Service.Name)" "OK"
            }
            catch {
                Write-Log "Échec complet pour le service $($Service.Name)" "WARN"
            }
        }
    }

    Start-Sleep -Seconds 2
}


function ConvertTo-SilentUninstallCommand {

    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandLine
    )

    $CommandLine = $CommandLine.Trim()

    if ([string]::IsNullOrWhiteSpace($CommandLine)) {
        return $null
    }

    # --------------------------------------------------------
    # MSIEXEC
    # --------------------------------------------------------

    if ($CommandLine -match '(?i)^\s*"[^"]*msiexec(?:\.exe)?"?\s+') {

        if ($CommandLine -match '(?i)(\{[0-9A-F-]{36}\})') {

            $ProductCode = $Matches[1]

            return [PSCustomObject]@{
                FilePath  = "$env:SystemRoot\System32\msiexec.exe"
                Arguments = "/x $ProductCode /qn /norestart REBOOT=ReallySuppress"
            }
        }

        $Arguments = $CommandLine `
            -replace '(?i)^\s*"[^"]*msiexec(?:\.exe)?"?\s*', ''

        $Arguments = $Arguments `
            -replace '(?i)/I', '/X'

        if ($Arguments -notmatch '(?i)/q') {
            $Arguments += ' /qn'
        }

        if ($Arguments -notmatch '(?i)/norestart') {
            $Arguments += ' /norestart REBOOT=ReallySuppress'
        }

        return [PSCustomObject]@{
            FilePath  = "$env:SystemRoot\System32\msiexec.exe"
            Arguments = $Arguments.Trim()
        }
    }

    # --------------------------------------------------------
    # EXE
    # --------------------------------------------------------

    $FilePath = $null
    $Arguments = $null

    if ($CommandLine -match '^\s*"([^"]+)"(?:\s+(.*))?$') {

        $FilePath = $Matches[1]
        $Arguments = $Matches[2]
    }
    else {

        if ($CommandLine -match '^\s*(\S+)(?:\s+(.*))?$') {

            $FilePath = $Matches[1]
            $Arguments = $Matches[2]
        }
    }

    if ([string]::IsNullOrWhiteSpace($FilePath)) {
        return $null
    }

    if (-not (Test-Path $FilePath)) {
        Write-Log "Programme de désinstallation introuvable : $FilePath" "WARN"
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($Arguments)) {
        $Arguments = ''
    }

    # Ajout des commutateurs silencieux agressifs
    if ($Arguments -notmatch '(?i)(^|\s)(/quiet|/silent|/s|/qn|/verysilent)(\s|$)') {
        $Arguments += ' /quiet'
    }

    if ($Arguments -notmatch '(?i)(^|\s)(/norestart|/noRestart|REBOOT=ReallySuppress)(\s|$)') {
        $Arguments += ' /norestart REBOOT=ReallySuppress'
    }

    return [PSCustomObject]@{
        FilePath  = $FilePath
        Arguments = $Arguments.Trim()
    }
}


function Invoke-McAfeeUninstall {

    param(
        [Parameter(Mandatory = $true)]
        $Entry
    )

    Write-Log "------------------------------------------------------------" "INFO"
    Write-Log "Produit McAfee : $($Entry.DisplayName)" "INFO"

    if (-not [string]::IsNullOrWhiteSpace($Entry.DisplayVersion)) {
        Write-Log "Version : $($Entry.DisplayVersion)" "INFO"
    }

    Write-Log "Clé : $($Entry.RegistryPath)" "INFO"

    # 1. QuietUninstallString
    $CommandLine = $Entry.QuietUninstallString

    if (-not [string]::IsNullOrWhiteSpace($CommandLine)) {

        Write-Log "QuietUninstallString détecté" "INFO"
        Write-Log "Commande : $CommandLine" "INFO"

        $SilentCommand = ConvertTo-SilentUninstallCommand `
            -CommandLine $CommandLine
    }
    else {

        # 2. UninstallString
        $CommandLine = $Entry.UninstallString

        if ([string]::IsNullOrWhiteSpace($CommandLine)) {

            Write-Log "Aucune commande de désinstallation disponible pour $($Entry.DisplayName)" "ERROR"
            return $false
        }

        Write-Log "UninstallString détecté" "INFO"
        Write-Log "Commande : $CommandLine" "INFO"

        $SilentCommand = ConvertTo-SilentUninstallCommand `
            -CommandLine $CommandLine
    }

    if ($null -eq $SilentCommand) {

        Write-Log "Impossible de construire une commande de désinstallation silencieuse pour $($Entry.DisplayName)" "ERROR"

        return $false
    }

    Write-Log "Exécution silencieuse : $($SilentCommand.FilePath) $($SilentCommand.Arguments)" "INFO"

    try {

        $Process = Start-Process `
            -FilePath $SilentCommand.FilePath `
            -ArgumentList $SilentCommand.Arguments `
            -Wait `
            -PassThru `
            -WindowStyle Hidden `
            -ErrorAction Stop

        $ExitCode = $Process.ExitCode

        Write-Log "Programme de désinstallation terminé avec le code $ExitCode" "INFO"

        if ($ExitCode -eq 0) {
            Write-Log "Désinstallation terminée avec succès : $($Entry.DisplayName)" "OK"
            return $true
        }

        if ($ExitCode -eq 1641 -or $ExitCode -eq 3010) {
            Write-Log "Désinstallation réussie mais un redémarrage est requis (code $ExitCode)" "WARN"
            return $true
        }

        Write-Log "Le désinstalleur a retourné le code $ExitCode" "WARN"
        return $false
    }
    catch {

        Write-Log "Erreur lors de l'exécution du désinstalleur : $($_.Exception.Message)" "ERROR"

        return $false
    }
}


function Invoke-MCPR {

    Write-Log "============================================================" "INFO"
    Write-Log "Utilisation de MCPR (McAfee Consumer Product Removal)" "INFO"
    Write-Log "============================================================" "INFO"

    # Chercher MCPR.exe (clé USB, disque dur, ou téléchargement)
    $MCPRPath = Find-MCPR

    if ($null -eq $MCPRPath) {
        Write-Log "MCPR.exe introuvable (local et Internet). Passage à la suppression manuelle." "WARN"
        return $false
    }

    Write-Log "Utilisation de MCPR.exe : $MCPRPath" "INFO"

    # Exécuter MCPR en mode silencieux
    Write-Log "Exécution de MCPR.exe en mode silencieux..." "INFO"

    try {
        # MCPR accepte /quiet pour une exécution sans interface
        $Process = Start-Process `
            -FilePath $MCPRPath `
            -ArgumentList "/quiet" `
            -Wait `
            -PassThru `
            -WindowStyle Hidden `
            -ErrorAction Stop

        $ExitCode = $Process.ExitCode

        Write-Log "MCPR terminé avec le code $ExitCode" "INFO"

        if ($ExitCode -eq 0) {
            Write-Log "MCPR a supprimé McAfee avec succès" "OK"
            return $true
        }

        Write-Log "MCPR a retourné le code $ExitCode" "WARN"
        return $false
    }
    catch {
        Write-Log "Erreur lors de l'exécution de MCPR : $($_.Exception.Message)" "ERROR"
        return $false
    }
}


function Remove-McAfeeManually {

    Write-Log "============================================================" "INFO"
    Write-Log "Suppression manuelle forcée de McAfee" "INFO"
    Write-Log "============================================================" "INFO"

    # 1. Supprimer les services
    Write-Log "Suppression des services McAfee..." "INFO"

    $Services = @(
        Get-Service -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -match '(?i)McAfee' -or
                $_.Name -match '(?i)^McAfee|^mfe|^macmnsvc|^mfewsp'
            }
    )

    foreach ($Service in $Services) {
        try {
            Write-Log "Suppression du service : $($Service.Name)" "INFO"
            & sc.exe delete $Service.Name 2>&1 | Out-Null
            Write-Log "Service supprimé : $($Service.Name)" "OK"
        }
        catch {
            Write-Log "Impossible de supprimer le service $($Service.Name)" "WARN"
        }
    }

    # 2. Supprimer les dossiers
    Write-Log "Suppression des dossiers McAfee..." "INFO"

    $Folders = @(
        "$env:ProgramFiles\McAfee",
        "${env:ProgramFiles(x86)}\McAfee",
        "$env:ProgramData\McAfee",
        "$env:LOCALAPPDATA\McAfee",
        "$env:APPDATA\McAfee"
    )

    foreach ($Folder in $Folders) {
        if (Test-Path $Folder) {
            try {
                Write-Log "Suppression du dossier : $Folder" "INFO"
                Remove-Item -Path $Folder -Recurse -Force -ErrorAction Stop
                Write-Log "Dossier supprimé : $Folder" "OK"
            }
            catch {
                Write-Log "Impossible de supprimer le dossier $Folder : $($_.Exception.Message)" "WARN"
            }
        }
    }

    # 3. Supprimer les clés de registre
    Write-Log "Suppression des clés de registre McAfee..." "INFO"

    $RegPaths = @(
        "HKLM:\SOFTWARE\McAfee",
        "HKLM:\SOFTWARE\WOW6432Node\McAfee",
        "HKCU:\SOFTWARE\McAfee"
    )

    foreach ($RegPath in $RegPaths) {
        if (Test-Path $RegPath) {
            try {
                Write-Log "Suppression de la clé : $RegPath" "INFO"
                Remove-Item -Path $RegPath -Recurse -Force -ErrorAction Stop
                Write-Log "Clé supprimée : $RegPath" "OK"
            }
            catch {
                Write-Log "Impossible de supprimer la clé $RegPath : $($_.Exception.Message)" "WARN"
            }
        }
    }

    # 4. Supprimer les entrées Uninstall
    Write-Log "Suppression des entrées Uninstall McAfee..." "INFO"

    $UninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($UninstallPath in $UninstallPaths) {
        if (Test-Path $UninstallPath) {
            $Keys = Get-ChildItem -Path $UninstallPath -ErrorAction SilentlyContinue
            foreach ($Key in $Keys) {
                $Props = Get-ItemProperty -Path $Key.PSPath -ErrorAction SilentlyContinue
                if ($Props.DisplayName -match '(?i)\bMcAfee\b') {
                    try {
                        Write-Log "Suppression de l'entrée Uninstall : $($Props.DisplayName)" "INFO"
                        Remove-Item -Path $Key.PSPath -Recurse -Force -ErrorAction Stop
                        Write-Log "Entrée supprimée : $($Props.DisplayName)" "OK"
                    }
                    catch {
                        Write-Log "Impossible de supprimer l'entrée $($Props.DisplayName)" "WARN"
                    }
                }
            }
        }
    }

    Write-Log "Suppression manuelle terminée" "OK"
    return $true
}


try {

    Write-Log "============================================================" "INFO"
    Write-Log "=== DÉSINSTALLATION MCAFEE (VERSION FORCÉE) ===" "INFO"
    Write-Log "============================================================" "INFO"

    # --------------------------------------------------------
    # 1. DÉTECTION
    # --------------------------------------------------------

    Write-Log "Recherche des produits McAfee installés..." "INFO"

    $McAfeeEntries = @(Get-McAfeeUninstallEntries)

    if ($McAfeeEntries.Count -eq 0) {

        Write-Log "Aucun produit McAfee détecté dans les programmes installés" "OK"
        Write-Log "Aucune action nécessaire" "INFO"

        exit 0
    }

    Write-Log "$($McAfeeEntries.Count) produit(s) McAfee détecté(s)" "WARN"

    foreach ($Entry in $McAfeeEntries) {
        Write-Log "McAfee détecté : $($Entry.DisplayName)" "WARN"
    }

    # --------------------------------------------------------
    # 2. ARRÊT DES PROCESSUS ET SERVICES
    # --------------------------------------------------------

    Stop-McAfeeProcesses
    Stop-McAfeeServices

    # --------------------------------------------------------
    # 3. DÉSINSTALLATION CLASSIQUE
    # --------------------------------------------------------

    $SuccessCount = 0
    $FailureCount = 0

    foreach ($Entry in $McAfeeEntries) {

        $Result = Invoke-McAfeeUninstall -Entry $Entry

        if ($Result) {
            $SuccessCount++
        }
        else {
            $FailureCount++
        }

        Start-Sleep -Seconds 2
    }

    # --------------------------------------------------------
    # 4. VÉRIFICATION
    # --------------------------------------------------------

    Write-Log "Vérification après désinstallation classique..." "INFO"
    Start-Sleep -Seconds 3

    $RemainingEntries = @(Get-McAfeeUninstallEntries)

    if ($RemainingEntries.Count -eq 0) {

        Write-Log "Aucun produit McAfee restant" "OK"
        Write-Log "=== DÉSINSTALLATION MCAFEE TERMINÉE ===" "OK"

        exit 0
    }

    Write-Log "$($RemainingEntries.Count) produit(s) McAfee restent après désinstallation classique" "WARN"

    # --------------------------------------------------------
    # 5. MCPR (outil officiel McAfee)
    # --------------------------------------------------------

    Write-Log "Tentative avec MCPR.exe..." "WARN"

    $MCPRResult = Invoke-MCPR

    Start-Sleep -Seconds 3

    $RemainingEntries = @(Get-McAfeeUninstallEntries)

    if ($RemainingEntries.Count -eq 0) {

        Write-Log "MCPR a supprimé tous les composants McAfee" "OK"
        Write-Log "=== DÉSINSTALLATION MCAFEE TERMINÉE ===" "OK"

        exit 0
    }

    Write-Log "$($RemainingEntries.Count) produit(s) McAfee restent après MCPR" "WARN"

    # --------------------------------------------------------
    # 6. SUPPRESSION MANUELLE FORCÉE
    # --------------------------------------------------------

    Write-Log "Dernier recours : suppression manuelle forcée..." "WARN"

    $ManualResult = Remove-McAfeeManually

    Start-Sleep -Seconds 2

    $FinalEntries = @(Get-McAfeeUninstallEntries)

    if ($FinalEntries.Count -eq 0) {

        Write-Log "Tous les composants McAfee ont été supprimés" "OK"
        Write-Log "=== DÉSINSTALLATION MCAFEE TERMINÉE ===" "OK"

        exit 0
    }

    # --------------------------------------------------------
    # 7. RÉSULTAT PARTIEL
    # --------------------------------------------------------

    Write-Log "$($FinalEntries.Count) produit(s) McAfee restent après toutes les tentatives" "WARN"

    foreach ($Remaining in $FinalEntries) {
        Write-Log "Produit restant : $($Remaining.DisplayName)" "WARN"
    }

    Write-Log "Un redémarrage du poste peut être nécessaire pour finaliser la suppression" "WARN"

    exit 0
}
catch {

    Write-Log "ERREUR CRITIQUE : $($_.Exception.Message)" "ERROR"

    if ($_.ScriptStackTrace) {
        Write-Log $_.ScriptStackTrace "ERROR"
    }

    exit 1
}
