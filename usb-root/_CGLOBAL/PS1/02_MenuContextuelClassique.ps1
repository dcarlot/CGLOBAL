#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

$LogFile = "C:\_CGLOBAL\Logs\Log02_MenuContextuelClassique.txt"

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
Initialize-CGlobalLog -LogFile $LogFile

try {

    Write-Log "Configuration du menu contextuel classique"

    $RegKey = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"

    New-Item -Path $RegKey -Force | Out-Null

    Set-ItemProperty `
        -Path $RegKey `
        -Name "(Default)" `
        -Value "" `
        -Force

    $Value = (Get-ItemProperty -Path $RegKey)."(default)"

    if ($null -ne $Value -and $Value -ne "") {
        throw "Verification echouee"
    }

    Write-Log "Verification OK" "OK"
    Write-Log "Configuration terminee" "OK"

}
catch {

    Write-Log $_.Exception.Message "ERROR"
    exit 1
}