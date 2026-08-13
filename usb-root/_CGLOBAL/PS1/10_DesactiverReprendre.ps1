#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

try {

    Write-Log "Desactivation du bouton Reprendre"

    $RegKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    if (-not (Test-Path $RegKey)) {
        throw "Cle registre introuvable"
    }

    New-ItemProperty `
        -Path $RegKey `
        -Name "IsEnabled" `
        -Value 0 `
        -PropertyType DWord `
        -Force | Out-Null

    Write-Log "Parametre applique" "OK"

    $Value = (
        Get-ItemProperty `
            -Path $RegKey `
            -Name IsEnabled
    ).IsEnabled

    if ($Value -ne 0) {
        throw "Verification echouee"
    }

    Write-Log "Verification OK" "OK"

    Write-Log "Configuration terminee" "OK"

}
catch {

    Write-Log $_.Exception.Message "ERROR"
    exit 1
}