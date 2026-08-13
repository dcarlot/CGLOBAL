#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

$LogFile = "C:\_CGLOBAL\Logs\Log13_NumLockDemarrage.txt"

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
Initialize-CGlobalLog -LogFile $LogFile

try {

    Write-Log "Activation du Verrouillage Numerique"

    #
    # Utilisateur courant
    #
    $CurrentUserKey = "HKCU:\Control Panel\Keyboard"

    Set-ItemProperty `
        -Path $CurrentUserKey `
        -Name "InitialKeyboardIndicators" `
        -Value "2"

    Write-Log "Utilisateur courant configure" "OK"

    #
    # Ecran de connexion / contexte système
    #
    $DefaultKey = "Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard"

    Set-ItemProperty `
        -Path $DefaultKey `
        -Name "InitialKeyboardIndicators" `
        -Value "2"

    Write-Log "Profil par defaut configure" "OK"

    #
    # Verifications
    #
    $CurrentUserValue = (
        Get-ItemProperty `
            -Path $CurrentUserKey `
            -Name InitialKeyboardIndicators
    ).InitialKeyboardIndicators

    $DefaultValue = (
        Get-ItemProperty `
            -Path $DefaultKey `
            -Name InitialKeyboardIndicators
    ).InitialKeyboardIndicators

    if ($CurrentUserValue -ne "2") {
        throw "Verification HKCU echouee"
    }

    if ($DefaultValue -ne "2") {
        throw "Verification HKU.DEFAULT echouee"
    }

    Write-Log "Verification OK" "OK"

    Write-Log "Configuration terminee" "OK"
}
catch {

    Write-Log $_.Exception.Message "ERROR"
    exit 1
}