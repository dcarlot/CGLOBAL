#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Import-Module "C:\\_CGLOBAL\\PS1\\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

try {
    Write-Log "=== DÉSINSTALLATION ONEDRIVE ===" "INFO"

    # --------------------------------------------
    # 1. DÉTECTION DE ONEDRIVE
    # --------------------------------------------

    Write-Log "Recherche de OneDrive..." "INFO"

    $OneDriveFound = $false
    $OneDriveDetails = @()
    $UninstallKeyPath = $null
    $UninstallString = $null

    # 1.1 Detection AppX (utilisateur courant)
    $OneDriveAppX = Get-AppxPackage -Name "*OneDrive*" -ErrorAction SilentlyContinue
    if ($null -ne $OneDriveAppX) {
        Write-Log "OneDrive AppX détecté: $($OneDriveAppX.Name)" "WARN"
        $OneDriveFound = $true
        $OneDriveDetails += "AppX: $($OneDriveAppX.Name)"
    }

    # 1.2 Detection AppX provisionne (tous les utilisateurs)
    $OneDriveAppXProvisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "*OneDrive*" }
    if ($null -ne $OneDriveAppXProvisioned) {
        Write-Log "OneDrive AppX provisionné détecté: $($OneDriveAppXProvisioned.DisplayName)" "WARN"
        $OneDriveFound = $true
        $OneDriveDetails += "AppXProvisioned: $($OneDriveAppXProvisioned.DisplayName)"
    }

    # 1.3 Detection OneDrive.exe (version desktop)
    $OneDriveExe = Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
    if ($OneDriveExe) {
        Write-Log "OneDrive.exe détecté: $env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe" "WARN"
        $OneDriveFound = $true
        $OneDriveDetails += "Exe: OneDrive.exe"
    }

    # 1.4 Detection dossier OneDrive (seulement si OneDrive.exe present)
    $OneDriveFolder = Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive"
    if ($OneDriveFolder -and -not $OneDriveExe) {
        Write-Log "Dossier OneDrive présent mais OneDrive.exe absent (résidu)" "INFO"
    }
    elseif ($OneDriveFolder -and $OneDriveExe) {
        Write-Log "Dossier OneDrive détecté: $env:LOCALAPPDATA\Microsoft\OneDrive" "WARN"
        $OneDriveDetails += "Dossier: $env:LOCALAPPDATA\Microsoft\OneDrive"
    }

    # 1.5 Detection registre (Programmes et fonctionnalites)
    $RegPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($RegPath in $RegPaths) {
        if (Test-Path $RegPath) {
            $UninstallKeys = Get-ChildItem -Path $RegPath -ErrorAction SilentlyContinue
            foreach ($Key in $UninstallKeys) {
                try {
                    $DisplayName = (Get-ItemProperty -Path $Key.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue).DisplayName
                    if ($DisplayName -like "*OneDrive*") {
                        Write-Log "OneDrive détecté dans le registre: $DisplayName" "WARN"
                        $OneDriveFound = $true
                        $OneDriveDetails += "Registre: $DisplayName"
                        $UninstallKeyPath = $Key.PSPath
                        $UninstallString = (Get-ItemProperty -Path $Key.PSPath -Name "UninstallString" -ErrorAction SilentlyContinue).UninstallString
                    }
                }
                catch {
                    # Cle sans DisplayName, on continue
                }
            }
        }
    }

    # 1.6 Detection dossier d'installation (seulement si OneDrive.exe present)
    if ($OneDriveExe) {
        $InstallPaths = @(
            "$env:PROGRAMFILES\Microsoft\OneDrive",
            "${env:PROGRAMFILES(X86)}\Microsoft\OneDrive"
        )
        foreach ($Path in $InstallPaths) {
            if (Test-Path $Path) {
                Write-Log "Dossier OneDrive détecté: $Path" "WARN"
                $OneDriveDetails += "Dossier: $Path"
            }
        }
    }

    # 1.7 Resultat
    if (-not $OneDriveFound) {
        Write-Log "OneDrive non installé sur ce poste" "OK"
        Write-Log "Aucune action nécessaire" "INFO"
        exit 0
    }

    Write-Log "OneDrive détecté via: $($OneDriveDetails -join ', ')" "WARN"

    # --------------------------------------------
    # 2. DEMANDE DE CONFIRMATION
    # --------------------------------------------

    Write-Log "Demande de confirmation à l'utilisateur" "INFO"

    $Choice = Show-CGlobalPopup `
        -Message "OneDrive est installé sur ce poste.`n`nVoulez-vous le désinstaller ?`n`n- Suppression de la session actuelle`n- Blocage pour les futures sessions`n`nATTENTION: Cette action est irreversible.`nATTENTION: Si OneDrive à été installé volontairement, cliquez sur NON." `
        -Title "Désinstallation OneDrive" `
        -Buttons "YesNo" `
        -Icon "Exclamation"

    if ($Choice -ne "Yes") {
        Write-Log "Désinstallation OneDrive refusée par l'utilisateur" "WARN"
        exit 0
    }

    Write-Log "Désinstallation OneDrive validée par l'utilisateur" "OK"

    # --------------------------------------------
    # 3. ARRET DU PROCESSUS ONEDRIVE
    # --------------------------------------------

    Write-Log "Arrêt des processus OneDrive..." "INFO"

    Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    Write-Log "Processus OneDrive arrêtés" "OK"

    # --------------------------------------------
    # 4. DÉSINSTALLATION VIA REGISTRE (methode propre)
    # --------------------------------------------

    $RegUninstallDone = $false

    if ($null -ne $UninstallString -and $UninstallString -ne "") {
        Write-Log "Commande de désinstallation trouvée: $UninstallString" "INFO"

        # Parsing robuste du UninstallString
        $UninstallString = $UninstallString.Trim()

        $ExePath = $null
        $Arguments = $null

        if ($UninstallString.StartsWith('"')) {
            $EndQuote = $UninstallString.IndexOf('"', 1)
            if ($EndQuote -gt 0) {
                $ExePath = $UninstallString.Substring(1, $EndQuote - 1)
                $Arguments = $UninstallString.Substring($EndQuote + 1).Trim()
            }
        }

        if ($null -eq $ExePath -and $UninstallString -match '^(\S+\.exe)\s*(.*)$') {
            $ExePath = $matches[1]
            $Arguments = $matches[2].Trim()
        }

        if ($null -ne $ExePath -and (Test-Path $ExePath)) {
            Write-Log "Execution de la désinstallation via registre: $ExePath $Arguments" "INFO"

            try {
                $Process = Start-Process -FilePath $ExePath -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
                Write-Log "Désinstallation via registre terminee (code: $($Process.ExitCode))" "OK"
                $RegUninstallDone = $true
            }
            catch {
                Write-Log "Échec désinstallation via registre: $($_.Exception.Message)" "WARN"
            }
        }
        else {
            Write-Log "Fichier de désinstallation introuvable: $ExePath" "WARN"
        }
    }
    else {
        Write-Log "Aucune commande de désinstallation trouvée dans le registre" "WARN"
    }

    # --------------------------------------------
    # 5. DÉSINSTALLATION EXE (fallback si registre échoue)
    # --------------------------------------------

    if (-not $RegUninstallDone -and $OneDriveExe) {
        Write-Log "Désinstallation via OneDrive.exe /uninstall (fallback)..." "INFO"

        try {
            $UninstallPath = "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
            $Process = Start-Process -FilePath $UninstallPath -ArgumentList "/uninstall" -Wait -PassThru -NoNewWindow
            Write-Log "OneDrive.exe /uninstall termine (code: $($Process.ExitCode))" "OK"
        }
        catch {
            Write-Log "Échec désinstallation OneDrive.exe: $($_.Exception.Message)" "ERROR"
        }
    }

    # --------------------------------------------
    # 6. SUPPRESSION DE LA CLÉ DE REGISTRE UNINSTALL
    # --------------------------------------------
    # OneDriveSetup.exe supprime souvent la clé lui-meme.
    # Si elle est déjà absente, c'est le résultat souhaite.

    if ($null -ne $UninstallKeyPath) {
        Write-Log "Suppression de la clé de registre Uninstall..." "INFO"
        if (Test-Path $UninstallKeyPath) {
            try {
                Remove-Item -Path $UninstallKeyPath -Recurse -Force -ErrorAction Stop
                Write-Log "Clé de registre Uninstall supprimée" "OK"
            }
            catch {
                Write-Log "Échec suppression clé de registre: $($_.Exception.Message)" "WARN"
            }
        }
        else {
            Write-Log "Clé de registre Uninstall déjà supprimée (par le désinstalleur)" "OK"
        }
    }

    # --------------------------------------------
    # 7. DÉSINSTALLATION APPX (si présent)
    # --------------------------------------------

    # 7.1 Package AppX utilisateur courant
    if ($null -ne $OneDriveAppX) {
        Write-Log "Désinstallation du package AppX utilisateur..." "INFO"

        try {
            Remove-AppxPackage -Package $OneDriveAppX.PackageFullName -ErrorAction Stop
            Write-Log "Package AppX désinstallé avec succès" "OK"
        }
        catch {
            $ErrorMsg = $_.Exception.Message
            if ($ErrorMsg -match '0x80073CF1|package introuvable|package is not installed') {
                Write-Log "Package AppX déjà supprimé ou non installé pour cet utilisateur" "INFO"
            }
            else {
                Write-Log "Échec désinstallation AppX: $ErrorMsg" "WARN"
            }
        }
    }

    # 7.2 Package AppX provisionne (tous les utilisateurs)
    if ($null -ne $OneDriveAppXProvisioned) {
        Write-Log "Désinstallation du package AppX provisionné..." "INFO"

        try {
            Remove-AppxProvisionedPackage -Online -PackageName $OneDriveAppXProvisioned.PackageName -ErrorAction Stop
            Write-Log "Package AppX provisionné désinstallé avec succès" "OK"
        }
        catch {
            $ErrorMsg = $_.Exception.Message
            if ($ErrorMsg -match '0x80073CF1|package introuvable|package is not installed') {
                Write-Log "Package AppX provisionné déjà supprimé" "INFO"
            }
            else {
                Write-Log "Échec désinstallation AppX provisionné: $ErrorMsg" "WARN"
            }
        }
    }

    # --------------------------------------------
    # 8. NETTOYAGE DOSSIER RÉSIDUEL
    # --------------------------------------------

    $OneDriveFolder = "$env:LOCALAPPDATA\Microsoft\OneDrive"
    if (Test-Path $OneDriveFolder) {
        Write-Log "Suppression du dossier résiduel: $OneDriveFolder" "INFO"
        Remove-Item -Path $OneDriveFolder -Recurse -Force -ErrorAction SilentlyContinue
    }

    # --------------------------------------------
    # 9. BLOCAGE POUR LES FUTURS PROFILS
    # --------------------------------------------

    Write-Log "Configuration du blocage pour les futurs profils..." "INFO"

    # Cle de blocage OneDrive pour les nouveaux utilisateurs (HKLM)
    $RegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
    if (-not (Test-Path $RegPath)) {
        New-Item -Path $RegPath -Force | Out-Null
    }
    Set-ItemProperty -Path $RegPath -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -Force
    Write-Log "Clé de registre HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive\DisableFileSyncNGSC = 1" "OK"

    # désactiver OneDrive dans le profil par défaut
    $DefaultNTUSER = "C:\Users\Default\NTUSER.DAT"
    if (Test-Path $DefaultNTUSER) {
        Write-Log "Chargement du profil par défaut (NTUSER.DAT)..." "INFO"

        $LoadResult = Start-Process -FilePath "reg.exe" -ArgumentList "LOAD", "HKU\DefaultProfile", $DefaultNTUSER -Wait -PassThru -NoNewWindow

        if ($LoadResult.ExitCode -eq 0) {
            Start-Sleep -Seconds 1

            $SetResult = Start-Process -FilePath "reg.exe" -ArgumentList "ADD", "HKU\DefaultProfile\SOFTWARE\Policies\Microsoft\Windows\OneDrive", "/v", "DisableFileSyncNGSC", "/t", "REG_DWORD", "/d", "1", "/f" -Wait -PassThru -NoNewWindow

            if ($SetResult.ExitCode -eq 0) {
                Write-Log "Blocage OneDrive appliqué au profil par défaut (HKU\DefaultProfile)" "OK"
            }
            else {
                Write-Log "Échec application blocage profil par défaut" "ERROR"
            }

            [gc]::Collect()
            Start-Sleep -Seconds 1
            $UnloadResult = Start-Process -FilePath "reg.exe" -ArgumentList "UNLOAD", "HKU\DefaultProfile" -Wait -PassThru -NoNewWindow

            if ($UnloadResult.ExitCode -eq 0) {
                Write-Log "Profil par défaut démonté avec succès" "OK"
            }
            else {
                Write-Log "Échec démontage profil par défaut" "WARN"
            }
        }
        else {
            Write-Log "Échec chargement profil par défaut (code: $($LoadResult.ExitCode))" "ERROR"
        }
    }
    else {
        Write-Log "Profil par défaut introuvable (C:\Users\Default\NTUSER.DAT)" "WARN"
    }

    # --------------------------------------------
    # 10. SUPPRESSION RACCOURCIS
    # --------------------------------------------

    Write-Log "Suppression des raccourcis OneDrive..." "INFO"

    $Shortcuts = @(
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk",
        "$env:PUBLIC\Desktop\OneDrive.lnk"
    )

    foreach ($Shortcut in $Shortcuts) {
        if (Test-Path $Shortcut) {
            Remove-Item -Path $Shortcut -Force -ErrorAction SilentlyContinue
            Write-Log "Raccourci supprimé: $Shortcut" "OK"
        }
    }

    # --------------------------------------------
    # 11. MESSAGE DE SUCCES
    # --------------------------------------------

    Write-Log "=== DÉSINSTALLATION ONEDRIVE TERMINÉE ===" "OK"

    # Show-CGlobalPopup `
    #     -Message "OneDrive a ete desinstalle avec succes.`n`n- Session actuelle: nettoyee`n- Futures sessions: bloquees." `
    #     -Title "Succes" `
    #     -Buttons "OK" `
    #     -Icon "Information"

    exit 0
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    Write-Log $_.ScriptStackTrace "ERROR"

    Show-CGlobalPopup `
        -Message "Une erreur est survenue lors de la désinstallation de OneDrive.`n`nErreur: $($_.Exception.Message)`n`nConsultez le fichier de log pour plus de details." `
        -Title "Erreur" `
        -Buttons "OK" `
        -Icon "Stop"

    exit 1
}
