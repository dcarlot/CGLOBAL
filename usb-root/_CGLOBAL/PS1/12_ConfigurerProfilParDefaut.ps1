#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
 Configure le profil utilisateur par defaut de Windows.

.DESCRIPTION
 Charge C:\Users\Default\NTUSER.DAT dans une ruche temporaire,
 applique les reglages utilisateur valides dans la chaine CGLOBAL,
 puis decharge proprement la ruche.

 Les reglages seront appliques uniquement aux nouveaux profils
 utilisateurs crees apres l'execution du script.

 Ce script ne copie pas le profil courant dans son integralite.

.NOTES
 Compatible avec Windows PowerShell 5.1.
 Execution avec privileges administrateur requise.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$LogFolder = "C:\_CGLOBAL\Logs"
$LogFile = "$LogFolder\Log12_ConfigurerProfilParDefaut.txt"

$DefaultProfilePath = Join-Path $env:SystemDrive "Users\Default"
$DefaultHiveFile = Join-Path $DefaultProfilePath "NTUSER.DAT"

$HiveName = "CGLOBAL_DefaultUser"
$HiveRegPath = "HKLM\$HiveName"
$HivePowerShell = "Registry::HKEY_LOCAL_MACHINE\$HiveName"

$HiveLoadedByScript = $false
$WarningCount = 0
$ErrorCount = 0

if (-not (Test-Path $LogFolder)) {
    New-Item `
        -Path $LogFolder `
        -ItemType Directory `
        -Force | Out-Null
}

function Write-Log {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $Line = "[{0}] [{1,-5}] {2}" -f `
        (Get-Date -Format "HH:mm:ss"), `
        $Level, `
        $Message

    Add-Content `
        -Path $LogFile `
        -Value $Line `
        -Encoding UTF8

    $Color = @{
        INFO = 'Cyan'
        OK = 'Green'
        WARN = 'Yellow'
        ERROR = 'Red'
    }

    Write-Host $Line -ForegroundColor $Color[$Level]
}

function Add-Warning {

    param(
        [string]$Message
    )

    $script:WarningCount++
    Write-Log $Message "WARN"
}

function Add-Error {

    param(
        [string]$Message
    )

    $script:ErrorCount++
    Write-Log $Message "ERROR"
}

function Test-RegistryKey {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {

        New-Item `
            -Path $Path `
            -ItemType Directory `
            -Force | Out-Null

        Write-Log "Cle creee : $Path"
    }
}

