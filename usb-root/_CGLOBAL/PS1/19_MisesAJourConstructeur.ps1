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

    Write-Log "Constructeur détecté : $Manufacturer"
    Write-Log "Modèle détecté       : $Model"

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
    Write-Log 'Winget détecté' 'OK'
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
        throw "Échec de l'installation du package $PackageId (code $($Result.ExitCode))"
    }
    Write-Log "$PackageId installé" 'OK'
}

function Get-UpdateMode {
    param([Parameter(Mandatory = $true)][string]$ManufacturerName)

    $Message = @"
Choisissez le mode d'installation pour $ManufacturerName :

Oui = TOUTES les mises à jour (BIOS / Firmware inclus)
      Le poste peut redémarrer avant la fin des scripts CGLOBAL.

Non = Mises à jour sans redémarrage forcé
      Les mises à jour peuvent demander un redémarrage, mais celui-ci
      ne sera pas déclenché automatiquement pendant la séquence CGLOBAL.

Annuler = Ignorer CE script et continuer les scripts suivants.
"@

    $Choice = Show-CGlobalPopup -Message $Message -Title 'Mises à jour constructeur' `
        -Buttons 'YesNoCancel' -Icon 'Question'

    if ($Choice -eq [System.Windows.Forms.DialogResult]::Yes) {
        Write-Log 'Mode choisi : toutes les mises à jour, redémarrage constructeur autorisé' 'WARN'
        return 'ALL'
    }
    if ($Choice -eq [System.Windows.Forms.DialogResult]::No) {
        Write-Log 'Mode choisi : mises à jour sans redémarrage forcé' 'OK'
        return 'NO_FORCED_REBOOT'
    }

    Write-Log 'Script 19 ignoré par l utilisateur : poursuite des scripts suivants' 'WARN'
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
        Write-Log 'Lenovo Vantage ou Lenovo Commercial Vantage est déjà installé' 'OK'
        return
    }

    Write-Log 'Lenovo Commercial Vantage absent : installation depuis Microsoft Store' 'WARN'
    Test-WingetAvailable
    Install-WingetPackage -PackageId '9NR5B8GVVM13' -Source 'msstore'

    if (-not (Test-AppxPackageInstalled -NamePatterns $Patterns)) {
        throw 'Lenovo Commercial Vantage reste introuvable après installation'
    }
    Write-Log 'Lenovo Commercial Vantage vérifié après installation' 'OK'
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
        Write-Log "Lenovo System Update déjà installé : $TvsuPath" 'OK'
        return $TvsuPath
    }

    Write-Log 'Lenovo System Update absent : installation via Winget' 'WARN'
    Test-WingetAvailable
    Install-WingetPackage -PackageId 'Lenovo.SystemUpdate'
    $TvsuPath = Get-LenovoSystemUpdatePath
    if ($null -eq $TvsuPath) {
        throw 'tvsu.exe introuvable après installation de Lenovo System Update'
    }
    Write-Log "Lenovo System Update installé : $TvsuPath" 'OK'
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
    Write-Log "Politique Lenovo configurée : $AdminCommandLine" 'OK'
}

function Disable-LenovoAutomaticScheduler {
    # Les deux vues de registre sont écrites car Lenovo System Update peut être
    # installé en version 32 ou 64 bits selon le poste (cf. Get-LenovoSystemUpdatePath),
    # de la même manière que Set-LenovoSystemUpdatePolicy pour AdminCommandLine.
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
    Write-Log 'Planification automatique Lenovo System Update désactivée (32 et 64 bits)' 'OK'
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
        Write-Log 'Traitement Lenovo terminé : redémarrage requis' 'WARN'
    }
    elseif ($Result.ExitCode -ne 0) {
        throw "Lenovo System Update a retourné le code $($Result.ExitCode)"
    }
    else {
        Write-Log 'Traitement Lenovo System Update terminé' 'OK'
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
        Write-Log "Dell Command Update déjà installé : $DcuPath" 'OK'
        return $DcuPath
    }

    Test-WingetAvailable
    Write-Log 'Dell Command Update absent : installation via Winget' 'WARN'
    Install-WingetPackage -PackageId 'Dell.CommandUpdate'

    $DcuPath = Get-DellCommandUpdatePath
    if ($null -eq $DcuPath) {
        throw 'dcu-cli.exe introuvable après installation de Dell Command Update'
    }
    Write-Log "Dell Command Update installé : $DcuPath" 'OK'
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
        Write-Log 'Dell : toutes les mises à jour sont autorisées avec redémarrage automatique' 'WARN'
    }
    else {
        $RebootArgument = '-reboot=disable'
        Write-Log 'Dell : redémarrage automatique désactivé pour poursuivre CGLOBAL' 'OK'
    }

    $Result = Invoke-LoggedCommand -FilePath $DcuPath -Arguments @(
        '/applyUpdates',
        '-updateType=bios,firmware,driver,application,others',
        '-silent',
        $RebootArgument,
        "-outputLog=$DellLog"
    )

    # 0 : succès ; 1/3010 : redémarrage requis selon les versions DCU ;
    # 500 : aucune mise à jour disponible (constaté sur le terrain, pas une erreur).
    # Les autres codes sont journalisés comme erreurs de traitement.
    if ($Result.ExitCode -eq 0) {
        Write-Log 'Traitement Dell Command Update terminé' 'OK'
    }
    elseif ($Result.ExitCode -eq 1 -or $Result.ExitCode -eq 3010) {
        $script:RebootRequired = $true
        Write-Log "Traitement Dell terminé avec le code $($Result.ExitCode) : redémarrage requis" 'WARN'
    }
    elseif ($Result.ExitCode -eq 500) {
        Write-Log 'Dell Command Update : aucune mise à jour disponible (code 500)' 'WARN'
        Show-CGlobalPopup -Title 'Mises à jour Dell' -Buttons 'OK' -Icon 'Information' `
            -Message "Dell Command Update n'a trouvé aucune mise à jour disponible pour ce poste." | Out-Null
    }
    else {
        throw "Dell Command Update a retourné le code $($Result.ExitCode)"
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
        Write-Log 'Un redémarrage est requis' 'WARN'
    }
    else {
        Write-Log 'Aucun redémarrage en attente détecté' 'OK'
    }
}

try {
    Write-Log '=== MISES À JOUR CONSTRUCTEUR ==='
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
            Write-Log 'Poste HP détecté : HP Image Assistant non encore activé dans cette version' 'WARN'
        }
        'ASUS' {
            Write-Log 'Poste ASUS détecté : automatisation MyASUS non implémentée' 'WARN'
        }
        default {
            Write-Log 'Constructeur non pris en charge : aucune action effectuée' 'WARN'
        }
    }

    if ($script:RebootRequired) {
        Show-CGlobalPopup -Message "Les mises à jour constructeur nécessitent un redémarrage du poste.`n`nPensez à redémarrer avant de considérer le déploiement terminé." `
            -Title 'Redémarrage requis' -Buttons 'OK' -Icon 'Exclamation' | Out-Null
        Write-Log 'Popup de redémarrage requis affichée à l opérateur' 'WARN'
    }

    Write-Log 'Mises à jour constructeur terminées' 'OK'
    exit 0
}
catch {
    Write-Log $_.Exception.Message 'ERROR'
    exit 1
}
