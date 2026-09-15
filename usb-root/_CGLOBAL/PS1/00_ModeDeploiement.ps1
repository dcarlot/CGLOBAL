#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

# ------------------------------------------------------------------
# Fonctions
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

function Set-DWordValue {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [int]$Value,

        [Parameter(Mandatory)]
        [string]$Description
    )

    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }

    Set-ItemProperty `
        -Path $Path `
        -Name $Name `
        -Type DWord `
        -Value $Value

    Write-Log $Description "OK"
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
        -Arguments @("/change", "standby-timeout-ac", "0") `
        -Description "Veille secteur desactivee"

    Invoke-PowerCfg `
        -Arguments @("/change", "standby-timeout-dc", "0") `
        -Description "Veille batterie desactivee"

    # --------------------------------------------------------------
    # Extinction ecran
    # --------------------------------------------------------------

    Invoke-PowerCfg `
        -Arguments @("/change", "monitor-timeout-ac", "0") `
        -Description "Extinction ecran secteur desactivee"

    Invoke-PowerCfg `
        -Arguments @("/change", "monitor-timeout-dc", "0") `
        -Description "Extinction ecran batterie desactivee"

    # --------------------------------------------------------------
    # Windows Update - blocage pendant le deploiement
    # --------------------------------------------------------------

    $WUKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"

    if (-not (Test-Path $WUKey)) {
        New-Item -Path $WUKey -Force | Out-Null
        Write-Log "Cle Windows Update creee" "OK"
    }

    # Bloque les mises a jour automatiques :
    # recherche, telechargement et installation automatiques.
    Set-DWordValue `
        -Path $WUKey `
        -Name "NoAutoUpdate" `
        -Value 1 `
        -Description "Mises a jour automatiques Windows Update desactivees"

    # Bloque le redemarrage automatique lorsqu'un utilisateur
    # est connecte.
    Set-DWordValue `
        -Path $WUKey `
        -Name "NoAutoRebootWithLoggedOnUsers" `
        -Value 1 `
        -Description "Redemarrage automatique Windows Update bloque"

    # --------------------------------------------------------------
    # Verification
    # --------------------------------------------------------------

    $Settings = Get-ItemProperty -Path $WUKey -ErrorAction Stop

    if (
        $Settings.NoAutoUpdate -eq 1 -and
        $Settings.NoAutoRebootWithLoggedOnUsers -eq 1
    ) {
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