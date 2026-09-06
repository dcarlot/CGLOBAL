#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$USBPath = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

# ============================================================
# Chargement du module commun
# ============================================================
$ModulePath = "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1"
if (Test-Path $ModulePath) {
    Import-Module $ModulePath -Force
}

# ============================================================
# Configuration du log
# ============================================================
$LogFolder = "C:\_CGLOBAL\Logs"
if (-not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}
$LogFile = "$LogFolder\LogRun_Selective.txt"

function Write-LogSelective {
    param(
        [string]$Message,
        [ValidateSet('INFO','OK','WARN','ERROR')]
        [string]$Level = 'INFO'
    )
    $Line = "[{0}] [{1,-5}] {2}" -f (Get-Date -Format "HH:mm:ss"), $Level, $Message
    Add-Content -Path $LogFile -Value $Line -Encoding UTF8
    Write-Host $Line -ForegroundColor $(@{INFO='Cyan';OK='Green';WARN='Yellow';ERROR='Red'}[$Level])
}

Write-LogSelective "=== LANCEMENT MODE SELECTIF ===" "INFO"

# ============================================================
# Fichier de memorisation (.sel = simple, pas de JSON)
# ============================================================
$SelFile = "C:\_CGLOBAL\Run_Selective.sel"

function Export-Selection {
    param($Checkboxes)
    $Lines = @()
    foreach ($Num in ($Checkboxes.Keys | Sort-Object)) {
        $Checked = if ($Checkboxes[$Num].Checked) { 1 } else { 0 }
        $Lines += "$Num=$Checked"
    }
    $Lines | Set-Content -Path $SelFile -Encoding UTF8
    Write-LogSelective "Selection sauvegardee dans $SelFile" "OK"
}

function Import-Selection {
    param($Checkboxes)
    if (-not (Test-Path $SelFile)) {
        Write-LogSelective "Aucune selection precedente trouvee" "INFO"
        return $false
    }
    try {
        $Lines = Get-Content -Path $SelFile -Encoding UTF8
        foreach ($Line in $Lines) {
            if ($Line -match '^([0-9]+)=(0|1)$') {
                $Num = $Matches[1]
                $Checked = [int]$Matches[2]
                if ($Checkboxes.ContainsKey($Num)) {
                    $Checkboxes[$Num].Checked = ($Checked -eq 1)
                }
            }
        }
        Write-LogSelective "Selection chargee depuis $SelFile" "OK"
        return $true
    }
    catch {
        Write-LogSelective "Erreur chargement selection : $($_.Exception.Message)" "WARN"
        return $false
    }
}

