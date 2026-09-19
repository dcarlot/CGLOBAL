#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$USBPath = [System.IO.Path]::GetPathRoot($PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

# ============================================================
# Initialisation DPI moderne AVANT le module commun et WinForms
# ============================================================
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class RunSelectiveDpiBootstrap {
    [DllImport("user32.dll", SetLastError=true)]
    static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("shcore.dll", SetLastError=true)]
    static extern int SetProcessDpiAwareness(int value);
    [DllImport("user32.dll", SetLastError=true)]
    static extern bool SetProcessDPIAware();
    public static void Enable() {
        try { if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return; } catch {}
        try { if (SetProcessDpiAwareness(2) == 0) return; } catch {}
        try { SetProcessDPIAware(); } catch {}
    }
}
"@ -ErrorAction SilentlyContinue
if ("RunSelectiveDpiBootstrap" -as [type]) { [RunSelectiveDpiBootstrap]::Enable() }

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

    for ($Attempt = 1; $Attempt -le 10; $Attempt++) {
        try {
            Add-Content -Path $LogFile -Value $Line -Encoding UTF8 -ErrorAction Stop
            break
        }
        catch {
            if ($Attempt -lt 10) { Start-Sleep -Milliseconds 150 }
        }
    }

    Write-Host $Line -ForegroundColor $(@{INFO='Cyan';OK='Green';WARN='Yellow';ERROR='Red'}[$Level])
}

Write-LogSelective "=== LANCEMENT MODE SELECTIF ===" "INFO"

# ============================================================
# Fichier de mémorisation (.sel = simple, pas de JSON)
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
    Write-LogSelective "Sélection sauvegardée dans $SelFile" "OK"
}

function Import-Selection {
    param($Checkboxes)
    if (-not (Test-Path $SelFile)) {
        Write-LogSelective "Aucune sélection précédente trouvée" "INFO"
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
        Write-LogSelective "Sélection chargée depuis $SelFile" "OK"
        return $true
    }
    catch {
        Write-LogSelective "Erreur chargement sélection : $($_.Exception.Message)" "WARN"
        return $false
    }
}

# ============================================================
# Definition des scripts (a jour avec le depot GitHub)
# ============================================================
$Scripts = @(
    @{ Num="00"; File="00_ModeDeploiement.ps1"; Desc="Mode déploiement (veille, ecran, WU)"; Tooltip="Désactive la veille, l'extinction d'écran et les redémarrages auto de Windows Update"; Net=$false },
    @{ Num="01"; File="01_Bureau.ps1"; Desc="Icônes système sur le bureau"; Tooltip="Affiche Ce PC, Panneau de configuration, Corbeille et Réseau sur le Bureau"; Net=$false },
    @{ Num="02"; File="02_MenuContextuelClassique.ps1"; Desc="Menu contextuel classique"; Tooltip="Restaure le menu contextuel de Windows 10/11 classique (clic droit)"; Net=$false },
    @{ Num="03"; File="03_Explorateur.ps1"; Desc="Explorateur (Ce PC, extensions)"; Tooltip="Ouvre l'Explorateur sur Ce PC et affiche les extensions de fichiers"; Net=$false },
    @{ Num="04"; File="04_ZoneNotification.ps1"; Desc="Zone de notification"; Tooltip="Affiche toutes les icônes connues dans la zone de notification"; Net=$false },
    @{ Num="05"; File="05_BarreTachesGauche.ps1"; Desc="Barre des tâches à gauche"; Tooltip="Aligne les icônes de la barre des tâches à gauche"; Net=$false },
    @{ Num="06"; File="06_RechercheBarreTaches.ps1"; Desc="Recherche en mode icône"; Tooltip="Affiche uniquement l'icône de recherche (pas la barre complète)"; Net=$false },
    @{ Num="07"; File="07_MasquerVueTaches.ps1"; Desc="Masquer le bouton Vue des tâches"; Tooltip="Masque le bouton Vue des tâches de la barre des tâches"; Net=$false },
    @{ Num="08"; File="08_MasquerWidgets.ps1"; Desc="Désinstaller les Widgets"; Tooltip="Désinstalle completement le package Windows Web Experience Pack (Widgets)"; Net=$false },
    @{ Num="09"; File="09_MSStoreBarreTache.ps1"; Desc="Supprimer MS Store barre des tâches"; Tooltip="Supprime l'epingle Microsoft Store de la barre des tâches et bloque son retour"; Net=$false },
    @{ Num="10"; File="10_DesactiverReprendre.ps1"; Desc="Désactiver Reprendre"; Tooltip="Désactive la fonction Reprendre (Resume) au démarrage"; Net=$false },
    @{ Num="11"; File="11_ConfidentialiteLocalisation.ps1"; Desc="Confidentialité / localisation"; Tooltip="Désactive les notifications de localisation et le remplacement de localisation"; Net=$false },
    @{ Num="12"; File="12_ConfigurerProfilParDefaut.ps1"; Desc="Configurer profil par défaut"; Tooltip="Configure les réglages pour les futurs profils utilisateurs (NTUSER.DAT)"; Net=$false },
    @{ Num="13"; File="13_NumLockDemarrage.ps1"; Desc="NumLock au démarrage"; Tooltip="Force l'activation du verrouillage numerique au démarrage"; Net=$false },
    @{ Num="14"; File="14_DesinstallationOffice.ps1"; Desc="Désinstallation Office / OneNote"; Tooltip="Détecte et désinstalle toutes les versions d'Office et OneNote (C2R, MSI)"; Net=$false },
    @{ Num="15"; File="15_ApplicationsWinget.ps1"; Desc="Applications Winget [INTERNET]"; Tooltip="Installe 7-Zip, Acrobat Reader, Chrome et Firefox via WinGet (connexion Internet requise)"; Net=$true },
    @{ Num="16"; File="16_TeamViewerQS.ps1"; Desc="TeamViewer QuickSupport [INTERNET]"; Tooltip="Télécharge et installe TeamViewer QuickSupport (connexion Internet requise)"; Net=$true },
    @{ Num="17"; File="17_DesinstallationOneDrive.ps1"; Desc="Désinstallation OneDrive"; Tooltip="Désinstalle OneDrive, bloque son retour pour les futurs profils et supprime les raccourcis"; Net=$false },
    @{ Num="19"; File="19_MisesAJourConstructeur.ps1"; Desc="Mises à jour constructeur [INTERNET]"; Tooltip="Détecte le constructeur et installe les mises à jour pilotes, BIOS et firmware sans redémarrer le poste pendant la séquence"; Net=$true },
    @{ Num="85"; File="85_RenommagePoste.ps1"; Desc="Renommage du poste"; Tooltip="Affiche le nom actuel du poste et permet de le modifier après vérification de compatibilité (lettres, chiffres, trait d'union)"; Net=$false },
    @{ Num="90"; File="90_VerificationMotDePasseCompteLocal.ps1"; Desc="Vérification mot de passe local"; Tooltip="Vérifie si le compte local possède un mot de passe et propose d'en définir un"; Net=$false },
    @{ Num="99"; File="99_FinDeploiement.ps1"; Desc="Fin déploiement (restauration)"; Tooltip="Restaure les paramètres énergétiques et Windows Update (fin du mode déploiement)"; Net=$false }
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
        Write-LogSelective "Aucune connexion Internet détectée" "WARN"
    }
    return $false
}

