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
# Services de localisation Windows
# Requis par "netsh wlan show networks" depuis Windows 10 1803+.
# Sans cela, netsh renvoie une erreur de permission au lieu de la liste
# des reseaux Wi-Fi, et la detection du Wi-Fi invite echoue silencieusement.
# ============================================================
function Enable-WindowsLocationServices {
    # --- Verifier d'abord si une strategie de groupe (GPO/MDM) desactive purement et
    # simplement la localisation. Si c'est le cas, aucune cle ConsentStore locale ne
    # pourra la contourner : c'est une decision d'administration du parc, a lever
    # cote GPO/Intune, pas via ce script.
    try {
        $GpoKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"
        if (Test-Path $GpoKey) {
            $GpoValue = (Get-ItemProperty -Path $GpoKey -Name "DisableLocation" -ErrorAction SilentlyContinue).DisableLocation
            if ($GpoValue -eq 1) {
                Write-LogSelective "La localisation est desactivee par strategie de groupe (GPO/MDM) : $GpoKey\DisableLocation = 1. Impossible de l'activer depuis ce script, il faut modifier la strategie appliquee au poste." "ERROR"
                return
            }
        }
    }
    catch {
        Write-LogSelective "Impossible de verifier la strategie de groupe de localisation : $($_.Exception.Message)" "WARN"
    }

    try {
        $Changed = $false

        # --- Commutateur MAITRE "Services de localisation" (Parametres > Confidentialite
        # et securite > Localisation, tout en haut de la page). C'est CETTE cle qui est
        # responsable du message "Access refuse / autorisation de localisation requise"
        # renvoye par netsh, meme quand le consentement par application (ci-dessous) est
        # deja sur Allow. Sans elle, netsh wlan show networks echoue systematiquement.
        $LocKeyMaster = "HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration"
        if (-not (Test-Path $LocKeyMaster)) {
            New-Item -Path $LocKeyMaster -Force | Out-Null
        }
        $MasterValue = (Get-ItemProperty -Path $LocKeyMaster -Name "Status" -ErrorAction SilentlyContinue).Status
        $MasterChanged = $MasterValue -ne 1
        if ($MasterChanged) {
            Set-ItemProperty -Path $LocKeyMaster -Name "Status" -Value 1 -Type DWord -Force
        }

        # --- Bascule machine ("Autoriser les applications a acceder a la position") ---
        $LocKeyMachine = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"
        if (-not (Test-Path $LocKeyMachine)) {
            New-Item -Path $LocKeyMachine -Force | Out-Null
        }
        $MachineValue = (Get-ItemProperty -Path $LocKeyMachine -Name "Value" -ErrorAction SilentlyContinue).Value
        $MachineChanged = $MachineValue -ne "Allow"
        if ($MachineChanged) {
            Set-ItemProperty -Path $LocKeyMachine -Name "Value" -Value "Allow" -Type String -Force
        }

        # --- Bascule utilisateur courant (peut surcharger la bascule machine) ---
        $LocKeyUser = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"
        if (-not (Test-Path $LocKeyUser)) {
            New-Item -Path $LocKeyUser -Force | Out-Null
        }
        $UserValue = (Get-ItemProperty -Path $LocKeyUser -Name "Value" -ErrorAction SilentlyContinue).Value
        $UserChanged = $UserValue -ne "Allow"
        if ($UserChanged) {
            Set-ItemProperty -Path $LocKeyUser -Name "Value" -Value "Allow" -Type String -Force
        }

        # --- "Autoriser les applications DE BUREAU a acceder a la position" ---
        # Cle distincte et INDISPENSABLE pour netsh.exe : c'est une application Win32
        # situee dans C:\Windows\System32, donc concernee par la bascule "applications
        # de bureau" (NonPackaged) et non par la bascule "applications" ci-dessus (qui
        # vise les apps UWP/Store). D'apres la documentation Microsoft, les processus
        # situes dans System32 ne declenchent JAMAIS l'invite de consentement a
        # l'utilisateur : sans cette cle deja a "Allow", ils sont refuses silencieusement,
        # meme avec les deux bascules precedentes et le commutateur maitre actives.
        $LocKeyMachineDesktop = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location\NonPackaged"
        if (-not (Test-Path $LocKeyMachineDesktop)) {
            New-Item -Path $LocKeyMachineDesktop -Force | Out-Null
        }
        $MachineDesktopValue = (Get-ItemProperty -Path $LocKeyMachineDesktop -Name "Value" -ErrorAction SilentlyContinue).Value
        $MachineDesktopChanged = $MachineDesktopValue -ne "Allow"
        if ($MachineDesktopChanged) {
            Set-ItemProperty -Path $LocKeyMachineDesktop -Name "Value" -Value "Allow" -Type String -Force
        }

        $LocKeyUserDesktop = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location\NonPackaged"
        if (-not (Test-Path $LocKeyUserDesktop)) {
            New-Item -Path $LocKeyUserDesktop -Force | Out-Null
        }
        $UserDesktopValue = (Get-ItemProperty -Path $LocKeyUserDesktop -Name "Value" -ErrorAction SilentlyContinue).Value
        $UserDesktopChanged = $UserDesktopValue -ne "Allow"
        if ($UserDesktopChanged) {
            Set-ItemProperty -Path $LocKeyUserDesktop -Name "Value" -Value "Allow" -Type String -Force
        }

        $Changed = $MasterChanged -or $MachineChanged -or $UserChanged -or $MachineDesktopChanged -or $UserDesktopChanged

        if (-not $Changed) {
            Write-LogSelective "Services de localisation deja actifs (maitre + apps + apps de bureau, machine + utilisateur)" "INFO"
            return
        }

        # --- S'assurer que le service de localisation peut demarrer, puis le relancer ---
        $LfSvc = Get-Service -Name lfsvc -ErrorAction SilentlyContinue
        if ($LfSvc) {
            if ($LfSvc.StartType -eq 'Disabled') {
                Set-Service -Name lfsvc -StartupType Manual
            }
            Restart-Service -Name lfsvc -Force -ErrorAction SilentlyContinue
        }

        # --- Redemarrer le service WLAN pour qu'il prenne en compte le changement ---
        # (evite d'avoir besoin d'une deconnexion/reconnexion de session pour que
        # "netsh wlan show networks" arrete de renvoyer une erreur de permission)
        Restart-Service -Name WlanSvc -Force -ErrorAction SilentlyContinue

        # Laisser le temps aux services de redemarrer completement avant que le
        # reste du script n'appelle netsh wlan show networks.
        Start-Sleep -Seconds 2

        Write-LogSelective "Services de localisation Windows actives (maitre + apps + apps de bureau, machine + utilisateur), services lfsvc/WlanSvc redemarres" "OK"
    }
    catch {
        Write-LogSelective "Impossible d'activer completement les services de localisation : $($_.Exception.Message)" "WARN"
    }
}

