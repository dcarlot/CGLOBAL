#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

$script:RebootRequired = $false

function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @()
    )

    Write-Log ("Commande : {0} {1}" -f $FilePath, ($Arguments -join ' '))
    $PreviousEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $Output = & $FilePath @Arguments 2>&1
        $ExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousEAP
    }

    foreach ($Line in $Output) {
        if ($null -ne $Line -and $Line.ToString().Trim() -ne '') {
            Write-Log $Line.ToString()
        }
    }

    return [PSCustomObject]@{
        ExitCode    = $ExitCode
        OutputLines = $Output
        OutputText  = ($Output -join "`n")
    }
}

function Get-ComputerManufacturer {
    $ComputerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
    $Manufacturer = ([string]$ComputerSystem.Manufacturer).Trim()
    $Model = ([string]$ComputerSystem.Model).Trim()

    Write-Log "Constructeur detecte : $Manufacturer"
    Write-Log "Modele detecte       : $Model"

    if ($Manufacturer -match '(?i)lenovo') { return 'LENOVO' }
    if ($Manufacturer -match '(?i)dell') { return 'DELL' }
    if ($Manufacturer -match '(?i)hewlett-packard|\bhp\b') { return 'HP' }
    if ($Manufacturer -match '(?i)asus|asustek') { return 'ASUS' }
    return 'AUTRE'
}

function Test-WingetAvailable {
    if (-not (Get-Command 'winget.exe' -ErrorAction SilentlyContinue)) {
        throw 'winget.exe introuvable'
    }
    Write-Log 'Winget detecte' 'OK'
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [ValidateSet('winget', 'msstore')][string]$Source = 'winget'
    )

    $Result = Invoke-LoggedCommand -FilePath 'winget.exe' -Arguments @(
        'install', '--id', $PackageId, '-e', '--source', $Source, '--silent',
        '--accept-package-agreements', '--accept-source-agreements',
        '--disable-interactivity'
    )

    if ($Result.ExitCode -ne 0) {
        throw "Echec de l'installation du package $PackageId (code $($Result.ExitCode))"
    }
    Write-Log "$PackageId installe" 'OK'
}

