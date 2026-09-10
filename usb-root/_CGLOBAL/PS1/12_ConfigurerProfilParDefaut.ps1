#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Configure le profil utilisateur par defaut de Windows.

.DESCRIPTION
    Configure les parametres communs des futurs profils en modifiant :
      - C:\Users\Default\NTUSER.DAT pour les parametres HKCU classiques ;
      - C:\Users\Default\AppData\Local\Microsoft\Windows\UsrClass.dat
        pour les parametres HKCU\Software\Classes.

    Le menu contextuel classique est stocke dans UsrClass.dat.
    Le modifier uniquement dans NTUSER.DAT ne se propage donc pas aux nouveaux utilisateurs.

    Les reglages sont appliques uniquement aux nouveaux profils crees apres
    l'execution du script.

.NOTES
    Compatible Windows PowerShell 5.1.
    Execution administrateur requise.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$ModulePath = "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1"
if (-not (Test-Path -LiteralPath $ModulePath)) {
    throw "Module commun introuvable : $ModulePath"
}

Import-Module $ModulePath -Force

$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

$DefaultProfilePath = Join-Path $env:SystemDrive "Users\Default"
$DefaultUserHiveFile = Join-Path $DefaultProfilePath "NTUSER.DAT"
$DefaultClassesHiveFile = Join-Path $DefaultProfilePath "AppData\Local\Microsoft\Windows\UsrClass.dat"

$DefaultUserHiveName = "CGLOBAL_DefaultUser"
$DefaultClassesHiveName = "CGLOBAL_DefaultUserClasses"

$DefaultUserRoot = "Registry::HKEY_LOCAL_MACHINE\$DefaultUserHiveName"
$DefaultClassesRoot = "Registry::HKEY_LOCAL_MACHINE\$DefaultClassesHiveName"

$DefaultUserLoaded = $false
$DefaultClassesLoaded = $false
$WarningCount = 0
$ErrorCount = 0

function Add-CGlobalWarning {
    param([Parameter(Mandatory = $true)][string]$Message)

    $script:WarningCount++
    Write-Log $Message "WARN"
}

function Add-CGlobalError {
    param([Parameter(Mandatory = $true)][string]$Message)

    $script:ErrorCount++
    Write-Log $Message "ERROR"
}

function Invoke-RegCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

    try {
        $output = & reg.exe @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    [PSCustomObject]@{
        Output   = $output
        ExitCode = $exitCode
    }
}

function Write-RegOutput {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Output
    )

    foreach ($line in $Output) {
        if ($null -ne $line -and $line.ToString().Trim() -ne "") {
            Write-Log $line.ToString()
        }
    }
}

function Mount-CGlobalHive {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HiveName,

        [Parameter(Mandatory = $true)]
        [string]$HiveFile,

        [Parameter(Mandatory = $true)]
        [string]$ProviderPath
    )

    if (-not (Test-Path -LiteralPath $HiveFile)) {
        throw "Fichier de ruche introuvable : $HiveFile"
    }

    if (Test-Path -LiteralPath $ProviderPath) {
        Add-CGlobalWarning "La ruche $HiveName etait deja chargee ; tentative de dechargement"

        $unload = Invoke-RegCommand -Arguments @("unload", "HKLM\$HiveName")
        Write-RegOutput -Output $unload.Output

        if ($unload.ExitCode -ne 0 -or (Test-Path -LiteralPath $ProviderPath)) {
            throw "Impossible de decharger la ruche deja chargee : HKLM\$HiveName"
        }
    }

    Write-Log "Chargement de la ruche : $HiveFile"

    $load = Invoke-RegCommand -Arguments @("load", "HKLM\$HiveName", $HiveFile)
    Write-RegOutput -Output $load.Output

    if ($load.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $ProviderPath)) {
        throw "Echec du chargement de la ruche HKLM\$HiveName, code=$($load.ExitCode)"
    }

    Write-Log "Ruche chargee : HKLM\$HiveName" "OK"
    return $true
}

function Dismount-CGlobalHive {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HiveName,

        [Parameter(Mandatory = $true)]
        [string]$ProviderPath
    )

    if (-not (Test-Path -LiteralPath $ProviderPath)) {
        return
    }

    # Aucun objet RegistryKey n'est conserve volontairement :
    # toutes les operations passent par le provider puis sont relachees.
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()
    Start-Sleep -Milliseconds 500

    Write-Log "Dechargement de la ruche HKLM\$HiveName"

    $unload = Invoke-RegCommand -Arguments @("unload", "HKLM\$HiveName")
    Write-RegOutput -Output $unload.Output

    if ($unload.ExitCode -ne 0 -or (Test-Path -LiteralPath $ProviderPath)) {
        Add-CGlobalError "Echec du dechargement de HKLM\$HiveName, code=$($unload.ExitCode)"
        return
    }

    Write-Log "Ruche HKLM\$HiveName dechargee" "OK"
}


