#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$LogFolder = "C:\_CGLOBAL\Logs"
$LogFile   = "$LogFolder\Log04_ZoneNotification.txt"

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

    Write-Log "Configuration de la zone de notification"

    $NotifyRoot = "HKCU:\Control Panel\NotifyIconSettings"

    if (-not (Test-Path $NotifyRoot)) {

        Write-Log "Cle NotifyIconSettings absente" "WARN"
        Write-Log "Aucune icone connue a traiter" "WARN"
        exit 0
    }

    $Keys = Get-ChildItem -Path $NotifyRoot

    if ($Keys.Count -eq 0) {

        Write-Log "Aucune icone detectee" "WARN"
        exit 0
    }

    Write-Log "$($Keys.Count) icone(s) trouvee(s)"

    $SuccessCount = 0

    foreach ($Key in $Keys) {

        try {

            New-ItemProperty `
                -Path $Key.PSPath `
                -Name "IsPromoted" `
                -Value 1 `
                -PropertyType DWord `
                -Force | Out-Null

            $SuccessCount++
        }
        catch {

            Write-Log "Impossible de modifier : $($Key.PSChildName)" "WARN"
        }
    }

    Write-Log "$SuccessCount icone(s) activee(s)" "OK"

    #
    # Verification
    #

    $Failed = 0

    foreach ($Key in $Keys) {

        try {

            $Value = (
                Get-ItemProperty `
                -Path $Key.PSPath `
                -Name IsPromoted `
                -ErrorAction Stop
            ).IsPromoted

            if ($Value -ne 1) {
                $Failed++
            }

        }
        catch {
            $Failed++
        }
    }

    if ($Failed -gt 0) {

        throw "$Failed verification(s) en echec"
    }

    Write-Log "Verification OK" "OK"

    Write-Log "Configuration terminee" "OK"
}
catch {

    Write-Log $_.Exception.Message "ERROR"
    exit 1
}