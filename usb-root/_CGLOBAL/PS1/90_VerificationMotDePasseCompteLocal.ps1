#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

# ============================================================
# API Windows LogonUser pour test d'authentification
# ============================================================
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class AuthHelper {
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool LogonUser(string lpszUsername, string lpszDomain, string lpszPassword, int dwLogonType, int dwLogonProvider, out IntPtr phToken);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);

    public const int LOGON32_LOGON_INTERACTIVE = 2;
    public const int LOGON32_PROVIDER_DEFAULT = 0;
    public const int ERROR_LOGON_FAILURE = 1326;
    public const int ERROR_ACCOUNT_RESTRICTION = 1327;
}
"@

function Test-UserHasPassword {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserName
    )

    # ------------------------------------------------------------------
    # Methode 1 : [ADSI] PasswordAge
    # PasswordAge = 0  -> jamais de mot de passe defini
    # PasswordAge > 0  -> un mot de passe a ete defini (peut etre vide maintenant)
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
    # Methode 2 : LogonUser avec mot de passe vide (API Windows native)
    # C'est la methode la plus fiable pour detecter un MDP vide.
    # Si l'authentification reussit avec MDP vide -> MDP est vide.
    # Si elle echoue avec ERROR_LOGON_FAILURE (1326) -> MDP est non vide.
    # ------------------------------------------------------------------
    try {
        Write-Log "Test d'authentification Windows avec mot de passe vide (LogonUser)..." "INFO"

        $Token = [IntPtr]::Zero
        $Result = [AuthHelper]::LogonUser($UserName, ".", "", [AuthHelper]::LOGON32_LOGON_INTERACTIVE, [AuthHelper]::LOGON32_PROVIDER_DEFAULT, [ref]$Token)

        if ($Result) {
            # Authentification avec MDP vide REUSSIE -> le MDP est vide
            [void][AuthHelper]::CloseHandle($Token)
            Write-Log "LogonUser : authentification avec MDP vide REUSSIE -> MDP est vide" "INFO"
            return $false
        }
        else {
            $ErrorCode = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            Write-Log "LogonUser : echec (code Win32: $ErrorCode)" "INFO"

            if ($ErrorCode -eq [AuthHelper]::ERROR_LOGON_FAILURE) {
                # Mauvais mot de passe = le MDP n'est PAS vide
                Write-Log "LogonUser : ERROR_LOGON_FAILURE (1326) -> MDP est NON vide" "INFO"
                return $true
            }
            elseif ($ErrorCode -eq [AuthHelper]::ERROR_ACCOUNT_RESTRICTION) {
                # Compte avec restriction (ex: MDP vide interdit par politique)
                # Dans ce cas, le MDP est vide mais on ne peut pas l'utiliser
                Write-Log "LogonUser : ERROR_ACCOUNT_RESTRICTION (1327) -> MDP vide mais interdit" "INFO"
                return $false
            }
            else {
                Write-Log "LogonUser : code d'erreur inattendu ($ErrorCode)" "WARN"
            }
        }
    }
    catch {
        Write-Log "Exception LogonUser : $($_.Exception.Message)" "WARN"
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
    # POPUP : Saisie du mot de passe (boucle jusqu'a validation)
    # ------------------------------------------------------------------

    $PasswordValid = $false

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

        # ------------------------------------------------------------------
        # Verification : mot de passe vide refuse (retour en boucle)
        # ------------------------------------------------------------------
        if ([string]::IsNullOrWhiteSpace($Password1)) {
            Write-Log "Mot de passe vide refuse" "WARN"
            Show-CGlobalPopup `
                -Message "Le mot de passe ne peut pas etre vide.`n`nVeuillez saisir un mot de passe valide." `
                -Title "Mot de passe invalide" `
                -Buttons "OK" `
                -Icon "Exclamation"
            continue
        }

        # ------------------------------------------------------------------
        # Verification : correspondance des deux saisies
        # ------------------------------------------------------------------
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
            continue
        }

        $PasswordValid = $true

    } while (-not $PasswordValid)

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
