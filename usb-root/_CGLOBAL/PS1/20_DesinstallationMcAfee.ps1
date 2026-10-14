#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
 Désinstalle complètement McAfee de manière totalement silencieuse.

.DESCRIPTION
 Stratégie en 2 étapes :
   1. Utilisation directe de MCPR.exe (outil officiel McAfee)
   2. En dernier recours : suppression manuelle forcée (services, fichiers, registre)

 Note : La désinstallation classique de McAfee n'est PAS silencieuse
 (McAfee force l'affichage de popups). On utilise donc directement MCPR.exe.

.NOTES
 A executer en tant qu'administrateur (elevation requise).
#>

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

# ============================================================
# Configuration du cache MCPR.exe
# ============================================================

$script:MCPR_CacheMaxAgeDays = 90
$script:MCPR_MinValidSizeBytes = 5242880
$script:MCPR_Url = "https://download.mcafee.com/products/licensed/cust_support_patches/MCPR.exe"

# ------------------------------------------------------------------
# Détection de la clé USB
# ------------------------------------------------------------------

function Get-UsbCGlobalPath {
    $UsbDrives = Get-CimInstance Win32_LogicalDisk |
        Where-Object { $_.DriveType -eq 2 }

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
    param([string]$FilePath)

    if (-not (Test-Path $FilePath)) {
        return $false
    }

    $File = Get-Item $FilePath
    $FileAge = (Get-Date) - $File.LastWriteTime

    Write-Log "Fichier MCPR détecté : $FilePath"
    Write-Log "Age: $($FileAge.Days) jours"

    if ($FileAge.TotalDays -gt $script:MCPR_CacheMaxAgeDays) {
        Write-Log "Fichier trop ancien" "WARN"
        return $false
    }

    if ($File.Length -lt $script:MCPR_MinValidSizeBytes) {
        Write-Log "Fichier trop petit" "WARN"
        return $false
    }

    return $true
}

# ------------------------------------------------------------------
# Recherche et préparation de MCPR.exe
# ------------------------------------------------------------------

function Find-MCPR {
    $UsbCGlobalPath = Get-UsbCGlobalPath

    # 1. Chercher sur la clé USB
    if ($UsbCGlobalPath) {
        $UsbFile = Join-Path $UsbCGlobalPath "tools\MCPR.exe"
        if (Test-MCPRFileValid -FilePath $UsbFile) {
            Write-Log "MCPR.exe valide trouvé sur la clé USB" "OK"

            # Copier sur le disque dur
            $LocalFile = "C:\_CGLOBAL\tools\MCPR.exe"
            if (-not (Test-Path $LocalFile) -or (Get-Item $LocalFile).LastWriteTime -lt (Get-Item $UsbFile).LastWriteTime) {
                if (-not (Test-Path "C:\_CGLOBAL\tools")) {
                    New-Item -Path "C:\_CGLOBAL\tools" -ItemType Directory -Force | Out-Null
                }
                Copy-Item -Path $UsbFile -Destination $LocalFile -Force
                Write-Log "MCPR.exe copié vers $LocalFile" "OK"
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
    Write-Log "Téléchargement de MCPR.exe..." "INFO"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        if (-not (Test-Path "C:\_CGLOBAL\tools")) {
            New-Item -Path "C:\_CGLOBAL\tools" -ItemType Directory -Force | Out-Null
        }

        Invoke-WebRequest -Uri $script:MCPR_Url -OutFile $LocalFile -UseBasicParsing

        $File = Get-Item $LocalFile
        if ($File.Length -lt $script:MCPR_MinValidSizeBytes) {
            throw "Fichier téléchargé invalide"
        }

        Write-Log "MCPR.exe téléchargé : $([Math]::Round($File.Length / 1MB, 2)) Mo" "OK"

        # Copier vers la clé USB
        if ($UsbCGlobalPath) {
            $ToolsFolder = Join-Path $UsbCGlobalPath "tools"
            if (-not (Test-Path $ToolsFolder)) {
                New-Item -Path $ToolsFolder -ItemType Directory -Force | Out-Null
            }
            Copy-Item -Path $LocalFile -Destination (Join-Path $ToolsFolder "MCPR.exe") -Force
            Write-Log "MCPR.exe copié vers la clé USB" "OK"
        }

        return $LocalFile
    }
    catch {
        Write-Log "Échec du téléchargement : $($_.Exception.Message)" "ERROR"
        return $null
    }
}

# ------------------------------------------------------------------
# Arrêt des processus et services McAfee
# ------------------------------------------------------------------

function Stop-McAfeeProcessesAndServices {
    Write-Log "Arrêt des processus McAfee..." "INFO"

    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -match '(?i)^McAfee|^mf|^mfe' } |
        ForEach-Object {
            try {
                Write-Log "Arrêt : $($_.ProcessName)" "INFO"
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            }
            catch { }
        }

    Start-Sleep -Seconds 2

    Write-Log "Arrêt des services McAfee..." "INFO"

    Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match '(?i)McAfee' -or $_.Name -match '(?i)^McAfee|^mfe' } |
        ForEach-Object {
            try {
                Write-Log "Désactivation : $($_.Name)" "INFO"
                Set-Service -Name $_.Name -StartupType Disabled -ErrorAction SilentlyContinue
                if ($_.Status -eq 'Running') {
                    Stop-Service -Name $_.Name -Force -ErrorAction Stop
                }
            }
            catch {
                & sc.exe stop $_.Name 2>&1 | Out-Null
                & sc.exe config $_.Name start= disabled 2>&1 | Out-Null
            }
        }

    Start-Sleep -Seconds 2
}

# ------------------------------------------------------------------
# Exécution de MCPR.exe en mode silencieux
# ------------------------------------------------------------------

function Invoke-MCPR {
    Write-Log "============================================================" "INFO"
    Write-Log "Exécution de MCPR.exe (McAfee Consumer Product Removal)" "INFO"
    Write-Log "============================================================" "INFO"

    $MCPRPath = Find-MCPR

    if ($null -eq $MCPRPath) {
        Write-Log "MCPR.exe introuvable" "ERROR"
        return $false
    }

    Write-Log "Utilisation de : $MCPRPath" "INFO"

    try {
        # MCPR.exe avec paramètres silencieux
        # /Q = Quiet, /A = Automatic, /S = Silent
        $Process = Start-Process `
            -FilePath $MCPRPath `
            -ArgumentList "/Q", "/A", "/S" `
            -Wait `
            -PassThru `
            -WindowStyle Hidden `
            -ErrorAction Stop

        $ExitCode = $Process.ExitCode
        Write-Log "MCPR terminé avec le code $ExitCode" "INFO"

        return ($ExitCode -eq 0)
    }
    catch {
        Write-Log "Erreur MCPR : $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# ------------------------------------------------------------------
# Suppression manuelle forcée
# ------------------------------------------------------------------

function Remove-McAfeeManually {
    Write-Log "============================================================" "INFO"
    Write-Log "Suppression manuelle forcée de McAfee" "INFO"
    Write-Log "============================================================" "INFO"

    # 1. Supprimer les services
    Write-Log "Suppression des services..." "INFO"
    Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match '(?i)McAfee' -or $_.Name -match '(?i)^McAfee|^mfe' } |
        ForEach-Object {
            try {
                & sc.exe delete $_.Name 2>&1 | Out-Null
                Write-Log "Service supprimé : $($_.Name)" "OK"
            }
            catch { }
        }

    # 2. Supprimer les dossiers
    Write-Log "Suppression des dossiers..." "INFO"
    $Folders = @(
        "$env:ProgramFiles\McAfee",
        "${env:ProgramFiles(x86)}\McAfee",
        "$env:ProgramData\McAfee",
        "$env:LOCALAPPDATA\McAfee",
        "$env:APPDATA\McAfee",
        "$env:ProgramFiles\Common Files\McAfee"
    )

    foreach ($Folder in $Folders) {
        if (Test-Path $Folder) {
            try {
                Remove-Item -Path $Folder -Recurse -Force -ErrorAction Stop
                Write-Log "Dossier supprimé : $Folder" "OK"
            }
            catch {
                Write-Log "Impossible de supprimer : $Folder" "WARN"
            }
        }
    }

    # 3. Supprimer les clés de registre
    Write-Log "Suppression des clés de registre..." "INFO"
    $RegPaths = @(
        "HKLM:\SOFTWARE\McAfee",
        "HKLM:\SOFTWARE\WOW6432Node\McAfee",
        "HKCU:\SOFTWARE\McAfee"
    )

    foreach ($RegPath in $RegPaths) {
        if (Test-Path $RegPath) {
            try {
                Remove-Item -Path $RegPath -Recurse -Force -ErrorAction Stop
                Write-Log "Clé supprimée : $RegPath" "OK"
            }
            catch { }
        }
    }

    # 4. Supprimer les entrées Uninstall
    Write-Log "Suppression des entrées Uninstall..." "INFO"
    $UninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($UninstallPath in $UninstallPaths) {
        if (Test-Path $UninstallPath) {
            Get-ChildItem -Path $UninstallPath -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $Props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
                    if ($Props.DisplayName -match '(?i)\bMcAfee\b') {
                        try {
                            Remove-Item -Path $_.PSPath -Recurse -Force -ErrorAction Stop
                            Write-Log "Entrée supprimée : $($Props.DisplayName)" "OK"
                        }
                        catch { }
                    }
                }
        }
    }

    # 5. Supprimer les tâches planifiées
    Write-Log "Suppression des tâches planifiées..." "INFO"
    Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object { $_.TaskName -match '(?i)McAfee' } |
        ForEach-Object {
            try {
                Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction Stop
                Write-Log "Tâche supprimée : $($_.TaskName)" "OK"
            }
            catch { }
        }

    Write-Log "Suppression manuelle terminée" "OK"
    return $true
}

# ------------------------------------------------------------------
# Programme principal
# ------------------------------------------------------------------

try {
    Write-Log "============================================================" "INFO"
    Write-Log "=== DÉSINSTALLATION MCAFEE ===" "INFO"
    Write-Log "============================================================" "INFO"

    # 1. Détection
    Write-Log "Recherche des produits McAfee..." "INFO"

    $McAfeeEntries = @()
    $RegistryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($RegPath in $RegistryPaths) {
        if (Test-Path $RegPath) {
            Get-ChildItem -Path $RegPath -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $Props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
                    if ($Props.DisplayName -match '(?i)\bMcAfee\b') {
                        $McAfeeEntries += $Props
                    }
                }
        }
    }

    if ($McAfeeEntries.Count -eq 0) {
        Write-Log "Aucun produit McAfee détecté" "OK"
        exit 0
    }

    Write-Log "$($McAfeeEntries.Count) produit(s) McAfee détecté(s)" "WARN"

    # 2. Arrêt des processus et services
    Stop-McAfeeProcessesAndServices

    # 3. Exécution de MCPR.exe
    Write-Log "Tentative avec MCPR.exe..." "WARN"
    Invoke-MCPR

    Start-Sleep -Seconds 3

    # 4. Vérification
    $RemainingEntries = @()
    foreach ($RegPath in $RegistryPaths) {
        if (Test-Path $RegPath) {
            Get-ChildItem -Path $RegPath -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $Props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
                    if ($Props.DisplayName -match '(?i)\bMcAfee\b') {
                        $RemainingEntries += $Props
                    }
                }
        }
    }

    if ($RemainingEntries.Count -eq 0) {
        Write-Log "MCPR a supprimé tous les composants McAfee" "OK"
        Write-Log "=== DÉSINSTALLATION MCAFEE TERMINÉE ===" "OK"
        exit 0
    }

    Write-Log "$($RemainingEntries.Count) produit(s) restent après MCPR" "WARN"

    # 5. Suppression manuelle forcée
    Write-Log "Suppression manuelle forcée..." "WARN"
    Remove-McAfeeManually

    Start-Sleep -Seconds 2

    # 6. Vérification finale
    $FinalEntries = @()
    foreach ($RegPath in $RegistryPaths) {
        if (Test-Path $RegPath) {
            Get-ChildItem -Path $RegPath -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $Props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
                    if ($Props.DisplayName -match '(?i)\bMcAfee\b') {
                        $FinalEntries += $Props
                    }
                }
        }
    }

    if ($FinalEntries.Count -eq 0) {
        Write-Log "Tous les composants McAfee ont été supprimés" "OK"
        Write-Log "=== DÉSINSTALLATION MCAFEE TERMINÉE ===" "OK"
    }
    else {
        Write-Log "$($FinalEntries.Count) produit(s) restent" "WARN"
        Write-Log "Un redémarrage peut être nécessaire" "WARN"
    }

    exit 0
}
catch {
    Write-Log "ERREUR CRITIQUE : $($_.Exception.Message)" "ERROR"
    exit 1
}