Enable-WindowsLocationServices

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
# Wi-Fi invite du bureau : detection + connexion automatique proposee
# ============================================================
$script:GuestWifiSSID = "CGLOBAL INVITES"

# ============================================================
# Recuperation du mot de passe Wi-Fi invite (JAMAIS en clair dans le depot,
# celui-ci etant public sur GitHub). Ordre de priorite :
#   1. Variable d'environnement CGLOBAL_WIFI_PASSWORD
#   2. Fichier local non versionne C:\_CGLOBAL\wifi.secret
#   3. Saisie manuelle (boite de dialogue), avec proposition de sauvegarde locale
# ============================================================
function Get-GuestWifiPassword {
    $SecretFile = "C:\_CGLOBAL\wifi.secret"

    if ($env:CGLOBAL_WIFI_PASSWORD) {
        Write-LogSelective "Mot de passe Wi-Fi invite recupere depuis la variable d'environnement" "INFO"
        return $env:CGLOBAL_WIFI_PASSWORD
    }

    if (Test-Path $SecretFile) {
        try {
            $Content = (Get-Content -Path $SecretFile -Encoding UTF8 -ErrorAction Stop | Select-Object -First 1)
            if (-not [string]::IsNullOrWhiteSpace($Content)) {
                Write-LogSelective "Mot de passe Wi-Fi invite recupere depuis $SecretFile" "INFO"
                return $Content.Trim()
            }
        }
        catch {
            Write-LogSelective "Impossible de lire $SecretFile : $($_.Exception.Message)" "WARN"
        }
    }

    Write-LogSelective "Aucun mot de passe Wi-Fi invite trouve (env/variable ou fichier), saisie manuelle demandee" "WARN"

    Add-Type -AssemblyName Microsoft.VisualBasic
    $Entered = [Microsoft.VisualBasic.Interaction]::InputBox(
        "Mot de passe du Wi-Fi invite '$($script:GuestWifiSSID)' introuvable.`n`nSaisissez-le pour cette session :",
        "Mot de passe Wi-Fi invite requis",
        ""
    )

    if ([string]::IsNullOrWhiteSpace($Entered)) {
        Write-LogSelective "Aucun mot de passe saisi : connexion automatique au Wi-Fi invite desactivee pour cette session" "WARN"
        return $null
    }

    try {
        $SecretFolder = Split-Path -Path $SecretFile -Parent
        if (-not (Test-Path $SecretFolder)) {
            New-Item -Path $SecretFolder -ItemType Directory -Force | Out-Null
        }
        Set-Content -Path $SecretFile -Value $Entered -Encoding UTF8 -Force
        Write-LogSelective "Mot de passe Wi-Fi invite sauvegarde localement dans $SecretFile pour les prochains lancements" "OK"
    }
    catch {
        Write-LogSelective "Impossible de sauvegarder le mot de passe localement : $($_.Exception.Message)" "WARN"
    }

    return $Entered
}

