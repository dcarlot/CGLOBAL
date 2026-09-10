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

    Les reglages sont appliques uniquement aux nouveaux profils crees apres
    l'execution du script.
.NOTES
    Compatible Windows PowerShell 5.1.
    Execution administrateur requise.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$ModulePath = 'C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1'
if (-not (Test-Path -LiteralPath $ModulePath)) {
    throw "Module commun introuvable : $ModulePath"
}

Import-Module $ModulePath -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

$DefaultProfilePath       = Join-Path $env:SystemDrive 'Users\Default'
$DefaultUserHiveFile      = Join-Path $DefaultProfilePath 'NTUSER.DAT'
$DefaultClassesHiveFile   = Join-Path $DefaultProfilePath 'AppData\Local\Microsoft\Windows\UsrClass.dat'
$DefaultClassesDirectory  = Split-Path -Path $DefaultClassesHiveFile -Parent

$DefaultUserHiveName      = 'CGLOBAL_DefaultUser'
$DefaultClassesHiveName   = 'CGLOBAL_DefaultUserClasses'
$DefaultUserRoot          = "Registry::HKEY_LOCAL_MACHINE\$DefaultUserHiveName"
$DefaultClassesRoot       = "Registry::HKEY_LOCAL_MACHINE\$DefaultClassesHiveName"

$DefaultUserLoaded = $false
$DefaultClassesLoaded = $false
$WarningCount = 0
$ErrorCount = 0

function Add-CGlobalWarning {
    param([Parameter(Mandatory = $true)][string]$Message)
    $script:WarningCount++
    Write-Log $Message 'WARN'
}

function Add-CGlobalError {
    param([Parameter(Mandatory = $true)][string]$Message)
    $script:ErrorCount++
    Write-Log $Message 'ERROR'
}

function Invoke-RegCommand {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $PreviousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $Output = @(& reg.exe @Arguments 2>&1)
        $ExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousPreference
    }

    [PSCustomObject]@{
        Output   = $Output
        ExitCode = $ExitCode
    }
}

function Write-RegOutput {
    param([AllowNull()][object[]]$Output)

    if ($null -eq $Output) {
        return
    }

    foreach ($Line in $Output) {
        if ($null -ne $Line -and -not [string]::IsNullOrWhiteSpace($Line.ToString())) {
            Write-Log $Line.ToString()
        }
    }
}

function Mount-CGlobalHive {
    param(
        [Parameter(Mandatory = $true)][string]$HiveName,
        [Parameter(Mandatory = $true)][string]$HiveFile,
        [Parameter(Mandatory = $true)][string]$ProviderPath
    )

    if (-not (Test-Path -LiteralPath $HiveFile)) {
        throw "Fichier de ruche introuvable : $HiveFile"
    }

    if (Test-Path -LiteralPath $ProviderPath) {
        Add-CGlobalWarning "La ruche $HiveName etait deja chargee ; tentative de dechargement"
        $Unload = Invoke-RegCommand -Arguments @('unload', "HKLM\$HiveName")
        Write-RegOutput -Output $Unload.Output
        if ($Unload.ExitCode -ne 0 -or (Test-Path -LiteralPath $ProviderPath)) {
            throw "Impossible de decharger la ruche deja chargee : HKLM\$HiveName"
        }
    }

    Write-Log "Chargement de la ruche : $HiveFile"
    $Load = Invoke-RegCommand -Arguments @('load', "HKLM\$HiveName", $HiveFile)
    Write-RegOutput -Output $Load.Output

    if ($Load.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $ProviderPath)) {
        throw "Echec du chargement de la ruche HKLM\$HiveName, code=$($Load.ExitCode)"
    }

    Write-Log "Ruche chargee : HKLM\$HiveName" 'OK'
}

function Dismount-CGlobalHive {
    param(
        [Parameter(Mandatory = $true)][string]$HiveName,
        [Parameter(Mandatory = $true)][string]$ProviderPath
    )

    if (-not (Test-Path -LiteralPath $ProviderPath)) {
        return
    }

    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()
    Start-Sleep -Milliseconds 500

    Write-Log "Dechargement de la ruche HKLM\$HiveName"
    $Unload = Invoke-RegCommand -Arguments @('unload', "HKLM\$HiveName")
    Write-RegOutput -Output $Unload.Output

    if ($Unload.ExitCode -ne 0 -or (Test-Path -LiteralPath $ProviderPath)) {
        Add-CGlobalError "Echec du dechargement de HKLM\$HiveName, code=$($Unload.ExitCode)"
        return
    }

    Write-Log "Ruche HKLM\$HiveName dechargee" 'OK'
}

