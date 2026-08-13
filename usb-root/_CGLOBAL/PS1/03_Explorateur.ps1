#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$LogFolder = "C:\_CGLOBAL\Logs"
$LogFile = "$LogFolder\Log03_Explorateur.txt"

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

    Write-Log "Configuration de l Explorateur"

    $ExplorerKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    #
    # Ouvrir sur Ce PC
    #
    New-ItemProperty `
        -Path $ExplorerKey `
        -Name "LaunchTo" `
        -Value 1 `
        -PropertyType DWord `
        -Force | Out-Null

    Write-Log "Ouverture par defaut sur Ce PC" "OK"

    #
    # Afficher les extensions
    #
    New-ItemProperty `
        -Path $ExplorerKey `
        -Name "HideFileExt" `
        -Value 0 `
        -PropertyType DWord `
        -Force | Out-Null

    Write-Log "Affichage des extensions active" "OK"

    #
    # Verification
    #
    $LaunchTo   = (Get-ItemProperty -Path $ExplorerKey -Name LaunchTo).LaunchTo
    $HideFileExt = (Get-ItemProperty -Path $ExplorerKey -Name HideFileExt).HideFileExt

    if ($LaunchTo -ne 1) {
        throw "Verification echouee : LaunchTo"
    }

    if ($HideFileExt -ne 0) {
        throw "Verification echouee : HideFileExt"
    }

    Write-Log "Verification OK" "OK"

    Write-Log "Configuration terminee" "OK"

}
catch {

    Write-Log $_.Exception.Message "ERROR"
    exit 1
}