function Get-UpdateMode {
    param([Parameter(Mandatory = $true)][string]$ManufacturerName)

    $Message = @"
Choisissez le mode d'installation pour $ManufacturerName :

Oui = TOUTES les mises a jour (BIOS / Firmware inclus)
      Le poste peut redemarrer avant la fin des scripts CGLOBAL.

Non = Mises a jour sans redemarrage force
      Les mises a jour peuvent demander un redemarrage, mais celui-ci
      ne sera pas declenche automatiquement pendant la sequence CGLOBAL.

Annuler = Ignorer CE script et continuer les scripts suivants.
"@

    $Choice = Show-CGlobalPopup -Message $Message -Title 'Mises a jour constructeur' `
        -Buttons 'YesNoCancel' -Icon 'Question'

    if ($Choice -eq [System.Windows.Forms.DialogResult]::Yes) {
        Write-Log 'Mode choisi : toutes les mises a jour, redemarrage constructeur autorise' 'WARN'
        return 'ALL'
    }
    if ($Choice -eq [System.Windows.Forms.DialogResult]::No) {
        Write-Log 'Mode choisi : mises a jour sans redemarrage force' 'OK'
        return 'NO_FORCED_REBOOT'
    }

    Write-Log 'Script 19 ignore par l utilisateur : poursuite des scripts suivants' 'WARN'
    return 'CANCEL'
}

function Test-AppxPackageInstalled {
    param([Parameter(Mandatory = $true)][string[]]$NamePatterns)

    $Packages = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
    foreach ($Package in $Packages) {
        foreach ($Pattern in $NamePatterns) {
            if ($Package.Name -like $Pattern -or $Package.PackageFamilyName -like $Pattern) {
                return $true
            }
        }
    }
    return $false
}

function Install-LenovoCommercialVantage {
    $Patterns = @(
        'E046963F.LenovoSettingsforEnterprise*',
        'E046963F.LenovoCompanion*',
        '*LenovoCommercialVantage*',
        '*LenovoVantage*'
    )

    if (Test-AppxPackageInstalled -NamePatterns $Patterns) {
        Write-Log 'Lenovo Vantage ou Lenovo Commercial Vantage est deja installe' 'OK'
        return
    }

    Write-Log 'Lenovo Commercial Vantage absent : installation depuis Microsoft Store' 'WARN'
    Test-WingetAvailable
    Install-WingetPackage -PackageId '9NR5B8GVVM13' -Source 'msstore'

    if (-not (Test-AppxPackageInstalled -NamePatterns $Patterns)) {
        throw 'Lenovo Commercial Vantage reste introuvable apres installation'
    }
    Write-Log 'Lenovo Commercial Vantage verifie apres installation' 'OK'
}

function Get-LenovoSystemUpdatePath {
    $Paths = @(
        'C:\Program Files (x86)\Lenovo\System Update\tvsu.exe',
        'C:\Program Files\Lenovo\System Update\tvsu.exe'
    )
    foreach ($Path in $Paths) {
        if (Test-Path -LiteralPath $Path) { return $Path }
    }
    return $null
}

function Install-LenovoSystemUpdate {
    $TvsuPath = Get-LenovoSystemUpdatePath
    if ($null -ne $TvsuPath) {
        Write-Log "Lenovo System Update deja installe : $TvsuPath" 'OK'
        return $TvsuPath
    }

    Write-Log 'Lenovo System Update absent : installation via Winget' 'WARN'
    Test-WingetAvailable
    Install-WingetPackage -PackageId 'Lenovo.SystemUpdate'
    $TvsuPath = Get-LenovoSystemUpdatePath
    if ($null -eq $TvsuPath) {
        throw 'tvsu.exe introuvable apres installation de Lenovo System Update'
    }
    Write-Log "Lenovo System Update installe : $TvsuPath" 'OK'
    return $TvsuPath
}

function Set-LenovoSystemUpdatePolicy {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('ALL', 'NO_FORCED_REBOOT')][string]$UpdateMode
    )

    $PolicyPaths = @(
        'HKLM:\SOFTWARE\Policies\Lenovo\System Update\UserSettings\General',
        'HKLM:\SOFTWARE\WOW6432Node\Policies\Lenovo\System Update\UserSettings\General'
    )

    if ($UpdateMode -eq 'ALL') {
        $AdminCommandLine = '/CM -search A -action INSTALL -includerebootpackages 1,3,4,5 -nolicense -noicon -exporttowmi'
    }
    else {
        # Types 1 et 3 autorises ; redemarrage du type 3 neutralise.
        # Types 4 (arret) et 5 (redemarrage obligatoire) exclus.
        $AdminCommandLine = '/CM -search A -action INSTALL -includerebootpackages 1,3 -noreboot -nolicense -noicon -exporttowmi'
    }

    foreach ($PolicyPath in $PolicyPaths) {
        if (-not (Test-Path -LiteralPath $PolicyPath)) {
            New-Item -Path $PolicyPath -Force | Out-Null
        }
        New-ItemProperty -Path $PolicyPath -Name 'AdminCommandLine' `
            -PropertyType String -Value $AdminCommandLine -Force | Out-Null
    }
    Write-Log "Politique Lenovo configuree : $AdminCommandLine" 'OK'
}