function New-DefaultClassesHive {
    if (Test-Path -LiteralPath $DefaultClassesHiveFile) {
        Write-Log 'UsrClass.dat existe deja : aucune creation necessaire'
        return
    }

    if ([string]::IsNullOrWhiteSpace($DefaultClassesDirectory)) {
        throw 'Le repertoire parent de UsrClass.dat est vide ou non initialise'
    }

    if (-not (Test-Path -LiteralPath $DefaultClassesDirectory)) {
        New-Item -Path $DefaultClassesDirectory -ItemType Directory -Force | Out-Null
        Write-Log "Repertoire cree : $DefaultClassesDirectory"
    }

    $TemporaryKeyName = 'CGLOBAL_CreateDefaultClasses'
    $TemporaryRoot = "Registry::HKEY_LOCAL_MACHINE\$TemporaryKeyName"

    Write-Log "UsrClass.dat absent : creation d'une ruche Registry valide"

    try {
        if (Test-Path -LiteralPath $TemporaryRoot) {
            $Delete = Invoke-RegCommand -Arguments @('delete', "HKLM\$TemporaryKeyName", '/f')
            Write-RegOutput -Output $Delete.Output
            if ($Delete.ExitCode -ne 0 -and (Test-Path -LiteralPath $TemporaryRoot)) {
                throw "Impossible de supprimer l'ancienne cle temporaire HKLM\$TemporaryKeyName"
            }
        }

        New-Item -Path $TemporaryRoot -Force | Out-Null
        New-ItemProperty -Path $TemporaryRoot -Name 'CGLOBALHiveMarker' -PropertyType String -Value 'UsrClass' -Force | Out-Null

        $Save = Invoke-RegCommand -Arguments @('save', "HKLM\$TemporaryKeyName", $DefaultClassesHiveFile, '/y')
        Write-RegOutput -Output $Save.Output

        if ($Save.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $DefaultClassesHiveFile)) {
            throw "Impossible de creer la ruche UsrClass.dat, code=$($Save.ExitCode)"
        }

        Write-Log 'UsrClass.dat cree comme vraie ruche Registry' 'OK'
    }
    finally {
        if (Test-Path -LiteralPath $TemporaryRoot) {
            $Delete = Invoke-RegCommand -Arguments @('delete', "HKLM\$TemporaryKeyName", '/f')
            Write-RegOutput -Output $Delete.Output
            if ($Delete.ExitCode -ne 0 -and (Test-Path -LiteralPath $TemporaryRoot)) {
                Add-CGlobalWarning "Nettoyage incomplet de HKLM\$TemporaryKeyName"
            }
        }
    }
}

function Set-DefaultDWord {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$Value,
        [Parameter(Mandatory = $true)][string]$Description
    )

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
        $Read = (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name
        if ([int]$Read -ne $Value) {
            throw "Verification incorrecte : valeur lue=$Read, valeur attendue=$Value"
        }
        Write-Log "$Description : valeur $Value appliquee" 'OK'
    }
    catch {
        Add-CGlobalError "$Description : $($_.Exception.Message)"
    }
}

function Set-DefaultString {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowEmptyString()][string]$Value,
        [Parameter(Mandatory = $true)][string]$Description
    )

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        New-ItemProperty -Path $Path -Name $Name -PropertyType String -Value $Value -Force | Out-Null
        $Read = (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name
        if ([string]$Read -cne [string]$Value) {
            throw "Verification incorrecte : valeur lue='$Read', valeur attendue='$Value'"
        }
        Write-Log "$Description applique" 'OK'
    }
    catch {
        Add-CGlobalError "$Description : $($_.Exception.Message)"
    }
}

