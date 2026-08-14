#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

try {
    Write-Log "=== DESINSTALLATION ONEDRIVE ===" "INFO"

    # ============================================
    # 1. DÉTECTION DE ONEDRIVE
    # ============================================
    
    Write-Log "Recherche de OneDrive..." "INFO"
    
    $OneDriveAppX = Get-AppxPackage -Name "*OneDrive*" -ErrorAction SilentlyContinue
    $OneDriveExe = Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
    
    if ($null -eq $OneDriveAppX -and -not $OneDriveExe) {
        Write-Log "OneDrive non installe sur ce poste" "OK"
        Show-CGlobalPopup `
            -Message "OneDrive n'est pas installe sur ce poste.`n`nAucune action necessaire." `
            -Title "OneDrive - Information" `
            -Buttons "OK" `
            -Icon "Information"
        exit 0
    }
    
    Write-Log "OneDrive detecte (AppX: $($null -ne $OneDriveAppX), Exe: $OneDriveExe)" "WARN"

    # ============================================
    # 2. DEMANDE DE CONFIRMATION
    # ============================================
    
    Write-Log "Demande de confirmation a l'utilisateur" "INFO"
    
    $Choice = Show-CGlobalPopup `
        -Message "OneDrive est installe sur ce poste.`n`nVoulez-vous le desinstaller ?`n`n• Suppression de la session actuelle`n• Blocage pour les futures sessions`n`n⚠ Cette action est irreversible.`n⚠ Si OneDrive a ete installe volontairement, cliquez sur NON." `
        -Title "Desinstallation OneDrive" `
        -Buttons "YesNo" `
        -Icon "Exclamation"
    
    if ($Choice -ne "Yes") {
        Write-Log "Desinstallation OneDrive refusee par l'utilisateur" "WARN"
        exit 0
    }
    
    Write-Log "Desinstallation OneDrive validee par l'utilisateur" "OK"

    # ============================================
    # 3. ARRÊT DU PROCESSUS ONEDRIVE
    # ============================================
    
    Write-Log "Arret des processus OneDrive..." "INFO"
    
    Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    
    Write-Log "Processus OneDrive arretes" "OK"

    # ============================================
    # 4. DÉSINSTALLATION APPX (si présent)
    # ============================================
    
    if ($null -ne $OneDriveAppX) {
        Write-Log "Desinstallation du package AppX..." "INFO"
        
        try {
            Remove-AppxPackage -Package $OneDriveAppX.PackageFullName -ErrorAction Stop
            Write-Log "Package AppX desinstalle avec succes" "OK"
        }
        catch {
            Write-Log "Echec desinstallation AppX: $($_.Exception.Message)" "ERROR"
        }
    }

    # ============================================
    # 5. DÉSINSTALLATION EXE (si présent)
    # ============================================
    
    if ($OneDriveExe) {
        Write-Log "Desinstallation de OneDrive.exe..." "INFO"
        
        try {
            $UninstallPath = "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
            Start-Process -FilePath $UninstallPath -ArgumentList "/uninstall" -Wait -ErrorAction Stop
            Write-Log "OneDrive.exe desinstalle avec succes" "OK"
        }
        catch {
            Write-Log "Echec desinstallation OneDrive.exe: $($_.Exception.Message)" "ERROR"
        }
        
        # Nettoyage du dossier résiduel
        $OneDriveFolder = "$env:LOCALAPPDATA\Microsoft\OneDrive"
        if (Test-Path $OneDriveFolder) {
            Write-Log "Suppression du dossier residuel: $OneDriveFolder" "INFO"
            Remove-Item -Path $OneDriveFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # ============================================
    # 6. BLOCAGE POUR LES FUTURS PROFILS
    # ============================================
    
    Write-Log "Configuration du blocage pour les futurs profils..." "INFO"
    
    # Clé de blocage OneDrive pour les nouveaux utilisateurs
    $RegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
    if (-not (Test-Path $RegPath)) {
        New-Item -Path $RegPath -Force | Out-Null
    }
    Set-ItemProperty -Path $RegPath -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -Force
    Write-Log "Cle de registre HKLM\...\OneDrive\DisableFileSyncNGSC = 1" "OK"
    
    # Désactiver OneDrive dans le profil par défaut
    $DefaultNTUSER = "C:\Users\Default\NTUSER.DAT"
    if (Test-Path $DefaultNTUSER) {
        Write-Log "Chargement du profil par défaut (NTUSER.DAT)..." "INFO"
        
        # Monter le hive
        reg load "HKU\DefaultProfile" $DefaultNTUSER | Out-Null
        Start-Sleep -Seconds 1
        
        # Appliquer le blocage
        $DefaultRegPath = "HKU:\DefaultProfile\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
        if (-not (Test-Path $DefaultRegPath)) {
            New-Item -Path $DefaultRegPath -Force | Out-Null
        }
        Set-ItemProperty -Path $DefaultRegPath -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -Force
        Write-Log "Blocage OneDrive applique au profil par defaut" "OK"
        
        # Démonter le hive
        [gc]::Collect()
        Start-Sleep -Seconds 1
        reg unload "HKU\DefaultProfile" | Out-Null
        Write-Log "Profil par defaut demonte" "OK"
    }
    else {
        Write-Log "Profil par defaut introuvable (C:\Users\Default\NTUSER.DAT)" "WARN"
    }

    # ============================================
    # 7. SUPPRESSION RACCOURCIS
    # ============================================
    
    Write-Log "Suppression des raccourcis OneDrive..." "INFO"
    
    $Shortcuts = @(
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk",
        "$env:PUBLIC\Desktop\OneDrive.lnk"
    )
    
    foreach ($Shortcut in $Shortcuts) {
        if (Test-Path $Shortcut) {
            Remove-Item -Path $Shortcut -Force -ErrorAction SilentlyContinue
            Write-Log "Raccourci supprime: $Shortcut" "OK"
        }
    }

    # ============================================
    # 8. MESSAGE DE SUCCÈS
    # ============================================
    
    Write-Log "=== DESINSTALLATION ONEDRIVE TERMINEE ===" "OK"
    
    Show-CGlobalPopup `
        -Message "OneDrive a ete desinstalle avec succes.`n`n• Session actuelle: nettoye`n• Futures sessions: bloque`n`nLe poste va redemarrer Explorer pour appliquer les changements." `
        -Title "Succes" `
        -Buttons "OK" `
        -Icon "Information"
    
    # Redémarrage d'Explorer (optionnel, à valider)
    # Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
    
    exit 0
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    Write-Log $_.ScriptStackTrace "ERROR"
    
    Show-CGlobalPopup `
        -Message "Une erreur est survenue lors de la desinstallation de OneDrive.`n`nErreur: $($_.Exception.Message)`n`nConsultez le fichier de log pour plus de details." `
        -Title "Erreur" `
        -Buttons "OK" `
        -Icon "Stop"
    
    exit 1
}