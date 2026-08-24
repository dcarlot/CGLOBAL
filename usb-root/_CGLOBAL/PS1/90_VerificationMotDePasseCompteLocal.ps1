#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Import-Module "C:\\_CGLOBAL\\PS1\\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

# ------------------------------------------------------------------
# P/Invoke LogonUser : seule methode fiable pour tester un mot de
# passe vide. Contrairement a System.DirectoryServices.DirectoryEntry
# (qui effectue une authentification de type "reseau"), LOGON32_LOGON_
# INTERACTIVE n'est PAS bloque par la strategie de securite "Comptes :
# limiter l'utilisation des mots de passe vides par les comptes locaux
# a l'ouverture de session sur console uniquement" (LimitBlankPasswordUse),
# activee par defaut sur Windows. C'est cette strategie qui faisait
# echouer a tort l'ancien test des lors qu'un mot de passe avait deja
# ete defini une fois puis vide.
# ------------------------------------------------------------------
if (-not ([System.Management.Automation.PSTypeName]'CGlobal.NativeMethods').Type) {
    Add-Type -Namespace CGlobal -Name NativeMethods -MemberDefinition @"
[DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern bool LogonUser(
    string lpszUsername,
    string lpszDomain,
    string lpszPassword,
    int dwLogonType,
    int dwLogonProvider,
    out IntPtr phToken);

[DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
public static extern bool CloseHandle(IntPtr handle);
"@
}

function Test-EmptyPasswordViaLogonUser {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserName
    )

    $LOGON32_LOGON_INTERACTIVE = 2
    $LOGON32_PROVIDER_DEFAULT  = 0
    $TokenHandle = [IntPtr]::Zero

    try {
        $Success = [CGlobal.NativeMethods]::LogonUser(
            $UserName,
            $env:COMPUTERNAME,
            "",
            $LOGON32_LOGON_INTERACTIVE,
            $LOGON32_PROVIDER_DEFAULT,
            [ref]$TokenHandle
        )

        if ($Success) {
            [void][CGlobal.NativeMethods]::CloseHandle($TokenHandle)
            Write-Log "LogonUser (interactif, MDP vide) reussi -> mot de passe vide" "INFO"
            return $false   # authentification reussie avec MDP vide => pas de MDP
        }
        else {
            $LastError = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            Write-Log "LogonUser (interactif, MDP vide) echoue - code erreur Win32: $LastError" "INFO"
            # 1326 = ERROR_LOGON_FAILURE (mauvais mot de passe) -> un MDP est bien defini
            # 1327 = ERROR_INVALID_LOGON_HOURS, 1328 = ERROR_INVALID_WORKSTATION, etc.
            # 1330 = ERROR_PASSWORD_EXPIRED
            # Tout code d'echec ici signifie que le MDP vide a ete rejete => MDP present
            return $true
        }
    }
    catch {
        Write-Log "Exception lors de l'appel LogonUser : $($_.Exception.Message)" "WARN"
        return $null    # indetermine -> on se rabat sur les autres methodes
    }
}

function Test-UserHasPassword {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserName
    )

    # ------------------------------------------------------------------
    # Methode 0 (prioritaire) : LogonUser interactif avec MDP vide
    # C'est la seule methode qui n'est pas biaisee par la strategie
    # LimitBlankPasswordUse. On lui fait confiance en priorite.
    # ------------------------------------------------------------------
    $LogonUserResult = Test-EmptyPasswordViaLogonUser -UserName $UserName
    if ($null -ne $LogonUserResult) {
        return $LogonUserResult
    }
    Write-Log "Resultat LogonUser indetermine, poursuite avec methodes de secours" "WARN"

    # ------------------------------------------------------------------
    # Methode 1 : [ADSI] PasswordAge
    # PasswordAge = 0  -> jamais de mot de passe defini
    # PasswordAge > 0  -> un mot de passe a ete defini (mais peut etre vide maintenant)
    # ------------------------------------------------------------------
    try {
        Write-Log "Verification via [ADSI] PasswordAge..." "INFO"

        $Computer = $env:COMPUTERNAME
        $User = [ADSI]"WinNT://$Computer/$UserName,user"
        $PasswordAge = $User.InvokeGet("PasswordAge")

        Write-Log "[ADSI] PasswordAge = $PasswordAge" "INFO"

        if ($PasswordAge -eq 0) {
            Write-Log "[ADSI] : jamais de mot de passe defini" "INFO"
            return $false
        }

        Write-Log "[ADSI] : un mot de passe a ete defini (age: $PasswordAge s)" "INFO"
    }
    catch {
        Write-Log "Echec [ADSI] PasswordAge : $($_.Exception.Message)" "WARN"
    }

    # ------------------------------------------------------------------
    # Methode 2 : test d'authentification avec mot de passe vide
    # Si l'authentification reussit, le mot de passe est vide.
    # Si elle echoue, le mot de passe est non vide.
    # ------------------------------------------------------------------
    try {
        Write-Log "Test d'authentification avec mot de passe vide..." "INFO"

        $Computer = $env:COMPUTERNAME
        $Entry = New-Object System.DirectoryServices.DirectoryEntry("WinNT://$Computer/$UserName,user", $UserName, "")

        # Force une operation qui necessite l'authentification
        # [void] supprime le warning "variable assigned but never used"
        [void]$Entry.InvokeGet("Name")

        # Si on arrive ici, l'authentification avec MDP vide a reussi
        Write-Log "Authentification avec MDP vide reussie -> MDP est vide" "INFO"
        return $false
    }
    catch [System.Runtime.InteropServices.COMException] {
        $HResult = $_.Exception.HResult
        Write-Log "Authentification avec MDP vide echouee (HResult: $HResult)" "INFO"

        # HResult connus :
        # 0x8007052E = -2147023570 = ERROR_LOGON_FAILURE (mauvais MDP)
        # 0x80070005 = -2147024891 = E_ACCESSDENIED
        # 0x800708C5 = -2147026747 = ERROR_PASSWORD_RESTRICTION
        # Tous indiquent que le MDP n'est pas vide

        Write-Log "Mot de passe non vide (authentification refusee)" "INFO"
        return $true
    }
    catch {
        Write-Log "Exception inattendue lors du test d'authentification : $($_.Exception.Message)" "WARN"
    }

    # ------------------------------------------------------------------
    # Methode 3 : net user (fallback)
    # ------------------------------------------------------------------
    $TempFile = $null
    try {
        Write-Log "Fallback sur net user..." "INFO"

        $TempFile = [System.IO.Path]::GetTempFileName()

        Start-Process -FilePath "cmd.exe" `
            -ArgumentList "/c", "net user `"$UserName`" > `"$TempFile`" 2>&1" `
            -Wait -NoNewWindow -WindowStyle Hidden

        $Lines = Get-Content -Path $TempFile -ErrorAction SilentlyContinue

        if ($null -ne $Lines) {
            foreach ($Line in $Lines) {
                $LineStr = $Line.ToString().Trim()

                if ($LineStr -match "Mot de passe|Password") {
                    Write-Log "net user : [$LineStr]" "INFO"
                }

                if ($LineStr -match "Mot de passe requis" -and $LineStr -match "Non|No") {
                    return $false
                }
                if ($LineStr -match "Mot de passe requis" -and $LineStr -match "Oui|Yes") {
                    return $true
                }
                if ($LineStr -match "Password required" -and $LineStr -match "No|Non") {
                    return $false
                }
                if ($LineStr -match "Password required" -and $LineStr -match "Yes|Oui") {
                    return $true
                }
            }
        }
    }
    catch {
        Write-Log "Echec net user : $($_.Exception.Message)" "WARN"
    }
    finally {
        if ($null -ne $TempFile -and (Test-Path $TempFile)) {
            Remove-Item -Path $TempFile -Force -ErrorAction SilentlyContinue
        }
    }

    # ------------------------------------------------------------------
    # Methode 4 : Get-LocalUser (dernier recours)
    # ------------------------------------------------------------------
    try {
        Write-Log "Fallback sur Get-LocalUser..." "INFO"

        $User = Get-LocalUser -Name $UserName -ErrorAction Stop

        Write-Log "Get-LocalUser : PasswordRequired=$($User.PasswordRequired), PasswordLastSet=$($User.PasswordLastSet)" "INFO"

        if ($User.PasswordRequired) {
            return $true
        }

        if ($null -eq $User.PasswordLastSet) {
            return $false
        }

        return $true
    }
    catch {
        Write-Log "Echec Get-LocalUser : $($_.Exception.Message)" "WARN"
    }

    # ------------------------------------------------------------------
    # Dernier recours : securite par defaut
    # ------------------------------------------------------------------
    Write-Log "Aucune methode fiable - MDP present par defaut" "WARN"
    return $true
}

try {

    Write-Log "Verification du compte utilisateur courant"

    $CurrentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $CurrentUserName = $CurrentIdentity.Name.Split('\\')[-1]

    Write-Log "Utilisateur courant : $CurrentUserName"

    # ------------------------------------------------------------------
    # Verification du mot de passe
    # ------------------------------------------------------------------

    $HasPassword = Test-UserHasPassword -UserName $CurrentUserName

    if ($HasPassword) {
        Write-Log "Compte local protege par un mot de passe" "OK"
        exit 0
    }

    Write-Log "Compte local sans mot de passe detecte" "WARN"

    # ------------------------------------------------------------------
    # POPUP : Demande de confirmation
    # ------------------------------------------------------------------

    $Choice = Show-CGlobalPopup `
        -Message "Le compte local '$CurrentUserName' n'a pas de mot de passe.`n`nSouhaitez-vous definir un mot de passe ?" `
        -Title "Mot de passe requis" `
        -Buttons "YesNo" `
        -Icon "Exclamation"

    if ($Choice -ne "Yes") {
        Write-Log "Creation du mot de passe refusee par l'utilisateur" "WARN"
        exit 0
    }

    # ------------------------------------------------------------------
    # POPUP : Saisie du mot de passe (2 fois)
    # ------------------------------------------------------------------

    do {
        $PasswordForm = New-Object System.Windows.Forms.Form
        $PasswordForm.Text = "Definition du mot de passe"
        $PasswordForm.Width = 450
        $PasswordForm.Height = 280
        $PasswordForm.StartPosition = "CenterScreen"
        $PasswordForm.TopMost = $true
        $PasswordForm.FormBorderStyle = "FixedDialog"
        $PasswordForm.MaximizeBox = $false
        $PasswordForm.MinimizeBox = $false

        $Label1 = New-Object System.Windows.Forms.Label
        $Label1.Text = "Entrez le mot de passe :"
        $Label1.Location = New-Object System.Drawing.Point(20, 20)
        $Label1.Width = 400
        $Label1.Height = 20
        $PasswordForm.Controls.Add($Label1)

        $TextBox1 = New-Object System.Windows.Forms.TextBox
        $TextBox1.Location = New-Object System.Drawing.Point(20, 45)
        $TextBox1.Width = 400
        $TextBox1.PasswordChar = "*"
        $TextBox1.UseSystemPasswordChar = $true
        $PasswordForm.Controls.Add($TextBox1)

        $Label2 = New-Object System.Windows.Forms.Label
        $Label2.Text = "Confirmez le mot de passe :"
        $Label2.Location = New-Object System.Drawing.Point(20, 85)
        $Label2.Width = 400
        $Label2.Height = 20
        $PasswordForm.Controls.Add($Label2)

        $TextBox2 = New-Object System.Windows.Forms.TextBox
        $TextBox2.Location = New-Object System.Drawing.Point(20, 110)
        $TextBox2.Width = 400
        $TextBox2.PasswordChar = "*"
        $TextBox2.UseSystemPasswordChar = $true
        $PasswordForm.Controls.Add($TextBox2)

        $BtnValider = New-Object System.Windows.Forms.Button
        $BtnValider.Text = "Valider"
        $BtnValider.Location = New-Object System.Drawing.Point(120, 160)
        $BtnValider.Width = 90
        $BtnValider.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $PasswordForm.Controls.Add($BtnValider)

        $BtnAnnuler = New-Object System.Windows.Forms.Button
        $BtnAnnuler.Text = "Annuler"
        $BtnAnnuler.Location = New-Object System.Drawing.Point(230, 160)
        $BtnAnnuler.Width = 90
        $BtnAnnuler.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $PasswordForm.Controls.Add($BtnAnnuler)

        $PasswordForm.AcceptButton = $BtnValider
        $PasswordForm.CancelButton = $BtnAnnuler

        $Result = $PasswordForm.ShowDialog()

        if ($Result -ne [System.Windows.Forms.DialogResult]::OK) {
            Write-Log "Saisie du mot de passe annulee" "WARN"
            $PasswordForm.Dispose()
            exit 0
        }

        $Password1 = $TextBox1.Text
        $Password2 = $TextBox2.Text

        $PasswordForm.Dispose()

        if ($Password1 -ne $Password2) {
            $ErrorForm = New-Object System.Windows.Forms.Form
            $ErrorForm.Text = "Erreur"
            $ErrorForm.Width = 350
            $ErrorForm.Height = 150
            $ErrorForm.StartPosition = "CenterScreen"
            $ErrorForm.TopMost = $true

            $ErrorLabel = New-Object System.Windows.Forms.Label
            $ErrorLabel.Text = "Les mots de passe ne correspondent pas."
            $ErrorLabel.Location = New-Object System.Drawing.Point(20, 20)
            $ErrorLabel.Width = 300
            $ErrorForm.Controls.Add($ErrorLabel)

            $ErrorButton = New-Object System.Windows.Forms.Button
            $ErrorButton.Text = "OK"
            $ErrorButton.Location = New-Object System.Drawing.Point(130, 80)
            $ErrorButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $ErrorForm.AcceptButton = $ErrorButton
            $ErrorForm.Controls.Add($ErrorButton)

            $ErrorForm.ShowDialog()
            $ErrorForm.Dispose()
        }

    } while ($Password1 -ne $Password2)

    # Convertir en SecureString
    $SecurePassword = ConvertTo-SecureString -String $Password1 -AsPlainText -Force

    Set-LocalUser -Name $CurrentUserName -Password $SecurePassword

    Write-Log "Mot de passe defini avec succes" "OK"

    Show-CGlobalPopup `
        -Message "Mot de passe applique avec succes." `
        -Title "Succes" `
        -Buttons "OK" `
        -Icon "Information"
}
catch {

    Write-Log $_.Exception.Message "ERROR"

    exit 1
}

Write-Log "Verification du mot de passe terminee" "OK"

exit 0
