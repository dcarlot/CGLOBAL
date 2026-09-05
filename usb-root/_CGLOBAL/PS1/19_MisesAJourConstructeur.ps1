#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

$script:RebootRequired = $false

function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
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

function Test-AppxPackageInstalled {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$NamePatterns
    )

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

function Install-WingetPackage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageId,
        [ValidateSet('winget', 'msstore')]
        [string]$Source = 'winget'
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
    Install-WingetPackage -PackageId 'Lenovo.SystemUpdate' -Source 'winget'

    $TvsuPath = Get-LenovoSystemUpdatePath
    if ($null -eq $TvsuPath) {
        throw 'tvsu.exe introuvable apres installation de Lenovo System Update'
    }
    Write-Log "Lenovo System Update installe : $TvsuPath" 'OK'
    return $TvsuPath
}

function Get-LenovoUpdateMode {
    $Message = @"
Choisissez le mode d'installation :

Oui = TOUTES les mises a jour (BIOS / Firmware inclus)
      ATTENTION : le poste peut redemarrer avant la fin des scripts CGLOBAL.

Non = Uniquement les mises a jour sans redemarrage
      La sequence CGLOBAL pourra continuer normalement.

Annuler = Ignorer CE script et continuer les scripts suivants.
"@

    $Choice = Show-CGlobalPopup `
        -Message $Message `
        -Title 'Mises a jour constructeur' `
        -Buttons 'YesNoCancel' `
        -Icon 'Question'

    if ($Choice -eq [System.Windows.Forms.DialogResult]::Yes) {
        Write-Log 'Mode choisi : toutes les mises a jour, redemarrage constructeur autorise' 'WARN'
        return 'ALL'
    }
    if ($Choice -eq [System.Windows.Forms.DialogResult]::No) {
        Write-Log 'Mode choisi : mises a jour sans redemarrage uniquement' 'OK'
        return 'NO_REBOOT'
    }

    Write-Log 'Script 19 ignore par l utilisateur : poursuite des scripts suivants' 'WARN'
    return 'CANCEL'
}

function Set-LenovoSystemUpdatePolicy {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('ALL', 'NO_REBOOT')]
        [string]$UpdateMode
    )

    $PolicyPaths = @(
        'HKLM:\SOFTWARE\Policies\Lenovo\System Update\UserSettings\General',
        'HKLM:\SOFTWARE\WOW6432Node\Policies\Lenovo\System Update\UserSettings\General'
    )

    if ($UpdateMode -eq 'ALL') {
        $AdminCommandLine = '/CM -search A -action INSTALL -includerebootpackages 1,3,4,5 -nolicense -noicon -exporttowmi'
    }
    else {
        # Sans -includerebootpackages, seuls les packages de type 0 sont traites.
        $AdminCommandLine = '/CM -search A -action INSTALL -nolicense -noicon -exporttowmi'
    }

    foreach ($PolicyPath in $PolicyPaths) {
        if (-not (Test-Path -LiteralPath $PolicyPath)) {
            New-Item -Path $PolicyPath -Force | Out-Null
        }
        New-ItemProperty -Path $PolicyPath -Name 'AdminCommandLine' `
            -PropertyType String -Value $AdminCommandLine -Force | Out-Null
    }

    Write-Log "Politique Lenovo configuree : $AdminCommandLine" 'OK'
    if ($UpdateMode -eq 'ALL') {
        Write-Log 'Toutes les mises a jour Lenovo sont autorisees, y compris celles pouvant redemarrer ou arreter le poste' 'WARN'
    }
    else {
        Write-Log 'Seules les mises a jour Lenovo ne demandant aucun redemarrage sont autorisees' 'OK'
    }
}

function Disable-LenovoAutomaticScheduler {
    $SchedulerPath = 'HKLM:\SOFTWARE\WOW6432Node\Lenovo\System Update\Preferences\UserSettings\Scheduler'
    if (-not (Test-Path -LiteralPath $SchedulerPath)) {
        New-Item -Path $SchedulerPath -Force | Out-Null
    }
    New-ItemProperty -Path $SchedulerPath -Name 'SchedulerAbility' `
        -PropertyType String -Value 'NO' -Force | Out-Null
    Write-Log 'Planification automatique Lenovo System Update desactivee' 'OK'
}

function Invoke-LenovoUpdates {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('ALL', 'NO_REBOOT')]
        [string]$UpdateMode
    )

    Test-WingetAvailable
    Install-LenovoCommercialVantage
    $TvsuPath = Install-LenovoSystemUpdate
    Set-LenovoSystemUpdatePolicy -UpdateMode $UpdateMode
    Disable-LenovoAutomaticScheduler

    if ($UpdateMode -eq 'ALL') {
        Write-Log 'Recherche et installation de toutes les mises a jour Lenovo' 'WARN'
    }
    else {
        Write-Log 'Recherche et installation des mises a jour Lenovo sans redemarrage'
    }

    $Result = Invoke-LoggedCommand -FilePath $TvsuPath -Arguments @('/CM')

    if ($Result.ExitCode -eq 0) {
        Write-Log 'Traitement Lenovo System Update termine' 'OK'
    }
    elseif ($Result.ExitCode -eq 3010) {
        $script:RebootRequired = $true
        Write-Log 'Traitement Lenovo termine : redemarrage requis' 'WARN'
    }
    else {
        throw "Lenovo System Update a retourne le code $($Result.ExitCode)"
    }

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
            Write-Log 'Traitement constructeur Lenovo'
            $UpdateMode = Get-LenovoUpdateMode
            if ($UpdateMode -eq 'CANCEL') {
                Write-Log 'Fin du script 19 sans action' 'OK'
                exit 0
            }
            Invoke-LenovoUpdates -UpdateMode $UpdateMode
        }
        'DELL' {
            Write-Log 'Poste Dell detecte' 'WARN'
            Write-Log 'Dell Command Update n est pas encore active dans cette version' 'WARN'
        }
        'HP' {
            Write-Log 'Poste HP detecte' 'WARN'
            Write-Log 'HP Image Assistant n est pas encore active dans cette version' 'WARN'
        }
        'ASUS' {
            Write-Log 'Poste ASUS detecte' 'WARN'
            Write-Log 'MyASUS ne fournit pas de ligne de commande documentee equivalente' 'WARN'
        }
        default {
            Write-Log 'Constructeur non pris en charge : aucune action effectuee' 'WARN'
        }
    }

    Write-Log 'Mises a jour constructeur terminees' 'OK'
    exit 0
}
catch {
    Write-Log $_.Exception.Message 'ERROR'
    exit 1
}
