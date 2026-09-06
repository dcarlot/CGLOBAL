#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

# Limite historique du nom NetBIOS, toujours appliquee par Windows pour le nom du poste
$script:MaxComputerNameLength = 15

function Test-ComputerNameCompatibility {
    param([Parameter(Mandatory = $true)][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return [PSCustomObject]@{ IsValid = $false; Reason = 'Le nom ne peut pas etre vide.' }
    }

    $Trimmed = $Name.Trim()

    if ($Trimmed.Length -gt $script:MaxComputerNameLength) {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = "Le nom depasse $script:MaxComputerNameLength caracteres (limite Windows/NetBIOS)."
        }
    }

    if ($Trimmed -notmatch '^[A-Za-z0-9-]+$') {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = 'Seuls les lettres, les chiffres et le trait d''union sont autorises (sans espace ni accent).'
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
            Reason  = 'Le nom ne peut pas etre compose uniquement de chiffres.'
        }
    }

    return [PSCustomObject]@{ IsValid = $true; Reason = $null }
}

function Read-NewComputerName {
    param([Parameter(Mandatory = $true)][string]$CurrentName)

    $NewName = Show-CGlobalInputBox -Title 'Renommage du poste' -DefaultText $CurrentName -Message @"
Nom actuel du poste : $CurrentName

Saisissez le nouveau nom du poste (lettres, chiffres et trait d'union uniquement, 15 caracteres maximum) :
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
        Write-Log 'Renommage du poste ignore par l utilisateur' 'OK'
        exit 0
    }

    $RenameDone = $false

    while (-not $RenameDone) {
        $NewName = Read-NewComputerName -CurrentName $CurrentName

        if ($null -eq $NewName) {
            Write-Log 'Saisie du nouveau nom annulee par l utilisateur' 'WARN'
            exit 0
        }

        $NewName = $NewName.Trim()

        if ($NewName.ToUpperInvariant() -eq $CurrentName.ToUpperInvariant()) {
            Show-CGlobalPopup -Title 'Renommage du poste' -Buttons 'OK' -Icon 'Information' `
                -Message "Le nom saisi est identique au nom actuel ($CurrentName).`n`nAucune modification n'est necessaire." | Out-Null
            Write-Log 'Nom saisi identique au nom actuel : aucune modification effectuee' 'OK'
            exit 0
        }

        $Check = Test-ComputerNameCompatibility -Name $NewName

        if (-not $Check.IsValid) {
            Write-Log "Nom refuse ($NewName) : $($Check.Reason)" 'WARN'
            $Retry = Show-CGlobalPopup -Title 'Nom de poste invalide' -Buttons 'OKCancel' -Icon 'Exclamation' -Message @"
Le nom saisi n'est pas compatible avec les regles Windows :

$($Check.Reason)

Cliquez sur OK pour ressaisir un nom, ou sur Annuler pour abandonner le renommage.
"@
            if ($Retry -ne [System.Windows.Forms.DialogResult]::OK) {
                Write-Log 'Renommage du poste abandonne apres nom invalide' 'WARN'
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
            Write-Log "Echec du renommage vers '$NewName' : $($_.Exception.Message)" 'ERROR'
            $Retry = Show-CGlobalPopup -Title 'Echec du renommage' -Buttons 'OKCancel' -Icon 'Exclamation' -Message @"
Le renommage du poste vers '$NewName' a echoue :

$($_.Exception.Message)

Cliquez sur OK pour ressaisir un nom, ou sur Annuler pour abandonner le renommage.
"@
            if ($Retry -ne [System.Windows.Forms.DialogResult]::OK) {
                Write-Log 'Renommage du poste abandonne apres echec' 'WARN'
                exit 0
            }
        }
    }

    Write-Log "Poste renomme avec succes : $CurrentName -> $NewName" 'OK'

    Show-CGlobalPopup -Title 'Redemarrage requis' -Buttons 'OK' -Icon 'Exclamation' -Message @"
Le poste a ete renomme en '$NewName'.

Ce changement ne sera effectif qu'apres un redemarrage complet du poste.
"@ | Out-Null

    Write-Log 'Popup de redemarrage requis affichee a l operateur' 'WARN'
    Write-Log 'Renommage du poste termine' 'OK'
    exit 0
}
catch {
    Write-Log $_.Exception.Message 'ERROR'
    exit 1
}
