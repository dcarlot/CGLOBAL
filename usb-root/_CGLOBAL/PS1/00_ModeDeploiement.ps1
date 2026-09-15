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

    Write-Log "Activation du mode déploiement"

    # --------------------------------------------------------------
    # Veille
    # --------------------------------------------------------------

    Invoke-PowerCfg `
        -Arguments @("/change", "standby-timeout-ac", "0") `
        -Description "Veille secteur désactivée"

    Invoke-PowerCfg `
        -Arguments @("/change", "standby-timeout-dc", "0") `
        -Description "Veille batterie désactivée"

    # --------------------------------------------------------------
    # Extinction ecran
    # --------------------------------------------------------------

    Invoke-PowerCfg `
        -Arguments @("/change", "monitor-timeout-ac", "0") `
        -Description "Extinction écran secteur désactivée"

    Invoke-PowerCfg `
        -Arguments @("/change", "monitor-timeout-dc", "0") `
        -Description "Extinction écran batterie désactivée"

    # --------------------------------------------------------------
    # Windows Update - blocage pendant le déploiement
    # --------------------------------------------------------------

    $WUKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"

    if (-not (Test-Path $WUKey)) {
        New-Item -Path $WUKey -Force | Out-Null
        Write-Log "Cle Windows Update créée" "OK"
    }

    # Bloque les mises a jour automatiques :
    # recherche, téléchargement et installation automatiques.
    Set-DWordValue `
        -Path $WUKey `
        -Name "NoAutoUpdate" `
        -Value 1 `
        -Description "Mises a jour automatiques Windows Update désactivées"

    # Bloque le redémarrage automatique lorsqu'un utilisateur
    # est connecté.
    Set-DWordValue `
        -Path $WUKey `
        -Name "NoAutoRebootWithLoggedOnUsers" `
        -Value 1 `
        -Description "Redémarrage automatique Windows Update bloqué"

    # --------------------------------------------------------------
    # Verification
    # --------------------------------------------------------------

    $Settings = Get-ItemProperty -Path $WUKey -ErrorAction Stop

    if (
        $Settings.NoAutoUpdate -eq 1 -and
        $Settings.NoAutoRebootWithLoggedOnUsers -eq 1
    ) {
        Write-Log "Vérification Windows Update OK" "OK"
    }
    else {
        Write-Log "Vérification Windows Update KO" "WARN"
    }

    Write-Log "Mode déploiement actif" "OK"

    exit 0
}
catch {

    Write-Log $_.Exception.Message "ERROR"

    exit 1
}