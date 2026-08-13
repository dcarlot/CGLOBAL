$script:CGLOBAL_LogFolder = "C:\_CGLOBAL\Logs"
$script:CGLOBAL_LogFile   = $null

function Initialize-CGlobalLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )

    $script:CGLOBAL_LogFile = $LogFile

    $LogDirectory = Split-Path -Path $LogFile -Parent

    if (-not (Test-Path -Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path -Path $LogFile)) {
        New-Item -Path $LogFile -ItemType File -Force | Out-Null
    }

    return $script:CGLOBAL_LogFile
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    if (-not $script:CGLOBAL_LogFile) {
        $script:CGLOBAL_LogFile = Join-Path $script:CGLOBAL_LogFolder "CGLOBAL_Common.log"
        if (-not (Test-Path (Split-Path $script:CGLOBAL_LogFile -Parent))) {
            New-Item -Path (Split-Path $script:CGLOBAL_LogFile -Parent) -ItemType Directory -Force | Out-Null
        }
    }

    $Line = "[{0}] [{1,-5}] {2}" -f `
        (Get-Date -Format "HH:mm:ss"), `
        $Level, `
        $Message

    Add-Content -Path $script:CGLOBAL_LogFile -Value $Line -Encoding UTF8

    $Color = @{
        INFO  = 'Cyan'
        OK    = 'Green'
        WARN  = 'Yellow'
        ERROR = 'Red'
    }

    Write-Host $Line -ForegroundColor $Color[$Level]
}

Export-ModuleMember -Function Initialize-CGlobalLog, Write-Log
