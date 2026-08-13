#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

try {

    Write-Log "Configuration de l Explorateur"

    $ExplorerKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    #
    # Ouvrir sur Ce PC
    #
    New-ItemProperty `
        -Path $ExplorerKey `
        -Name "LaunchTo" `
        -Value 1 `
        -PropertyType DWord `
        -Force | Out-Null

    Write-Log "Ouverture par defaut sur Ce PC" "OK"

    #
    # Afficher les extensions
    #
    New-ItemProperty `
        -Path $ExplorerKey `
        -Name "HideFileExt" `
        -Value 0 `
        -PropertyType DWord `
        -Force | Out-Null

    Write-Log "Affichage des extensions active" "OK"

    #
    # Verification
    #
    $LaunchTo   = (Get-ItemProperty -Path $ExplorerKey -Name LaunchTo).LaunchTo
    $HideFileExt = (Get-ItemProperty -Path $ExplorerKey -Name HideFileExt).HideFileExt

    if ($LaunchTo -ne 1) {
        throw "Verification echouee : LaunchTo"
    }

    if ($HideFileExt -ne 0) {
        throw "Verification echouee : HideFileExt"
    }

    Write-Log "Verification OK" "OK"

    Write-Log "Configuration terminee" "OK"

}
catch {

    Write-Log $_.Exception.Message "ERROR"
    exit 1
}