function New-DefaultClassesHive {
    <#
        UsrClass.dat peut ne pas exister dans C:\Users\Default.
        Il ne faut surtout pas le creer avec New-Item : cela produirait
        un fichier ordinaire et non une ruche Registry.

        On cree une petite ruche temporaire sous HKLM, puis on la sauvegarde
        avec reg.exe save. Le fichier obtenu est une vraie ruche Registry.
    #>

    if (Test-Path -LiteralPath $DefaultClassesHiveFile) {
        Write-Log "UsrClass.dat existe deja : aucune creation necessaire"
        return
    }

    if (-not (Test-Path -LiteralPath $DefaultClassesDirectory)) {
        New-Item -Path $DefaultClassesDirectory -ItemType Directory -Force | Out-Null
    }

    $temporaryKeyName = "CGLOBAL_CreateDefaultClasses"
    $temporaryRoot = "Registry::HKEY_LOCAL_MACHINE\$temporaryKeyName"

    Write-Log "UsrClass.dat absent du profil Default : creation d'une ruche Registry valide"

    try {
        if (Test-Path -LiteralPath $temporaryRoot) {
            $delete = Invoke-RegCommand -Arguments @("delete", "HKLM\$temporaryKeyName", "/f")
            Write-RegOutput -Output $delete.Output
            if ($delete.ExitCode -ne 0) {
                throw "Impossible de supprimer l'ancienne ruche temporaire HKLM\$temporaryKeyName"
            }
        }

        New-Item -Path $temporaryRoot -Force | Out-Null

        $save = Invoke-RegCommand -Arguments @(
            "save",
            "HKLM\$temporaryKeyName",
            $DefaultClassesHiveFile,
            "/y"
        )
        Write-RegOutput -Output $save.Output

        if ($save.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $DefaultClassesHiveFile)) {
            throw "Impossible de creer la ruche UsrClass.dat, code=$($save.ExitCode)"
        }

        Write-Log "UsrClass.dat cree comme vraie ruche Registry" "OK"
    }
    finally {
        if (Test-Path -LiteralPath $temporaryRoot) {
            $delete = Invoke-RegCommand -Arguments @("delete", "HKLM\$temporaryKeyName", "/f")
            Write-RegOutput -Output $delete.Output
        }
    }
}

function Set-DefaultDWord {
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
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }

        New-ItemProperty `
            -Path $Path `
            -Name $Name `
            -PropertyType DWord `
            -Value $Value `
            -Force | Out-Null

        $read = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name

        if ([int]$read -ne $Value) {
            throw "Verification incorrecte : valeur lue=$read, valeur attendue=$Value"
        }

        Write-Log "$Description : valeur $Value appliquee" "OK"
    }
    catch {
        Add-CGlobalError "$Description : $($_.Exception.Message)"
    }
}

function Set-DefaultString {
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
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }

        New-ItemProperty `
            -Path $Path `
            -Name $Name `
            -PropertyType String `
            -Value $Value `
            -Force | Out-Null

        $read = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name

        if ([string]$read -ne [string]$Value) {
            throw "Verification incorrecte : valeur lue='$read', valeur attendue='$Value'"
        }

        Write-Log "$Description applique" "OK"
    }
    catch {
        Add-CGlobalError "$Description : $($_.Exception.Message)"
    }
}

