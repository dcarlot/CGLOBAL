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

    Write-Log ("Commande : {0} {1}" -f $FilePath, ($Arguments -join " "))

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
        if ($null -ne $Line -and $Line.ToString().Trim() -ne "") {
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

    if ($Manufacturer -match '(?i)lenovo') {
        return 'LENOVO'
    }

    if ($Manufacturer -match '(?i)dell') {
        return 'DELL'
    }

    if ($Manufacturer -match '(?i)hewlett-packard|\bhp\b') {
        return 'HP'
    }

    if ($Manufacturer -match '(?i)asus|asustek') {
        return 'ASUS'
    }

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

    $Result = Invoke-LoggedCommand `
        -FilePath 'winget.exe' `
        -Arguments @(
            'install',
            '--id', $PackageId,
            '-e',
            '--source', $Source,
            '--silent',
            '--accept-package-agreements',
            '--accept-source-agreements',
            '--disable-interactivity'
        )

    if ($Result.ExitCode -ne 0) {
        throw "Echec de l'installation du package $PackageId (code $($Result.ExitCode))"
    }

    Write-Log "$PackageId installe" 'OK'
}

function Install-LenovoCommercialVantage {
    $VantagePatterns = @(
        'E046963F.LenovoSettingsforEnterprise*',
        'E046963F.LenovoCompanion*',
        '*LenovoCommercialVantage*',
        '*LenovoVantage*'
    )

    if (Test-AppxPackageInstalled -NamePatterns $VantagePatterns) {
        Write-Log 'Lenovo Vantage ou Lenovo Commercial Vantage est deja installe' 'OK'
        return
    }

    Write-Log 'Lenovo Commercial Vantage absent : installation depuis Microsoft Store' 'WARN'
    Install-WingetPackage -PackageId '9NR5B8GVVM13' -Source 'msstore'

    if (-not (Test-AppxPackageInstalled -NamePatterns $VantagePatterns)) {
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
        if (Test-Path -LiteralPath $Path) {
            return $Path
        }
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

function Set-LenovoSystemUpdatePolicy {
    $PolicyPaths = @(
        'HKLM:\SOFTWARE\Policies\Lenovo\System Update\UserSettings\General',
        'HKLM:\SOFTWARE\WOW6432Node\Policies\Lenovo\System Update\UserSettings\General'
    )

    # Types de redemarrage Lenovo inclus :
    # 1 = redemarrage differe/controle par le package
    # 3 = redemarrage requis, neutralise par -noreboot
    # Les types 4 (arret) et 5 (redemarrage obligatoire sous 5 minutes) sont exclus.
    # Cela garantit qu'aucun BIOS/firmware de type 4 ou 5 ne coupe la sequence CGLOBAL.
    $AdminCommandLine = '/CM -search A -action INSTALL -includerebootpackages 1,3 -noreboot -nolicense -noicon -exporttowmi'

    foreach ($PolicyPath in $PolicyPaths) {
        if (-not (Test-Path -LiteralPath $PolicyPath)) {
            New-Item -Path $PolicyPath -Force | Out-Null
        }

        New-ItemProperty `
            -Path $PolicyPath `
            -Name 'AdminCommandLine' `
            -PropertyType String `
            -Value $AdminCommandLine `
            -Force | Out-Null
    }

    Write-Log "Politique Lenovo configuree : $AdminCommandLine" 'OK'
    Write-Log 'Les mises a jour imposant un arret ou un redemarrage obligatoire sous 5 minutes sont exclues' 'WARN'
}

function Disable-LenovoAutomaticScheduler {
    $SchedulerPath = 'HKLM:\SOFTWARE\WOW6432Node\Lenovo\System Update\Preferences\UserSettings\Scheduler'

    if (-not (Test-Path -LiteralPath $SchedulerPath)) {
        New-Item -Path $SchedulerPath -Force | Out-Null
    }

    New-ItemProperty `
        -Path $SchedulerPath `
        -Name 'SchedulerAbility' `
        -PropertyType String `
        -Value 'NO' `
        -Force | Out-Null

    Write-Log 'Planification automatique Lenovo System Update desactivee pendant la gestion CGLOBAL' 'OK'
}

function Invoke-LenovoUpdates {
    Test-WingetAvailable
    Install-LenovoCommercialVantage

    $TvsuPath = Install-LenovoSystemUpdate
    Set-LenovoSystemUpdatePolicy
    Disable-LenovoAutomaticScheduler

    Write-Log 'Recherche et installation des mises a jour Lenovo sans redemarrage automatique'

    $Result = Invoke-LoggedCommand `
        -FilePath $TvsuPath `
        -Arguments @('/CM')

    # Lenovo System Update peut signaler differents etats selon les mises a jour
    # trouvees. Les sorties detaillees sont deja recopiees dans le log CGLOBAL.
    if ($Result.ExitCode -eq 0) {
        Write-Log 'Traitement Lenovo System Update termine' 'OK'
    }
    elseif ($Result.ExitCode -eq 3010) {
        $script:RebootRequired = $true
        Write-Log 'Traitement Lenovo termine : redemarrage requis mais non declenche' 'WARN'
    }
    else {
        throw "Lenovo System Update a retourne le code $($Result.ExitCode)"
    }

    # Indicateurs Windows generiques de redemarrage en attente.
    if (
        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
    ) {
        $script:RebootRequired = $true
    }

    if ($script:RebootRequired) {
        Write-Log 'Un redemarrage sera necessaire apres la fin de tous les scripts CGLOBAL' 'WARN'
    }
    else {
        Write-Log 'Aucun redemarrage en attente detecte apres les mises a jour Lenovo' 'OK'
    }
}

try {
    Write-Log '=== MISES A JOUR CONSTRUCTEUR ==='

    $Manufacturer = Get-ComputerManufacturer

    switch ($Manufacturer) {
        'LENOVO' {
            Write-Log 'Traitement constructeur Lenovo'
            Invoke-LenovoUpdates
        }

        'DELL' {
            Write-Log 'Poste Dell detecte' 'WARN'
            Write-Log 'Dell Command Update est l outil adapte, mais son automatisation n est pas activee dans cette version du script' 'WARN'
        }

        'HP' {
            Write-Log 'Poste HP detecte' 'WARN'
            Write-Log 'HP Image Assistant est l outil adapte, mais son automatisation n est pas activee dans cette version du script' 'WARN'
        }

        'ASUS' {
            Write-Log 'Poste ASUS detecte' 'WARN'
            Write-Log 'MyASUS est l outil adapte, mais ASUS ne documente pas de ligne de commande equivalente pour automatiser System Update' 'WARN'
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
