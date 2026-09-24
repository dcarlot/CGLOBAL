#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

# ============================================================
# 20 - DESINSTALLATION MCAFEE
# ============================================================
#
# Objectif :
#   Détecter les produits McAfee installés sur le poste et les
#   désinstaller automatiquement, sans confirmation utilisateur
#   et sans afficher de fenêtre de désinstallation.
#
# Le script s'appuie prioritairement sur les informations de
# désinstallation enregistrées par Windows.
#
# ============================================================

function Get-McAfeeUninstallEntries {

    $Entries = @()

    $RegistryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($RegistryPath in $RegistryPaths) {

        if (-not (Test-Path $RegistryPath)) {
            continue
        }

        try {
            $Keys = Get-ChildItem -Path $RegistryPath -ErrorAction SilentlyContinue
        }
        catch {
            Write-Log "Impossible d'interroger $RegistryPath : $($_.Exception.Message)" "WARN"
            continue
        }

        foreach ($Key in $Keys) {

            try {
                $Properties = Get-ItemProperty `
                    -Path $Key.PSPath `
                    -ErrorAction SilentlyContinue

                if ($null -eq $Properties) {
                    continue
                }

                $DisplayName = [string]$Properties.DisplayName

                if ([string]::IsNullOrWhiteSpace($DisplayName)) {
                    continue
                }

                # Détection volontairement ciblée sur McAfee.
                if ($DisplayName -notmatch '(?i)\bMcAfee\b') {
                    continue
                }

                $Entry = [PSCustomObject]@{
                    DisplayName          = $DisplayName
                    DisplayVersion       = [string]$Properties.DisplayVersion
                    Publisher            = [string]$Properties.Publisher
                    UninstallString      = [string]$Properties.UninstallString
                    QuietUninstallString = [string]$Properties.QuietUninstallString
                    RegistryPath         = $Key.PSPath
                    WindowsInstaller     = [int]$Properties.WindowsInstaller
                    ProductCode          = [string]$Properties.PSChildName
                }

                $Entries += $Entry
            }
            catch {
                # Une entrée de registre invalide ne doit pas
                # interrompre la recherche des autres produits.
                continue
            }
        }
    }

    # Supprimer les doublons éventuels.
    return @(
        $Entries |
            Sort-Object RegistryPath -Unique
    )
}


