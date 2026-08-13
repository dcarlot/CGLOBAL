#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$LogFolder = "C:\_CGLOBAL\Logs"
$LogFile   = "$LogFolder\Log08_MasquerWidgets.txt"

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

    Write-Log "Masquage du bouton Widgets"

    $RegKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    Write-Log "Cle cible : $RegKey"

    #
    # Creation de la valeur si absente
    #
    if ($null -eq (Get-ItemProperty `
        -Path $RegKey `
        -Name TaskbarDa `
        -ErrorAction SilentlyContinue))
    {
        New-ItemProperty `
            -Path $RegKey `
            -Name "TaskbarDa" `
            -Value 0 `
            -PropertyType DWord `
            -Force | Out-Null
    }

    #
    # Application de la valeur
    #
    Set-ItemProperty `
        -Path $RegKey `
        -Name "TaskbarDa" `
        -Value 0

    Write-Log "Parametre applique" "OK"

    #
    # Verification
    #
    $Value = (
        Get-ItemProperty `
            -Path $RegKey `
            -Name TaskbarDa
    ).TaskbarDa

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