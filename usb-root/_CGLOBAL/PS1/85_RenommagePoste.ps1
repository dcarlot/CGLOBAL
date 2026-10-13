#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
 Affiche le nom actuel du poste et permet de le modifier après
 vérification de compatibilité (lettres, chiffres, trait d'union).

.NOTES
 A executer en tant qu'administrateur (elevation requise).
 Limite historique du nom NetBIOS, toujours appliquée par Windows
 pour le nom du poste (15 caractères maximum).

 VERSION CORRIGEE : Support du mode Prevalidé / Silencieux via
 Get-CGlobalDecision -Key 'RenameComputer' et 'NewComputerName'
#>

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

# Limite historique du nom NetBIOS, toujours appliquée par Windows pour le nom du poste
$script:MaxComputerNameLength = 15

function Test-ComputerNameCompatibility {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Name,
        [Parameter(Mandatory = $true)][string]$CurrentName
    )

    # Saisie vide (y compris un champ effacé puis validé avec OK) : traitée ici,
    # distincte du clic sur Annuler qui renvoie $null à un niveau au-dessus.
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return [PSCustomObject]@{ IsValid = $false; Reason = 'Le nom ne peut pas etre vide.' }
    }

    $Trimmed = $Name.Trim()

    if ($Trimmed.ToUpperInvariant() -eq $CurrentName.ToUpperInvariant()) {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = "Le nom saisi est identique au nom actuel ($CurrentName)."
        }
    }

    if ($Trimmed.Length -gt $script:MaxComputerNameLength) {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = "Le nom dépasse $script:MaxComputerNameLength caractères (limite Windows/NetBIOS)."
        }
    }

    if ($Trimmed -notmatch '^[A-Za-z0-9-]+$') {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = 'Seuls les lettres, les chiffres et le trait d''union sont autorisés (sans espace ni accent).'
        }
    }

    if ($Trimmed -match '^-|-$') {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = 'Le nom ne peut pas commencer ni se terminer par un trait d''union.'
        }
    }

    if ($Trimmed -match '^[0-9]+$') {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = 'Le nom ne peut pas être composé uniquement de chiffres.'
        }
    }

    return [PSCustomObject]@{ IsValid = $true; Reason = $null }
}

function Read-NewComputerName {
    param([Parameter(Mandatory = $true)][string]$CurrentName)

    $NewName = Show-CGlobalInputBox -Title 'Renommage du poste' -DefaultText $CurrentName -Message @"
Nom actuel du poste : $CurrentName

Saisissez le nouveau nom du poste (lettres, chiffres et trait d'union uniquement, 15 caractères maximum) :
"@

    return $NewName
}

try {
    Write-Log '=== RENOMMAGE DU POSTE ==='

    $CurrentName = $env:COMPUTERNAME
    Write-Log "Nom actuel du poste : $CurrentName"

    # ============================================================
    # CORRIGE : Support du mode Prevalidé/Silencieux
    # ============================================================
    $ExecutionMode = Get-CGlobalExecutionMode
    $Choice = $null
    $PrevalidatedName = $null

    if ($ExecutionMode -ne 'Interactif') {
        # Mode Prévalidé ou Silencieux : utiliser les décisions centralisées
        $Choice = [string](Get-CGlobalDecision -Key 'RenameComputer' -Default 'No')
        $PrevalidatedName = [string](Get-CGlobalDecision -Key 'NewComputerName' -Default '')
        Write-Log "Mode $ExecutionMode : décision prévalidée Rename = $Choice, Nom = $PrevalidatedName" "INFO"
    }

    if ($null -eq $Choice) {
        # Mode Interactif : popup classique
        $Choice = [string](Show-CGlobalPopup -Title 'Renommage du poste' -Buttons 'YesNoCancel' -Icon 'Question' -Message @"
Le nom actuel du poste est : $CurrentName

Voulez-vous modifier le nom du poste ?
"@)
    }

    if ($Choice -ne 'Yes') {
        Write-Log 'Renommage du poste ignoré' 'OK'
        exit 0
    }

    $RenameDone = $false

    while (-not $RenameDone) {
        # Utiliser le nom prévalidé s'il est disponible (une seule fois)
        if ($null -ne $PrevalidatedName -and -not [string]::IsNullOrWhiteSpace($PrevalidatedName)) {
            $NewName = $PrevalidatedName
            $PrevalidatedName = $null  # Ne plus utiliser après la première tentative
        }
        else {
            $NewName = Read-NewComputerName -CurrentName $CurrentName
        }

        if ($null -eq $NewName) {
            Write-Log 'Saisie du nouveau nom annulée par l''utilisateur' 'WARN'
            exit 0
        }

        $NewName = $NewName.Trim()

        $Check = Test-ComputerNameCompatibility -Name $NewName -CurrentName $CurrentName

        if (-not $Check.IsValid) {
            Write-Log "Nom refuse ($NewName) : $($Check.Reason)" 'WARN'
            if ($ExecutionMode -ne 'Interactif') {
                Write-Log 'Renommage annule : le nom prevalide est invalide' 'ERROR'
                exit 1
            }
            $Retry = Show-CGlobalPopup -Title 'Nom de poste invalide' -Buttons 'OKCancel' -Icon 'Exclamation' -Message @"
Le nom saisi n'est pas compatible avec les règles Windows :

$($Check.Reason)

Cliquez sur OK pour ressaisir un nom, ou sur Annuler pour abandonner le renommage.
"@
            if ($Retry -ne [System.Windows.Forms.DialogResult]::OK) {
                Write-Log 'Renommage du poste abandonné après nom invalide' 'WARN'
                exit 0
            }
            continue
        }

        Write-Log "Nom '$NewName' valide, tentative de renommage du poste" 'OK'

        try {
            Rename-Computer -NewName $NewName -Force -ErrorAction Stop
            $RenameDone = $true
        }
        catch {
            Write-Log "Échec du renommage vers '$NewName' : $($_.Exception.Message)" 'ERROR'
            if ($ExecutionMode -ne 'Interactif') {
                Write-Log 'Renommage annule : échec en mode non-interactif' 'ERROR'
                exit 1
            }
            $Retry = Show-CGlobalPopup -Title 'Échec du renommage' -Buttons 'OKCancel' -Icon 'Exclamation' -Message @"
Le renommage du poste vers '$NewName' a échoué :

$($_.Exception.Message)

Cliquez sur OK pour ressaisir un nom, ou sur Annuler pour abandonner le renommage.
"@
            if ($Retry -ne [System.Windows.Forms.DialogResult]::OK) {
                Write-Log 'Renommage du poste abandonné après échec' 'WARN'
                exit 0
            }
        }
    }

    Write-Log "Poste renommé avec succès : $CurrentName -> $NewName" 'OK'

    # Popup de redémarrage uniquement en mode interactif
    if ($ExecutionMode -eq 'Interactif') {
        Show-CGlobalPopup -Title 'Redémarrage requis' -Buttons 'OK' -Icon 'Exclamation' -Message @"
Le poste a été renommé en '$NewName'.

Ce changement ne sera effectif qu'après un redémarrage complet du poste.
"@ | Out-Null

        Write-Log 'Popup de redémarrage requis affiché à l opérateur' 'WARN'
    }
    else {
        Write-Log "Redémarrage requis pour appliquer le renommage (mode $ExecutionMode, pas de popup)" 'WARN'
    }

    Write-Log 'Renommage du poste terminé' 'OK'
    exit 0
}
catch {
    Write-Log $_.Exception.Message 'ERROR'
    exit 1
}