function Stop-McAfeeProcesses {

    Write-Log "Recherche des processus McAfee en cours..." "INFO"

    $Processes = @(
        Get-Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.ProcessName -match '(?i)^McAfee|^mf|^mfe'
            }
    )

    if ($Processes.Count -eq 0) {
        Write-Log "Aucun processus McAfee à arrêter" "INFO"
        return
    }

    foreach ($Process in $Processes) {

        try {
            Write-Log "Arrêt du processus McAfee : $($Process.ProcessName) (PID $($Process.Id))" "INFO"

            Stop-Process `
                -Id $Process.Id `
                -Force `
                -ErrorAction SilentlyContinue

        }
        catch {
            Write-Log "Impossible d'arrêter $($Process.ProcessName) : $($_.Exception.Message)" "WARN"
        }
    }

    Start-Sleep -Seconds 2
}


function ConvertTo-SilentUninstallCommand {

    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandLine
    )

    $CommandLine = $CommandLine.Trim()

    if ([string]::IsNullOrWhiteSpace($CommandLine)) {
        return $null
    }

    # --------------------------------------------------------
    # MSIEXEC
    # --------------------------------------------------------

    if ($CommandLine -match '(?i)^\s*"?[^"]*msiexec(?:\.exe)?"?\s+') {

        # Extraire le ProductCode si présent.
        if ($CommandLine -match '(?i)(\{[0-9A-F-]{36}\})') {

            $ProductCode = $Matches[1]

            return [PSCustomObject]@{
                FilePath  = "$env:SystemRoot\System32\msiexec.exe"
                Arguments = "/x $ProductCode /qn /norestart"
            }
        }

        # Si la commande MSI existante ne contient pas de code,
        # essayer de transformer /I en /X.
        $Arguments = $CommandLine `
            -replace '(?i)^\s*"?[^"]*msiexec(?:\.exe)?"?\s*', ''

        $Arguments = $Arguments `
            -replace '(?i)/I', '/X'

        if ($Arguments -notmatch '(?i)/q') {
            $Arguments += ' /qn'
        }

        if ($Arguments -notmatch '(?i)/norestart') {
            $Arguments += ' /norestart'
        }

        return [PSCustomObject]@{
            FilePath  = "$env:SystemRoot\System32\msiexec.exe"
            Arguments = $Arguments.Trim()
        }
    }

    # --------------------------------------------------------
    # EXE
    # --------------------------------------------------------

    $FilePath = $null
    $Arguments = $null

    # Commande entre guillemets :
    # "C:\Program Files\...\uninstall.exe" arguments
    if ($CommandLine -match '^\s*"([^"]+)"(?:\s+(.*))?$') {

        $FilePath = $Matches[1]
        $Arguments = $Matches[2]
    }
    else {

        # Chemin sans guillemets :
        # C:\...\uninstall.exe arguments
        if ($CommandLine -match '^\s*(\S+)(?:\s+(.*))?$') {

            $FilePath = $Matches[1]
            $Arguments = $Matches[2]
        }
    }

    if ([string]::IsNullOrWhiteSpace($FilePath)) {
        return $null
    }

    if (-not (Test-Path $FilePath)) {
        Write-Log "Programme de désinstallation introuvable : $FilePath" "WARN"
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($Arguments)) {
        $Arguments = ''
    }

    # --------------------------------------------------------
    # Ajout des commutateurs silencieux.
    #
    # On évite de doubler un paramètre déjà présent.
    # --------------------------------------------------------

    if ($Arguments -notmatch '(?i)(^|\s)(/quiet|/silent|/s|/qn|/verysilent)(\s|$)') {
        $Arguments += ' /quiet'
    }

    if ($Arguments -notmatch '(?i)(^|\s)(/norestart|/noRestart|REBOOT=ReallySuppress)(\s|$)') {
        $Arguments += ' /norestart'
    }

    return [PSCustomObject]@{
        FilePath  = $FilePath
        Arguments = $Arguments.Trim()
    }
}


function Invoke-McAfeeUninstall {

    param(
        [Parameter(Mandatory = $true)]
        $Entry
    )

    Write-Log "------------------------------------------------------------" "INFO"
    Write-Log "Produit McAfee : $($Entry.DisplayName)" "INFO"

    if (-not [string]::IsNullOrWhiteSpace($Entry.DisplayVersion)) {
        Write-Log "Version : $($Entry.DisplayVersion)" "INFO"
    }

    if (-not [string]::IsNullOrWhiteSpace($Entry.Publisher)) {
        Write-Log "Éditeur : $($Entry.Publisher)" "INFO"
    }

    Write-Log "Clé : $($Entry.RegistryPath)" "INFO"

    # --------------------------------------------------------
    # 1. QuietUninstallString
    # --------------------------------------------------------

    $CommandLine = $Entry.QuietUninstallString

    if (-not [string]::IsNullOrWhiteSpace($CommandLine)) {

        Write-Log "QuietUninstallString détecté" "INFO"
        Write-Log "Commande : $CommandLine" "INFO"

        $SilentCommand = ConvertTo-SilentUninstallCommand `
            -CommandLine $CommandLine
    }
    else {

        # ----------------------------------------------------
        # 2. UninstallString
        # ----------------------------------------------------

        $CommandLine = $Entry.UninstallString

        if ([string]::IsNullOrWhiteSpace($CommandLine)) {

            Write-Log "Aucune commande de désinstallation disponible pour $($Entry.DisplayName)" "ERROR"
            return $false
        }

        Write-Log "UninstallString détecté" "INFO"
        Write-Log "Commande : $CommandLine" "INFO"

        $SilentCommand = ConvertTo-SilentUninstallCommand `
            -CommandLine $CommandLine
    }

    if ($null -eq $SilentCommand) {

        Write-Log "Impossible de construire une commande de désinstallation silencieuse pour $($Entry.DisplayName)" "ERROR"

        return $false
    }

    Write-Log "Exécution silencieuse : $($SilentCommand.FilePath) $($SilentCommand.Arguments)" "INFO"

    try {

        $Process = Start-Process `
            -FilePath $SilentCommand.FilePath `
            -ArgumentList $SilentCommand.Arguments `
            -Wait `
            -PassThru `
            -WindowStyle Hidden `
            -ErrorAction Stop

        $ExitCode = $Process.ExitCode

        Write-Log "Programme de désinstallation terminé avec le code $ExitCode" "INFO"

        # Codes MSI classiques :
        # 0    = succès
        # 1641 = succès + redémarrage initié
        # 3010 = succès + redémarrage requis
        #
        # Pour CGLOBAL, on ne redémarre pas le poste ici.
        if ($ExitCode -eq 0) {
            Write-Log "Désinstallation terminée avec succès : $($Entry.DisplayName)" "OK"
            return $true
        }

        if ($ExitCode -eq 1641 -or $ExitCode -eq 3010) {
            Write-Log "Désinstallation réussie mais un redémarrage est requis (code $ExitCode)" "WARN"
            return $true
        }

        # Certains désinstalleurs renvoient 1 alors que la
        # désinstallation s'est néanmoins effectuée. On ne
        # considère pas encore cela comme un succès :
        # la vérification finale décidera.
        Write-Log "Le désinstalleur a retourné le code $ExitCode" "WARN"
        return $false
    }
    catch {

        Write-Log "Erreur lors de l'exécution du désinstalleur : $($_.Exception.Message)" "ERROR"

        return $false
    }
}


try {

    Write-Log "============================================================" "INFO"
    Write-Log "=== DÉSINSTALLATION MCAFEE ===" "INFO"
    Write-Log "============================================================" "INFO"

    # --------------------------------------------------------
    # 1. DÉTECTION
    # --------------------------------------------------------

    Write-Log "Recherche des produits McAfee installés..." "INFO"

    $McAfeeEntries = @(Get-McAfeeUninstallEntries)

    if ($McAfeeEntries.Count -eq 0) {

        Write-Log "Aucun produit McAfee détecté dans les programmes installés" "OK"
        Write-Log "Aucune action nécessaire" "INFO"

        exit 0
    }

    Write-Log "$($McAfeeEntries.Count) produit(s) McAfee détecté(s)" "WARN"

    foreach ($Entry in $McAfeeEntries) {

        Write-Log "McAfee détecté : $($Entry.DisplayName)" "WARN"

        if (-not [string]::IsNullOrWhiteSpace($Entry.DisplayVersion)) {
            Write-Log "  Version : $($Entry.DisplayVersion)" "INFO"
        }
    }

    # --------------------------------------------------------
    # 2. ARRÊT DES PROCESSUS
    # --------------------------------------------------------

    Stop-McAfeeProcesses

    # --------------------------------------------------------
    # 3. DÉSINSTALLATION
    # --------------------------------------------------------

    $SuccessCount = 0
    $FailureCount = 0

    foreach ($Entry in $McAfeeEntries) {

        $Result = Invoke-McAfeeUninstall -Entry $Entry

        if ($Result) {
            $SuccessCount++
        }
        else {
            $FailureCount++
        }

        # Laisser Windows actualiser les entrées
        # de désinstallation avant de passer au produit suivant.
        Start-Sleep -Seconds 2
    }

    # --------------------------------------------------------
    # 4. NOUVELLE DÉTECTION
    # --------------------------------------------------------

    Write-Log "Vérification finale de la présence de McAfee..." "INFO"

    Start-Sleep -Seconds 3

    $RemainingEntries = @(Get-McAfeeUninstallEntries)

    if ($RemainingEntries.Count -eq 0) {

        Write-Log "Aucun produit McAfee restant dans les programmes installés" "OK"
        Write-Log "=== DÉSINSTALLATION MCAFEE TERMINÉE ===" "OK"

        exit 0
    }

    # --------------------------------------------------------
    # 5. RÉSULTAT PARTIEL
    # --------------------------------------------------------

    Write-Log "$($RemainingEntries.Count) produit(s) McAfee restent enregistrés après la désinstallation" "WARN"

    foreach ($Remaining in $RemainingEntries) {
        Write-Log "Produit restant : $($Remaining.DisplayName)" "WARN"
    }

    Write-Log "Certaines composantes McAfee n'ont pas pu être supprimées automatiquement" "WARN"

    # Code 0 car le script a effectué son traitement sans
    # erreur PowerShell. La présence résiduelle est signalée
    # dans le journal.
    exit 0
}
catch {

    Write-Log "ERREUR CRITIQUE : $($_.Exception.Message)" "ERROR"

    if ($_.ScriptStackTrace) {
        Write-Log $_.ScriptStackTrace "ERROR"
    }

    exit 1
}