# NOTE (correctif) : on ne recupere plus le mot de passe ici de facon systematique.
# Il est desormais demande "a la volee", uniquement si le SSID invite est reellement
# detecte a proximite (voir Resolve-InternetRequirement). Cela evite d'afficher une
# InputBox au tout debut du script, sans contexte, meme quand Internet est deja
# disponible ou que le Wi-Fi invite n'est pas a portee.
$script:GuestWifiPassword = $null

# ============================================================
# Detection Wi-Fi via le fournisseur WMI natif NDIS (sans compilation, sans outil externe)
# ------------------------------------------------------------
# root\wmi\MSNdis_80211_BSSIList est un fournisseur WMI historique qui interroge
# directement le pilote de la carte Wi-Fi (miniport NDIS) pour obtenir la liste des
# reseaux 802.11 visibles. Il est ANTERIEUR a la couche de consentement de
# localisation introduite avec l'API WLAN moderne (WlanGetAvailableNetworkList,
# utilisee par netsh wlan show networks) et n'est donc pas soumis a cette
# restriction : c'est une simple requete WMI en PowerShell pur, sans compilation
# ni executable externe a maintenir.
# ============================================================

function Get-WifiSsidListViaWmi {
    # Retourne la liste des SSID visibles (tableau de chaines, eventuellement vide),
    # ou $null si le fournisseur WMI n'est pas disponible/interrogeable sur ce poste.
    try {
        $BssiLists = Get-CimInstance -Namespace "root\wmi" -ClassName "MSNdis_80211_BSSIList" -ErrorAction Stop
    }
    catch {
        Write-LogSelective "Fournisseur WMI MSNdis_80211_BSSIList indisponible sur ce poste : $($_.Exception.Message)" "WARN"
        return $null
    }

    $SsidList = [System.Collections.Generic.List[string]]::new()

    foreach ($Item in $BssiLists) {
        foreach ($Bssi in $Item.Ndis80211BssiList) {
            try {
                $SsidInfo = $Bssi.Ndis80211Ssid
                $Len = [int]$SsidInfo.Ndis80211SsidLength
                if ($Len -gt 0 -and $Len -le $SsidInfo.Ndis80211Ssid.Length) {
                    $Bytes = $SsidInfo.Ndis80211Ssid[0..($Len - 1)]
                    $Ssid = [System.Text.Encoding]::UTF8.GetString([byte[]]$Bytes)
                    if (-not [string]::IsNullOrWhiteSpace($Ssid)) {
                        $SsidList.Add($Ssid)
                    }
                }
            }
            catch {
                # Une entree malformee ou un format inattendu ne doit pas interrompre
                # le parcours des autres reseaux detectes.
                continue
            }
        }
    }

    return $SsidList
}

