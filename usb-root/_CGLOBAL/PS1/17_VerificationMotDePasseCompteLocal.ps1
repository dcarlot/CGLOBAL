#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

try {

    Write-Log "Verification du compte utilisateur courant"

    $CurrentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $CurrentUserName = $CurrentIdentity.Name.Split('\')[-1]

    Write-Log "Utilisateur courant : $CurrentUserName"

    # Recherche du compte local
    $LocalUser = Get-LocalUser -Name $CurrentUserName -ErrorAction SilentlyContinue

    if ($null -eq $LocalUser) {
        Write-Log "Le compte courant n'est pas un compte local (Microsoft ou Entra ID)" "OK"
        exit 0
    }

    Write-Log "Compte local detecte" "OK"

    # Verification du mot de passe
    if (-not $LocalUser.PasswordRequired) {

        Write-Log "Le compte local ne possede pas de mot de passe" "WARN"

        # POPUP : Demande de confirmation
        $Choice = Show-CGlobalPopup `
            -Message "Le compte local '$CurrentUserName' n'a pas de mot de passe.`n`nSouhaitez-vous definir un mot de passe ?" `
            -Title "Mot de passe requis" `
            -Buttons "YesNo" `
            -Icon "Exclamation"

        if ($Choice -ne "Yes") {
            Write-Log "Creation du mot de passe refusee par l'utilisateur" "WARN"
            exit 0
        }

        # POPUP : Saisie du mot de passe (2 fois)
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
    else {
        Write-Log "Le compte local est deja protege par un mot de passe" "OK"
    }
}
catch {

    Write-Log $_.Exception.Message "ERROR"

    exit 1
}

Write-Log "Verification du mot de passe terminee" "OK"

exit 0