# ============================================================
# Definition des scripts (a jour avec le depot GitHub)
# ============================================================
$Scripts = @(
    @{ Num="00"; File="00_ModeDeploiement.ps1"; Desc="Mode deploiement (veille, ecran, WU)"; Tooltip="Desactive la veille, l extinction d ecran et les redemarrages auto de Windows Update"; Net=$false },
    @{ Num="01"; File="01_Bureau.ps1"; Desc="Icones systeme sur le bureau"; Tooltip="Affiche Ce PC, Panneau de configuration, Corbeille et Reseau sur le Bureau"; Net=$false },
    @{ Num="02"; File="02_MenuContextuelClassique.ps1"; Desc="Menu contextuel classique"; Tooltip="Restaure le menu contextuel de Windows 10/11 classique (clic droit)"; Net=$false },
    @{ Num="03"; File="03_Explorateur.ps1"; Desc="Explorateur (Ce PC, extensions)"; Tooltip="Ouvre l Explorateur sur Ce PC et affiche les extensions de fichiers"; Net=$false },
    @{ Num="04"; File="04_ZoneNotification.ps1"; Desc="Zone de notification"; Tooltip="Affiche toutes les icones connues dans la zone de notification"; Net=$false },
    @{ Num="05"; File="05_BarreTachesGauche.ps1"; Desc="Barre des taches a gauche"; Tooltip="Aligne les icones de la barre des taches a gauche"; Net=$false },
    @{ Num="06"; File="06_RechercheBarreTaches.ps1"; Desc="Recherche en mode icone"; Tooltip="Affiche uniquement l icone de recherche (pas la barre complete)"; Net=$false },
    @{ Num="07"; File="07_MasquerVueTaches.ps1"; Desc="Masquer le bouton Vue des taches"; Tooltip="Masque le bouton Vue des taches de la barre des taches"; Net=$false },
    @{ Num="08"; File="08_MasquerWidgets.ps1"; Desc="Desinstaller les Widgets"; Tooltip="Desinstalle completement le package Windows Web Experience Pack (Widgets)"; Net=$false },
    @{ Num="09"; File="09_MSStoreBarreTache.ps1"; Desc="Supprimer MS Store barre des taches"; Tooltip="Supprime l epingle Microsoft Store de la barre des taches et bloque son retour"; Net=$false },
    @{ Num="10"; File="10_DesactiverReprendre.ps1"; Desc="Desactiver Reprendre"; Tooltip="Desactive la fonction Reprendre (Resume) au demarrage"; Net=$false },
    @{ Num="11"; File="11_ConfidentialiteLocalisation.ps1"; Desc="Confidentialite / localisation"; Tooltip="Desactive les notifications de localisation et le remplacement de localisation"; Net=$false },
    @{ Num="12"; File="12_ConfigurerProfilParDefaut.ps1"; Desc="Configurer profil par defaut"; Tooltip="Configure les reglages pour les futurs profils utilisateurs (NTUSER.DAT)"; Net=$false },
    @{ Num="13"; File="13_NumLockDemarrage.ps1"; Desc="NumLock au demarrage"; Tooltip="Force l activation du verrouillage numerique au demarrage"; Net=$false },
    @{ Num="14"; File="14_DesinstallationOffice.ps1"; Desc="Desinstallation Office / OneNote"; Tooltip="Detecte et desinstalle toutes les versions d Office et OneNote (C2R, MSI)"; Net=$false },
    @{ Num="15"; File="15_ApplicationsWinget.ps1"; Desc="Applications Winget [INTERNET]"; Tooltip="Installe 7-Zip, Acrobat Reader, Chrome et Firefox via WinGet (connexion Internet requise)"; Net=$true },
    @{ Num="16"; File="16_TeamViewerQS.ps1"; Desc="TeamViewer QuickSupport [INTERNET]"; Tooltip="Telecharge et installe TeamViewer QuickSupport (connexion Internet requise)"; Net=$true },
    @{ Num="17"; File="17_DesinstallationOneDrive.ps1"; Desc="Desinstallation OneDrive"; Tooltip="Desinstalle OneDrive, bloque son retour pour les futurs profils et supprime les raccourcis"; Net=$false },
    @{ Num="19"; File="19_MisesAJourConstructeur.ps1"; Desc="Mises a jour constructeur [INTERNET]"; Tooltip="Detecte le constructeur et installe les mises a jour pilotes, BIOS et firmware sans redemarrer le poste pendant la sequence"; Net=$true },
    @{ Num="85"; File="85_RenommagePoste.ps1"; Desc="Renommage du poste"; Tooltip="Affiche le nom actuel du poste et permet de le modifier apres verification de compatibilite (lettres, chiffres, trait d union)"; Net=$false },
    @{ Num="90"; File="90_VerificationMotDePasseCompteLocal.ps1"; Desc="Verification mot de passe local"; Tooltip="Verifie si le compte local possede un mot de passe et propose d en definir un"; Net=$false },
    @{ Num="99"; File="99_FinDeploiement.ps1"; Desc="Fin deploiement (restauration)"; Tooltip="Restaure les parametres energetiques et Windows Update (fin du mode deploiement)"; Net=$false }
)

# ============================================================
# Test de connexion Internet (identique a Run_Install.cmd)
# ============================================================
function Test-InternetConnection {
    param([switch]$Silent)

    if (-not $Silent) {
        Write-LogSelective "Test de connexion Internet..." "INFO"
    }

    $Urls = @(
        @{ Host = "download.microsoft.com"; Port = 443 },
        @{ Host = "get.teamviewer.com"; Port = 443 }
    )

    $Connected = $false
    foreach ($Url in $Urls) {
        try {
            $TcpClient = New-Object System.Net.Sockets.TcpClient
            $TcpClient.Connect($Url.Host, $Url.Port)
            if ($TcpClient.Connected) {
                $TcpClient.Close()
                $Connected = $true
                break
            }
        }
        catch {
            # URL suivante
        }
        finally {
            if ($null -ne $TcpClient) {
                $TcpClient.Dispose()
            }
        }
    }

    if ($Connected) {
        if (-not $Silent) {
            Write-LogSelective "Connexion Internet OK" "OK"
        }
        return $true
    }

    if (-not $Silent) {
        Write-LogSelective "Aucune connexion Internet detectee" "WARN"
    }
    return $false
}

