#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
 Désinstalle complètement McAfee de manière totalement silencieuse.

.DESCRIPTION
 Stratégie :
   0. Détection (registre Uninstall + paquets AppX)
   1. Suppression des paquets AppX McAfee (Lenovo récents)
   2. Arrêt des processus / services McAfee
   3. mccleanup.exe (moteur de MCPR, sans interface) depuis C:\_CGLOBAL\tools\mccleaner
   4. En dernier recours : suppression manuelle forcée (services, fichiers, registre)

 Le dossier tools\mccleaner contient le contenu extrait de MCPR.exe (dossier $1) :
 mccleanup.exe, master.ini, les .wse, les sous-dossiers, etc.
 Ordre de recherche : disque local -> clé USB (_CGLOBAL\tools\mccleaner)
 -> (secours) téléchargement de MCPR.exe + extraction avec 7-Zip.

.NOTES
 A exécuter en tant qu'administrateur (élévation requise).
 Fichier à enregistrer en UTF-8 avec BOM (accents lisibles par PowerShell 5.1).
#>

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

# ============================================================
# Configuration
# ============================================================

$script:ToolsDir            = "C:\_CGLOBAL\tools"
$script:McCleanerDir        = Join-Path $script:ToolsDir "mccleaner"
$script:McCleanupExe        = Join-Path $script:McCleanerDir "mccleanup.exe"
$script:McCleanerWarnDays   = 180          # simple avertissement, ne bloque pas
$script:McCleanupTimeoutSec = 1200         # 20 min max pour mccleanup

# Secours uniquement : MCPR.exe téléchargé puis extrait avec 7-Zip
$script:MCPR_Url               = "https://download.mcafee.com/products/licensed/cust_support_patches/MCPR.exe"
$script:MCPR_MinValidSizeBytes = 5242880

# Liste des composants issue de StartCleanup.bat (MCPR)
$script:McCleanupComponents = "StopServices,MFSY,PEF,MXD,CSP,Sustainability,MOCP,MFP,APPSTATS,Auth,EMproxy,FWdiver,HW,MAS,MAT,MBK,MCPR,McProxy,McSvcHost,VUL,MHN,MNA,MOBK,MPFP,MPFPCU,MPS,SHRED,MPSCU,MQC,MQCCU,MSAD,MSHR,MSK,MSKCU,MWL,NMC,RedirSvc,VS,REMEDIATION,MSC,YAP,TRUEKEY,LAM,PCB,Symlink,SafeConnect,MGS,WMIRemover,RESIDUE"

$script:UninstallRegPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

# ============================================================
# Détection
# ============================================================

function Get-McAfeeRegistryEntries {
    $Entries = @()
    foreach ($RegPath in $script:UninstallRegPaths) {
        if (Test-Path $RegPath) {
            Get-ChildItem -Path $RegPath -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $Props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
                    if ($Props.DisplayName -match '(?i)\bMcAfee\b') {
                        $Entries += $Props
                    }
                }
        }
    }
    return $Entries
}

function Get-McAfeeAppx {
    try {
        return @(Get-AppxPackage -AllUsers -ErrorAction Stop |
            Where-Object { $_.Name -match '(?i)McAfee' -or $_.PublisherId -match '(?i)McAfee' })
    }
    catch {
        Write-Log "Lecture des paquets AppX impossible : $($_.Exception.Message)" "WARN"
        return @()
    }
}

function Get-McAfeeRemainingCount {
    $Reg  = @(Get-McAfeeRegistryEntries).Count
    $Appx = @(Get-McAfeeAppx).Count
    return ($Reg + $Appx)
}

# ============================================================
# Clé USB
# ============================================================

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

# ============================================================
# Préparation du dossier mccleaner
# ============================================================

function Test-McCleanerValid {
    param([string]$Dir)

    $Exe = Join-Path $Dir "mccleanup.exe"
    $Ini = Join-Path $Dir "master.ini"

    if (-not (Test-Path $Exe)) { return $false }
    if (-not (Test-Path $Ini)) {
        Write-Log "master.ini absent dans $Dir (dossier incomplet)" "WARN"
        return $false
    }

    $Age = (Get-Date) - (Get-Item $Exe).LastWriteTime
    if ($Age.TotalDays -gt $script:McCleanerWarnDays) {
        Write-Log "mccleanup.exe date de $([int]$Age.TotalDays) jours : pensez à mettre à jour le dossier mccleaner" "WARN"
    }

    return $true
}