function Set-DefaultUserDWord {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [int]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    try {

        Test-RegistryKey -Path $Path

        # CORRECTION : Set-ItemProperty au lieu de New-ItemProperty
        # Set-ItemProperty cree ou modifie la valeur existante
        Set-ItemProperty `
            -Path $Path `
            -Name $Name `
            -Value $Value `
            -Force | Out-Null

        $ReadValue = (
            Get-ItemProperty `
                -Path $Path `
                -Name $Name `
                -ErrorAction Stop
        ).$Name

        if ($ReadValue -eq $Value) {
            Write-Log "$Description : valeur $Value appliquee" "OK"
        }
        else {
            Add-Warning "$Description : verification incorrecte, valeur lue=$ReadValue"
        }
    }
    catch {

        Add-Error "$Description : $($_.Exception.Message)"
    }
}

function Set-DefaultUserString {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [AllowEmptyString()]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    try {

        Test-RegistryKey -Path $Path

        # CORRECTION : Set-ItemProperty au lieu de New-ItemProperty
        # New-ItemProperty -Name "(Default)" cree une valeur NOMMEE "(Default)"
        # au lieu de modifier la valeur par defaut de la cle.
        # Set-ItemProperty interprete correctement "(Default)" comme la
        # valeur par defaut native de la cle de registre.
        Set-ItemProperty `
            -Path $Path `
            -Name $Name `
            -Value $Value `
            -Force | Out-Null

        $Property = Get-ItemProperty `
            -Path $Path `
            -Name $Name `
            -ErrorAction Stop

        $ReadValue = $Property.$Name

        if ($ReadValue -eq $Value) {
            Write-Log "$Description applique" "OK"
        }
        else {
            Add-Warning "$Description : verification incorrecte"
        }
    }
    catch {

        Add-Error "$Description : $($_.Exception.Message)"
    }
}

function Mount-DefaultUserHive {

    if (-not (Test-Path $DefaultHiveFile)) {
        throw "Fichier de profil par defaut introuvable : $DefaultHiveFile"
    }

    if (Test-Path $HivePowerShell) {

        Add-Warning "La ruche temporaire $HiveRegPath etait deja chargee"

        $UnloadOutput = & reg.exe unload $HiveRegPath 2>&1
        $UnloadCode = $LASTEXITCODE

        foreach ($Line in $UnloadOutput) {
            if ($null -ne $Line -and $Line.ToString().Trim() -ne "") {
                Write-Log $Line.ToString()
            }
        }

        if ($UnloadCode -ne 0 -and (Test-Path $HivePowerShell)) {
            throw "Impossible de decharger l'ancienne ruche $HiveRegPath"
        }
    }

    Write-Log "Chargement de la ruche : $DefaultHiveFile"

    $LoadOutput = & reg.exe load $HiveRegPath $DefaultHiveFile 2>&1
    $LoadCode = $LASTEXITCODE

    foreach ($Line in $LoadOutput) {
        if ($null -ne $Line -and $Line.ToString().Trim() -ne "") {
            Write-Log $Line.ToString()
        }
    }

    if ($LoadCode -ne 0 -or -not (Test-Path $HivePowerShell)) {
        throw "Echec du chargement de la ruche Default User, code=$LoadCode"
    }

    $script:HiveLoadedByScript = $true

    Write-Log "Ruche Default User chargee sous $HiveRegPath" "OK"
}

function Dismount-DefaultUserHive {

    if (-not $script:HiveLoadedByScript) {
        return
    }

    Write-Log "Fermeture des handles de la ruche Default User"

    Get-Variable `
        -Scope Script `
        -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Value -is [Microsoft.Win32.RegistryKey]
    } |
    ForEach-Object {
        try {
            $_.Value.Close()
        }
        catch {
        }
    }

    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()

    Start-Sleep -Milliseconds 500

    Write-Log "Dechargement de la ruche $HiveRegPath"

    $UnloadOutput = & reg.exe unload $HiveRegPath 2>&1
    $UnloadCode = $LASTEXITCODE

    foreach ($Line in $UnloadOutput) {
        if ($null -ne $Line -and $Line.ToString().Trim() -ne "") {
            Write-Log $Line.ToString()
        }
    }

    if ($UnloadCode -ne 0 -or (Test-Path $HivePowerShell)) {

        Add-Error "Echec du dechargement de la ruche Default User, code=$UnloadCode"

        return
    }

    $script:HiveLoadedByScript = $false

    Write-Log "Ruche Default User dechargee" "OK"
}