try {
    Write-Log "Configuration du profil utilisateur par defaut"
    Write-Log "Profil cible : $DefaultProfilePath"
    Write-Log "NTUSER.DAT : $DefaultUserHiveFile"
    Write-Log "UsrClass.dat : $DefaultClassesHiveFile"

    # ------------------------------------------------------------
    # 1. NTUSER.DAT : parametres HKCU classiques
    # ------------------------------------------------------------
    Mount-CGlobalHive `
        -HiveName $DefaultUserHiveName `
        -HiveFile $DefaultUserHiveFile `
        -ProviderPath $DefaultUserRoot | Out-Null
    $DefaultUserLoaded = $true

    $DesktopIconsKey = Join-Path `
        $DefaultUserRoot `
        "Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"

    $DesktopIcons = @(
        @{ Name = "Ce PC"; Guid = "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" }
        @{ Name = "Panneau de configuration"; Guid = "{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}" }
        @{ Name = "Corbeille"; Guid = "{645FF040-5081-101B-9F08-00AA002F954E}" }
        @{ Name = "Reseau"; Guid = "{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}" }
    )

    Write-Log "Application des icones systeme du Bureau"

    foreach ($icon in $DesktopIcons) {
        Set-DefaultDWord `
            -Path $DesktopIconsKey `
            -Name $icon.Guid `
            -Value 0 `
            -Description "Icone Bureau $($icon.Name)"
    }

    $ExplorerAdvancedKey = Join-Path `
        $DefaultUserRoot `
        "Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    Set-DefaultDWord -Path $ExplorerAdvancedKey -Name "LaunchTo" -Value 1 `
        -Description "Explorateur ouvert sur Ce PC"

    Set-DefaultDWord -Path $ExplorerAdvancedKey -Name "HideFileExt" -Value 0 `
        -Description "Extensions de fichiers visibles"

    Set-DefaultDWord -Path $ExplorerAdvancedKey -Name "TaskbarAl" -Value 0 `
        -Description "Alignement de la barre des taches a gauche"

    $SearchKey = Join-Path `
        $DefaultUserRoot `
        "Software\Microsoft\Windows\CurrentVersion\Search"

    Set-DefaultDWord -Path $SearchKey -Name "SearchboxTaskbarMode" -Value 1 `
        -Description "Recherche en mode icone uniquement"

    Set-DefaultDWord -Path $ExplorerAdvancedKey -Name "ShowTaskViewButton" -Value 0 `
        -Description "Bouton Vue des taches masque"

    Set-DefaultDWord -Path $ExplorerAdvancedKey -Name "IsEnabled" -Value 0 `
        -Description "Fonction Reprendre desactivee"

    $LocationConsentKey = Join-Path `
        $DefaultUserRoot `
        "Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"

    Set-DefaultDWord -Path $LocationConsentKey -Name "ShowGlobalPrompts" -Value 0 `
        -Description "Notifications de demandes de localisation desactivees"

    $LocationOverrideKey = Join-Path `
        $DefaultUserRoot `
        "Software\Microsoft\Windows\CurrentVersion\CPSS\Store\UserLocationOverridePrivacySetting"

    Set-DefaultDWord -Path $LocationOverrideKey -Name "Value" -Value 0 `
        -Description "Remplacement de la localisation desactive"

    $KeyboardKey = Join-Path $DefaultUserRoot "Control Panel\Keyboard"

    Set-DefaultString -Path $KeyboardKey -Name "InitialKeyboardIndicators" -Value "2" `
        -Description "Verrouillage numerique configure"

    Write-Log "Parametres NTUSER.DAT appliques" "OK"

    # ------------------------------------------------------------
    # 2. UsrClass.dat : HKCU\Software\Classes
    # ------------------------------------------------------------
    New-DefaultClassesHive

    Mount-CGlobalHive `
        -HiveName $DefaultClassesHiveName `
        -HiveFile $DefaultClassesHiveFile `
        -ProviderPath $DefaultClassesRoot | Out-Null
    $DefaultClassesLoaded = $true

    # IMPORTANT :
    # UsrClass.dat correspond a HKCU\Software\Classes.
    # Il ne faut donc PAS ajouter "Software\Classes" au chemin.
    $ContextMenuKey = Join-Path `
        $DefaultClassesRoot `
        "CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"

    Set-DefaultString `
        -Path $ContextMenuKey `
        -Name "(Default)" `
        -Value "" `
        -Description "Menu contextuel classique (UsrClass.dat)"

    # Verification explicite de la valeur par defaut attendue :
    # elle doit exister et etre une chaine vide, et non "valeur non definie".
    try {
        $contextValue = (Get-ItemProperty `
            -Path $ContextMenuKey `
            -Name "(Default)" `
            -ErrorAction Stop)."(Default)"

        if ($null -ne $contextValue -and [string]$contextValue -ne "") {
            throw "Valeur (Default) incorrecte : '$contextValue'"
        }

        Write-Log "Verification du menu contextuel classique : valeur (Default) vide" "OK"
    }
    catch {
        Add-CGlobalError "Verification du menu contextuel classique : $($_.Exception.Message)"
    }

    Write-Log "Parametres UsrClass.dat appliques" "OK"
}
catch {
    Add-CGlobalError $_.Exception.Message
}
finally {
    if ($DefaultClassesLoaded) {
        Dismount-CGlobalHive `
            -HiveName $DefaultClassesHiveName `
            -ProviderPath $DefaultClassesRoot
    }

    if ($DefaultUserLoaded) {
        Dismount-CGlobalHive `
            -HiveName $DefaultUserHiveName `
            -ProviderPath $DefaultUserRoot
    }
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
