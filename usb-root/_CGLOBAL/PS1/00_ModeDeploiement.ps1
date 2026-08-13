#Requires -RunAsAdministrator

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------

$LogFolder = "C:\_CGLOBAL\Logs"
$LogFile   = "$LogFolder\Log00_ModeDeploiement.txt"

# ------------------------------------------------------------------
# Initialisation
# ------------------------------------------------------------------

if (-not (Test-Path $LogFolder)) {
    New-Item `
        -Path $LogFolder `
        -ItemType Directory `
        -Force | Out-Null
}

# ------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------

function Write-Log {

    param(
        [string]$Message,

        [ValidateSet('INFO','OK','WARN','ERROR')]
        [string]$Level = 'INFO'
    )

    $Line = "[{0}] [{1,-5}] {2}" -f `
        (Get-Date -Format "HH:mm:ss"), `
        $Level, `
        $Message

    Add-Content `
        -Path $LogFile `
        -Value $Line `
        -Encoding UTF8

    $Color = @{
        INFO  = 'Cyan'
        OK    = 'Green'
        WARN  = 'Yellow'
        ERROR = 'Red'
    }

    Write-Host $Line -ForegroundColor $Color[$Level]
}

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