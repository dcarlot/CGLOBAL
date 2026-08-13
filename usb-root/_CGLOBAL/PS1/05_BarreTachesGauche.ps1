#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$LogFolder = "C:\_CGLOBAL\Logs"
$LogFile   = "$LogFolder\Log05_BarreTachesGauche.txt"

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
        (Get-Date -Format "HH:mm:ss"),
        $Level,
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

    Write-Log "Configuration de la barre des taches"

    $RegKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    New-ItemProperty `
        -Path $RegKey `
        -Name "TaskbarAl" `
        -Value 0 `
        -PropertyType DWord `
        -Force | Out-Null

    Write-Log "Alignement a gauche applique" "OK"

    $Value = (
        Get-ItemProperty `
            -Path $RegKey `
            -Name TaskbarAl
    ).TaskbarAl

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