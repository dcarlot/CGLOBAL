#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

try {

    Write-Log "Configuration de la recherche de la barre des tâches"

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

    Write-Log "Mode icône uniquement appliqué" "OK"

    $Value = (
        Get-ItemProperty `
            -Path $RegKey `
            -Name SearchboxTaskbarMode
    ).SearchboxTaskbarMode

    if ($Value -ne 1) {
        throw "Vérification échouée"
    }

    Write-Log "Vérification OK" "OK"

    Write-Log "Configuration terminée" "OK"

}
catch {

    Write-Log $_.Exception.Message "ERROR"
    exit 1
}