# ============================================================
# Wi-Fi invite du bureau : SSID + mot de passe charges depuis wifi.secret
# Format obligatoire de <LettreDeLaCleUSB>:\_CGLOBAL\wifi.secret :
#   ligne 1 = SSID
#   ligne 2 = mot de passe Wi-Fi
# ============================================================
# Le fichier secret reste exclusivement sur la clé USB.
# Exemple : E:\_CGLOBAL\wifi.secret
$script:WifiSecretFile = Join-Path -Path $USBPath -ChildPath "_CGLOBAL\wifi.secret"
$script:GuestWifiSSID = $null
$script:GuestWifiPassword = $null

function Get-GuestWifiCredentials {
    $SecretFile = $script:WifiSecretFile

    if (-not (Test-Path $SecretFile)) {
        Write-LogSelective "Fichier Wi-Fi introuvable : $SecretFile" "ERROR"
        return $false
    }

    try {
        $Lines = @(Get-Content -Path $SecretFile -Encoding UTF8 -ErrorAction Stop)

        if ($Lines.Count -lt 2) {
            Write-LogSelective "Fichier Wi-Fi invalide : $SecretFile doit contenir au moins 2 lignes (SSID puis mot de passe)" "ERROR"
            return $false
        }

        $SSID = $Lines[0].Trim()
        $Password = $Lines[1].Trim()

        if ([string]::IsNullOrWhiteSpace($SSID)) {
            Write-LogSelective "Fichier Wi-Fi invalide : le SSID (ligne 1) est vide" "ERROR"
            return $false
        }

        if ([string]::IsNullOrWhiteSpace($Password)) {
            Write-LogSelective "Fichier Wi-Fi invalide : le mot de passe (ligne 2) est vide" "ERROR"
            return $false
        }

        $script:GuestWifiSSID = $SSID
        $script:GuestWifiPassword = $Password

        Write-LogSelective "SSID Wi-Fi récupéré depuis $SecretFile" "INFO"
        Write-LogSelective "Mot de passe Wi-Fi récupéré depuis $SecretFile" "INFO"
        return $true
    }
    catch {
        Write-LogSelective "Impossible de lire $SecretFile : $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function ConvertTo-XmlSafeText {
    param([AllowEmptyString()][string]$Value)

    if ($null -eq $Value) {
        return ""
    }

    return [System.Security.SecurityElement]::Escape($Value)
}

# ============================================================
# Connexion directe au Wi-Fi invite
# Aucun scan des réseaux disponibles n'est éffectué.
# ============================================================
function Connect-CGlobalGuestWifi {
    Write-LogSelective "Tentative de connexion au Wi-Fi invité '$($script:GuestWifiSSID)'" "INFO"

    $SafeSSID = ConvertTo-XmlSafeText $script:GuestWifiSSID
    $SafePassword = ConvertTo-XmlSafeText $script:GuestWifiPassword

    $ProfileXml = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$SafeSSID</name>
    <SSIDConfig>
        <SSID>
            <name>$SafeSSID</name>
        </SSID>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>WPA2PSK</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$SafePassword</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>
"@

    $ProfilePath = Join-Path $env:TEMP "CGlobalGuestWifi.xml"

    try {
        Set-Content -Path $ProfilePath -Value $ProfileXml -Encoding UTF8

        $AddResult = (netsh wlan add profile filename="$ProfilePath" user=all) -join " "
        Write-LogSelective "Ajout du profil Wi-Fi invité : $AddResult" "INFO"

        $ConnectResult = (netsh wlan connect name="$($script:GuestWifiSSID)" ssid="$($script:GuestWifiSSID)") -join " "
        Write-LogSelective "Connexion au Wi-Fi invité : $ConnectResult" "INFO"

        # Laisser le temps a Windows d'établir la connexion et d'obtenir une adresse IP
        Start-Sleep -Seconds 5
        return $true
    }
    catch {
        Write-LogSelective "Erreur lors de la connexion au Wi-Fi invité : $($_.Exception.Message)" "ERROR"
        return $false
    }
    finally {
        Remove-Item -Path $ProfilePath -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================
# Détection et activation éventuelle d'une carte WLAN
# ============================================================
function Get-CGlobalWlanAdapters {
    try {
        $Adapters = @(Get-NetAdapter -IncludeHidden -ErrorAction Stop | Where-Object {
            $_.NdisPhysicalMedium -eq 9 -or
            $_.PhysicalMediaType -eq 9 -or
            $_.InterfaceDescription -match '(?i)wireless|wi-fi|wifi|wlan|802\.11'
        })
        return @($Adapters)
    }
    catch {
        Write-LogSelective "Impossible d'interroger les cartes réseau : $($_.Exception.Message)" "WARN"
        return @()
    }
}

function Enable-CGlobalWlanAdapter {
    $WlanAdapters = @(Get-CGlobalWlanAdapters)

    if ($WlanAdapters.Count -eq 0) {
        Write-LogSelective "Aucune carte WLAN détectée sur ce poste : proposition Wi-Fi ignorée" "INFO"
        return $false
    }

    $UsableAdapter = $WlanAdapters | Where-Object { $_.Status -ne 'Disabled' } | Select-Object -First 1
    if ($null -ne $UsableAdapter) {
        Write-LogSelective "Carte WLAN détectée : $($UsableAdapter.Name) - État : $($UsableAdapter.Status)" "INFO"
        return $true
    }

    foreach ($Adapter in ($WlanAdapters | Where-Object { $_.Status -eq 'Disabled' })) {
        try {
            Write-LogSelective "Carte WLAN désactivée détectée : $($Adapter.Name). Tentative d'activation..." "INFO"
            Enable-NetAdapter -Name $Adapter.Name -Confirm:$false -ErrorAction Stop
            Start-Sleep -Seconds 3

            $UpdatedAdapter = Get-NetAdapter -Name $Adapter.Name -ErrorAction Stop
            if ($UpdatedAdapter.Status -ne 'Disabled') {
                Write-LogSelective "Carte WLAN '$($Adapter.Name)' activée - État : $($UpdatedAdapter.Status)" "OK"
                return $true
            }

            Write-LogSelective "La carte WLAN '$($Adapter.Name)' reste désactivée après la tentative d'activation" "WARN"
        }
        catch {
            Write-LogSelective "Impossible d'activer la carte WLAN '$($Adapter.Name)' : $($_.Exception.Message)" "WARN"
        }
    }

    Write-LogSelective "Aucune carte WLAN utilisable sur ce poste : proposition Wi-Fi ignorée" "WARN"
    return $false
}

# ============================================================
# Detection et suppression facultative du profil Wi-Fi invité
# ============================================================
function Test-GuestWifiProfileExists {
    param([Parameter(Mandatory = $true)][string]$SSID)

    try {
        $ProfileOutput = @(& netsh.exe wlan show profile name="$SSID" 2>&1)
        if ($LASTEXITCODE -eq 0) {
            Write-LogSelective "Profil Wi-Fi '$SSID' détecté sur ce poste" "INFO"
            return $true
        }
        Write-LogSelective "Aucun profil Wi-Fi enregistré pour '$SSID'" "INFO"
        return $false
    }
    catch {
        Write-LogSelective "Erreur lors de la recherche du profil Wi-Fi '$SSID' : $($_.Exception.Message)" "WARN"
        return $false
    }
}

function Confirm-GuestWifiProfileRemoval {
    # Sans carte WLAN, aucun profil Wi-Fi exploitable n'est attendu.
    if (@(Get-CGlobalWlanAdapters).Count -eq 0) {
        Write-LogSelective "Vérification finale du profil Wi-Fi ignorée : aucune carte WLAN détectée" "INFO"
        return
    }

    if (-not (Get-GuestWifiCredentials)) {
        Write-LogSelective "Vérification finale du profil Wi-Fi invité impossible : wifi.secret indisponible ou invalide" "INFO"
        return
    }

    try {
        if (-not (Test-GuestWifiProfileExists -SSID $script:GuestWifiSSID)) { return }

        if ($script:ExecutionMode -eq 'Interactif') {
            $Choice = [System.Windows.Forms.MessageBox]::Show(
                "Le profil Wi-Fi '$($script:GuestWifiSSID)' est enregistré sur ce poste.`n`nVoulez-vous le supprimer ?`n`nOUI = supprimer le profil enregistré`nNON = conserver le profil et la connexion automatique",
                "Profil Wi-Fi invité",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
        }
        else {
            $Choice = [System.Enum]::Parse([System.Windows.Forms.DialogResult], [string](Get-CGlobalDecision -Key 'RemoveGuestWifi' -Default 'Yes'))
            Write-LogSelective "Décision Wi-Fi centralisée : $Choice" 'INFO'
        }

        if ($Choice -ne [System.Windows.Forms.DialogResult]::Yes) {
            Write-LogSelective "Profil Wi-Fi '$($script:GuestWifiSSID)' conservé à la demande de l'utilisateur" "INFO"
            return
        }

        $DeleteOutput = @(& netsh.exe wlan delete profile name="$($script:GuestWifiSSID)" 2>&1)
        $DeleteExitCode = $LASTEXITCODE
        $DeleteMessage = $DeleteOutput -join " "

        if ($DeleteExitCode -eq 0) {
            Write-LogSelective "Profil Wi-Fi '$($script:GuestWifiSSID)' supprimé : $DeleteMessage" "OK"
            if ($script:ExecutionMode -eq 'Interactif') {
                [void][System.Windows.Forms.MessageBox]::Show(
                    "Le profil Wi-Fi '$($script:GuestWifiSSID)' a été supprimé de ce poste.",
                    "Profil Wi-Fi supprimé",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
            }
        }
        else {
            Write-LogSelective "Échec de suppression du profil Wi-Fi '$($script:GuestWifiSSID)' (code $DeleteExitCode) : $DeleteMessage" "ERROR"
            if ($script:ExecutionMode -eq 'Interactif') {
                [void][System.Windows.Forms.MessageBox]::Show(
                    "Impossible de supprimer le profil Wi-Fi '$($script:GuestWifiSSID)'.`n`nConsultez le journal pour les détails.",
                    "Erreur de suppression",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
            }
        }
    }
    catch {
        Write-LogSelective "Erreur lors de la suppression du profil Wi-Fi '$($script:GuestWifiSSID)' : $($_.Exception.Message)" "ERROR"
    }
    finally {
        $script:GuestWifiPassword = $null
    }
}

# ============================================================
# Résolution de l'absence de connexion Internet
# Retourne : "OK" (connexion rétablie), "CANCEL" (annuler tout),
#            "CONTINUE_WITHOUT" (continuer sans les scripts Internet)
# ============================================================
function Resolve-InternetRequirement {
    param(
        [array]$ScriptsNeedingNet
    )
    if ($script:ExecutionMode -ne 'Interactif') {
        Write-LogSelective "Absence d'Internet en mode $($script:ExecutionMode) : tentative Wi-Fi automatique puis poursuite sans scripts Internet en cas d'échec" 'WARN'
        if ((Enable-CGlobalWlanAdapter) -and (Get-GuestWifiCredentials)) {
            if ((Connect-CGlobalGuestWifi) -and (Test-InternetConnection)) { return 'OK' }
        }
        return 'CONTINUE_WITHOUT'
    }

    $ScriptsInternetText = ($ScriptsNeedingNet | ForEach-Object { "[$($_.Num)] $($_.Desc)" }) -join "`n"

    # --- Proposer le Wi-Fi uniquement si une carte WLAN est présente et utilisable ---
    # Une carte désactivee est activée automatiquement avant l'affichage du popup.
    if (Enable-CGlobalWlanAdapter) {
        # Charger d'abord le SSID afin de l'afficher correctement dans la question.
        if (-not (Get-GuestWifiCredentials)) {
            Write-LogSelective "Identifiants Wi-Fi indisponibles dans $($script:WifiSecretFile) : proposition de connexion ignorée" "WARN"
        }
        else {
            $WifiChoice = [System.Windows.Forms.MessageBox]::Show(
                "Pas de connexion Internet.`n`nVoulez-vous essayer de vous connecter au Wi-Fi '$($script:GuestWifiSSID)' (si disponible) ?",
                "Connexion Internet requise",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )

            if ($WifiChoice -eq [System.Windows.Forms.DialogResult]::Yes) {
                $WifiConnectionStarted = Connect-CGlobalGuestWifi

                if (-not $WifiConnectionStarted) {
                    Write-LogSelective "La tentative de connexion au Wi-Fi '$($script:GuestWifiSSID)' a échoué" "WARN"
                }
                elseif (Test-InternetConnection) {
                    Write-LogSelective "Connexion Internet rétablie via le Wi-Fi '$($script:GuestWifiSSID)'" "OK"
                    return "OK"
                }
                else {
                    Write-LogSelective "Connexion au Wi-Fi '$($script:GuestWifiSSID)' tentée, mais aucun accès Internet n'est disponible" "WARN"
                }
            }
            else {
                Write-LogSelective "Tentative de connexion au Wi-Fi '$($script:GuestWifiSSID)' refusée par l'utilisateur" "INFO"
            }
        }
    }

    # --- Boucle de réessai de l'acces Internet ---
    do {
        $RetryResult = [System.Windows.Forms.MessageBox]::Show(
            "Aucun accès Internet détecté.`n`nLes scripts suivants nécessitent Internet :`n$ScriptsInternetText`n`nVérifiez la connexion réseau, puis cliquez sur OUI pour tester de nouveau.`n`nVoulez-vous reessayer ?",
            "Internet requis",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($RetryResult -eq [System.Windows.Forms.DialogResult]::No) {
            break
        }

        if (Test-InternetConnection) {
            Write-LogSelective "Connexion Internet détectée apres une nouvelle vérification" "OK"
            return "OK"
        }
    } while ($true)

    # --- Toujours pas de connexion : choix final ---
    $CancelResult = [System.Windows.Forms.MessageBox]::Show(
        "Toujours aucun accès Internet.`n`nLes scripts suivants nécessitent Internet :`n$ScriptsInternetText`n`n- OUI = Annuler tout le lancement (retour à la sélection)`n- NON = Continuer SANS ces scripts (avertissement)",
        "Internet requis",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($CancelResult -eq [System.Windows.Forms.DialogResult]::Yes) {
        return "CANCEL"
    }

    return "CONTINUE_WITHOUT"
}

# ============================================================
# Création du formulaire principal : layout adaptatif DPI
# ============================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function New-PercentColumn([single]$Value) {
    New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, $Value)
}
function New-PercentRow([single]$Value) {
    New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, $Value)
}
function New-AutoRow {
    New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)
}
function Set-ButtonLayout {
    param([System.Windows.Forms.Button]$Button, [int]$Height = 36)
    $Button.Dock = 'Fill'
    $Button.AutoSize = $true
    $Button.AutoSizeMode = 'GrowAndShrink'
    $Button.MinimumSize = New-Object System.Drawing.Size(105, $Height)
    $Button.Margin = New-Object System.Windows.Forms.Padding(4)
    $Button.Padding = New-Object System.Windows.Forms.Padding(8, 3, 8, 3)
}

$Form = New-Object System.Windows.Forms.Form
$Form.Text = 'CGLOBAL - Mode Selectif'
$Form.StartPosition = 'Manual'
$Form.FormBorderStyle = 'Sizable'
$Form.MaximizeBox = $true
$Form.MinimizeBox = $true
$Form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$Form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
$Form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$Form.ClientSize = New-Object System.Drawing.Size(920, 700)
$Form.MinimumSize = New-Object System.Drawing.Size(760, 580)

$MainLayout = New-Object System.Windows.Forms.TableLayoutPanel
$MainLayout.Dock = 'Fill'; $MainLayout.Padding = New-Object System.Windows.Forms.Padding(15)
$MainLayout.Margin = New-Object System.Windows.Forms.Padding(0)
$MainLayout.ColumnCount = 1; $MainLayout.RowCount = 4
$MainLayout.ColumnStyles.Add((New-PercentColumn 100)) | Out-Null
$MainLayout.RowStyles.Add((New-AutoRow)) | Out-Null
$MainLayout.RowStyles.Add((New-PercentRow 64)) | Out-Null
$MainLayout.RowStyles.Add((New-AutoRow)) | Out-Null
$MainLayout.RowStyles.Add((New-PercentRow 36)) | Out-Null
$Form.Controls.Add($MainLayout)

$Header = New-Object System.Windows.Forms.TableLayoutPanel
$Header.Dock = 'Fill'; $Header.AutoSize = $true; $Header.ColumnCount = 1; $Header.RowCount = 2
$Header.Margin = New-Object System.Windows.Forms.Padding(0,0,0,10)
$Header.ColumnStyles.Add((New-PercentColumn 100)) | Out-Null
$Header.RowStyles.Add((New-AutoRow)) | Out-Null; $Header.RowStyles.Add((New-AutoRow)) | Out-Null
$MainLayout.Controls.Add($Header,0,0)

$TitleLabel = New-Object System.Windows.Forms.Label
$TitleLabel.Text = 'CGLOBAL - Sélection des scripts à exécuter'
$TitleLabel.Font = New-Object System.Drawing.Font('Segoe UI',12,[System.Drawing.FontStyle]::Bold)
$TitleLabel.AutoSize = $true; $TitleLabel.Dock = 'Fill'; $TitleLabel.Margin = New-Object System.Windows.Forms.Padding(0,0,0,4)
$Header.Controls.Add($TitleLabel,0,0)
$SubLabel = New-Object System.Windows.Forms.Label
$SubLabel.Text = 'Cochez les scripts à lancer, puis cliquez sur Executer. Survolez un script pour voir sa description.'
$SubLabel.AutoSize = $true; $SubLabel.Dock = 'Fill'; $SubLabel.Margin = New-Object System.Windows.Forms.Padding(0)
$Header.Controls.Add($SubLabel,0,1)

$Content = New-Object System.Windows.Forms.TableLayoutPanel
$Content.Dock = 'Fill'; $Content.Margin = New-Object System.Windows.Forms.Padding(0)
$Content.ColumnCount = 2; $Content.RowCount = 1
$Content.ColumnStyles.Add((New-PercentColumn 66)) | Out-Null
$Content.ColumnStyles.Add((New-PercentColumn 34)) | Out-Null
$Content.RowStyles.Add((New-PercentRow 100)) | Out-Null
$MainLayout.Controls.Add($Content,0,1)

$Panel = New-Object System.Windows.Forms.FlowLayoutPanel
$Panel.Dock = 'Fill'; $Panel.FlowDirection = 'TopDown'; $Panel.WrapContents = $false
$Panel.AutoScroll = $true; $Panel.BorderStyle = 'FixedSingle'
$Panel.Padding = New-Object System.Windows.Forms.Padding(8); $Panel.Margin = New-Object System.Windows.Forms.Padding(0,0,10,0)
$Content.Controls.Add($Panel,0,0)

$Tooltip = New-Object System.Windows.Forms.ToolTip
$Tooltip.AutoPopDelay = 10000; $Tooltip.InitialDelay = 500; $Tooltip.ReshowDelay = 200; $Tooltip.ShowAlways = $true
$Checkboxes = @{}; $Results = @{}
$script:ExecutionMode = 'Interactif'
$script:SessionFile = 'C:\_CGLOBAL\CGLOBAL.Session.json'
foreach ($Script in $Scripts) {
    $CB = New-Object System.Windows.Forms.CheckBox
    $CB.Text = "[$($Script.Num)] $($Script.Desc)"; $CB.AutoSize = $true
    $CB.Margin = New-Object System.Windows.Forms.Padding(3,3,3,5)
    $CB.Padding = New-Object System.Windows.Forms.Padding(0,1,0,1); $CB.Tag = $Script
    if ($Script.Net) { $CB.ForeColor = [System.Drawing.Color]::DarkOrange }
    $Tooltip.SetToolTip($CB,$Script.Tooltip); $Panel.Controls.Add($CB)
    $Checkboxes[$Script.Num] = $CB; $Results[$Script.Num] = $null
}
$ResizeCheckboxes = {
    $Width = [Math]::Max(200,$Panel.ClientSize.Width - 28)
    foreach ($CB in $Checkboxes.Values) { $CB.MaximumSize = New-Object System.Drawing.Size($Width,0) }
}
$Panel.Add_ClientSizeChanged($ResizeCheckboxes)

$Commands = New-Object System.Windows.Forms.TableLayoutPanel
$Commands.Dock = 'Fill'; $Commands.AutoScroll = $true; $Commands.Margin = New-Object System.Windows.Forms.Padding(0)
$Commands.ColumnCount = 2; $Commands.RowCount = 10
$Commands.ColumnStyles.Add((New-PercentColumn 50)) | Out-Null; $Commands.ColumnStyles.Add((New-PercentColumn 50)) | Out-Null
1..9 | ForEach-Object { $Commands.RowStyles.Add((New-AutoRow)) | Out-Null }
$Commands.RowStyles.Add((New-PercentRow 100)) | Out-Null
$Content.Controls.Add($Commands,1,0)

$BtnTous = New-Object System.Windows.Forms.Button; $BtnTous.Text='Tous'; Set-ButtonLayout $BtnTous
$BtnTous.Add_Click({ foreach($CB in $Checkboxes.Values){$CB.Checked=$true} }); $Commands.Controls.Add($BtnTous,0,0)
$BtnAucun = New-Object System.Windows.Forms.Button; $BtnAucun.Text='Aucun'; Set-ButtonLayout $BtnAucun
$BtnAucun.Add_Click({ foreach($CB in $Checkboxes.Values){$CB.Checked=$false} }); $Commands.Controls.Add($BtnAucun,1,0)
$BtnSave = New-Object System.Windows.Forms.Button; $BtnSave.Text='Sauvegarder'; Set-ButtonLayout $BtnSave
$BtnSave.Add_Click({ Export-Selection $Checkboxes; [void][System.Windows.Forms.MessageBox]::Show('Sélection sauvegardée avec succès.','Sauvegarde','OK','Information') }); $Commands.Controls.Add($BtnSave,0,1)
$BtnLoad = New-Object System.Windows.Forms.Button; $BtnLoad.Text='Charger'; Set-ButtonLayout $BtnLoad
$BtnLoad.Add_Click({
    if(Import-Selection $Checkboxes){ [void][System.Windows.Forms.MessageBox]::Show('Sélection chargée avec succès.','Chargement','OK','Information') }
    else { [void][System.Windows.Forms.MessageBox]::Show('Aucune sélection précédente trouvée.','Chargement','OK','Warning') }
}); $Commands.Controls.Add($BtnLoad,1,1)

$NetLabel = New-Object System.Windows.Forms.Label
$NetLabel.Text="[INTERNET] =`r`nnécessite une connexion Internet"; $NetLabel.ForeColor=[System.Drawing.Color]::DarkOrange
$NetLabel.AutoSize=$true; $NetLabel.Dock='Fill'; $NetLabel.Margin=New-Object System.Windows.Forms.Padding(4,8,4,4)
$Commands.Controls.Add($NetLabel,0,2); $Commands.SetColumnSpan($NetLabel,2)
$LegendLabel = New-Object System.Windows.Forms.Label
$LegendLabel.Text="Légende :`r`n  Vert  = succès`r`n  Jaune = avertissement`r`n  Rouge = erreur / introuvable"
$LegendLabel.AutoSize=$true; $LegendLabel.Dock='Fill'; $LegendLabel.Margin=New-Object System.Windows.Forms.Padding(4,4,4,8)
$Commands.Controls.Add($LegendLabel,0,3); $Commands.SetColumnSpan($LegendLabel,2)

$ModeGroup = New-Object System.Windows.Forms.GroupBox
$ModeGroup.Text = 'Mode d execution'
$ModeGroup.Dock = 'Fill'; $ModeGroup.AutoSize = $true
$ModeFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$ModeFlow.Dock = 'Fill'; $ModeFlow.AutoSize = $true; $ModeFlow.WrapContents = $true
$RadioInteractif = New-Object System.Windows.Forms.RadioButton
$RadioInteractif.Text = 'Interactif'; $RadioInteractif.Checked = $true; $RadioInteractif.AutoSize = $true
$RadioPrevalide = New-Object System.Windows.Forms.RadioButton
$RadioPrevalide.Text = 'Prévalidé'; $RadioPrevalide.AutoSize = $true
$RadioSilencieux = New-Object System.Windows.Forms.RadioButton
$RadioSilencieux.Text = 'Silencieux'; $RadioSilencieux.AutoSize = $true
$ModeFlow.Controls.AddRange(@($RadioInteractif,$RadioPrevalide,$RadioSilencieux))
$ModeGroup.Controls.Add($ModeFlow)
$Tooltip.SetToolTip($RadioInteractif,'Les scripts conservent leurs demandes et confirmations habituelles.')
$Tooltip.SetToolTip($RadioPrevalide,'Toutes les décisions sont demandées avant le lancement, puis aucun popup pendant la séquence.')
$Tooltip.SetToolTip($RadioSilencieux,'Aucune question pendant la séquence. Les choix prudents par défaut sont appliqués.')
$Commands.Controls.Add($ModeGroup,0,4); $Commands.SetColumnSpan($ModeGroup,2)

$ProgressBar = New-Object System.Windows.Forms.ProgressBar
$ProgressBar.Dock='Fill'; $ProgressBar.MinimumSize=New-Object System.Drawing.Size(0,22); $ProgressBar.Margin=New-Object System.Windows.Forms.Padding(4)
$ProgressBar.Minimum=0; $ProgressBar.Maximum=100; $ProgressBar.Value=0
$Commands.Controls.Add($ProgressBar,0,5); $Commands.SetColumnSpan($ProgressBar,2)
$ProgressLabel = New-Object System.Windows.Forms.Label
$ProgressLabel.Text='Pret'; $ProgressLabel.AutoSize=$true; $ProgressLabel.Dock='Fill'; $ProgressLabel.AutoEllipsis=$true
$ProgressLabel.Margin=New-Object System.Windows.Forms.Padding(4); $Commands.Controls.Add($ProgressLabel,0,6); $Commands.SetColumnSpan($ProgressLabel,2)
$BtnExecuter = New-Object System.Windows.Forms.Button; $BtnExecuter.Text='Executer'
$BtnExecuter.Font=New-Object System.Drawing.Font('Segoe UI',10,[System.Drawing.FontStyle]::Bold); $BtnExecuter.BackColor=[System.Drawing.Color]::LightGreen
Set-ButtonLayout $BtnExecuter 42; $Commands.Controls.Add($BtnExecuter,0,7)
$BtnQuitter = New-Object System.Windows.Forms.Button; $BtnQuitter.Text='Quitter'
$BtnQuitter.Font=New-Object System.Drawing.Font('Segoe UI',10); $BtnQuitter.BackColor=[System.Drawing.Color]::LightCoral
Set-ButtonLayout $BtnQuitter 42
$BtnQuitter.Add_Click({ Export-Selection $Checkboxes; Write-LogSelective 'Fermeture par l''utilisateur (bouton Quitter)' 'INFO'; $Form.Close() })
$Commands.Controls.Add($BtnQuitter,1,7)

$LogLabel = New-Object System.Windows.Forms.Label
$LogLabel.Text='Journal en direct du script en cours :'; $LogLabel.Font=New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
$LogLabel.AutoSize=$true; $LogLabel.Dock='Fill'; $LogLabel.Margin=New-Object System.Windows.Forms.Padding(0,10,0,4)
$MainLayout.Controls.Add($LogLabel,0,2)
$LogBox = New-Object System.Windows.Forms.RichTextBox
$LogBox.Dock='Fill'; $LogBox.ReadOnly=$true; $LogBox.Font=New-Object System.Drawing.Font('Consolas',9)
$LogBox.BackColor=[System.Drawing.Color]::White; $LogBox.MinimumSize=New-Object System.Drawing.Size(0,80); $LogBox.Margin=New-Object System.Windows.Forms.Padding(0)
$MainLayout.Controls.Add($LogBox,0,3)

# Taille calculee apres la mise a l'echelle DPI effective.
$Form.Add_Shown({
    $Area = [System.Windows.Forms.Screen]::FromControl($Form).WorkingArea
    $TargetWidth  = [int][Math]::Round($Area.Width * 0.82)
    $TargetHeight = [int][Math]::Round($Area.Height * 0.90)
    $TargetWidth  = [Math]::Max([Math]::Min(760,$Area.Width-20),$TargetWidth)
    $TargetHeight = [Math]::Max([Math]::Min(580,$Area.Height-20),$TargetHeight)
    $TargetWidth  = [Math]::Min($TargetWidth,$Area.Width-20)
    $TargetHeight = [Math]::Min($TargetHeight,$Area.Height-20)
    $Left = $Area.Left + [int](($Area.Width-$TargetWidth)/2)
    $Top  = $Area.Top  + [int](($Area.Height-$TargetHeight)/2)
    $Form.SuspendLayout()
    try { $Form.Bounds = New-Object System.Drawing.Rectangle($Left,$Top,$TargetWidth,$TargetHeight) }
    finally { $Form.ResumeLayout($true) }
    & $ResizeCheckboxes
})

# Lecture du fichier de log en partage total (lecture ET ecriture), pour ne jamais
# bloquer Add-Content dans Write-Log pendant que le script en cours ecrit ses lignes.
# Get-Content seul provoquait des erreurs "fichier en cours d'utilisation" cote script.
function Read-CGlobalLogLines {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return @() }

    try {
        $FileStream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $Reader = New-Object System.IO.StreamReader($FileStream)
        $Content = $Reader.ReadToEnd()
        $Reader.Close()
        $FileStream.Close()
    }
    catch {
        return @()
    }

    if ([string]::IsNullOrEmpty($Content)) { return @() }
    return @($Content -split "`r?`n" | Where-Object { $_ -ne '' })
}

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
# Chargement automatique de la dernière selection
# ============================================================
$Form.Add_Shown({
    Import-Selection -Checkboxes $Checkboxes | Out-Null
})

# ============================================================
# Prévalidation centralisée
# ============================================================
function New-CGlobalSessionConfig {
    param([array]$SelectedScripts, [string]$Mode)
    $Config = [ordered]@{
        Mode = $Mode
        OfficeUninstall = 'No'
        OneDriveUninstall = 'No'
        ManufacturerUpdate = 'Cancel'
        RenameComputer = 'No'
        NewComputerName = ''
        LocalPasswordAction = 'No'
        LocalPasswordBlob = ''
        DisableDeploymentMode = 'Yes'
        LaunchWindowsUpdate = 'No'
        RemoveGuestWifi = 'Yes'
    }
    if ($Mode -eq 'Prévalidé') {
        $Nums = @($SelectedScripts | ForEach-Object { $_.Num })
        if ('14' -in $Nums) {
            $Config.OfficeUninstall = [string][System.Windows.Forms.MessageBox]::Show('Si Office ou OneNote est détecté, faut-il tout désinstaller ?','Prevalidation Office','YesNo','Question')
        }
        if ('17' -in $Nums) {
            $Config.OneDriveUninstall = [string][System.Windows.Forms.MessageBox]::Show('Si OneDrive est détecté, faut-il le désinstaller et le bloquer ?','Prévalidation OneDrive','YesNo','Question')
        }
        if ('19' -in $Nums) {
            $Config.ManufacturerUpdate = [string][System.Windows.Forms.MessageBox]::Show('Mises a jour constructeur :`n`nOUI = toutes, redémarrage autorisé`nNON = sans redémarrage forcé`nANNULER = ignorer le script','Prévalidation constructeur','YesNoCancel','Question')
        }
        if ('85' -in $Nums) {
            $Config.RenameComputer = [string][System.Windows.Forms.MessageBox]::Show("Voulez-vous renommer le poste '$env:COMPUTERNAME' ?",'Prévalidation renommage','YesNo','Question')
            if ($Config.RenameComputer -eq 'Yes') {
                $Config.NewComputerName = Show-CGlobalInputBox -Title 'Prévalidation du renommage' -Message 'Nouveau nom du poste (15 caracteres maximum) :' -DefaultText $env:COMPUTERNAME
                if ([string]::IsNullOrWhiteSpace($Config.NewComputerName)) { $Config.RenameComputer = 'No' }
            }
        }
        if ('90' -in $Nums) {
            $Config.LocalPasswordAction = [string][System.Windows.Forms.MessageBox]::Show('Si le compte local ne possède pas de mot de passe, faut-il en définir un ?','Prévalidation mot de passe','YesNo','Question')
            if ($Config.LocalPasswordAction -eq 'Yes') {
                $Config.LocalPasswordBlob = Show-CGlobalPasswordBox -Title 'Prévalidation du mot de passe local'
                if ([string]::IsNullOrWhiteSpace($Config.LocalPasswordBlob)) { $Config.LocalPasswordAction = 'No' }
            }
        }
        if ('99' -in $Nums) {
            $Config.DisableDeploymentMode = [string][System.Windows.Forms.MessageBox]::Show('Faut-il désactiver le mode déploiement et restaurer Windows Update ?','Prévalidation fin déploiement','YesNo','Question')
            if ($Config.DisableDeploymentMode -eq 'Yes') {
                $Config.LaunchWindowsUpdate = [string][System.Windows.Forms.MessageBox]::Show('Faut-il lancer immédiatement la recherche et installation Windows Update ?','Prévalidation Windows Update','YesNo','Question')
            }
        }
        $Config.RemoveGuestWifi = [string][System.Windows.Forms.MessageBox]::Show('Si le profil Wi-Fi invité est présent en fin de séquence, faut-il le supprimer ?','Prévalidation Wi-Fi','YesNo','Question')
    }
    $Config | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:SessionFile -Encoding UTF8
    return $Config
}

# ============================================================
# Logique d'exécution
# ============================================================
$BtnExecuter.Add_Click({

    $script:ExecutionInProgress = $true
    $script:CancelRequested = $false
    $script:CurrentChildProcess = $null

    # --- Récupérer les scripts coches ---
    $Selected = @()
    foreach ($Script in $Scripts) {
        if ($Checkboxes[$Script.Num].Checked) {
            $Selected += $Script
        }
    }

    # --- Aucun script coche ---
    if ($Selected.Count -eq 0) {
        $Result = [System.Windows.Forms.MessageBox]::Show(
            "Attention, aucun script n'est coché.`n`nVoulez-vous quitter ou revenir à la sélection ?",
            "Aucun script sélectionné",
            [System.Windows.Forms.MessageBoxButtons]::RetryCancel,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )

        if ($Result -eq [System.Windows.Forms.DialogResult]::Cancel) {
            Write-LogSelective "Fermeture par l'utilisateur (aucun script coché)" "WARN"
            Export-Selection -Checkboxes $Checkboxes
            $Form.Close()
        }
        return
    }


    if ($RadioPrevalide.Checked) { $script:ExecutionMode = 'Prévalidé' }
    elseif ($RadioSilencieux.Checked) { $script:ExecutionMode = 'Silencieux' }
    else { $script:ExecutionMode = 'Interactif' }
    $SessionConfig = New-CGlobalSessionConfig -SelectedScripts $Selected -Mode $script:ExecutionMode
    $env:CGLOBAL_EXECUTION_MODE = $script:ExecutionMode
    $env:CGLOBAL_SESSION_FILE = $script:SessionFile
    Write-LogSelective "Mode d'exécution : $($script:ExecutionMode)" 'INFO'

    # --- Vérifier si Internet nécessaire ---
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
                    Write-LogSelective "Execution annulée par l'utilisateur (pas de connexion Internet)" "WARN"
                    $ProgressLabel.Text = "Execution annulée (pas de connexion Internet)"
                    return
                }
                "CONTINUE_WITHOUT" {
                    $Selected = $Selected | Where-Object { -not $_.Net }
                    Write-LogSelective "Continuation sans les scripts Internet ($($ScriptsInternet.Count) script(s) ignorés)" "WARN"
                    $ProgressLabel.Text = "Continuation sans les scripts nécessitant Internet..."
                    $Form.Refresh()
                    [System.Windows.Forms.Application]::DoEvents()
                    Start-Sleep -Milliseconds 500
                }
                "OK" {
                    Write-LogSelective "Connexion Internet rétablie, poursuite normale" "OK"
                    $ProgressLabel.Text = "Connexion Internet rétablie"
                    $Form.Refresh()
                    [System.Windows.Forms.Application]::DoEvents()
                }
            }
        }
    }

    # --- Désactiver les controles pendant l'exécution ---
    $BtnExecuter.Enabled = $false
    $BtnTous.Enabled = $false
    $BtnAucun.Enabled = $false
    $BtnSave.Enabled = $false
    $BtnLoad.Enabled = $false
    foreach ($CB in $Checkboxes.Values) {
        $CB.Enabled = $false
    }

    # --- Réinitialiser les couleurs de résultat ---
    foreach ($Num in $Checkboxes.Keys) {
        $Checkboxes[$Num].BackColor = [System.Drawing.Color]::Transparent
    }

    # --- Executer les scripts ---
    $Total = $Selected.Count
    $Current = 0

    Write-LogSelective "Execution de $Total script(s) selectionné(s)" "INFO"

    foreach ($Script in $Selected) {
        if ($script:CancelRequested) {
            Write-LogSelective "Exécution interrompue par la fermeture de la fenêtre" "WARN"
            break
        }

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

            # IMPORTANT : forcer .NET à conserver le handle du processus des le départ.
            # Sans cela, $Process.ExitCode peut rester vide (null) même après la sortie
            # du processus (bug connu de Start-Process -PassThru sous PowerShell 5.1).
            $null = $Process.Handle
            $script:CurrentChildProcess = $Process

            # Boucle d'attente réactive, avec suivi en direct du log du script en cours
            while (-not $Process.HasExited) {
                [System.Windows.Forms.Application]::DoEvents()

                if ($script:CancelRequested) {
                    try { $Process.Kill() } catch { }
                    break
                }

                if (Test-Path $ScriptLogPath) {
                    $AllLines = Read-CGlobalLogLines -Path $ScriptLogPath
                    if ($AllLines.Count -gt $LastLineCount) {
                        foreach ($NewLine in $AllLines[$LastLineCount..($AllLines.Count - 1)]) {
                            Add-LogBoxLine -LogBox $LogBox -Line $NewLine
                        }
                        $LastLineCount = $AllLines.Count
                    }
                }

                Start-Sleep -Milliseconds 200
            }

            # Derniere lecture après la sortie du process, au cas ou des lignes
            # auraient été écrites juste avant la fin et pas encore captées
            if (Test-Path $ScriptLogPath) {
                $AllLines = Read-CGlobalLogLines -Path $ScriptLogPath
                if ($AllLines.Count -gt $LastLineCount) {
                    foreach ($NewLine in $AllLines[$LastLineCount..($AllLines.Count - 1)]) {
                        Add-LogBoxLine -LogBox $LogBox -Line $NewLine
                    }
                }
            }

            if ($script:CancelRequested) {
                Write-LogSelective "$($Script.File) interrompu (fermeture de la fenêtre)" "WARN"
                $Checkboxes[$Script.Num].BackColor = [System.Drawing.Color]::LightCoral
                $Results[$Script.Num] = "CANCELLED"
                break
            }

            # Synchronise proprement la sortie avant de lire le code (évite un ExitCode
            # non encore disponible juste après le passage de HasExited à $true)
            $Process.WaitForExit()
            $ExitCode = $Process.ExitCode

            if ($ExitCode -eq 0) {
                Write-LogSelective "$($Script.File) terminé avec succes" "OK"
                $Checkboxes[$Script.Num].BackColor = [System.Drawing.Color]::LightGreen
                $Results[$Script.Num] = "OK"
            }
            else {
                Write-LogSelective "$($Script.File) terminé avec le code $ExitCode" "WARN"
                $Checkboxes[$Script.Num].BackColor = [System.Drawing.Color]::LightYellow
                $Results[$Script.Num] = "WARN:$ExitCode"
            }
        }
        catch {
            Write-LogSelective "Erreur lors de l'exécution de $($Script.File) : $($_.Exception.Message)" "ERROR"
            $Checkboxes[$Script.Num].BackColor = [System.Drawing.Color]::LightCoral
            $Results[$Script.Num] = "ERROR"
        }
    }

    $ProgressBar.Value = 100
    $ProgressLabel.Text = "Execution terminée ($Total script(s))"
    $Form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
    Write-LogSelective "=== EXECUTION TERMINÉE ===" "OK"

    Export-Selection -Checkboxes $Checkboxes

    $OkCount = ($Results.Values | Where-Object { $_ -eq "OK" }).Count
    $WarnCount = ($Results.Values | Where-Object { $_ -like "WARN:*" }).Count
    $ErrCount = ($Results.Values | Where-Object { $_ -eq "ERROR" -or $_ -eq "MISSING" }).Count

    [System.Windows.Forms.MessageBox]::Show(
        "Execution terminée.`n`n$Total script(s) executés :`n  - $OkCount succès`n  - $WarnCount avertissement(s)`n  - $ErrCount erreur(s)`n`nConsultez le log pour les détails.",
        "Terminé",
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
# Sauvegarde automatique à la fermeture
# ============================================================
$Form.Add_FormClosing({
    Export-Selection -Checkboxes $Checkboxes
})

# ============================================================
# Affichage du formulaire
# ============================================================
Write-LogSelective "Affichage de l'interface de sélection" "INFO"
[void]$Form.ShowDialog()
Confirm-GuestWifiProfileRemoval
Write-LogSelective "=== FERMETURE MODE SÉLECTIF ===" "INFO"
Remove-Item -LiteralPath $script:SessionFile -Force -ErrorAction SilentlyContinue
Remove-Item Env:CGLOBAL_EXECUTION_MODE -ErrorAction SilentlyContinue
Remove-Item Env:CGLOBAL_SESSION_FILE -ErrorAction SilentlyContinue

# Fermeture explicite de la fenêtre DOS parente (Run_Selective.cmd). On ne compte
# plus sur le simple retour du .cmd après cet appel PowerShell : ça laissait parfois
# une fenêtre residuelle. On ne ferme que si le parent direct est bien un cmd.exe,
# par sécurité (évite de tuer un autre processus si le script est lancé autrement).
try {
    $ParentProcessId = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop).ParentProcessId
    $ParentProcess = Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue
    if ($ParentProcess -and $ParentProcess.ProcessName -eq 'cmd') {
        Stop-Process -Id $ParentProcessId -Force -ErrorAction SilentlyContinue
    }
}
catch {
    # Non bloquant : si la fermeture forcée échoue, le script se termine normalement quand même
}

exit 0
