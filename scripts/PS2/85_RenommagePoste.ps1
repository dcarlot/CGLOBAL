#Requires -Version 5.1
#Requires -RunAsAdministrator

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

    $Choice = Show-CGlobalPopup -Title 'Renommage du poste' -Buttons 'YesNoCancel' -Icon 'Question' -Message @"
Le nom actuel du poste est : $CurrentName

Voulez-vous modifier le nom du poste ?
"@

    if ($Choice -ne [System.Windows.Forms.DialogResult]::Yes) {
        Write-Log 'Renommage du poste ignoré par l utilisateur' 'OK'
        exit 0
    }

    $RenameDone = $false

    while (-not $RenameDone) {
        $NewName = Read-NewComputerName -CurrentName $CurrentName

        if ($null -eq $NewName) {
            Write-Log 'Saisie du nouveau nom annulée par l''utilisateur' 'WARN'
            exit 0
        }

        $NewName = $NewName.Trim()

        $Check = Test-ComputerNameCompatibility -Name $NewName -CurrentName $CurrentName

        if (-not $Check.IsValid) {
            Write-Log "Nom refuse ($NewName) : $($Check.Reason)" 'WARN'
            if ((Get-CGlobalExecutionMode) -ne 'Interactif') {
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

    Show-CGlobalPopup -Title 'Redémarrage requis' -Buttons 'OK' -Icon 'Exclamation' -Message @"
Le poste a été renommé en '$NewName'.

Ce changement ne sera effectif qu'après un redémarrage complet du poste.
"@ | Out-Null

    Write-Log 'Popup de redémarrage requis affichée à l opérateur' 'WARN'
    Write-Log 'Renommage du poste terminé' 'OK'
    exit 0
}
catch {
    Write-Log $_.Exception.Message 'ERROR'
    exit 1
}
