#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$LogFolder = "C:\_CGLOBAL\Logs"
$LogFile   = "$LogFolder\Log10_DesactiverReprendre.txt"

if (-not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}

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

    Add-Content -Path $LogFile -Value $Line -Encoding UTF8

    $Color = @{
        INFO  = 'Cyan'
        OK    = 'Green'
        WARN  = 'Yellow'
        ERROR = 'Red'
    }

    Write-Host $Line -ForegroundColor $Color[$Level]
}

try {

    Write-Log "Desactivation du bouton Reprendre"

    $RegKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    if (-not (Test-Path $RegKey)) {
        throw "Cle registre introuvable"
    }

    New-ItemProperty `
        -Path $RegKey `
        -Name "IsEnabled" `
        -Value 0 `
        -PropertyType DWord `
        -Force | Out-Null

    Write-Log "Parametre applique" "OK"

    $Value = (
        Get-ItemProperty `
            -Path $RegKey `
            -Name IsEnabled
    ).IsEnabled

    if ($Value -ne 0) {
        throw "Verification echouee"
    }

    Write-Log "Verification OK" "OK"

    Write-Log "Configuration terminee" "OK"

}
catch {

    Write-Log $_.Exception.Message "ERROR"
    exit 1
}