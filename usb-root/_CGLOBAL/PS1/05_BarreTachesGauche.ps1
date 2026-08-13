#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

$LogFile = "C:\_CGLOBAL\Logs\Log05_BarreTachesGauche.txt"

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
Initialize-CGlobalLog -LogFile $LogFile

try {

    Write-Log "Configuration de la barre des taches"

    $RegKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    New-ItemProperty `
        -Path $RegKey `
        -Name "TaskbarAl" `
        -Value 0 `
        -PropertyType DWord `
        -Force | Out-Null

    Write-Log "Alignement a gauche applique" "OK"

    $Value = (
        Get-ItemProperty `
            -Path $RegKey `
            -Name TaskbarAl
    ).TaskbarAl

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