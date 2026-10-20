#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

try {

    Write-Log "Configuration de la confidentialité de localisation"

    #
    # Notifier lorsque les applications demandent l'emplacement
    #
    $LocationKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"

    if (-not (Test-Path $LocationKey)) {
        throw "Clé location introuvable"
    }

    New-ItemProperty `
        -Path $LocationKey `
        -Name "ShowGlobalPrompts" `
        -Value 0 `
        -PropertyType DWord `
        -Force | Out-Null

    Write-Log "Notifications de localisation désactivées" "OK"

    #
    # Autoriser le remplacement de la localisation
    # (CORRIGE : test direct sur la clé, plus de variable $OverrideKeyExists non définie)
    #
    $OverrideKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CPSS\Store\UserLocationOverridePrivacySetting"
    $OverrideKeyExists = Test-Path $OverrideKey

    if (-not $OverrideKeyExists) {
        Write-Log "Clé UserLocationOverridePrivacySetting absente : paramètre ignoré" "WARN"
    }
    else {
        New-ItemProperty `
            -Path $OverrideKey `
            -Name "Value" `
            -Value 0 `
            -PropertyType DWord `
            -Force | Out-Null

        Write-Log "Remplacement de la localisation désactivé" "OK"
    }

    #
    # Vérification
    #
    $ShowGlobalPrompts = (
        Get-ItemProperty `
            -Path $LocationKey `
            -Name ShowGlobalPrompts
    ).ShowGlobalPrompts

    if ($ShowGlobalPrompts -ne 0) {
        throw "Vérification ShowGlobalPrompts échouée"
    }

    if ($OverrideKeyExists) {
        $OverrideValue = (
            Get-ItemProperty `
                -Path $OverrideKey `
                -Name Value
        ).Value

        if ($OverrideValue -ne 0) {
            throw "Vérification UserLocationOverridePrivacySetting échouée"
        }
    }

    Write-Log "Vérification OK" "OK"
    Write-Log "Configuration terminée" "OK"
}
catch {

    Write-Log $_.Exception.Message "ERROR"
    exit 1
}