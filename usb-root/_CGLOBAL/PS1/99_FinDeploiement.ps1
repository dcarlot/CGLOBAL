#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

$LogFile = "C:\_CGLOBAL\Logs\Log99_FinDeploiement.txt"

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
Initialize-CGlobalLog -LogFile $LogFile

# ------------------------------------------------------------------
# PowerCfg wrapper
# ------------------------------------------------------------------

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

# ------------------------------------------------------------------
# Programme principal
# ------------------------------------------------------------------

try {

    Write-Log "Fin de deploiement"

    Write-Host ""
    Write-Host "============================================"
    Write-Host "Le mode deploiement est actuellement actif."
    Write-Host ""
    Write-Host "- Veille desactivee"
    Write-Host "- Extinction ecran desactivee"
    Write-Host "- Reboot automatique Windows Update bloque"
    Write-Host ""
    Write-Host "Restaurer les parametres standards CGLOBAL ?"
    Write-Host ""
    Write-Host "O = Oui"
    Write-Host "N = Non"
    Write-Host "============================================"
    Write-Host ""

    $Choice = Read-Host "Votre choix"

    if ($Choice -notmatch '^[oOnN]$') {

        Write-Log "Choix invalide : aucune modification" "WARN"
        exit 0
    }

    if ($Choice -match '^[nN]$') {

        Write-Log "Mode deploiement conserve" "WARN"
        exit 0
    }

    Write-Log "Restauration des parametres standards"

    # --------------------------------------------------------------
    # Secteur
    # --------------------------------------------------------------

    Invoke-PowerCfg `
        -Arguments @("/change","monitor-timeout-ac","5") `
        -Description "Ecran secteur : 5 minutes"

    Invoke-PowerCfg `
        -Arguments @("/change","standby-timeout-ac","0") `
        -Description "Veille secteur : jamais"

    # --------------------------------------------------------------
    # Batterie
    # --------------------------------------------------------------

    Invoke-PowerCfg `
        -Arguments @("/change","monitor-timeout-dc","5") `
        -Description "Ecran batterie : 5 minutes"

    Invoke-PowerCfg `
        -Arguments @("/change","standby-timeout-dc","30") `
        -Description "Veille batterie : 30 minutes"

    # --------------------------------------------------------------
    # Windows Update
    # --------------------------------------------------------------

    $WUKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"

    if (Test-Path $WUKey) {

        Remove-ItemProperty `
            -Path $WUKey `
            -Name "NoAutoRebootWithLoggedOnUsers" `
            -ErrorAction SilentlyContinue

        Write-Log "Blocage du reboot Windows Update supprime" "OK"
    }

    Write-Log "Parametres standards CGLOBAL appliques" "OK"

    exit 0
}
catch {

    Write-Log $_.Exception.Message "ERROR"

    exit 1
}