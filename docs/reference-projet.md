# CGLOBAL - Référence Projet

**Version : Octobre 2026**  
**Auteur : David Carlot**  
**Projet : CGLOBAL**  
**Plateforme cible : Windows 11 (24H2 / 25H2)**

---

## Table des matières

- [CGLOBAL - Référence Projet](#cglobal---référence-projet)
  - [Table des matières](#table-des-matières)
  - [1. Présentation ↑](#1-présentation-)
  - [2. Objectifs ↑](#2-objectifs-)
  - [3. Architecture du projet ↑](#3-architecture-du-projet-)
  - [4. Arborescence ↑](#4-arborescence-)
    - [Sur la clé USB](#sur-la-clé-usb)
    - [Sur le poste cible](#sur-le-poste-cible)
  - [5. Module commun CGLOBAL.Common.psm1 ↑](#5-module-commun-cglobalcommonpsm1-)
    - [5.1 Journalisation](#51-journalisation)
    - [5.2 Popups](#52-popups)
    - [5.3 Gestion DPI-Aware](#53-gestion-dpi-aware)
    - [5.4 Fenêtres au premier plan](#54-fenêtres-au-premier-plan)
    - [5.5 Modes d’exécution et décisions centralisées](#55-modes-dexécution-et-décisions-centralisées)
  - [6. Modes d’exécution ↑](#6-modes-dexécution-)
    - [6.1 Interactif (par défaut — ✅ fonctionnel)](#61-interactif-par-défaut---fonctionnel)
    - [6.2 Prévalidé (🟡 quasi opérationnel — validation finale en cours)](#62-prévalidé--quasi-opérationnel--validation-finale-en-cours)
    - [6.3 Silencieux (⚪ présent, non testé)](#63-silencieux--présent-non-testé)
  - [7. Gestion réseau et Wi-Fi ↑](#7-gestion-réseau-et-wi-fi-)
    - [7.1 Connectivité Internet](#71-connectivité-internet)
    - [7.2 Fichier wifi.secret](#72-fichier-wifisecret)
    - [7.3 Détection WLAN](#73-détection-wlan)
      - [Carte absente](#carte-absente)
      - [Carte désactivée](#carte-désactivée)
    - [7.4 Gestion des profils Wi-Fi](#74-gestion-des-profils-wi-fi)
    - [7.5 Nettoyage des profils invités](#75-nettoyage-des-profils-invités)
    - [7.6 Sécurité](#76-sécurité)
  - [8. Compatibilité affichage et DPI ↑](#8-compatibilité-affichage-et-dpi-)
  - [9. Catalogue des scripts ↑](#9-catalogue-des-scripts-)
    - [9.1 Configuration Windows](#91-configuration-windows)
    - [9.2 Applications](#92-applications)
    - [9.3 Maintenance et support](#93-maintenance-et-support)
    - [9.4 Script retiré du périmètre actif](#94-script-retiré-du-périmètre-actif)
  - [10. Focus sur les scripts spécifiques ↑](#10-focus-sur-les-scripts-spécifiques-)
    - [10.1 12_ConfigurerProfilParDefaut.ps1](#101-12_configurerprofilpardefautps1)
    - [10.2 18_AssociationsFichiers.ps1 (abandonné)](#102-18_associationsfichiersps1-abandonné)
    - [10.3 19_MisesAJourConstructeur.ps1](#103-19_misesajourconstructeurps1)
      - [Lenovo](#lenovo)
      - [Dell](#dell)
      - [Choix utilisateur](#choix-utilisateur)
    - [10.4 20_DesinstallationMcAfee.ps1 (en développement)](#104-20_desinstallationmcafeeeps1-en-développement)
      - [Stratégie prévue](#stratégie-prévue)
      - [Dossier tools\mccleaner](#dossier-toolsmccleaner)
      - [Points à finaliser avant validation](#points-à-finaliser-avant-validation)
    - [10.5 Run_Selective.ps1 + Run_Selective.cmd](#105-run_selectiveps1--run_selectivecmd)
      - [Fonctionnalités principales](#fonctionnalités-principales)
      - [Gestion DPI-Aware et 4K](#gestion-dpi-aware-et-4k)
      - [Gestion de la connectivité](#gestion-de-la-connectivité)
      - [Conservation ou suppression du profil Wi-Fi](#conservation-ou-suppression-du-profil-wi-fi)
    - [10.6 Persistance de la sélection — Run_Selective.sel](#106-persistance-de-la-sélection--run_selectivesel)
    - [10.7 Fichier de session — CGLOBAL.Session.json](#107-fichier-de-session--cglobalsessionjson)
  - [11. Journalisation ↑](#11-journalisation-)
  - [12. Conventions de développement ↑](#12-conventions-de-développement-)
  - [13. Évolutions prévues ↑](#13-évolutions-prévues-)

---

## 1. Présentation [↑](#table-des-matières)

CGLOBAL est une solution d’automatisation du post-déploiement Windows destinée à standardiser la configuration des postes neufs ou réinstallés.

Le projet permet d’exécuter automatiquement une série d’actions de personnalisation, de configuration, d’installation logicielle et de maintenance afin de réduire les interventions manuelles et de garantir une configuration homogène.

---

## 2. Objectifs [↑](#table-des-matières)

Les objectifs du projet sont les suivants :

- Standardiser les déploiements Windows.
- Réduire le temps de préparation des postes.
- Limiter les erreurs humaines.
- Centraliser les personnalisations utilisateur.
- Garantir une traçabilité complète des opérations.
- Simplifier les opérations de maintenance.
- Faciliter l’évolution du projet grâce à une architecture modulaire.

---

## 3. Architecture du projet [↑](#table-des-matières)

CGLOBAL repose sur :

- un fichier Batch d’orchestration (`Run_Selective.cmd`) ;
- des scripts PowerShell indépendants ;
- un module PowerShell commun (`CGLOBAL.Common.psm1`) ;
- trois modes d’exécution : Interactif, Prévalidé, Silencieux.

Chaque script est autonome, mais suit les mêmes conventions :

- chargement du module commun ;
- journalisation ;
- gestion d’erreurs ;
- code de retour cohérent.

---

## 4. Arborescence [↑](#table-des-matières)

### Sur la clé USB

    X:\
    └── _CGLOBAL
        ├── PS1
        │   ├── CGLOBAL.Common.psm1
        │   ├── Run_Selective.ps1
        │   ├── 00_ModeDeploiement.ps1
        │   ├── ...
        │   └── 99_FinDeploiement.ps1
        ├── installers
        │   └── Dossier d'installation des applis via Winget
        ├── tools
        │   └── mccleaner
        │       └── Contenu extrait de MCPR.exe (mccleanup.exe, master.ini, .wse, ...)
        ├── wifi.secret
        └── autres fichiers du kit

Le fichier `Run_Selective.cmd` est lancé depuis la clé USB et détecte automatiquement son propre emplacement.

> **Note** : l’ancien `Run_Install.cmd` n’est plus utilisé. Il est remplacé par `Run_Selective.cmd`, seul point d’entrée actif du projet.

> ⚠️ Le dossier `tools\mccleaner` n’est utilisé que par le script 20, actuellement **non fonctionnel**. Sa présence dans le kit n’est pas requise pour les scripts validés.

### Sur le poste cible

    C:\_CGLOBAL
        ├── Logs
        ├── PS1
        │   ├── CGLOBAL.Common.psm1
        │   ├── Run_Selective.ps1
        │   ├── 00_ModeDeploiement.ps1
        │   ├── ...
        │   └── 99_FinDeploiement.ps1
        ├── installers
        │   └── Dossiers d'installation des applis via Winget
        ├── tools
        │   └── mccleaner
        │       └── Contenu extrait de MCPR.exe
        └── autres fichiers du kit

Le fichier `wifi.secret` n'est pas recopié sur le disque C:.

> Le dossier `tools\mccleaner` est copié depuis la clé USB par la troisième commande `robocopy` de `Run_Selective.cmd` (pas de `/MIR`, exclusion de `wifi.secret` uniquement).

---

## 5. Module commun CGLOBAL.Common.psm1 [↑](#table-des-matières)

Le module commun mutualise les fonctionnalités utilisées par les scripts du projet.

### 5.1 Journalisation

Fonctions :

    Get-CGlobalLogFile
    Initialize-CGlobalLog
    Write-Log

Les journaux sont créés dans :

    C:\_CGLOBAL\Logs

Chaque script dispose de son propre fichier journal (`Log<NomDuScript>.txt`).

### 5.2 Popups

Fonctions :

    Show-CGlobalPopup
    Show-CGlobalInputBox
    Show-CGlobalPasswordBox

Elles permettent d’obtenir un comportement homogène sur l’ensemble du projet.

- `Show-CGlobalPopup` : boîte de message standard (OK, OKCancel, YesNo, etc.).
- `Show-CGlobalInputBox` : saisie d’une chaîne (utilisée notamment pour le renommage du poste).
- `Show-CGlobalPasswordBox` : saisie et confirmation d’un mot de passe, retourne un blob chiffré via `ConvertFrom-SecureString` (utilisée en mode Prévalidé pour le script 90). **Statut : opérationnel, documenté.**

### 5.3 Gestion DPI-Aware

Le module active automatiquement :

    SetProcessDPIAware()

afin d’éviter :

- le flou ;
- les fenêtres mal dimensionnées ;
- les contrôles tronqués.

Cette gestion est utilisée notamment par :

- `Run_Selective.ps1` ;
- `85_RenommagePoste.ps1` ;
- `90_VerificationMotDePasseCompteLocal.ps1`.

### 5.4 Fenêtres au premier plan

Le module intègre également les mécanismes nécessaires au forçage de l’affichage des fenêtres au premier plan afin d’éviter qu’elles ne soient masquées derrière d’autres applications.

### 5.5 Modes d’exécution et décisions centralisées

Fonctions :

    Get-CGlobalExecutionMode
    Get-CGlobalSessionConfig
    Get-CGlobalDecision

Le mode est transmis par variable d’environnement `CGLOBAL_EXECUTION_MODE` (`Interactif`, `Prévalidé`, `Silencieux`). Les décisions prévalidées sont lues via `CGLOBAL_SESSION_FILE` (voir §6.2 et §10.7).

---

## 6. Modes d’exécution [↑](#table-des-matières)

Le script `Run_Selective.ps1` propose trois modes, sélectionnables avant lancement :

### 6.1 Interactif (par défaut — ✅ fonctionnel)

Les scripts conservent leurs demandes et confirmations habituelles. C’est le mode d’origine du projet, pleinement opérationnel.

### 6.2 Prévalidé (🟡 quasi opérationnel — validation finale en cours)

Toutes les décisions sont demandées avant le lancement (Office, OneDrive, MAJ constructeur, renommage, mot de passe local, fin de déploiement, Wi-Fi invité), puis aucun popup n’est affiché pendant la séquence. Les décisions sont stockées dans `C:\_CGLOBAL\CGLOBAL.Session.json` et transmises aux scripts via `CGLOBAL_SESSION_FILE`. Il reste un dernier test de bout en bout à valider.

### 6.3 Silencieux (⚪ présent, non testé)

Aucune question pendant la séquence. Les choix prudents par défaut sont appliqués. Le mode est implémenté mais n’a pas encore été testé.

Quel que soit le mode, `Run_Selective.ps1` permet :

- de sélectionner un ou plusieurs scripts ;
- de les lancer individuellement ou groupés ;
- de réaliser des opérations de maintenance après déploiement ;
- de relancer facilement certaines actions sans exécuter toute la chaîne.

---

## 7. Gestion réseau et Wi-Fi [↑](#table-des-matières)

### 7.1 Connectivité Internet

Avant certaines opérations nécessitant Internet, le projet vérifie la présence d’un accès réseau fonctionnel.

Exemples :

- WinGet ;
- TeamViewer ;
- McAfee ;
- mises à jour constructeur ;
- téléchargements externes.

### 7.2 Fichier wifi.secret

Le fichier :

    wifi.secret

contient :

    SSID
    MotDePasse

Il permet une connexion automatique au Wi-Fi invité lorsqu’aucune connexion Internet n’est disponible. Il reste exclusivement sur la clé USB et n’est pas recopié sur le disque C:.

### 7.3 Détection WLAN

Avant toute tentative de connexion Wi-Fi, les éléments suivants sont vérifiés :

- présence d’une carte WLAN ;
- état activé ou désactivé ;
- disponibilité du réseau.

#### Carte absente

Exemple : ordinateur fixe sans adaptateur Wi-Fi.

Aucune tentative de connexion n’est réalisée.

#### Carte désactivée

L’utilisateur est informé.

Le script poursuit son exécution sans erreur bloquante.

### 7.4 Gestion des profils Wi-Fi

Avant de créer un profil, la commande suivante est utilisée afin de détecter un profil déjà présent :

    netsh wlan show profiles

Cette logique évite :

- les doublons ;
- les profils inutiles ;
- les erreurs lors d’exécutions successives.

Les profils créés sont configurés en mode :

    Connexion automatique

### 7.5 Nettoyage des profils invités

Lorsqu’un profil invité a été utilisé durant une session, une confirmation utilisateur est affichée en fin de traitement.

Choix possibles :

- conserver le profil ;
- supprimer le profil.

La suppression utilise :

    netsh wlan delete profile

La suppression concerne uniquement le SSID utilisé.

### 7.6 Sécurité

La logique Wi-Fi a été conçue afin de limiter la persistance des informations réseau.

Objectifs :

- éviter les stockages inutiles ;
- permettre la suppression du profil invité ;
- limiter l’exposition des informations d’accès réseau.

---

## 8. Compatibilité affichage et DPI [↑](#table-des-matières)

Le projet est compatible avec :

- Full HD ;
- QHD ;
- UHD ;
- 4K.

Facteurs de mise à l’échelle pris en charge :

- 100 % ;
- 125 % ;
- 150 % ;
- 175 % ;
- 200 %.

`Run_Selective.ps1` adapte automatiquement :

- la taille de la fenêtre ;
- la zone de liste ;
- la zone des boutons ;
- les marges ;
- les dimensions minimales.

L’intégralité du contenu doit rester visible sans redimensionnement manuel, notamment sur un écran 4K avec une mise à l’échelle à 200 %.

---

## 9. Catalogue des scripts [↑](#table-des-matières)

### 9.1 Configuration Windows

| Script | Description |
|---|---|
| `00_ModeDeploiement.ps1` | Prépare le poste pour le déploiement : paramètres d’alimentation et blocage du redémarrage automatique Windows Update lorsqu’un utilisateur est connecté. |
| `01_Bureau.ps1` | Configuration du bureau. |
| `02_MenuContextuelClassique.ps1` | Active le menu contextuel Windows classique. |
| `03_Explorateur.ps1` | Paramétrage de l’Explorateur de fichiers. |
| `04_ZoneNotification.ps1` | Configuration des icônes système de la zone de notification. |
| `05_BarreTachesGauche.ps1` | Aligne la barre des tâches à gauche. |
| `06_RechercheBarreTaches.ps1` | Configure la recherche dans la barre des tâches. |
| `07_MasquerVueTaches.ps1` | Masque le bouton Vue des tâches. |
| `08_MasquerWidgets.ps1` | Masque les Widgets. |
| `09_MSStoreBarreTache.ps1` | Retire l’épinglage du Microsoft Store dans la barre des tâches. |
| `10_DesactiverReprendre.ps1` | Désactive la reprise automatique des applications. |
| `11_ConfidentialiteLocalisation.ps1` | Configure les paramètres de confidentialité et de localisation Windows. |
| `12_ConfigurerProfilParDefaut.ps1` | Personnalise le profil utilisateur par défaut. |
| `13_NumLockDemarrage.ps1` | Active le verrouillage numérique au démarrage. |

### 9.2 Applications

| Script | Description |
|---|---|
| `14_DesinstallationOffice.ps1` | Désinstalle la version d’Office préinstallée. |
| `15_ApplicationsWinget.ps1` | Installe les applications avec WinGet. |
| `16_TeamViewerQS.ps1` | Déploie TeamViewer QuickSupport. |
| `17_DesinstallationOneDrive.ps1` | Désinstalle OneDrive. |
| `20_DesinstallationMcAfee.ps1` | ⚠️ **Nouveauté, non fonctionnelle.** Désinstallation de McAfee — en cours de développement, non validée. Ne pas utiliser en production. |

### 9.3 Maintenance et support

| Script | Description |
|---|---|
| `19_MisesAJourConstructeur.ps1` | Gère les mises à jour constructeur Lenovo et Dell. |
| `85_RenommagePoste.ps1` | Renomme le poste. |
| `90_VerificationMotDePasseCompteLocal.ps1` | Vérifie la présence d’un mot de passe sur le compte local. |
| `99_FinDeploiement.ps1` | Termine la procédure de déploiement. |

### 9.4 Script retiré du périmètre actif

| Script | Statut |
|---|---|
| `18_AssociationsFichiers.ps1` | **Abandonné.** Non exposé dans `Run_Selective.ps1`. La gestion des associations de fichiers est rendue impossible par les restrictions fortes imposées par Microsoft sur les versions récentes de Windows 11. Voir §13. |

---

## 10. Focus sur les scripts spécifiques [↑](#table-des-matières)

### 10.1 12_ConfigurerProfilParDefaut.ps1

Configure le profil utilisateur par défaut afin que les nouveaux comptes créés sur la machine héritent automatiquement des paramètres souhaités.

### 10.2 18_AssociationsFichiers.ps1 (abandonné)

Le script est retiré du périmètre actif. Les restrictions Microsoft sur les versions récentes de Windows 11 ne permettent pas une méthode pérenne et fiable de gestion des associations de fichiers. Voir §13.

### 10.3 19_MisesAJourConstructeur.ps1

Le script prend en charge les outils constructeur suivants.

#### Lenovo

- Lenovo Vantage ;
- Lenovo System Update.

#### Dell

- Dell Command Update.

#### Choix utilisateur

    Oui     = Toutes les mises à jour
              BIOS / Firmware inclus

    Non     = Mises à jour sans redémarrage forcé

    Annuler = Retour au menu

Le comportement est identique pour Lenovo et Dell.

### 10.4 20_DesinstallationMcAfee.ps1 (en développement)

Script en cours de rédaction, **non fonctionnel à ce jour**. Il est présent dans `Run_Selective.ps1` pour préparer l’intégration mais ne doit pas être coché en production.

#### Stratégie prévue

1. Détection (registre Uninstall + paquets AppX McAfee).
2. Suppression des paquets AppX McAfee (présents sur certains Lenovo récents).
3. Arrêt des processus et services McAfee.
4. Exécution de `mccleanup.exe` (moteur de MCPR, en mode silencieux) depuis `C:\_CGLOBAL\tools\mccleaner`.
5. En dernier recours : suppression manuelle forcée (services, fichiers, registre, tâches planifiées).

#### Dossier tools\mccleaner

Contient le contenu extrait de `MCPR.exe` (dossier `$1`) : `mccleanup.exe`, `master.ini`, les `.wse`, les sous-dossiers, etc.

Ordre de recherche au moment de l’exécution :

1. disque local (`C:\_CGLOBAL\tools\mccleaner`) ;
2. clé USB (`X:\_CGLOBAL\tools\mccleaner`) ;
3. (secours) téléchargement de `MCPR.exe` + extraction avec 7-Zip, puis sauvegarde sur la clé USB.

#### Points à finaliser avant validation

- comportement de `mccleanup.exe` (codes retour, timeout, gestion des échecs partiels) ;
- robustesse de la suppression manuelle (droits, fichiers verrouillés, redémarrage différé) ;
- tests sur postes réels (Lenovo, Dell, autres) ;
- décision sur la politique de distribution de `tools\mccleaner` (clé USB seule, ou copie locale par `Run_Selective.cmd` — actuellement copié par la 3ᵉ commande `robocopy`).

### 10.5 Run_Selective.ps1 + Run_Selective.cmd

- `Run_Selective.cmd` : batch d'entrée (vérifie les droits admin, synchronise la clé USB, purge les anciens logs, minimise la console, lance le PS1 avec `-USBPath`)
- `Run_Selective.ps1` fournit une interface graphique permettant d’exécuter un ou plusieurs scripts CGLOBAL sans relancer l’intégralité du déploiement.

#### Fonctionnalités principales

- sélection d’un ou plusieurs scripts ;
- lancement individuel ou groupé ;
- journalisation des opérations ;
- support DPI-Aware ;
- adaptation dynamique de l’interface aux écrans haute résolution ;
- prise en charge du Wi-Fi invité ;
- détection d’une carte WLAN absente ou désactivée ;
- réutilisation d’un profil Wi-Fi existant ;
- création du profil Wi-Fi en mode de connexion automatique ;
- suppression optionnelle du profil Wi-Fi invité en fin d’exécution ;
- trois modes d’exécution (Interactif / Prévalidé / Silencieux) ;
- journal en direct dans l’interface.

#### Gestion DPI-Aware et 4K

Le module `CGLOBAL.Common.psm1` active la prise en charge DPI avant la création des contrôles Windows Forms. `Run_Selective.ps1` effectue en plus une initialisation DPI moderne (`SetProcessDpiAwarenessContext`) avant le chargement du module.

La fenêtre principale adapte sa taille, sa hauteur utile, sa zone de liste, ses boutons et ses marges en fonction de la résolution et de la mise à l’échelle Windows.

L’objectif est de conserver tous les contrôles visibles, y compris sur un écran 4K avec une mise à l’échelle à 200 %.

#### Gestion de la connectivité

Si une connexion Internet fonctionnelle est déjà disponible, aucune connexion Wi-Fi supplémentaire n’est tentée.

En l’absence de connexion Internet, le script peut utiliser les informations du fichier `wifi.secret` afin de proposer ou d’établir la connexion au réseau invité configuré.

Avant toute opération Wi-Fi, le script vérifie :

- la présence d’un adaptateur WLAN ;
- son état activé ou désactivé ;
- l’existence éventuelle du profil Wi-Fi ;
- la disponibilité du SSID configuré.

Un poste fixe sans carte Wi-Fi ne génère pas d’erreur bloquante. Si une carte WLAN est présente mais désactivée, l’utilisateur est informé.

#### Conservation ou suppression du profil Wi-Fi

Lorsqu’un profil Wi-Fi invité a été utilisé, une popup permet à l’utilisateur de choisir s’il souhaite le conserver ou le supprimer.

La suppression ne concerne que le SSID invité utilisé durant l’exécution.

### 10.6 Persistance de la sélection — Run_Selective.sel

Le fichier :

    C:\_CGLOBAL\Run_Selective.sel

conserve la dernière sélection de scripts (format texte simple `NN=0|1`, une ligne par script). **Statut : opérationnel.**

Il est :

- importé automatiquement à l’ouverture de l’interface (dernière sélection) ;
- exporté automatiquement à la fermeture du formulaire, à la fin d’une exécution, et via le bouton « Sauvegarder » ;
- rechargeable manuellement via le bouton « Charger ».

### 10.7 Fichier de session — CGLOBAL.Session.json

Le fichier :

    C:\_CGLOBAL\CGLOBAL.Session.json

est utilisé uniquement en mode **Prévalidé**. Il centralise les décisions utilisateur collectées avant le lancement (Office, OneDrive, MAJ constructeur, renommage, mot de passe local, fin de déploiement, Wi-Fi invité).

Il est :

- écrit par `Run_Selective.ps1` (`New-CGlobalSessionConfig`) ;
- transmis aux scripts enfants via la variable d’environnement `CGLOBAL_SESSION_FILE` ;
- lu par le module commun (`Get-CGlobalSessionConfig` / `Get-CGlobalDecision`) ;
- supprimé en fin de session, ainsi que les variables d’environnement associées.

---

## 11. Journalisation [↑](#table-des-matières)

Tous les scripts CGLOBAL doivent :

- charger `CGLOBAL.Common.psm1` ;
- initialiser leur fichier journal ;
- écrire dans `C:\_CGLOBAL\Logs` ;
- retourner un code de sortie cohérent ;
- tracer les actions principales ;
- tracer les avertissements et les erreurs.

Modèle d’initialisation :

    Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
    $LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
    Initialize-CGlobalLog -LogFile $LogFile

Niveaux couramment utilisés :

    Write-Log "Message d'information" "INFO"
    Write-Log "Opération réussie" "OK"
    Write-Log "Avertissement" "WARN"
    Write-Log "Erreur" "ERROR"

---

## 12. Conventions de développement [↑](#table-des-matières)

Les scripts doivent respecter les règles suivantes :

- PowerShell 5.1 minimum ;
- exécution administrateur lorsque nécessaire ;
- utilisation du module commun ;
- journalisation systématique ;
- gestion d’erreurs avec `try` / `catch` ;
- encodage UTF-8 ;
- nomenclature homogène ;
- code idempotent lorsque cela est possible ;
- codes de sortie explicites, généralement `0` en cas de succès et `1` en cas d’erreur ;
- utilisation des fonctions communes pour les fenêtres et popups ;
- absence de stockage local durable des informations sensibles lorsqu’une gestion temporaire est possible.

---

## 13. Évolutions prévues [↑](#table-des-matières)

- **Finaliser `20_DesinstallationMcAfee.ps1`** : script non fonctionnel, à valider avant exposition en production. À cette occasion, statuer sur la distribution de `tools\mccleaner` (clé USB seule, copie locale par `Run_Selective.cmd`, ou téléchargement à la volée via MCPR.exe + 7-Zip).
- **Valider le mode Prévalidé** : un dernier test de bout en bout reste à effectuer.
- **Tester le mode Silencieux** : implémenté mais non testé à ce jour.
- **Abandon de `18_AssociationsFichiers.ps1`** : les restrictions Microsoft empêchent une gestion pérenne des associations de fichiers.
- **Retrait de `Run_Install.cmd`** des documents et du dépôt (remplacé par `Run_Selective.cmd`).
- Harmonisation continue des scripts avec le module commun.
- Extension des contrôles de cohérence avant exécution.
- Renforcement de la documentation fonctionnelle de chaque script.
- Maintien de la compatibilité avec Windows 11 25H2 et les versions ultérieures.

---