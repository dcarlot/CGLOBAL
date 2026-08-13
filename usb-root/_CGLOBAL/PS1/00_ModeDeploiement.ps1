#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------

$LogFile = "C:\_CGLOBAL\Logs\Log00_ModeDeploiement.txt"

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
Initialize-CGlobalLog -LogFile $LogFile

# ------------------------------------------------------------------
# PowerCfg
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

    Write-Log "Activation du mode deploiement"

    # --------------------------------------------------------------
    # Veille
    # --------------------------------------------------------------

    Invoke-PowerCfg `
        -Arguments @("/change","standby-timeout-ac","0") `
        -Description "Veille secteur desactivee"

    Invoke-PowerCfg `
        -Arguments @("/change","standby-timeout-dc","0") `
        -Description "Veille batterie desactivee"

    # --------------------------------------------------------------
    # Extinction ecran
    # --------------------------------------------------------------

    Invoke-PowerCfg `
        -Arguments @("/change","monitor-timeout-ac","0") `
        -Description "Extinction ecran secteur desactivee"

    Invoke-PowerCfg `
        -Arguments @("/change","monitor-timeout-dc","0") `
        -Description "Extinction ecran batterie desactivee"

    # --------------------------------------------------------------
    # Windows Update
    # --------------------------------------------------------------

    $WUKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"

    if (-not (Test-Path $WUKey)) {

        New-Item `
            -Path $WUKey `
            -Force | Out-Null

        Write-Log "Cle Windows Update creee" "OK"
    }

    Set-ItemProperty `
        -Path $WUKey `
        -Name "NoAutoRebootWithLoggedOnUsers" `
        -Type DWord `
        -Value 1

    Write-Log "Redemarrage automatique Windows Update bloque" "OK"

    # --------------------------------------------------------------
    # Verification
    # --------------------------------------------------------------

    $Value = Get-ItemProperty `
        -Path $WUKey `
        -Name "NoAutoRebootWithLoggedOnUsers" `
        -ErrorAction Stop

    if ($Value.NoAutoRebootWithLoggedOnUsers -eq 1) {
        Write-Log "Verification Windows Update OK" "OK"
    }
    else {
        Write-Log "Verification Windows Update KO" "WARN"
    }

    Write-Log "Mode deploiement actif" "OK"

    exit 0
}
catch {

    Write-Log $_.Exception.Message "ERROR"

    exit 1
}