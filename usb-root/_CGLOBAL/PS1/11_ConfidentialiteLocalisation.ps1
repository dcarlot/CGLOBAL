#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$LogFolder = "C:\_CGLOBAL\Logs"
$LogFile   = "$LogFolder\Log11_ConfidentialiteLocalisation.txt"

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

    Write-Log "Configuration de la confidentialité de localisation"

    #
    # Notifier lorsque les applications demandent l'emplacement
    #
    $LocationKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"

    if (-not (Test-Path $LocationKey)) {
        throw "Clé location introuvable"
    }

    New-ItemProperty `
        -Path $LocationKey `
        -Name "ShowGlobalPrompts" `
        -Value 0 `
        -PropertyType DWord `
        -Force | Out-Null

    Write-Log "Notifications de localisation désactivées" "OK"

    #
    # Autoriser le remplacement de la localisation
    #
    $OverrideKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CPSS\Store\UserLocationOverridePrivacySetting"

    if (-not (Test-Path $OverrideKey)) {
        Write-Log "Clé UserLocationOverridePrivacySetting absente : paramètre ignoré" "WARN"
    }
	else {

    New-ItemProperty `
        -Path $OverrideKey `
        -Name "Value" `
        -Value 0 `
        -PropertyType DWord `
        -Force | Out-Null

    Write-Log "Remplacement de la localisation désactivé" "OK"
	}

    #
    # Vérification
    #
    $ShowGlobalPrompts = (
        Get-ItemProperty `
            -Path $LocationKey `
            -Name ShowGlobalPrompts
    ).ShowGlobalPrompts

	if ($OverrideKeyExists) {
    $OverrideValue = (
        Get-ItemProperty `
            -Path $OverrideKey `
            -Name Value
    ).Value
	}

    if ($ShowGlobalPrompts -ne 0) {
        throw "Vérification ShowGlobalPrompts échouée"
    }

	if ($OverrideKeyExists) {
		if ($OverrideValue -ne 0) {
			throw "Vérification UserLocationOverridePrivacySetting échouée"
		}
	}


    Write-Log "Vérification OK" "OK"
    Write-Log "Configuration terminée" "OK"
}
catch {

    Write-Log $_.Exception.Message "ERROR"
    exit 1
}