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
    @{ Num="09"; File="09_MasquerBoutonChatTeams.ps1"; Desc="Masquer bouton Chat Teams"; Tooltip="Masque le bouton Chat (Microsoft Teams) de la barre des taches"; Net=$false },
    @{ Num="10"; File="10_DesactiverReprendre.ps1"; Desc="Desactiver Reprendre"; Tooltip="Desactive la fonction Reprendre (Resume) au demarrage"; Net=$false },
    @{ Num="11"; File="11_ConfidentialiteLocalisation.ps1"; Desc="Confidentialite / localisation"; Tooltip="Desactive les notifications de localisation et le remplacement de localisation"; Net=$false },
    @{ Num="12"; File="12_ConfigurerProfilParDefaut.ps1"; Desc="Configurer profil par defaut"; Tooltip="Configure les reglages pour les futurs profils utilisateurs (NTUSER.DAT)"; Net=$false },
    @{ Num="13"; File="13_NumLockDemarrage.ps1"; Desc="NumLock au demarrage"; Tooltip="Force l activation du verrouillage numerique au demarrage"; Net=$false },
    @{ Num="14"; File="14_DesinstallationOffice.ps1"; Desc="Desinstallation Office / OneNote"; Tooltip="Detecte et desinstalle toutes les versions d Office et OneNote (C2R, MSI)"; Net=$false },
    @{ Num="15"; File="15_ApplicationsWinget.ps1"; Desc="Applications Winget [INTERNET]"; Tooltip="Installe 7-Zip, Acrobat Reader, Chrome et Firefox via WinGet (connexion Internet requise)"; Net=$true },
    @{ Num="16"; File="16_TeamViewerQS.ps1"; Desc="TeamViewer QuickSupport [INTERNET]"; Tooltip="Telecharge et installe TeamViewer QuickSupport (connexion Internet requise)"; Net=$true },
    @{ Num="17"; File="17_DesinstallationOneDrive.ps1"; Desc="Desinstallation OneDrive"; Tooltip="Desinstalle OneDrive, bloque son retour pour les futurs profils et supprime les raccourcis"; Net=$false },
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

    # Test TCP sur le port 443 (HTTPS) au lieu de ping ICMP
    # Le ping ICMP est souvent bloque par les firewalls et tres lent
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

