#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------

$LogFolder = "C:\_CGLOBAL\Logs"
$LogFile   = "$LogFolder\Log99_FinDeploiement.txt"

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