try {

    Write-Log "Configuration du profil utilisateur par defaut"
    Write-Log "Profil cible : $DefaultProfilePath"

    Mount-DefaultUserHive

    #
    # 01 - Icones systeme du Bureau
    #
    $DesktopIconsKey = Join-Path `
        $HivePowerShell `
        "Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"

    $DesktopIcons = @(
        @{
            Name = "Ce PC"
            Guid = "{20D04FE0-3AEA-1069-A2D8-08002B30309D}"
        },
        @{
            Name = "Panneau de configuration"
            Guid = "{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}"
        },
        @{
            Name = "Corbeille"
            Guid = "{645FF040-5081-101B-9F08-00AA002F954E}"
        },
        @{
            Name = "Reseau"
            Guid = "{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}"
        }
    )

    Write-Log "Application des icones systeme du Bureau"

    foreach ($Icon in $DesktopIcons) {

        Set-DefaultUserDWord `
            -Path $DesktopIconsKey `
            -Name $Icon.Guid `
            -Value 0 `
            -Description "Icone Bureau $($Icon.Name)"
    }

    #
    # 02 - Menu contextuel classique
    #
    $ContextMenuKey = Join-Path `
        $HivePowerShell `
        "Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"

    Set-DefaultUserString `
        -Path $ContextMenuKey `
        -Name "(Default)" `
        -Value "" `
        -Description "Menu contextuel classique"

    #
    # Cle commune Explorer Advanced
    #
    $ExplorerAdvancedKey = Join-Path `
        $HivePowerShell `
        "Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    #
    # 03 - Explorateur
    #
    Set-DefaultUserDWord `
        -Path $ExplorerAdvancedKey `
        -Name "LaunchTo" `
        -Value 1 `
        -Description "Explorateur ouvert sur Ce PC"

    Set-DefaultUserDWord `
        -Path $ExplorerAdvancedKey `
        -Name "HideFileExt" `
        -Value 0 `
        -Description "Extensions de fichiers visibles"

    #
    # 05 - Barre des taches a gauche
    #
    Set-DefaultUserDWord `
        -Path $ExplorerAdvancedKey `
        -Name "TaskbarAl" `
        -Value 0 `
        -Description "Alignement de la barre des taches a gauche"

    #
    # 06 - Recherche : icone uniquement
    #
    $SearchKey = Join-Path `
        $HivePowerShell `
        "Software\Microsoft\Windows\CurrentVersion\Search"

    Set-DefaultUserDWord `
        -Path $SearchKey `
        -Name "SearchboxTaskbarMode" `
        -Value 1 `
        -Description "Recherche en mode icone uniquement"

    #
    # 07 - Vue des taches masquee
    #
    Set-DefaultUserDWord `
        -Path $ExplorerAdvancedKey `
        -Name "ShowTaskViewButton" `
        -Value 0 `
        -Description "Bouton Vue des taches masque"

    #
    # 10 - Reprendre desactive
    #
    Set-DefaultUserDWord `
        -Path $ExplorerAdvancedKey `
        -Name "IsEnabled" `
        -Value 0 `
        -Description "Fonction Reprendre desactivee"

    #
    # 11 - Notifications lors des demandes de localisation
    #
    $LocationConsentKey = Join-Path `
        $HivePowerShell `
        "Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"

    Set-DefaultUserDWord `
        -Path $LocationConsentKey `
        -Name "ShowGlobalPrompts" `
        -Value 0 `
        -Description "Notifications de demandes de localisation desactivees"

    #
    # 11 - Remplacement de la localisation
    #
    $LocationOverrideKey = Join-Path `
        $HivePowerShell `
        "Software\Microsoft\Windows\CurrentVersion\CPSS\Store\UserLocationOverridePrivacySetting"

    Set-DefaultUserDWord `
        -Path $LocationOverrideKey `
        -Name "Value" `
        -Value 0 `
        -Description "Remplacement de la localisation desactive"

    #
    # 13 - Verrouillage numerique pour les futurs profils
    #
    $KeyboardKey = Join-Path `
        $HivePowerShell `
        "Control Panel\Keyboard"

    Set-DefaultUserString `
        -Path $KeyboardKey `
        -Name "InitialKeyboardIndicators" `
        -Value "2" `
        -Description "Verrouillage numerique configure"

    Write-Log "Reglages du profil par defaut appliques" "OK"
}
catch {

    Add-Error $_.Exception.Message
}
finally {

    Dismount-DefaultUserHive
}

Write-Log "----------------------------------------"
Write-Log "Avertissements : $WarningCount"
Write-Log "Erreurs : $ErrorCount"

if ($ErrorCount -gt 0) {

    Write-Log "Configuration du profil par defaut terminee avec erreurs" "ERROR"

    exit 1
}

if ($WarningCount -gt 0) {

    Write-Log "Configuration du profil par defaut terminee avec avertissements" "WARN"

    exit 0
}

Write-Log "Configuration du profil par defaut terminee avec succes" "OK"

exit 0
