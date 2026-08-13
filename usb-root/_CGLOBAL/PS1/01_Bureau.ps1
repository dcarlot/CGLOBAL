#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$LogFolder = "C:\_CGLOBAL\Logs"
$LogFile = "$LogFolder\Log01_Bureau.txt"

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

    Write-Log "Configuration des icones du Bureau"

    $DesktopKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"

    if (-not (Test-Path $DesktopKey)) {
        New-Item -Path $DesktopKey -Force | Out-Null
    }

    $Icons = @(
        @{ Name="Ce PC" ; Guid="{20D04FE0-3AEA-1069-A2D8-08002B30309D}" }
        @{ Name="Dossier utilisateur" ; Guid="{59031a47-3f72-44a7-89c5-5595fe6b30ee}" }
        @{ Name="Reseau" ; Guid="{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}" }
        @{ Name="Corbeille" ; Guid="{645FF040-5081-101B-9F08-00AA002F954E}" }
        @{ Name="Panneau de configuration" ; Guid="{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}" }
    )

    foreach ($Icon in $Icons) {

        Set-ItemProperty `
            -Path $DesktopKey `
            -Name $Icon.Guid `
            -Value 0 `
            -Type DWord

        Write-Log "$($Icon.Name) active" "OK"
    }

    foreach ($Icon in $Icons) {

        $Value = (Get-ItemProperty -Path $DesktopKey -Name $Icon.Guid).$($Icon.Guid)

        if ($Value -ne 0) {
            throw "Verification echouee : $($Icon.Name)"
        }
    }

    Write-Log "Verification OK" "OK"
    Write-Log "Configuration terminee" "OK"

}
catch {

    Write-Log $_.Exception.Message "ERROR"
    exit 1
}