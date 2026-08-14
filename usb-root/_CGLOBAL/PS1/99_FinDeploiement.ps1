#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

function Invoke-PowerCfg {
    param(
        [string[]]$Arguments,
        [string]$Description
    )
    try {
        & powercfg.exe @Arguments | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Log $Description "OK"
        }
        else {
            Write-Log "$Description (code $LASTEXITCODE)" "WARN"
        }
    }
    catch {
        Write-Log "$Description : $($_.Exception.Message)" "WARN"
    }
}

try {
    Write-Log "Fin de deploiement"
    
    $Choice = Show-CGlobalPopup `
        -Message "Le mode deploiement est actuellement actif.`n`n- Veille desactivee`n- Extinction ecran desactivee`n- Reboot automatique Windows Update bloque`n`nRestaurer les parametres standards CGLOBAL ?" `
        -Title "Fin de deploiement" `
        -Buttons "YesNo" `
        -Icon "Question"

    if ($Choice -ne 'Yes') {
        Write-Log "Mode deploiement conserve" "WARN"
        exit 0
    }

    Write-Log "Restauration des parametres standards"

    Invoke-PowerCfg -Arguments @("/change","monitor-timeout-ac","5") -Description "Ecran secteur : 5 minutes"
    Invoke-PowerCfg -Arguments @("/change","standby-timeout-ac","0") -Description "Veille secteur : jamais"
    Invoke-PowerCfg -Arguments @("/change","monitor-timeout-dc","5") -Description "Ecran batterie : 5 minutes"
    Invoke-PowerCfg -Arguments @("/change","standby-timeout-dc","30") -Description "Veille batterie : 30 minutes"

    $WUKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    if (Test-Path $WUKey) {
        Remove-ItemProperty -Path $WUKey -Name "NoAutoRebootWithLoggedOnUsers" -ErrorAction SilentlyContinue
        Write-Log "Blocage du reboot Windows Update supprime" "OK"
    }

    Write-Log "Parametres standards CGLOBAL appliques" "OK"
    
    Show-CGlobalPopup `
        -Message "Parametres standards CGLOBAL appliques avec succes.`n`nLe deploiement est termine." `
        -Title "Deploiement termine" `
        -Buttons "OK" `
        -Icon "Information"

    exit 0
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    exit 1
}