function Set-ClassicContextMenu {

    $NativeKey = "HKLM\$DefaultClassesHiveName\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"

    $ProviderKey = Join-Path `
        $DefaultClassesRoot `
        "CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"

    try {

        Write-Log "Configuration du menu contextuel classique"

        #
        # IMPORTANT :
        # Ne pas passer par Invoke-RegCommand ici.
        # Le parametre /d "" provoque une erreur avec le splatting
        # d'un tableau string[] contenant une chaine vide.
        #
        $PreviousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'

        try {
            $Output = & reg.exe add `
                $NativeKey `
                /ve `
                /t REG_SZ `
                /d "" `
                /f 2>&1

            $ExitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $PreviousPreference
        }

        Write-RegOutput -Output $Output

        if ($ExitCode -ne 0) {
            throw "Echec de la creation de la valeur par defaut, code=$ExitCode"
        }

        if (-not (Test-Path -LiteralPath $ProviderKey)) {
            throw "La cle InprocServer32 est introuvable apres creation"
        }

        #
        # Verification de la valeur par defaut native
        #
        $Query = Invoke-RegCommand -Arguments @(
            'query',
            $NativeKey,
            '/ve'
        )

        Write-RegOutput -Output $Query.Output

        if ($Query.ExitCode -ne 0) {
            throw "Verification impossible, code=$($Query.ExitCode)"
        }

        Write-Log "Menu contextuel classique configure et verifie" "OK"
    }
    catch {
        Add-CGlobalError "Menu contextuel classique : $($_.Exception.Message)"
    }
}

try {
    Write-Log 'Configuration du profil utilisateur par defaut'
    Write-Log "Profil cible : $DefaultProfilePath"
    Write-Log "NTUSER.DAT : $DefaultUserHiveFile"
    Write-Log "UsrClass.dat : $DefaultClassesHiveFile"

    Mount-CGlobalHive -HiveName $DefaultUserHiveName -HiveFile $DefaultUserHiveFile -ProviderPath $DefaultUserRoot
    $DefaultUserLoaded = $true

    $DesktopIconsKey = Join-Path $DefaultUserRoot 'Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel'
    $DesktopIcons = @(
        @{ Name = 'Ce PC'; Guid = '{20D04FE0-3AEA-1069-A2D8-08002B30309D}' }
        @{ Name = 'Panneau de configuration'; Guid = '{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}' }
        @{ Name = 'Corbeille'; Guid = '{645FF040-5081-101B-9F08-00AA002F954E}' }
        @{ Name = 'Reseau'; Guid = '{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}' }
    )

    Write-Log 'Application des icones systeme du Bureau'
    foreach ($Icon in $DesktopIcons) {
        Set-DefaultDWord -Path $DesktopIconsKey -Name $Icon.Guid -Value 0 -Description "Icone Bureau $($Icon.Name)"
    }

    $ExplorerAdvancedKey = Join-Path $DefaultUserRoot 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-DefaultDWord -Path $ExplorerAdvancedKey -Name 'LaunchTo' -Value 1 -Description 'Explorateur ouvert sur Ce PC'
    Set-DefaultDWord -Path $ExplorerAdvancedKey -Name 'HideFileExt' -Value 0 -Description 'Extensions de fichiers visibles'
    Set-DefaultDWord -Path $ExplorerAdvancedKey -Name 'TaskbarAl' -Value 0 -Description 'Alignement de la barre des taches a gauche'
    Set-DefaultDWord -Path $ExplorerAdvancedKey -Name 'ShowTaskViewButton' -Value 0 -Description 'Bouton Vue des taches masque'
    Set-DefaultDWord -Path $ExplorerAdvancedKey -Name 'IsEnabled' -Value 0 -Description 'Fonction Reprendre desactivee'

    $SearchKey = Join-Path $DefaultUserRoot 'Software\Microsoft\Windows\CurrentVersion\Search'
    Set-DefaultDWord -Path $SearchKey -Name 'SearchboxTaskbarMode' -Value 1 -Description 'Recherche en mode icone uniquement'

    $LocationConsentKey = Join-Path $DefaultUserRoot 'Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'
    Set-DefaultDWord -Path $LocationConsentKey -Name 'ShowGlobalPrompts' -Value 0 -Description 'Notifications de demandes de localisation desactivees'

    $LocationOverrideKey = Join-Path $DefaultUserRoot 'Software\Microsoft\Windows\CurrentVersion\CPSS\Store\UserLocationOverridePrivacySetting'
    Set-DefaultDWord -Path $LocationOverrideKey -Name 'Value' -Value 0 -Description 'Remplacement de la localisation desactive'

    $KeyboardKey = Join-Path $DefaultUserRoot 'Control Panel\Keyboard'
    Set-DefaultString -Path $KeyboardKey -Name 'InitialKeyboardIndicators' -Value '2' -Description 'Verrouillage numerique configure'
    Write-Log 'Parametres NTUSER.DAT appliques' 'OK'

    New-DefaultClassesHive
    Mount-CGlobalHive -HiveName $DefaultClassesHiveName -HiveFile $DefaultClassesHiveFile -ProviderPath $DefaultClassesRoot
    $DefaultClassesLoaded = $true

    Set-ClassicContextMenu
    Write-Log 'Parametres UsrClass.dat appliques' 'OK'
}
catch {
    Add-CGlobalError $_.Exception.Message
}
finally {
    if ($DefaultClassesLoaded) {
        Dismount-CGlobalHive -HiveName $DefaultClassesHiveName -ProviderPath $DefaultClassesRoot
    }
    if ($DefaultUserLoaded) {
        Dismount-CGlobalHive -HiveName $DefaultUserHiveName -ProviderPath $DefaultUserRoot
    }
}

Write-Log '----------------------------------------'
Write-Log "Avertissements : $WarningCount"
Write-Log "Erreurs : $ErrorCount"

if ($ErrorCount -gt 0) {
    Write-Log 'Configuration du profil par defaut terminee avec erreurs' 'ERROR'
    exit 1
}
if ($WarningCount -gt 0) {
    Write-Log 'Configuration du profil par defaut terminee avec avertissements' 'WARN'
    exit 0
}

Write-Log 'Configuration du profil par defaut terminee avec succes' 'OK'
exit 0