function Test-GuestWifiAvailable {
    # Retourne "Found", "NotFound" ou "Unknown" (detection impossible, ex. permission
    # de localisation refusee malgre toutes les cles de registre correctes -- ce cas
    # necessite normalement un redemarrage complet du poste pour etre resolu, ce que
    # ce script ne peut pas forcer silencieusement). "Unknown" permet a l'appelant de
    # quand meme proposer une tentative de connexion "a l'aveugle", puisque la commande
    # de connexion (netsh wlan connect) n'est elle-meme pas soumise a cette restriction.

    # --- Verifier qu'un adaptateur Wi-Fi existe et est actif ---
    try {
        $WifiAdapters = Get-NetAdapter -ErrorAction Stop | Where-Object { $_.MediaType -eq 'Native 802.11' }

        if (-not $WifiAdapters) {
            Write-LogSelective "Aucun adaptateur Wi-Fi detecte sur ce poste" "WARN"
            return "NotFound"
        }

        foreach ($Adapter in $WifiAdapters) {
            Write-LogSelective "Adaptateur Wi-Fi trouve : $($Adapter.Name) - Statut : $($Adapter.Status)" "INFO"

            if ($Adapter.Status -eq 'Not Present') {
                continue
            }

            if ($Adapter.Status -eq 'Disabled') {
                Write-LogSelective "Adaptateur Wi-Fi '$($Adapter.Name)' desactive, tentative de reactivation" "WARN"
                try {
                    Enable-NetAdapter -Name $Adapter.Name -Confirm:$false -ErrorAction Stop
                    Start-Sleep -Seconds 3
                    Write-LogSelective "Adaptateur Wi-Fi '$($Adapter.Name)' reactive" "OK"
                }
                catch {
                    Write-LogSelective "Impossible de reactiver l'adaptateur Wi-Fi '$($Adapter.Name)' : $($_.Exception.Message)" "ERROR"
                }
            }
        }
    }
    catch {
        Write-LogSelective "Impossible d'interroger les adaptateurs reseau (Get-NetAdapter) : $($_.Exception.Message)" "WARN"
    }

    # --- Methode 1 (prioritaire) : fournisseur WMI natif NDIS, non soumis a la
    # restriction de permission de localisation qui bloque netsh sur ce parc. ---
    $VisibleSsids = Get-WifiSsidListViaWmi
    if ($null -ne $VisibleSsids) {
        Write-LogSelective "Reseaux Wi-Fi visibles (via WMI root\wmi\MSNdis_80211_BSSIList) : $($VisibleSsids -join ', ')" "INFO"
        if ($VisibleSsids -contains $script:GuestWifiSSID) {
            return "Found"
        }
        if ($VisibleSsids.Count -gt 0) {
            # Le fournisseur WMI a bien renvoye des reseaux (donc il fonctionne), mais
            # aucun ne correspond au SSID invite : resultat fiable.
            return "NotFound"
        }
        # Liste vide : peu fiable (le fournisseur WMI peut renvoyer une liste vide meme
        # quand il fonctionne mal), on tente la methode de repli plutot que de conclure
        # trop vite a une absence de reseau.
        Write-LogSelective "Le fournisseur WMI MSNdis_80211_BSSIList n'a renvoye aucun reseau, tentative via netsh en repli" "WARN"
    }

    # --- Methode 2 (repli) : netsh wlan show networks (soumis a la restriction connue) ---
    try {
        $RawOutput = & netsh wlan show networks 2>&1
        $ExitCode = $LASTEXITCODE
        $NetworksText = ($RawOutput | Out-String)

        Write-LogSelective "Sortie de 'netsh wlan show networks' (code $ExitCode) :`r`n$NetworksText" "INFO"

        if ($NetworksText -match 'autorisation de localisation|location permission|Access is denied|Acc.s refus.') {
            # La detection elle-meme est bloquee par la restriction systeme de
            # localisation (connue pour persister meme apres correction du registre,
            # tant qu'un redemarrage complet n'a pas ete effectue). On ne peut pas
            # savoir si le SSID est present ou non : etat indetermine, pas "absent".
            Write-LogSelective "Impossible de scanner les reseaux Wi-Fi : restriction de permission de localisation active (necessite probablement un redemarrage complet du poste). Une tentative de connexion directe sera proposee malgre tout." "WARN"
            return "Unknown"
        }

        if ([string]::IsNullOrWhiteSpace($NetworksText)) {
            Write-LogSelective "netsh n'a renvoye aucune sortie : verifier que le service WLAN AutoConfig (WlanSvc) est bien demarre" "WARN"
            return "Unknown"
        }

        if ($NetworksText -match 'non g.r.e sur cette interface|not supported on this interface|no wireless interface') {
            Write-LogSelective "netsh indique l'absence d'interface Wi-Fi geree sur ce poste" "ERROR"
            return "NotFound"
        }

        $Found = $NetworksText -match [regex]::Escape($script:GuestWifiSSID)
        if ($Found) {
            return "Found"
        }

        Write-LogSelective "SSID '$($script:GuestWifiSSID)' non trouve dans la liste des reseaux visibles" "WARN"
        return "NotFound"
    }
    catch {
        Write-LogSelective "Erreur lors de l'appel a 'netsh wlan show networks' : $($_.Exception.Message)" "ERROR"
        return "Unknown"
    }
}

