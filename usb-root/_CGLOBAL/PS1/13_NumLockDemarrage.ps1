#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
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

    Write-Log "Utilisateur courant configuré" "OK"

    #
    # Écran de connexion / contexte système
    #
    $DefaultKey = "Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard"

    Set-ItemProperty `
        -Path $DefaultKey `
        -Name "InitialKeyboardIndicators" `
        -Value "2"

    Write-Log "Profil par défaut configuré" "OK"

    #
    # Vérifications
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
        throw "Vérification HKCU échouée"
    }

    if ($DefaultValue -ne "2") {
        throw "Vérification HKU.DEFAULT échouée"
    }

    Write-Log "Vérification OK" "OK"

    Write-Log "Configuration terminée" "OK"
}
catch {

    Write-Log $_.Exception.Message "ERROR"
    exit 1
}