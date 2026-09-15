#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

try {

    Write-Log "Configuration de la barre des tâches"

    $RegKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    New-ItemProperty `
        -Path $RegKey `
        -Name "TaskbarAl" `
        -Value 0 `
        -PropertyType DWord `
        -Force | Out-Null

    Write-Log "Alignement à gauche appliqué" "OK"

    $Value = (
        Get-ItemProperty `
            -Path $RegKey `
            -Name TaskbarAl
    ).TaskbarAl

    if ($Value -ne 0) {
        throw "Vérification échouée"
    }

    Write-Log "Vérification OK" "OK"

    Write-Log "Configuration terminée" "OK"

}
catch {

    Write-Log $_.Exception.Message "ERROR"
    exit 1
}