function Connect-CGlobalGuestWifi {
    Write-LogSelective "Tentative de connexion au Wi-Fi invite '$($script:GuestWifiSSID)'" "INFO"

    $ProfileXml = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$($script:GuestWifiSSID)</name>
    <SSIDConfig>
        <SSID>
            <name>$($script:GuestWifiSSID)</name>
        </SSID>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>manual</connectionMode>
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
                <keyMaterial>$($script:GuestWifiPassword)</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>
"@

    $ProfilePath = Join-Path $env:TEMP "CGlobalGuestWifi.xml"

    try {
        Set-Content -Path $ProfilePath -Value $ProfileXml -Encoding UTF8

        $AddResult = (netsh wlan add profile filename="$ProfilePath" user=all) -join " "
        Write-LogSelective "Ajout du profil Wi-Fi invite : $AddResult" "INFO"

        $ConnectResult = (netsh wlan connect name="$($script:GuestWifiSSID)" ssid="$($script:GuestWifiSSID)") -join " "
        Write-LogSelective "Connexion au Wi-Fi invite : $ConnectResult" "INFO"

        # Laisser le temps a Windows d'etablir la connexion et d'obtenir une adresse IP
        Start-Sleep -Seconds 5
        return $true
    }
    catch {
        Write-LogSelective "Erreur lors de la connexion au Wi-Fi invite : $($_.Exception.Message)" "ERROR"
        return $false
    }
    finally {
        Remove-Item -Path $ProfilePath -Force -ErrorAction SilentlyContinue
    }
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

    # --- Wi-Fi invite du bureau detecte a proximite : proposition de connexion automatique ---
    # CORRECTIF : la detection du SSID est testee EN PREMIER, independamment du fait
    # qu'un mot de passe soit deja connu. Test-GuestWifiAvailable renvoie desormais
    # "Found" / "NotFound" / "Unknown" : "Unknown" correspond au cas ou le scan lui-meme
    # est bloque par la restriction de permission de localisation de Windows (netsh wlan
    # show networks refuse l'acces meme avec toutes les cles de registre correctes, tant
    # qu'un redemarrage complet du poste n'a pas eu lieu). Dans ce cas, on ne sait pas si
    # le reseau est present, mais on peut quand meme PROPOSER une connexion directe : la
    # commande "netsh wlan connect" n'est elle-meme pas soumise a cette restriction.
    $WifiDetection = Test-GuestWifiAvailable

    if ($WifiDetection -eq "NotFound") {
        Write-LogSelective "Wi-Fi invite '$($script:GuestWifiSSID)' non detecte a proximite" "INFO"
    }
    else {
        if ($WifiDetection -eq "Found") {
            Write-LogSelective "Reseau Wi-Fi invite '$($script:GuestWifiSSID)' detecte a proximite" "INFO"
            $PromptMessage = "Aucun acces Internet detecte, mais le reseau Wi-Fi '$($script:GuestWifiSSID)' est visible a proximite.`n`nVoulez-vous vous y connecter automatiquement ?"
        }
        else {
            # $WifiDetection -eq "Unknown"
            $PromptMessage = "Aucun acces Internet detecte. La detection automatique des reseaux Wi-Fi est bloquee par une restriction systeme (permission de localisation), mais le reseau invite '$($script:GuestWifiSSID)' est peut-etre tout de meme a portee.`n`nVoulez-vous tenter de vous y connecter directement ?"
        }

        # Le mot de passe n'est demande qu'a ce moment precis, ce qui est beaucoup plus
        # clair pour l'utilisateur qu'une InputBox surprise au tout debut du script.
        if ([string]::IsNullOrWhiteSpace($script:GuestWifiPassword)) {
            $script:GuestWifiPassword = Get-GuestWifiPassword
        }

        if ([string]::IsNullOrWhiteSpace($script:GuestWifiPassword)) {
            Write-LogSelective "Aucun mot de passe fourni : connexion automatique au Wi-Fi invite ignoree" "WARN"
        }
        else {
            $WifiChoice = [System.Windows.Forms.MessageBox]::Show(
                $PromptMessage,
                "Wi-Fi invite",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )

            if ($WifiChoice -eq [System.Windows.Forms.DialogResult]::Yes) {
                Connect-CGlobalGuestWifi | Out-Null

                if (Test-InternetConnection) {
                    Write-LogSelective "Connexion Internet retablie via le Wi-Fi invite" "OK"
                    return "OK"
                }

                Write-LogSelective "Connexion au Wi-Fi invite tentee mais toujours aucun acces Internet" "WARN"
            }
        }
    }

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
$Form.Height = 700
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

# --- Panel de gauche : liste des scripts (avec ascenseur si necessaire) ---
$Panel = New-Object System.Windows.Forms.Panel
$Panel.Location = New-Object System.Drawing.Point(20, 80)
$Panel.Width = 560
$Panel.Height = 340
$Panel.BorderStyle = "FixedSingle"
$Panel.AutoScroll = $true
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
    $CB.Width = 500
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
$LogLabel.Location = New-Object System.Drawing.Point(20, 440)
$LogLabel.Width = 860
$LogLabel.Height = 20
$Form.Controls.Add($LogLabel)

$LogBox = New-Object System.Windows.Forms.RichTextBox
$LogBox.Location = New-Object System.Drawing.Point(20, 463)
$LogBox.Width = 860
$LogBox.Height = 140
$LogBox.ReadOnly = $true
$LogBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$LogBox.BackColor = [System.Drawing.Color]::White
$Form.Controls.Add($LogBox)

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
# Chargement automatique de la derniere selection
# ============================================================
$Form.Add_Shown({
    Import-Selection -Checkboxes $Checkboxes | Out-Null
})

# ============================================================
# Logique d'execution
# ============================================================
$BtnExecuter.Add_Click({

    $script:ExecutionInProgress = $true
    $script:CancelRequested = $false
    $script:CurrentChildProcess = $null

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
        if ($script:CancelRequested) {
            Write-LogSelective "Execution interrompue par la fermeture de la fenetre" "WARN"
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

            # IMPORTANT : forcer .NET a conserver le handle du processus des le depart.
            # Sans cela, $Process.ExitCode peut rester vide (null) meme apres la sortie
            # du processus (bug connu de Start-Process -PassThru sous PowerShell 5.1).
            $null = $Process.Handle
            $script:CurrentChildProcess = $Process

            # Boucle d attente reactive, avec suivi en direct du log du script en cours
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

            # Derniere lecture apres la sortie du process, au cas ou des lignes
            # auraient ete ecrites juste avant la fin et pas encore captees
            if (Test-Path $ScriptLogPath) {
                $AllLines = Read-CGlobalLogLines -Path $ScriptLogPath
                if ($AllLines.Count -gt $LastLineCount) {
                    foreach ($NewLine in $AllLines[$LastLineCount..($AllLines.Count - 1)]) {
                        Add-LogBoxLine -LogBox $LogBox -Line $NewLine
                    }
                }
            }

            if ($script:CancelRequested) {
                Write-LogSelective "$($Script.File) interrompu (fermeture de la fenetre)" "WARN"
                $Checkboxes[$Script.Num].BackColor = [System.Drawing.Color]::LightCoral
                $Results[$Script.Num] = "CANCELLED"
                break
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

# Fermeture explicite de la fenetre DOS parente (Run_Selective.cmd). On ne compte
# plus sur le simple retour du .cmd apres cet appel PowerShell : ca laissait parfois
# une fenetre residuelle. On ne ferme que si le parent direct est bien un cmd.exe,
# par securite (evite de tuer un autre processus si le script est lance autrement).
try {
    $ParentProcessId = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop).ParentProcessId
    $ParentProcess = Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue
    if ($ParentProcess -and $ParentProcess.ProcessName -eq 'cmd') {
        Stop-Process -Id $ParentProcessId -Force -ErrorAction SilentlyContinue
    }
}
catch {
    # Non bloquant : si la fermeture forcee echoue, le script se termine normalement quand meme
}

exit 0