function Disable-LenovoAutomaticScheduler {
    # Les deux vues de registre sont ecrites car Lenovo System Update peut etre
    # installe en version 32 ou 64 bits selon le poste (cf. Get-LenovoSystemUpdatePath),
    # de la meme maniere que Set-LenovoSystemUpdatePolicy pour AdminCommandLine.
    $SchedulerPaths = @(
        'HKLM:\SOFTWARE\Lenovo\System Update\Preferences\UserSettings\Scheduler',
        'HKLM:\SOFTWARE\WOW6432Node\Lenovo\System Update\Preferences\UserSettings\Scheduler'
    )

    foreach ($SchedulerPath in $SchedulerPaths) {
        if (-not (Test-Path -LiteralPath $SchedulerPath)) {
            New-Item -Path $SchedulerPath -Force | Out-Null
        }
        New-ItemProperty -Path $SchedulerPath -Name 'SchedulerAbility' `
            -PropertyType String -Value 'NO' -Force | Out-Null
    }
    Write-Log 'Planification automatique Lenovo System Update desactivee (32 et 64 bits)' 'OK'
}

function Invoke-LenovoUpdates {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('ALL', 'NO_FORCED_REBOOT')][string]$UpdateMode
    )

    Install-LenovoCommercialVantage
    $TvsuPath = Install-LenovoSystemUpdate
    Set-LenovoSystemUpdatePolicy -UpdateMode $UpdateMode
    Disable-LenovoAutomaticScheduler

    $Result = Invoke-LoggedCommand -FilePath $TvsuPath -Arguments @('/CM')
    if ($Result.ExitCode -eq 3010) {
        $script:RebootRequired = $true
        Write-Log 'Traitement Lenovo termine : redemarrage requis' 'WARN'
    }
    elseif ($Result.ExitCode -ne 0) {
        throw "Lenovo System Update a retourne le code $($Result.ExitCode)"
    }
    else {
        Write-Log 'Traitement Lenovo System Update termine' 'OK'
    }
}

function Get-DellCommandUpdatePath {
    $Paths = @(
        'C:\Program Files\Dell\CommandUpdate\dcu-cli.exe',
        'C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe'
    )
    foreach ($Path in $Paths) {
        if (Test-Path -LiteralPath $Path) { return $Path }
    }
    return $null
}

function Install-DellCommandUpdate {
    $DcuPath = Get-DellCommandUpdatePath
    if ($null -ne $DcuPath) {
        Write-Log "Dell Command Update deja installe : $DcuPath" 'OK'
        return $DcuPath
    }

    Test-WingetAvailable
    Write-Log 'Dell Command Update absent : installation via Winget' 'WARN'
    Install-WingetPackage -PackageId 'Dell.CommandUpdate'

    $DcuPath = Get-DellCommandUpdatePath
    if ($null -eq $DcuPath) {
        throw 'dcu-cli.exe introuvable apres installation de Dell Command Update'
    }
    Write-Log "Dell Command Update installe : $DcuPath" 'OK'
    return $DcuPath
}

function Invoke-DellUpdates {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('ALL', 'NO_FORCED_REBOOT')][string]$UpdateMode
    )

    $DcuPath = Install-DellCommandUpdate
    $DellLog = 'C:\_CGLOBAL\Logs\DellCommandUpdate.log'

    if ($UpdateMode -eq 'ALL') {
        $RebootArgument = '-reboot=enable'
        Write-Log 'Dell : toutes les mises a jour sont autorisees avec redemarrage automatique' 'WARN'
    }
    else {
        $RebootArgument = '-reboot=disable'
        Write-Log 'Dell : redemarrage automatique desactive pour poursuivre CGLOBAL' 'OK'
    }

    $Result = Invoke-LoggedCommand -FilePath $DcuPath -Arguments @(
        '/applyUpdates',
        '-updateType=bios,firmware,driver,application,others',
        '-silent',
        $RebootArgument,
        "-outputLog=$DellLog"
    )

    # 0 : succes ; 1 : redemarrage requis selon les versions DCU.
    # Les autres codes sont journalises comme erreurs de traitement.
    if ($Result.ExitCode -eq 0) {
        Write-Log 'Traitement Dell Command Update termine' 'OK'
    }
    elseif ($Result.ExitCode -eq 1 -or $Result.ExitCode -eq 3010) {
        $script:RebootRequired = $true
        Write-Log "Traitement Dell termine avec le code $($Result.ExitCode) : redemarrage requis" 'WARN'
    }
    else {
        throw "Dell Command Update a retourne le code $($Result.ExitCode)"
    }
}

function Test-PendingReboot {
    if (
        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
    ) {
        $script:RebootRequired = $true
    }

    if ($script:RebootRequired) {
        Write-Log 'Un redemarrage est requis' 'WARN'
    }
    else {
        Write-Log 'Aucun redemarrage en attente detecte' 'OK'
    }
}

try {
    Write-Log '=== MISES A JOUR CONSTRUCTEUR ==='
    $Manufacturer = Get-ComputerManufacturer

    switch ($Manufacturer) {
        'LENOVO' {
            $UpdateMode = Get-UpdateMode -ManufacturerName 'Lenovo'
            if ($UpdateMode -eq 'CANCEL') { exit 0 }
            Invoke-LenovoUpdates -UpdateMode $UpdateMode
            Test-PendingReboot
        }
        'DELL' {
            $UpdateMode = Get-UpdateMode -ManufacturerName 'Dell'
            if ($UpdateMode -eq 'CANCEL') { exit 0 }
            Invoke-DellUpdates -UpdateMode $UpdateMode
            Test-PendingReboot
        }
        'HP' {
            Write-Log 'Poste HP detecte : HP Image Assistant non encore active dans cette version' 'WARN'
        }
        'ASUS' {
            Write-Log 'Poste ASUS detecte : automatisation MyASUS non implementee' 'WARN'
        }
        default {
            Write-Log 'Constructeur non pris en charge : aucune action effectuee' 'WARN'
        }
    }

    if ($script:RebootRequired) {
        Show-CGlobalPopup -Message "Les mises a jour constructeur necessitent un redemarrage du poste.`n`nPensez a redemarrer avant de considerer le deploiement termine." `
            -Title 'Redemarrage requis' -Buttons 'OK' -Icon 'Exclamation' | Out-Null
        Write-Log 'Popup de redemarrage requis affichee a l operateur' 'WARN'
    }

    Write-Log 'Mises a jour constructeur terminees' 'OK'
    exit 0
}
catch {
    Write-Log $_.Exception.Message 'ERROR'
    exit 1
}
