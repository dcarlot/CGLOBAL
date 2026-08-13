#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

$LogFile = "C:\_CGLOBAL\Logs\Log06_RechercheBarreTaches.txt"

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
Initialize-CGlobalLog -LogFile $LogFile

try {

    Write-Log "Configuration de la recherche de la barre des taches"

    $RegKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"

    if (-not (Test-Path $RegKey)) {
        New-Item -Path $RegKey -Force | Out-Null
    }

    New-ItemProperty `
        -Path $RegKey `
        -Name "SearchboxTaskbarMode" `
        -Value 1 `
        -PropertyType DWord `
        -Force | Out-Null

    Write-Log "Mode icone uniquement applique" "OK"

    $Value = (
        Get-ItemProperty `
            -Path $RegKey `
            -Name SearchboxTaskbarMode
    ).SearchboxTaskbarMode

    if ($Value -ne 1) {
        throw "Verification echouee"
    }

    Write-Log "Verification OK" "OK"

    Write-Log "Configuration terminee" "OK"

}
catch {

    Write-Log $_.Exception.Message "ERROR"
    exit 1
}