function Copy-McCleanerFrom {
    param([string]$SourceDir)

    New-Item -Path $script:McCleanerDir -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Join-Path $SourceDir '*') -Destination $script:McCleanerDir -Recurse -Force
}

function Initialize-McCleaner {
    # 1. Disque local
    if (Test-McCleanerValid -Dir $script:McCleanerDir) {
        Write-Log "mccleaner valide sur le disque local : $script:McCleanerDir" "OK"
        return $true
    }

    # 2. Clé USB
    $Usb = Get-UsbCGlobalPath
    if ($Usb) {
        $UsbDir = Join-Path $Usb "tools\mccleaner"
        if (Test-McCleanerValid -Dir $UsbDir) {
            Copy-McCleanerFrom -SourceDir $UsbDir
            Write-Log "mccleaner copié depuis la clé USB vers $script:McCleanerDir" "OK"
            return $true
        }
    }

    # 3. Secours : MCPR.exe + 7-Zip
    Write-Log "Dossier mccleaner introuvable, tentative via MCPR.exe + 7-Zip" "WARN"

    $SevenZip = @("$env:ProgramFiles\7-Zip\7z.exe",
                  "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
                  (Join-Path $script:ToolsDir "7z.exe")) |
                Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $SevenZip) {
        Write-Log "7-Zip introuvable : impossible d'extraire MCPR.exe" "ERROR"
        return $false
    }

    $McprFile = Join-Path $script:ToolsDir "MCPR.exe"
    try {
        if (-not (Test-Path $script:ToolsDir)) {
            New-Item -Path $script:ToolsDir -ItemType Directory -Force | Out-Null
        }

        if (-not (Test-Path $McprFile) -or (Get-Item $McprFile).Length -lt $script:MCPR_MinValidSizeBytes) {
            Write-Log "Téléchargement de MCPR.exe..." "INFO"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $script:MCPR_Url -OutFile $McprFile -UseBasicParsing
            if ((Get-Item $McprFile).Length -lt $script:MCPR_MinValidSizeBytes) {
                throw "Fichier téléchargé invalide"
            }
            Write-Log "MCPR.exe téléchargé" "OK"
        }

        $Tmp = Join-Path $env:TEMP "mcpr_extract"
        Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue
        & $SevenZip x $McprFile "-o$Tmp" -y | Out-Null

        $Found = Get-ChildItem -Path $Tmp -Recurse -Filter mccleanup.exe -ErrorAction SilentlyContinue |
                 Select-Object -First 1
        if (-not $Found) {
            throw "mccleanup.exe introuvable après extraction"
        }

        Copy-McCleanerFrom -SourceDir $Found.DirectoryName
        Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "mccleaner extrait dans $script:McCleanerDir" "OK"

        # Sauvegarde sur la clé USB pour les prochaines fois
        if ($Usb) {
            $UsbDest = Join-Path $Usb "tools\mccleaner"
            New-Item -Path $UsbDest -ItemType Directory -Force | Out-Null
            Copy-Item -Path (Join-Path $script:McCleanerDir '*') -Destination $UsbDest -Recurse -Force
            Write-Log "mccleaner copié vers la clé USB" "OK"
        }

        return (Test-McCleanerValid -Dir $script:McCleanerDir)
    }
    catch {
        Write-Log "Échec de la préparation de mccleaner : $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# ============================================================
# Paquets AppX
# ============================================================

function Remove-McAfeeAppx {
    $Packages = Get-McAfeeAppx
    if ($Packages.Count -eq 0) { return }

    Write-Log "Suppression de $($Packages.Count) paquet(s) AppX McAfee..." "INFO"

    foreach ($Pkg in $Packages) {
        try {
            Remove-AppxPackage -Package $Pkg.PackageFullName -AllUsers -ErrorAction Stop
            Write-Log "AppX supprimé : $($Pkg.Name)" "OK"
        }
        catch {
            Write-Log "AppX non supprimé : $($Pkg.Name) - $($_.Exception.Message)" "WARN"
        }
    }

    try {
        Get-AppxProvisionedPackage -Online -ErrorAction Stop |
            Where-Object { $_.DisplayName -match '(?i)McAfee' } |
            ForEach-Object {
                Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction Stop | Out-Null
                Write-Log "Paquet provisionné supprimé : $($_.DisplayName)" "OK"
            }
    }
    catch {
        Write-Log "Paquets provisionnés : $($_.Exception.Message)" "WARN"
    }
}

# ============================================================
# Arrêt des processus et services McAfee
# ============================================================

function Stop-McAfeeProcessesAndServices {
    Write-Log "Arrêt des services McAfee (priorité)..." "INFO"

    # Arrêter les services EN PREMIER (plus fiable)
    Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match '(?i)McAfee' -or $_.Name -match '(?i)^McAfee|^mfe' } |
        ForEach-Object {
            try {
                Write-Log "Arrêt service : $($_.Name)" "INFO"
                # Désactiver d'abord pour éviter le redémarrage
                Set-Service -Name $_.Name -StartupType Disabled -ErrorAction SilentlyContinue
                if ($_.Status -eq 'Running') {
                    Stop-Service -Name $_.Name -Force -ErrorAction Stop
                    Write-Log "  → Service arrêté" "OK"
                }
            }
            catch {
                # Fallback avec sc.exe
                & sc.exe stop $_.Name 2>&1 | Out-Null
                & sc.exe config $_.Name start= disabled 2>&1 | Out-Null
                Write-Log "  → Service désactivé via sc.exe" "OK"
            }
        }

    Start-Sleep -Seconds 3

    Write-Log "Arrêt des processus McAfee..." "INFO"

    # Arrêter tous les processus McAfee de manière agressive
    $MaxRetries = 3
    for ($Retry = 1; $Retry -le $MaxRetries; $Retry++) {
        $McAfeeProcesses = Get-Process -ErrorAction SilentlyContinue |
            Where-Object { $_.ProcessName -match '(?i)McAfee|^mf|^mfe|WebAdvisor|TrueKey|SafeConnect' }

        if ($McAfeeProcesses.Count -eq 0) {
            Write-Log "Tous les processus McAfee arrêtés" "OK"
            break
        }

        Write-Log "Tentative $Retry/$MaxRetries : $($McAfeeProcesses.Count) processus restants" "INFO"

        foreach ($Proc in $McAfeeProcesses) {
            try {
                Write-Log "  Kill : $($Proc.ProcessName) (PID $($Proc.Id))" "INFO"
                Stop-Process -Id $Proc.Id -Force -ErrorAction Stop
            }
            catch {
                # Fallback avec taskkill
                & taskkill /F /PID $Proc.Id 2>&1 | Out-Null
            }
        }

        Start-Sleep -Seconds 2
    }

    # Vérification finale
    $Remaining = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -match '(?i)McAfee|^mf|^mfe|WebAdvisor|TrueKey|SafeConnect' }

    if ($Remaining.Count -gt 0) {
        Write-Log "ATTENTION : $($Remaining.Count) processus McAfee toujours actifs" "WARN"
        foreach ($Proc in $Remaining) {
            Write-Log "  → $($Proc.ProcessName) (PID $($Proc.Id))" "WARN"
        }
    }

    Start-Sleep -Seconds 3
}

