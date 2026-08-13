#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$LogFolder = "C:\_CGLOBAL\Logs"
$LogFile   = "$LogFolder\Log13_NumLockDemarrage.txt"

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

    Write-Log "Activation du Verrouillage Numerique"

    #
    # Utilisateur courant
    #
    $CurrentUserKey = "HKCU:\Control Panel\Keyboard"

    Set-ItemProperty `
        -Path $CurrentUserKey `
        -Name "InitialKeyboardIndicators" `
        -Value "2"

    Write-Log "Utilisateur courant configure" "OK"

    #
    # Ecran de connexion / contexte système
    #
    $DefaultKey = "Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard"

    Set-ItemProperty `
        -Path $DefaultKey `
        -Name "InitialKeyboardIndicators" `
        -Value "2"

    Write-Log "Profil par defaut configure" "OK"

    #
    # Verifications
    #
    $CurrentUserValue = (
        Get-ItemProperty `
            -Path $CurrentUserKey `
            -Name InitialKeyboardIndicators
    ).InitialKeyboardIndicators

    $DefaultValue = (
        Get-ItemProperty `
            -Path $DefaultKey `
            -Name InitialKeyboardIndicators
    ).InitialKeyboardIndicators

    if ($CurrentUserValue -ne "2") {
        throw "Verification HKCU echouee"
    }

    if ($DefaultValue -ne "2") {
        throw "Verification HKU.DEFAULT echouee"
    }

    Write-Log "Verification OK" "OK"

    Write-Log "Configuration terminee" "OK"
}
catch {

    Write-Log $_.Exception.Message "ERROR"
    exit 1
}