# ============================================================
# Resolution de l'absence de connexion Internet
# Retourne : "OK" (connexion retablie), "CANCEL" (annuler tout),
#            "CONTINUE_WITHOUT" (continuer sans les scripts Internet)
# ============================================================
function Resolve-InternetRequirement {
    param(
        [array]$ScriptsNeedingNet
    )

    $ScriptsInternetText = ($ScriptsNeedingNet | ForEach-Object { "[$($_.Num)] $($_.Desc)" }) -join "`n"

    # --- Boucle de reessai ---
    do {
        $RetryResult = [System.Windows.Forms.MessageBox]::Show(
            "Aucun acces Internet detecte.`n`nLes scripts suivants necessitent Internet :`n$ScriptsInternetText`n`nVoulez-vous reessayer ?",
            "Internet requis",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($RetryResult -eq [System.Windows.Forms.DialogResult]::No) {
            break
        }

        if (Test-InternetConnection) {
            return "OK"
        }

    } while ($true)

    # --- Toujours pas de connexion (ou l'utilisateur a refuse de reessayer) : choix final ---
    $CancelResult = [System.Windows.Forms.MessageBox]::Show(
        "Toujours aucun acces Internet.`n`nLes scripts suivants necessitent Internet :`n$ScriptsInternetText`n`n- OUI = Annuler tout le lancement (retour a la selection)`n- NON = Continuer SANS ces scripts (avertissement)",
        "Internet requis",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($CancelResult -eq [System.Windows.Forms.DialogResult]::Yes) {
        return "CANCEL"
    }
    else {
        return "CONTINUE_WITHOUT"
    }
}

# ============================================================
# Creation du formulaire principal
# ============================================================
Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public class DpiHelper {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@
[DpiHelper]::SetProcessDPIAware()

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "CGLOBAL - Mode Selectif"
$Form.Width = 920
$Form.Height = 860
$Form.StartPosition = "CenterScreen"
$Form.FormBorderStyle = "FixedDialog"
$Form.MaximizeBox = $false
$Form.MinimizeBox = $false
$Form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi

# --- Titre ---
$TitleLabel = New-Object System.Windows.Forms.Label
$TitleLabel.Text = "CGLOBAL - Selection des scripts a executer"
$TitleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$TitleLabel.Location = New-Object System.Drawing.Point(20, 15)
$TitleLabel.Width = 860
$TitleLabel.Height = 30
$Form.Controls.Add($TitleLabel)

# --- Sous-titre ---
$SubLabel = New-Object System.Windows.Forms.Label
$SubLabel.Text = "Cochez les scripts a lancer, puis cliquez sur Executer. Survolez un script pour voir sa description."
$SubLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$SubLabel.Location = New-Object System.Drawing.Point(20, 50)
$SubLabel.Width = 860
$SubLabel.Height = 20
$Form.Controls.Add($SubLabel)

# --- Panel de gauche : liste des scripts (sans scroll) ---
$Panel = New-Object System.Windows.Forms.Panel
$Panel.Location = New-Object System.Drawing.Point(20, 80)
$Panel.Width = 560
$Panel.Height = 560
$Panel.BorderStyle = "FixedSingle"
$Form.Controls.Add($Panel)

# --- Tooltip global ---
$Tooltip = New-Object System.Windows.Forms.ToolTip
$Tooltip.AutoPopDelay = 10000
$Tooltip.InitialDelay = 500
$Tooltip.ReshowDelay = 200
$Tooltip.ShowAlways = $true

$Checkboxes = @{}
$Results = @{}
$Y = 10

foreach ($Script in $Scripts) {
    $CB = New-Object System.Windows.Forms.CheckBox
    $CB.Text = "[$($Script.Num)] $($Script.Desc)"
    $CB.Location = New-Object System.Drawing.Point(10, $Y)
    $CB.Width = 530
    $CB.Height = 22
    $CB.Tag = $Script

    if ($Script.Net) {
        $CB.ForeColor = [System.Drawing.Color]::DarkOrange
    }

    $Tooltip.SetToolTip($CB, $Script.Tooltip)

    $Panel.Controls.Add($CB)
    $Checkboxes[$Script.Num] = $CB
    $Results[$Script.Num] = $null
    $Y += 26
}

# ============================================================
# Colonne de droite : boutons de controle
# ============================================================
$RightX = 600

# --- Bouton Tous ---
$BtnTous = New-Object System.Windows.Forms.Button
$BtnTous.Text = "Tous"
$BtnTous.Location = New-Object System.Drawing.Point($RightX, 80)
$BtnTous.Width = 120
$BtnTous.Height = 32
$BtnTous.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$BtnTous.Add_Click({
    foreach ($CB in $Checkboxes.Values) {
        $CB.Checked = $true
    }
})
$Form.Controls.Add($BtnTous)

# --- Bouton Aucun ---
$BtnAucun = New-Object System.Windows.Forms.Button
$BtnAucun.Text = "Aucun"
$BtnAucun.Location = New-Object System.Drawing.Point(($RightX + 130), 80)
$BtnAucun.Width = 120
$BtnAucun.Height = 32
$BtnAucun.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$BtnAucun.Add_Click({
    foreach ($CB in $Checkboxes.Values) {
        $CB.Checked = $false
    }
})
$Form.Controls.Add($BtnAucun)

# --- Bouton Sauvegarder ---
$BtnSave = New-Object System.Windows.Forms.Button
$BtnSave.Text = "Sauvegarder"
$BtnSave.Location = New-Object System.Drawing.Point($RightX, 125)
$BtnSave.Width = 120
$BtnSave.Height = 32
$BtnSave.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$BtnSave.Add_Click({
    Export-Selection -Checkboxes $Checkboxes
    [System.Windows.Forms.MessageBox]::Show(
        "Selection sauvegardee avec succes.",
        "Sauvegarde",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
})
$Form.Controls.Add($BtnSave)

# --- Bouton Charger ---
$BtnLoad = New-Object System.Windows.Forms.Button
$BtnLoad.Text = "Charger"
$BtnLoad.Location = New-Object System.Drawing.Point(($RightX + 130), 125)
$BtnLoad.Width = 120
$BtnLoad.Height = 32
$BtnLoad.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$BtnLoad.Add_Click({
    if (Import-Selection -Checkboxes $Checkboxes) {
        [System.Windows.Forms.MessageBox]::Show(
            "Selection chargee avec succes.",
            "Chargement",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    }
    else {
        [System.Windows.Forms.MessageBox]::Show(
            "Aucune selection precedente trouvee.",
            "Chargement",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
    }
})
$Form.Controls.Add($BtnLoad)

# --- Label Internet ---
$NetLabel = New-Object System.Windows.Forms.Label
$NetLabel.Text = "[INTERNET] = necessite une connexion Internet"
$NetLabel.ForeColor = [System.Drawing.Color]::DarkOrange
$NetLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$NetLabel.Location = New-Object System.Drawing.Point($RightX, 175)
$NetLabel.Width = 260
$NetLabel.Height = 20
$Form.Controls.Add($NetLabel)

# --- Legende resultats ---
$LegendLabel = New-Object System.Windows.Forms.Label
$LegendLabel.Text = "Legende :`n  Vert  = succes`n  Jaune = avertissement`n  Rouge = erreur / introuvable"
$LegendLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$LegendLabel.Location = New-Object System.Drawing.Point($RightX, 210)
$LegendLabel.Width = 260
$LegendLabel.Height = 80
$Form.Controls.Add($LegendLabel)

# --- Barre de progression ---
$ProgressBar = New-Object System.Windows.Forms.ProgressBar
$ProgressBar.Location = New-Object System.Drawing.Point($RightX, 300)
$ProgressBar.Width = 260
$ProgressBar.Height = 22
$ProgressBar.Minimum = 0
$ProgressBar.Maximum = 100
$ProgressBar.Value = 0
$Form.Controls.Add($ProgressBar)

$ProgressLabel = New-Object System.Windows.Forms.Label
$ProgressLabel.Text = "Pret"
$ProgressLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$ProgressLabel.Location = New-Object System.Drawing.Point($RightX, 328)
$ProgressLabel.Width = 260
$ProgressLabel.Height = 22
$Form.Controls.Add($ProgressLabel)

# --- Bouton Executer ---
$BtnExecuter = New-Object System.Windows.Forms.Button
$BtnExecuter.Text = "Executer"
$BtnExecuter.Location = New-Object System.Drawing.Point($RightX, 380)
$BtnExecuter.Width = 120
$BtnExecuter.Height = 42
$BtnExecuter.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$BtnExecuter.BackColor = [System.Drawing.Color]::LightGreen
$Form.Controls.Add($BtnExecuter)

# --- Bouton Quitter ---
$BtnQuitter = New-Object System.Windows.Forms.Button
$BtnQuitter.Text = "Quitter"
$BtnQuitter.Location = New-Object System.Drawing.Point(($RightX + 130), 380)
$BtnQuitter.Width = 120
$BtnQuitter.Height = 42
$BtnQuitter.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$BtnQuitter.BackColor = [System.Drawing.Color]::LightCoral
$BtnQuitter.Add_Click({
    Export-Selection -Checkboxes $Checkboxes
    Write-LogSelective "Fermeture par l utilisateur (bouton Quitter)" "INFO"
    $Form.Close()
})
$Form.Controls.Add($BtnQuitter)

# --- Journal en direct du script en cours ---
$LogLabel = New-Object System.Windows.Forms.Label
$LogLabel.Text = "Journal en direct du script en cours :"
$LogLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$LogLabel.Location = New-Object System.Drawing.Point(20, 650)
$LogLabel.Width = 860
$LogLabel.Height = 20
$Form.Controls.Add($LogLabel)

$LogBox = New-Object System.Windows.Forms.RichTextBox
$LogBox.Location = New-Object System.Drawing.Point(20, 673)
$LogBox.Width = 860
$LogBox.Height = 130
$LogBox.ReadOnly = $true
$LogBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$LogBox.BackColor = [System.Drawing.Color]::White
$Form.Controls.Add($LogBox)

function Add-LogBoxLine {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.RichTextBox]$LogBox,
        [Parameter(Mandatory = $true)]
        [string]$Line
    )

    $Color = [System.Drawing.Color]::Black
    if ($Line -match '\[ERROR\]') { $Color = [System.Drawing.Color]::Red }
    elseif ($Line -match '\[WARN \]') { $Color = [System.Drawing.Color]::DarkOrange }
    elseif ($Line -match '\[OK   \]') { $Color = [System.Drawing.Color]::DarkGreen }

    $LogBox.SelectionStart = $LogBox.TextLength
    $LogBox.SelectionLength = 0
    $LogBox.SelectionColor = $Color
    $LogBox.AppendText("$Line`r`n")
    $LogBox.SelectionStart = $LogBox.TextLength
    $LogBox.ScrollToCaret()
}

# ============================================================
# Chargement automatique de la derniere selection
# ============================================================
$Form.Add_Shown({
    Import-Selection -Checkboxes $Checkboxes | Out-Null
})

# ============================================================
# Logique d'execution
# ============================================================
$BtnExecuter.Add_Click({

    # --- Recuperer les scripts coches ---
    $Selected = @()
    foreach ($Script in $Scripts) {
        if ($Checkboxes[$Script.Num].Checked) {
            $Selected += $Script
        }
    }

    # --- Aucun script coche ---
    if ($Selected.Count -eq 0) {
        $Result = [System.Windows.Forms.MessageBox]::Show(
            "Attention, aucun script n est coche.`n`nVoulez-vous quitter ou revenir a la selection ?",
            "Aucun script selectionne",
            [System.Windows.Forms.MessageBoxButtons]::RetryCancel,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )

        if ($Result -eq [System.Windows.Forms.DialogResult]::Cancel) {
            Write-LogSelective "Fermeture par l utilisateur (aucun script coche)" "WARN"
            Export-Selection -Checkboxes $Checkboxes
            $Form.Close()
        }
        return
    }

    # --- Verifier si Internet necessaire ---
    $NeedInternet = $false
    foreach ($Script in $Selected) {
        if ($Script.Net) {
            $NeedInternet = $true
            break
        }
    }

    if ($NeedInternet) {
        $ProgressLabel.Text = "Test de connexion Internet..."
        $Form.Refresh()
        [System.Windows.Forms.Application]::DoEvents()

        if (-not (Test-InternetConnection)) {
            $ScriptsInternet = $Selected | Where-Object { $_.Net }

            $Decision = Resolve-InternetRequirement -ScriptsNeedingNet $ScriptsInternet

            switch ($Decision) {
                "CANCEL" {
                    Write-LogSelective "Execution annulee par l utilisateur (pas de connexion Internet)" "WARN"
                    $ProgressLabel.Text = "Execution annulee (pas de connexion Internet)"
                    return
                }
                "CONTINUE_WITHOUT" {
                    $Selected = $Selected | Where-Object { -not $_.Net }
                    Write-LogSelective "Continuation sans les scripts Internet ($($ScriptsInternet.Count) script(s) ignores)" "WARN"
                    $ProgressLabel.Text = "Continuation sans les scripts necessitant Internet..."
                    $Form.Refresh()
                    [System.Windows.Forms.Application]::DoEvents()
                    Start-Sleep -Milliseconds 500
                }
                "OK" {
                    Write-LogSelective "Connexion Internet retablie, poursuite normale" "OK"
                    $ProgressLabel.Text = "Connexion Internet retablie"
                    $Form.Refresh()
                    [System.Windows.Forms.Application]::DoEvents()
                }
            }
        }
    }

    # --- Desactiver les controles pendant l execution ---
    $BtnExecuter.Enabled = $false
    $BtnTous.Enabled = $false
    $BtnAucun.Enabled = $false
    $BtnSave.Enabled = $false
    $BtnLoad.Enabled = $false
    foreach ($CB in $Checkboxes.Values) {
        $CB.Enabled = $false
    }

    # --- Reinitialiser les couleurs de resultat ---
    foreach ($Num in $Checkboxes.Keys) {
        $Checkboxes[$Num].BackColor = [System.Drawing.Color]::Transparent
    }

    # --- Executer les scripts ---
    $Total = $Selected.Count
    $Current = 0

    Write-LogSelective "Execution de $Total script(s) selectionne(s)" "INFO"

    foreach ($Script in $Selected) {
        $Current++
        $Percent = [math]::Round(($Current / $Total) * 100)
        $ProgressBar.Value = $Percent
        $ProgressLabel.Text = "[$Current/$Total] $($Script.File)"
        $Form.Refresh()
        [System.Windows.Forms.Application]::DoEvents()

        $Checkboxes[$Script.Num].BackColor = [System.Drawing.Color]::LightYellow
        $Form.Refresh()
        [System.Windows.Forms.Application]::DoEvents()

        Write-LogSelective "[$Current/$Total] Lancement : $($Script.File)" "INFO"

        $ScriptPath = "C:\_CGLOBAL\PS1\$($Script.File)"
        $ScriptLogPath = "C:\_CGLOBAL\Logs\Log$([System.IO.Path]::GetFileNameWithoutExtension($Script.File)).txt"

        $LogBox.Clear()
        Add-LogBoxLine -LogBox $LogBox -Line "=== $($Script.File) ==="
        $LastLineCount = 0

        if (-not (Test-Path $ScriptPath)) {
            Write-LogSelective "Script introuvable : $ScriptPath" "ERROR"
            $Checkboxes[$Script.Num].BackColor = [System.Drawing.Color]::LightCoral
            $Results[$Script.Num] = "MISSING"
            continue
        }

        try {
            # Lancement sans -Wait pour garder la fenetre reactive
            $Process = Start-Process -FilePath "powershell.exe" `
                -ArgumentList "-ExecutionPolicy Bypass -File `"$ScriptPath`"" `
                -PassThru -NoNewWindow

            # IMPORTANT : forcer .NET a conserver le handle du processus des le depart.
            # Sans cela, $Process.ExitCode peut rester vide (null) meme apres la sortie
            # du processus (bug connu de Start-Process -PassThru sous PowerShell 5.1).
            $null = $Process.Handle

            # Boucle d attente reactive, avec suivi en direct du log du script en cours
            while (-not $Process.HasExited) {
                [System.Windows.Forms.Application]::DoEvents()

                if (Test-Path $ScriptLogPath) {
                    $AllLines = @(Get-Content -Path $ScriptLogPath -ErrorAction SilentlyContinue)
                    if ($AllLines.Count -gt $LastLineCount) {
                        foreach ($NewLine in $AllLines[$LastLineCount..($AllLines.Count - 1)]) {
                            Add-LogBoxLine -LogBox $LogBox -Line $NewLine
                        }
                        $LastLineCount = $AllLines.Count
                    }
                }

                Start-Sleep -Milliseconds 200
            }

            # Derniere lecture apres la sortie du process, au cas ou des lignes
            # auraient ete ecrites juste avant la fin et pas encore captees
            if (Test-Path $ScriptLogPath) {
                $AllLines = @(Get-Content -Path $ScriptLogPath -ErrorAction SilentlyContinue)
                if ($AllLines.Count -gt $LastLineCount) {
                    foreach ($NewLine in $AllLines[$LastLineCount..($AllLines.Count - 1)]) {
                        Add-LogBoxLine -LogBox $LogBox -Line $NewLine
                    }
                }
            }

            # Synchronise proprement la sortie avant de lire le code (evite un ExitCode
            # non encore disponible juste apres le passage de HasExited a $true)
            $Process.WaitForExit()
            $ExitCode = $Process.ExitCode

            if ($ExitCode -eq 0) {
                Write-LogSelective "$($Script.File) termine avec succes" "OK"
                $Checkboxes[$Script.Num].BackColor = [System.Drawing.Color]::LightGreen
                $Results[$Script.Num] = "OK"
            }
            else {
                Write-LogSelective "$($Script.File) termine avec le code $ExitCode" "WARN"
                $Checkboxes[$Script.Num].BackColor = [System.Drawing.Color]::LightYellow
                $Results[$Script.Num] = "WARN:$ExitCode"
            }
        }
        catch {
            Write-LogSelective "Erreur lors de l execution de $($Script.File) : $($_.Exception.Message)" "ERROR"
            $Checkboxes[$Script.Num].BackColor = [System.Drawing.Color]::LightCoral
            $Results[$Script.Num] = "ERROR"
        }
    }

    $ProgressBar.Value = 100
    $ProgressLabel.Text = "Execution terminee ($Total script(s))"
    $Form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
    Write-LogSelective "=== EXECUTION TERMINEE ===" "OK"

    Export-Selection -Checkboxes $Checkboxes

    $OkCount = ($Results.Values | Where-Object { $_ -eq "OK" }).Count
    $WarnCount = ($Results.Values | Where-Object { $_ -like "WARN:*" }).Count
    $ErrCount = ($Results.Values | Where-Object { $_ -eq "ERROR" -or $_ -eq "MISSING" }).Count

    [System.Windows.Forms.MessageBox]::Show(
        "Execution terminee.`n`n$Total script(s) executes :`n  - $OkCount succes`n  - $WarnCount avertissement(s)`n  - $ErrCount erreur(s)`n`nConsultez le log pour les details.",
        "Termine",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )

    # Reactiver les controles
    $BtnExecuter.Enabled = $true
    $BtnTous.Enabled = $true
    $BtnAucun.Enabled = $true
    $BtnSave.Enabled = $true
    $BtnLoad.Enabled = $true
    foreach ($CB in $Checkboxes.Values) {
        $CB.Enabled = $true
    }
})

# ============================================================
# Sauvegarde automatique a la fermeture
# ============================================================
$Form.Add_FormClosing({
    Export-Selection -Checkboxes $Checkboxes
})

# ============================================================
# Affichage du formulaire
# ============================================================
Write-LogSelective "Affichage de l interface de selection" "INFO"
[void]$Form.ShowDialog()
Write-LogSelective "=== FERMETURE MODE SELECTIF ===" "INFO"
