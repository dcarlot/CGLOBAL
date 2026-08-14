#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Liste toutes les versions d'Office installees sur le poste (Click-to-Run et MSI),
    puis demande une confirmation avant de les desinstaller (ou de ne rien faire).

.DESCRIPTION
    - Recherche les installations Office dans les cles de registre "Uninstall"
      standard (32 et 64 bits), qui sont les memes cles utilisees par
      "Programmes et fonctionnalites".
    - Reutilise directement la commande UninstallString presente dans le
      registre (celle que Windows utilise lui-meme), en y ajoutant les
      parametres de mode silencieux. C'est plus fiable que de reconstruire
      la commande soi-meme.
    - Affiche la liste numerotee des produits trouves.
    - Attend une validation explicite de l'utilisateur (O/N).
    - Si validation positive : desinstalle toutes les versions trouvees.
    - Si validation negative : ne fait rien et quitte proprement.

.NOTES
    A executer en tant qu'administrateur (elevation requise).
    Fichier enregistre sans caracteres accentues pour eviter les problemes
    d'affichage lies a l'encodage selon l'editeur utilise.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

function Get-OfficeInstalls {
    $installs = @()

# Monte HKU pour analyser tous les profils utilisateurs
if (-not (Get-PSDrive -Name HKU -ErrorAction SilentlyContinue)) {
    New-PSDrive -PSProvider Registry -Name HKU -Root HKEY_USERS | Out-Null
}

$uninstallKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKU:\*\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

    foreach ($keyPath in $uninstallKeys) {
        Get-ItemProperty -Path $keyPath -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -match 'Microsoft (Office|365|Project|Visio)' -and
                $_.DisplayName -notmatch 'Update|MUI|Redistributable|Runtime|Licensing' -and
                $_.UninstallString
            } |
            ForEach-Object {

                $type = 'Inconnu'
                if ($_.UninstallString -match 'OfficeClickToRun\.exe|OfficeC2RClient\.exe') {
                    $type = 'Click-to-Run'
                }
                elseif ($_.UninstallString -match 'msiexec') {
                    $type = 'MSI'
                }

                $installs += [PSCustomObject]@{
					Nom             = $_.DisplayName
					Version         = $_.DisplayVersion
					Type            = $type
					UninstallString = $_.UninstallString
					CleSource       = $_.PSParentPath
				}
            }
    }

    # Deduplique au cas ou la meme entree apparaisse dans les deux cles (32/64 bits)
    $installs = $installs | Sort-Object Nom, UninstallString -Unique

    return $installs
}

function Show-DiagnosticSiVide {

    Write-Log "Diagnostic de recherche Office" "WARN"

    $c2rPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'

    if (Test-Path $c2rPath) {

        $cfg = Get-ItemProperty `
            -Path $c2rPath `
            -ErrorAction SilentlyContinue

        Write-Log (
            "Configuration ClickToRun detectee : ProductReleaseIds={0}" -f `
                $cfg.ProductReleaseIds
        ) "WARN"

        Write-Log (
            "Office semble present mais aucune entree Uninstall n'a ete detectee"
        ) "WARN"

        Write-Log (
            "Probable preinstallation OEM de type Stub / Trial"
        ) "WARN"
    }
    else {

        Write-Log (
            "Aucune configuration ClickToRun detectee"
        ) "WARN"
    }
}

function Invoke-OfficeUninstall {

    param($item)

    if ($item.Type -eq 'Click-to-Run') {

        $cmd = $item.UninstallString

        if ($cmd -notmatch 'DisplayLevel=') {
            $cmd += ' DisplayLevel=False'
        }

        if ($cmd -match '^"([^"]+)"\s*(.*)$') {

            $exe  = $Matches[1]
            $Arguments = $Matches[2]

            Start-Process `
                -FilePath $exe `
                -ArgumentList $Arguments `
                -Wait

            Write-Log "$($item.Nom) desinstalle" "OK"
        }
        else {

            Write-Log (
                "Format de commande Click-to-Run inattendu pour : {0}" -f `
                    $item.Nom
            ) "WARN"
        }
    }

    elseif ($item.Type -eq 'MSI') {

        if ($item.UninstallString -match '\{[0-9A-Fa-f\-]+\}') {

            $guid = $Matches[0]

            Start-Process `
                -FilePath 'msiexec.exe' `
                -ArgumentList "/x $guid /quiet /norestart" `
                -Wait

            Write-Log "$($item.Nom) desinstalle" "OK"
        }
        else {

            Write-Log (
                "Impossible d extraire le GUID pour : {0}" -f `
                    $item.Nom
            ) "WARN"
        }
    }

    else {

        Write-Log (
            "Type de desinstallation non reconnu pour : {0} -> {1}" -f `
                $item.Nom,
                $item.UninstallString
        ) "WARN"
    }
}

# ------------------------------------------------------------------
# Etape 1 : Detection
# ------------------------------------------------------------------

Write-Log "Recherche des installations Microsoft Office sur ce poste"

$officeInstalls = Get-OfficeInstalls

# Force le resultat dans un tableau meme si un seul element est retourne
$officeInstalls = @($officeInstalls)

if (-not $officeInstalls -or $officeInstalls.Count -eq 0) {

    Write-Log "Aucune installation Office detectee sur ce poste" "OK"

    Show-DiagnosticSiVide

    exit 0
}

# ------------------------------------------------------------------
# Etape 2 : Affichage de la liste
# ------------------------------------------------------------------

Write-Host "`nVersions d'Office detectees :" -ForegroundColor Yellow

$i = 1

Write-Log "$($officeInstalls.Count) version(s) Office detectee(s)" "WARN"

foreach ($item in $officeInstalls) {

    Write-Log (
        "Detecte [{0}] {1} - Version={2}" -f `
            $item.Type, `
            $item.Nom, `
            $item.Version
    )

    Write-Log (
        "Source registre : {0}" -f `
            $item.CleSource
    )

    Write-Host (
        "  [{0}] {1} - Version : {2} - Type : {3}" -f `
            $i, `
            $item.Nom, `
            $item.Version, `
            $item.Type
    )

    $i++
}

# ------------------------------------------------------------------
# Etape 3 : Validation utilisateur
# ------------------------------------------------------------------

$reponse = Show-CGlobalPopup `
    -Message "Voulez-vous desinstaller TOUTES ces versions d'Office ?`n`nCette action est irreversible." `
    -Title "Desinstallation Office" `
    -Buttons "YesNo" `
    -Icon "Exclamation"


if ($reponse -ne 'Yes') {
    Write-Log "Desinstallation Office annulee par l utilisateur" "WARN"
    exit 0
}

# ------------------------------------------------------------------
# Etape 4 : Desinstallation
# ------------------------------------------------------------------
Write-Log "Desinstallation Office en cours" "WARN"

foreach ($item in $officeInstalls) {
    
	Write-Log (
    "Desinstallation [{0}] {1}" -f `
        $item.Type,
        $item.Nom
	) "WARN"

    try {
        Invoke-OfficeUninstall -item $item
    }
    catch {
        Write-Log (
    "Echec de la desinstallation de {0} : {1}" -f `
        $item.Nom,
        $_.Exception.Message
	) "ERROR"
    }
}

Write-Log "Desinstallation Office terminee" "OK"
Write-Log "Un redemarrage du poste est recommande" "WARN"