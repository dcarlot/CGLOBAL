#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$LogFolder = "C:\_CGLOBAL\Logs"
$LogFile = "$LogFolder\Log02_MenuContextuelClassique.txt"

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

    Write-Log "Configuration du menu contextuel classique"

    $RegKey = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"

    New-Item -Path $RegKey -Force | Out-Null

    Set-ItemProperty `
        -Path $RegKey `
        -Name "(Default)" `
        -Value "" `
        -Force

    $Value = (Get-ItemProperty -Path $RegKey)."(default)"

    if ($null -ne $Value -and $Value -ne "") {
        throw "Verification echouee"
    }

    Write-Log "Verification OK" "OK"
    Write-Log "Configuration terminee" "OK"

}
catch {

    Write-Log $_.Exception.Message "ERROR"
    exit 1
}