#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Import-Module "C:\\_CGLOBAL\\PS1\\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

try {
    Write-Log "=== DESINSTALLATION ONEDRIVE ===" "INFO"

    # --------------------------------------------
    # 1. DETECTION DE ONEDRIVE
    # --------------------------------------------

    Write-Log "Recherche de OneDrive..." "INFO"

    $OneDriveFound = $false
    $OneDriveDetails = @()
    $UninstallKeyPath = $null
    $UninstallString = $null

    # 1.1 Detection AppX
    $OneDriveAppX = Get-AppxPackage -Name "*OneDrive*" -ErrorAction SilentlyContinue
    if ($null -ne $OneDriveAppX) {
        Write-Log "OneDrive AppX detecte: $($OneDriveAppX.Name)" "WARN"
        $OneDriveFound = $true
        $OneDriveDetails += "AppX: $($OneDriveAppX.Name)"
    }

    # 1.2 Detection OneDrive.exe (version desktop)
    $OneDriveExe = Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
    if ($OneDriveExe) {
        Write-Log "OneDrive.exe detecte: $env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe" "WARN"
        $OneDriveFound = $true
        $OneDriveDetails += "Exe: OneDrive.exe"
    }

    # 1.3 Detection dossier OneDrive (seulement si OneDrive.exe present)
    $OneDriveFolder = Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive"
    if ($OneDriveFolder -and -not $OneDriveExe) {
        Write-Log "Dossier OneDrive present mais OneDrive.exe absent (residu)" "INFO"
    }
    elseif ($OneDriveFolder -and $OneDriveExe) {
        Write-Log "Dossier OneDrive detecte: $env:LOCALAPPDATA\Microsoft\OneDrive" "WARN"
        $OneDriveDetails += "Dossier: $env:LOCALAPPDATA\Microsoft\OneDrive"
    }

    # 1.4 Detection registre (Programmes et fonctionnalites)
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
                        Write-Log "OneDrive detecte dans le registre: $DisplayName" "WARN"
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

    # 1.5 Detection dossier d'installation (seulement si OneDrive.exe present)
    if ($OneDriveExe) {
        $InstallPaths = @(
            "$env:PROGRAMFILES\Microsoft\OneDrive",
            "${env:PROGRAMFILES(X86)}\Microsoft\OneDrive"
        )
        foreach ($Path in $InstallPaths) {
            if (Test-Path $Path) {
                Write-Log "Dossier OneDrive detecte: $Path" "WARN"
                $OneDriveDetails += "Dossier: $Path"
            }
        }
    }

    # 1.6 Resultat
    if (-not $OneDriveFound) {
        Write-Log "OneDrive non installe sur ce poste" "OK"
        Write-Log "Aucune action necessaire" "INFO"
        exit 0
    }

    Write-Log "OneDrive detecte via: $($OneDriveDetails -join ', ')" "WARN"

    # --------------------------------------------
    # 2. DEMANDE DE CONFIRMATION
    # --------------------------------------------

    Write-Log "Demande de confirmation a l'utilisateur" "INFO"

    $Choice = Show-CGlobalPopup `
        -Message "OneDrive est installe sur ce poste.`n`nVoulez-vous le desinstaller ?`n`n- Suppression de la session actuelle`n- Blocage pour les futures sessions`n`nATTENTION: Cette action est irreversible.`nATTENTION: Si OneDrive a ete installe volontairement, cliquez sur NON." `
        -Title "Desinstallation OneDrive" `
        -Buttons "YesNo" `
        -Icon "Exclamation"

    if ($Choice -ne "Yes") {
        Write-Log "Desinstallation OneDrive refusee par l'utilisateur" "WARN"
        exit 0
    }

    Write-Log "Desinstallation OneDrive validee par l'utilisateur" "OK"

    # --------------------------------------------
    # 3. ARRET DU PROCESSUS ONEDRIVE
    # --------------------------------------------

    Write-Log "Arret des processus OneDrive..." "INFO"

    Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    Write-Log "Processus OneDrive arretes" "OK"

    # --------------------------------------------
    # 4. DESINSTALLATION VIA REGISTRE (methode propre)
    # --------------------------------------------
    # On execute le UninstallString AVANT OneDrive.exe /uninstall car
    # OneDrive.exe /uninstall supprime le dossier contenant OneDriveSetup.exe

    $RegUninstallDone = $false

    if ($null -ne $UninstallString -and $UninstallString -ne "") {
        Write-Log "Commande de desinstallation trouvee: $UninstallString" "INFO"

        # Parsing robuste du UninstallString
        # Format possible: "C:\chemin\OneDriveSetup.exe" /uninstall
        #                 C:\chemin\OneDriveSetup.exe /uninstall
        $UninstallString = $UninstallString.Trim()

        $ExePath = $null
        $Arguments = $null

        if ($UninstallString.StartsWith('"')) {
            # Format avec guillemets: "chemin.exe" arguments
            $EndQuote = $UninstallString.IndexOf('"', 1)
            if ($EndQuote -gt 0) {
                $ExePath = $UninstallString.Substring(1, $EndQuote - 1)
                $Arguments = $UninstallString.Substring($EndQuote + 1).Trim()
            }
        }

        if ($null -eq $ExePath -and $UninstallString -match '^(\S+\.exe)\s*(.*)$') {
            # Format sans guillemets: chemin.exe arguments
            $ExePath = $matches[1]
            $Arguments = $matches[2].Trim()
        }

        if ($null -ne $ExePath -and (Test-Path $ExePath)) {
            Write-Log "Execution de la desinstallation via registre: $ExePath $Arguments" "INFO"

            try {
                $Process = Start-Process -FilePath $ExePath -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
                Write-Log "Desinstallation via registre terminee (code: $($Process.ExitCode))" "OK"
                $RegUninstallDone = $true
            }
            catch {
                Write-Log "Echec desinstallation via registre: $($_.Exception.Message)" "WARN"
            }
        }
        else {
            Write-Log "Fichier de desinstallation introuvable: $ExePath" "WARN"
        }
    }
    else {
        Write-Log "Aucune commande de desinstallation trouvee dans le registre" "WARN"
    }

    # --------------------------------------------
    # 5. DESINSTALLATION EXE (fallback si registre echoue)
    # --------------------------------------------

    if (-not $RegUninstallDone -and $OneDriveExe) {
        Write-Log "Desinstallation via OneDrive.exe /uninstall (fallback)..." "INFO"

        try {
            $UninstallPath = "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
            $Process = Start-Process -FilePath $UninstallPath -ArgumentList "/uninstall" -Wait -PassThru -NoNewWindow
            Write-Log "OneDrive.exe /uninstall termine (code: $($Process.ExitCode))" "OK"
        }
        catch {
            Write-Log "Echec desinstallation OneDrive.exe: $($_.Exception.Message)" "ERROR"
        }
    }

    # --------------------------------------------
    # 6. SUPPRESSION DE LA CLE DE REGISTRE UNINSTALL
    # --------------------------------------------
    # Nettoie l'entree dans Programmes et Fonctionnalites

    if ($null -ne $UninstallKeyPath) {
        Write-Log "Suppression de la cle de registre Uninstall..." "INFO"
        try {
            Remove-Item -Path $UninstallKeyPath -Recurse -Force -ErrorAction Stop
            Write-Log "Cle de registre Uninstall supprimee" "OK"
        }
        catch {
            Write-Log "Echec suppression cle de registre: $($_.Exception.Message)" "WARN"
        }
    }

    # --------------------------------------------
    # 7. DESINSTALLATION APPX (si present)
    # --------------------------------------------

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

    # --------------------------------------------
    # 8. NETTOYAGE DOSSIER RESIDUEL
    # --------------------------------------------

    $OneDriveFolder = "$env:LOCALAPPDATA\Microsoft\OneDrive"
    if (Test-Path $OneDriveFolder) {
        Write-Log "Suppression du dossier residuel: $OneDriveFolder" "INFO"
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
    Write-Log "Cle de registre HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive\DisableFileSyncNGSC = 1" "OK"

    # Desactiver OneDrive dans le profil par defaut
    $DefaultNTUSER = "C:\Users\Default\NTUSER.DAT"
    if (Test-Path $DefaultNTUSER) {
        Write-Log "Chargement du profil par defaut (NTUSER.DAT)..." "INFO"

        $LoadResult = Start-Process -FilePath "reg.exe" -ArgumentList "LOAD", "HKU\DefaultProfile", $DefaultNTUSER -Wait -PassThru -NoNewWindow

        if ($LoadResult.ExitCode -eq 0) {
            Start-Sleep -Seconds 1

            $SetResult = Start-Process -FilePath "reg.exe" -ArgumentList "ADD", "HKU\DefaultProfile\SOFTWARE\Policies\Microsoft\Windows\OneDrive", "/v", "DisableFileSyncNGSC", "/t", "REG_DWORD", "/d", "1", "/f" -Wait -PassThru -NoNewWindow

            if ($SetResult.ExitCode -eq 0) {
                Write-Log "Blocage OneDrive applique au profil par defaut (HKU\DefaultProfile)" "OK"
            }
            else {
                Write-Log "Echec application blocage profil par defaut" "ERROR"
            }

            [gc]::Collect()
            Start-Sleep -Seconds 1
            $UnloadResult = Start-Process -FilePath "reg.exe" -ArgumentList "UNLOAD", "HKU\DefaultProfile" -Wait -PassThru -NoNewWindow

            if ($UnloadResult.ExitCode -eq 0) {
                Write-Log "Profil par defaut demonte avec succes" "OK"
            }
            else {
                Write-Log "Echec demontage profil par defaut" "WARN"
            }
        }
        else {
            Write-Log "Echec chargement profil par defaut (code: $($LoadResult.ExitCode))" "ERROR"
        }
    }
    else {
        Write-Log "Profil par defaut introuvable (C:\Users\Default\NTUSER.DAT)" "WARN"
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
            Write-Log "Raccourci supprime: $Shortcut" "OK"
        }
    }

    # --------------------------------------------
    # 11. MESSAGE DE SUCCES
    # --------------------------------------------

    Write-Log "=== DESINSTALLATION ONEDRIVE TERMINEE ===" "OK"

    Show-CGlobalPopup `
        -Message "OneDrive a ete desinstalle avec succes.`n`n- Session actuelle: nettoyee`n- Futures sessions: bloquees." `
        -Title "Succes" `
        -Buttons "OK" `
        -Icon "Information"

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