# ============================================================
# mccleanup.exe en mode silencieux
# ============================================================

function Invoke-McCleanup {
    Write-Log "============================================================" "INFO"
    Write-Log "Exécution de mccleanup.exe (moteur MCPR, sans interface)" "INFO"
    Write-Log "============================================================" "INFO"

    if (-not (Initialize-McCleaner)) {
        Write-Log "mccleaner indisponible" "ERROR"
        return $false
    }

    try {
        # Paramètres : -p (composants), -s (silent)
        # Note : -v retiré car non documenté officiellement
        $Process = Start-Process `
            -FilePath $script:McCleanupExe `
            -ArgumentList "-p", $script:McCleanupComponents, "-s" `
            -WorkingDirectory $script:McCleanerDir `
            -PassThru `
            -WindowStyle Hidden `
            -ErrorAction Stop

        if (-not $Process.WaitForExit($script:McCleanupTimeoutSec * 1000)) {
            Write-Log "mccleanup dépasse $script:McCleanupTimeoutSec s : arrêt forcé" "ERROR"
            Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
            return $false
        }

        # Vérification du code retour
        if ($Process.ExitCode -eq 0) {
            Write-Log "mccleanup terminé avec succès (code 0)" "OK"
            return $true
        } else {
            Write-Log "mccleanup a échoué avec le code $($Process.ExitCode)" "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "Erreur mccleanup : $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# ============================================================
# Suppression manuelle forcée
# ============================================================

function Remove-McAfeeManually {
    Write-Log "============================================================" "INFO"
    Write-Log "Suppression manuelle forcée de McAfee" "INFO"
    Write-Log "============================================================" "INFO"

    # 1. Services
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

    # 2. Dossiers (avec retries et prise de possession)
    Write-Log "Suppression des dossiers..." "INFO"
    $Folders = @(
        "$env:ProgramFiles\McAfee",
        "${env:ProgramFiles(x86)}\McAfee",
        "$env:ProgramData\McAfee",
        "$env:LOCALAPPDATA\McAfee",
        "$env:APPDATA\McAfee",
        "$env:ProgramFiles\Common Files\McAfee",
        "C:\Program Files\McAfee",
        "C:\Program Files (x86)\McAfee",
        "C:\ProgramData\McAfee"
    )

    foreach ($Folder in $Folders) {
        if (Test-Path $Folder) {
            $Deleted = $false

            # Tentative 1 : suppression normale
            try {
                Remove-Item -Path $Folder -Recurse -Force -ErrorAction Stop
                Write-Log "Dossier supprimé : $Folder" "OK"
                $Deleted = $true
            }
            catch {
                Write-Log "Tentative 1 échouée pour $Folder, prise de possession..." "WARN"
            }

            # Tentative 2 : prise de possession + suppression
            if (-not $Deleted) {
                try {
                    # Prendre possession du dossier
                    & takeown /F $Folder /R /D Y 2>&1 | Out-Null
                    & icacls $Folder /grant administrators:F /T /Q 2>&1 | Out-Null

                    # Supprimer
                    Remove-Item -Path $Folder -Recurse -Force -ErrorAction Stop
                    Write-Log "Dossier supprimé après prise de possession : $Folder" "OK"
                    $Deleted = $true
                }
                catch {
                    Write-Log "Tentative 2 échouée pour $Folder" "WARN"
                }
            }

            # Tentative 3 : suppression au prochain redémarrage
            if (-not $Deleted) {
                try {
                    # Marquer pour suppression au redémarrage
                    $PendingDeleteKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
                    $ExistingValue = (Get-ItemProperty -Path $PendingDeleteKey -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue).PendingFileRenameOperations
                    if ($null -eq $ExistingValue) { $ExistingValue = @() }
                    $ExistingValue += "\??\$Folder"
                    $ExistingValue += ""
                    Set-ItemProperty -Path $PendingDeleteKey -Name "PendingFileRenameOperations" -Value $ExistingValue -Type MultiString
                    Write-Log "Dossier marqué pour suppression au redémarrage : $Folder" "WARN"
                }
                catch {
                    Write-Log "Impossible de marquer $Folder pour suppression" "ERROR"
                }
            }
        }
    }

    # 3. Clés de registre
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

    # 4. Entrées Uninstall
    Write-Log "Suppression des entrées Uninstall..." "INFO"
    $UninstallPaths = $script:UninstallRegPaths + "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"

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

    # 5. Tâches planifiées
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

# ============================================================
# Programme principal
# ============================================================

try {
    Write-Log "============================================================" "INFO"
    Write-Log "=== DÉSINSTALLATION MCAFEE ===" "INFO"
    Write-Log "============================================================" "INFO"

    # 0. Détection
    Write-Log "Recherche des produits McAfee..." "INFO"

    $Initial = Get-McAfeeRemainingCount
    if ($Initial -eq 0) {
        Write-Log "Aucun produit McAfee détecté" "OK"
        exit 0
    }
    Write-Log "$Initial produit(s) / paquet(s) McAfee détecté(s)" "WARN"

    # 1. Paquets AppX
    Remove-McAfeeAppx

    # 2. Arrêt des processus et services
    Stop-McAfeeProcessesAndServices

    # 3. mccleanup.exe
    $McCleanupResult = Invoke-McCleanup
    if ($McCleanupResult) {
        Write-Log "mccleanup exécuté avec succès" "OK"
    } else {
        Write-Log "mccleanup a échoué ou est indisponible" "ERROR"
        Write-Log "Passage à la suppression manuelle forcée" "WARN"
    }

    Start-Sleep -Seconds 3

    # 4. Vérification intermédiaire
    $Remaining = Get-McAfeeRemainingCount

    # Vérifier aussi les processus et services actifs
    $ActiveProcesses = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -match '(?i)McAfee|^mf|^mfe|WebAdvisor|TrueKey|SafeConnect' }

    $ActiveServices = Get-Service -ErrorAction SilentlyContinue |
        Where-Object { ($_.DisplayName -match '(?i)McAfee' -or $_.Name -match '(?i)^McAfee|^mfe') -and $_.Status -eq 'Running' }

    if ($Remaining -eq 0 -and $ActiveProcesses.Count -eq 0 -and $ActiveServices.Count -eq 0) {
        Write-Log "mccleanup a supprimé tous les composants McAfee" "OK"
        Write-Log "Un redémarrage est recommandé pour finaliser (pilotes)" "WARN"
        Write-Log "=== DÉSINSTALLATION MCAFEE TERMINÉE ===" "OK"
        exit 0
    }

    Write-Log "$Remaining produit(s) restent après mccleanup" "WARN"
    if ($ActiveProcesses.Count -gt 0) {
        Write-Log "$($ActiveProcesses.Count) processus McAfee encore actifs" "WARN"
    }
    if ($ActiveServices.Count -gt 0) {
        Write-Log "$($ActiveServices.Count) services McAfee encore actifs" "WARN"
    }

    # 4b. Deuxième arrêt des processus (au cas où mccleanup en a relancé)
    Write-Log "Deuxième arrêt des processus McAfee..." "INFO"
    Stop-McAfeeProcessesAndServices

    # 5. Suppression manuelle forcée
    $ManualResult = Remove-McAfeeManually
    if ($ManualResult) {
        Write-Log "Suppression manuelle exécutée avec succès" "OK"
    } else {
        Write-Log "Suppression manuelle a échoué" "WARN"
    }

    Start-Sleep -Seconds 2

    # 6. Vérification finale (registre + processus + services)
    $Final = Get-McAfeeRemainingCount

    # Vérifier aussi les processus actifs
    $ActiveProcesses = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -match '(?i)McAfee|^mf|^mfe|WebAdvisor|TrueKey|SafeConnect' }

    # Vérifier aussi les services actifs
    $ActiveServices = Get-Service -ErrorAction SilentlyContinue |
        Where-Object { ($_.DisplayName -match '(?i)McAfee' -or $_.Name -match '(?i)^McAfee|^mfe') -and $_.Status -eq 'Running' }

    if ($Final -eq 0 -and $ActiveProcesses.Count -eq 0 -and $ActiveServices.Count -eq 0) {
        Write-Log "Tous les composants McAfee ont été supprimés" "OK"
        Write-Log "=== DÉSINSTALLATION MCAFEE TERMINÉE ===" "OK"
        Write-Log "Un redémarrage est recommandé pour finaliser (pilotes)" "WARN"
        exit 0
    }
    else {
        if ($Final -gt 0) {
            Write-Log "$Final produit(s) restent dans le registre" "WARN"
        }
        if ($ActiveProcesses.Count -gt 0) {
            Write-Log "$($ActiveProcesses.Count) processus McAfee encore actifs" "WARN"
            foreach ($Proc in $ActiveProcesses) {
                Write-Log "  → $($Proc.ProcessName)" "WARN"
            }
        }
        if ($ActiveServices.Count -gt 0) {
            Write-Log "$($ActiveServices.Count) services McAfee encore actifs" "WARN"
            foreach ($Svc in $ActiveServices) {
                Write-Log "  → $($Svc.Name)" "WARN"
            }
        }
        Write-Log "=== DÉSINSTALLATION MCAFEE INCOMPLETE ===" "ERROR"
        Write-Log "Un redémarrage est OBLIGATOIRE pour finaliser" "ERROR"
        exit 1
    }
}
catch {
    Write-Log "ERREUR CRITIQUE : $($_.Exception.Message)" "ERROR"
    exit 1
}
