#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$LogFolder = "C:\_CGLOBAL\Logs"
$LogFile   = "$LogFolder\Log06_RechercheBarreTaches.txt"

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

    Write-Log "Configuration de la recherche de la barre des taches"

    $RegKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"

    if (-not (Test-Path $RegKey)) {
        New-Item -Path $RegKey -Force | Out-Null
    }

    New-ItemProperty `
        -Path $RegKey `
        -Name "SearchboxTaskbarMode" `
        -Value 1 `
        -PropertyType DWord `
        -Force | Out-Null

    Write-Log "Mode icone uniquement applique" "OK"

    $Value = (
        Get-ItemProperty `
            -Path $RegKey `
            -Name SearchboxTaskbarMode
    ).SearchboxTaskbarMode

    if ($Value -ne 1) {
        throw "Verification echouee"
    }

    Write-Log "Verification OK" "OK"

    Write-Log "Configuration terminee" "OK"

}
catch {

    Write-Log $_.Exception.Message "ERROR"
    exit 1
}