function Show-InternetPopup {
    Add-Type -AssemblyName System.Windows.Forms

    do {
        $Result = [System.Windows.Forms.MessageBox]::Show(
            "Aucun acces Internet detecte.`n`nLes scripts Winget et TeamViewer necessitent une connexion Internet.`n`nVoulez-vous reessayer ?",
            "Internet requis",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($Result -eq [System.Windows.Forms.DialogResult]::No) {
            return $false
        }

        if (Test-InternetConnection -Silent) {
            return $true
        }

    } while ($true)
}

# ============================================================
# Creation du formulaire principal
# ============================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "CGLOBAL - Mode Selectif"
$Form.Width = 600
$Form.Height = 780
$Form.StartPosition = "CenterScreen"
$Form.FormBorderStyle = "FixedDialog"
$Form.MaximizeBox = $false
$Form.MinimizeBox = $false

# --- Titre ---
$TitleLabel = New-Object System.Windows.Forms.Label
$TitleLabel.Text = "CGLOBAL - Selection des scripts a executer"
$TitleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$TitleLabel.Location = New-Object System.Drawing.Point(20, 15)
$TitleLabel.Width = 550
$TitleLabel.Height = 30
$Form.Controls.Add($TitleLabel)

# --- Sous-titre ---
$SubLabel = New-Object System.Windows.Forms.Label
$SubLabel.Text = "Cochez les scripts a lancer, puis cliquez sur Executer. Survolez un script pour voir sa description."
$SubLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$SubLabel.Location = New-Object System.Drawing.Point(20, 45)
$SubLabel.Width = 550
$SubLabel.Height = 20
$Form.Controls.Add($SubLabel)

# --- Panel scrollable pour les checkboxes ---
$Panel = New-Object System.Windows.Forms.Panel
$Panel.Location = New-Object System.Drawing.Point(20, 75)
$Panel.Width = 550
$Panel.Height = 520
$Panel.AutoScroll = $true
$Panel.BorderStyle = "FixedSingle"
$Form.Controls.Add($Panel)

# --- Tooltip global ---
$Tooltip = New-Object System.Windows.Forms.ToolTip
$Tooltip.AutoPopDelay = 10000
$Tooltip.InitialDelay = 500
$Tooltip.ReshowDelay = 200
$Tooltip.ShowAlways = $true

$Checkboxes = @{}
$Results = @{}  # Pour stocker le resultat de chaque script
$Y = 10

foreach ($Script in $Scripts) {
    $CB = New-Object System.Windows.Forms.CheckBox
    $CB.Text = "[$($Script.Num)] $($Script.Desc)"
    $CB.Location = New-Object System.Drawing.Point(10, $Y)
    $CB.Width = 510
    $CB.Height = 22
    $CB.Tag = $Script

    if ($Script.Net) {
        $CB.ForeColor = [System.Drawing.Color]::DarkOrange
    }

    # --- Info-bulle (Tooltip) ---
    $Tooltip.SetToolTip($CB, $Script.Tooltip)

    $Panel.Controls.Add($CB)
    $Checkboxes[$Script.Num] = $CB
    $Results[$Script.Num] = $null
    $Y += 26
}

# --- Boutons Tous / Aucun / Sauvegarder / Charger ---
$BtnTous = New-Object System.Windows.Forms.Button
$BtnTous.Text = "Tous"
$BtnTous.Location = New-Object System.Drawing.Point(20, 605)
$BtnTous.Width = 80
$BtnTous.Height = 30
$BtnTous.Add_Click({
    foreach ($CB in $Checkboxes.Values) {
        $CB.Checked = $true
    }
})
$Form.Controls.Add($BtnTous)

$BtnAucun = New-Object System.Windows.Forms.Button
$BtnAucun.Text = "Aucun"
$BtnAucun.Location = New-Object System.Drawing.Point(110, 605)
$BtnAucun.Width = 80
$BtnAucun.Height = 30
$BtnAucun.Add_Click({
    foreach ($CB in $Checkboxes.Values) {
        $CB.Checked = $false
    }
})
$Form.Controls.Add($BtnAucun)

$BtnSave = New-Object System.Windows.Forms.Button
$BtnSave.Text = "Sauvegarder"
$BtnSave.Location = New-Object System.Drawing.Point(200, 605)
$BtnSave.Width = 90
$BtnSave.Height = 30
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

$BtnLoad = New-Object System.Windows.Forms.Button
$BtnLoad.Text = "Charger"
$BtnLoad.Location = New-Object System.Drawing.Point(300, 605)
$BtnLoad.Width = 80
$BtnLoad.Height = 30
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
$NetLabel.Location = New-Object System.Drawing.Point(400, 610)
$NetLabel.Width = 170
$NetLabel.Height = 30
$Form.Controls.Add($NetLabel)

# --- Legende resultats ---
$LegendLabel = New-Object System.Windows.Forms.Label
$LegendLabel.Text = "Legende : Vert = OK  |  Rouge = Erreur  |  Jaune = Warning"
$LegendLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$LegendLabel.Location = New-Object System.Drawing.Point(20, 640)
$LegendLabel.Width = 400
$LegendLabel.Height = 18
$Form.Controls.Add($LegendLabel)

# --- Barre de progression ---
$ProgressBar = New-Object System.Windows.Forms.ProgressBar
$ProgressBar.Location = New-Object System.Drawing.Point(20, 665)
$ProgressBar.Width = 360
$ProgressBar.Height = 20
$ProgressBar.Minimum = 0
$ProgressBar.Maximum = 100
$ProgressBar.Value = 0
$Form.Controls.Add($ProgressBar)

$ProgressLabel = New-Object System.Windows.Forms.Label
$ProgressLabel.Text = "Pret"
$ProgressLabel.Location = New-Object System.Drawing.Point(20, 690)
$ProgressLabel.Width = 500
$ProgressLabel.Height = 20
$Form.Controls.Add($ProgressLabel)

# --- Bouton Executer ---
$BtnExecuter = New-Object System.Windows.Forms.Button
$BtnExecuter.Text = "Executer"
$BtnExecuter.Location = New-Object System.Drawing.Point(310, 660)
$BtnExecuter.Width = 100
$BtnExecuter.Height = 35
$BtnExecuter.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$BtnExecuter.BackColor = [System.Drawing.Color]::LightGreen
$Form.Controls.Add($BtnExecuter)

# --- Bouton Quitter ---
$BtnQuitter = New-Object System.Windows.Forms.Button
$BtnQuitter.Text = "Quitter"
$BtnQuitter.Location = New-Object System.Drawing.Point(420, 660)
$BtnQuitter.Width = 100
$BtnQuitter.Height = 35
$BtnQuitter.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$BtnQuitter.BackColor = [System.Drawing.Color]::LightCoral
$BtnQuitter.Add_Click({
    Export-Selection -Checkboxes $Checkboxes
    Write-LogSelective "Fermeture par l utilisateur (bouton Quitter)" "INFO"
    $Form.Close()
})
$Form.Controls.Add($BtnQuitter)

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

        if (-not (Test-InternetConnection)) {
            # Lister les scripts qui necessitent Internet
            $ScriptsInternet = $Selected | Where-Object { $_.Net } | ForEach-Object { "[$($_.Num)] $($_.Desc)" }
            $ScriptsInternetText = $ScriptsInternet -join "`n"

            $Result = [System.Windows.Forms.MessageBox]::Show(
                "Aucun acces Internet detecte.`n`nLes scripts suivants necessitent Internet :`n$ScriptsInternetText`n`nVoulez-vous :`n- OUI = Continuer SANS ces scripts`n- NON = Arreter completement`n- ANNULER = Revenir a la selection",
                "Internet requis",
                [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )

            if ($Result -eq [System.Windows.Forms.DialogResult]::No) {
                # Arreter completement
                Write-LogSelective "Execution annulee par l utilisateur (pas de connexion Internet)" "WARN"
                $ProgressLabel.Text = "Execution annulee (pas de connexion Internet)"
                return
            }
            elseif ($Result -eq [System.Windows.Forms.DialogResult]::Yes) {
                # Continuer sans les scripts Internet
                $Selected = $Selected | Where-Object { -not $_.Net }
                Write-LogSelective "Continuation sans les scripts Internet ($($ScriptsInternet.Count) script(s) ignores)" "WARN"
                $ProgressLabel.Text = "Continuation sans les scripts necessitant Internet..."
                $Form.Refresh()
                Start-Sleep -Milliseconds 500
            }
            else {
                # Cancel = revenir a la selection
                $ProgressLabel.Text = "Pret"
                return
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
        $ProgressLabel.Text = "[$Current/$Total] Execution de $($Script.File)..."
        $Form.Refresh()

        # Couleur en cours
        $Checkboxes[$Script.Num].BackColor = [System.Drawing.Color]::LightYellow
        $Form.Refresh()

        Write-LogSelective "[$Current/$Total] Lancement : $($Script.File)" "INFO"

        $ScriptPath = "C:\_CGLOBAL\PS1\$($Script.File)"

        if (-not (Test-Path $ScriptPath)) {
            Write-LogSelective "Script introuvable : $ScriptPath" "ERROR"
            $Checkboxes[$Script.Num].BackColor = [System.Drawing.Color]::LightCoral
            $Results[$Script.Num] = "MISSING"
            continue
        }

        try {
            $Process = Start-Process -FilePath "powershell.exe" `
                -ArgumentList "-ExecutionPolicy Bypass -File `"$ScriptPath`"" `
                -Wait -PassThru -NoNewWindow

            if ($Process.ExitCode -eq 0) {
                Write-LogSelective "$($Script.File) termine avec succes" "OK"
                $Checkboxes[$Script.Num].BackColor = [System.Drawing.Color]::LightGreen
                $Results[$Script.Num] = "OK"
            }
            else {
                Write-LogSelective "$($Script.File) termine avec le code $($Process.ExitCode)" "WARN"
                $Checkboxes[$Script.Num].BackColor = [System.Drawing.Color]::LightYellow
                $Results[$Script.Num] = "WARN:$($Process.ExitCode)"
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
    Write-LogSelective "=== EXECUTION TERMINEE ===" "OK"

    # --- Sauvegarder la selection ---
    Export-Selection -Checkboxes $Checkboxes

    # --- Compter les resultats ---
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
