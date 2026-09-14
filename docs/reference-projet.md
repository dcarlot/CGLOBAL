# CGLOBAL - Référence Projet

**Version : Septembre 2026**  
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
  - [6. Modes d’exécution ↑](#6-modes-dexécution-)
    - [6.1 Déploiement complet](#61-déploiement-complet)
    - [6.2 Déploiement sélectif](#62-déploiement-sélectif)
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
  - [10. Focus sur les scripts spécifiques ↑](#10-focus-sur-les-scripts-spécifiques-)
    - [10.1 12\_ConfigurerProfilParDefaut.ps1](#101-12_configurerprofilpardefautps1)
    - [10.2 18\_AssociationsFichiers.ps1](#102-18_associationsfichiersps1)
    - [10.3 19\_MisesAJourConstructeur.ps1](#103-19_misesajourconstructeurps1)
      - [Lenovo](#lenovo)
      - [Dell](#dell)
      - [Choix utilisateur](#choix-utilisateur)
    - [10.4 Run\_Selective.ps1](#104-run_selectiveps1)
      - [Fonctionnalités principales](#fonctionnalités-principales)
      - [Gestion DPI-Aware et 4K](#gestion-dpi-aware-et-4k)
      - [Gestion de la connectivité](#gestion-de-la-connectivité)
      - [Conservation ou suppression du profil Wi-Fi](#conservation-ou-suppression-du-profil-wi-fi)
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

- un fichier Batch d’orchestration ;
- des scripts PowerShell indépendants ;
- un module PowerShell commun ;
- un mode d’exécution complet ;
- un mode d’exécution sélectif.

Chaque script est autonome, mais suit les mêmes conventions :

- chargement du module commun ;
- journalisation ;
- gestion d’erreurs ;
- code de retour cohérent.

---

## 4. Arborescence [↑](#table-des-matières)

### Sur la clé USB

```
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
    ├── wifi.secret
    └── autres fichiers du kit
```

Le fichier `Run_Install.cmd` est lancé depuis la clé USB et détecte automatiquement son propre emplacement.

### Sur le poste cible

```
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
    └── autres fichiers du kit
```
Le fichier `wifi.secret` n'est pas recopié sur le disque C:

---

## 5. Module commun CGLOBAL.Common.psm1 [↑](#table-des-matières)

Le module commun mutualise les fonctionnalités utilisées par les scripts du projet.

### 5.1 Journalisation

Fonctions :

```powershell
Get-CGlobalLogFile
Initialize-CGlobalLog
Write-Log
```

Les journaux sont créés dans :

```text
C:\_CGLOBAL\Logs
```

Chaque script dispose de son propre fichier journal.

### 5.2 Popups

Fonctions :

```powershell
Show-CGlobalPopup
Show-CGlobalInputBox
```

Elles permettent d’obtenir un comportement homogène sur l’ensemble du projet.

### 5.3 Gestion DPI-Aware

Le module active automatiquement :

```powershell
SetProcessDPIAware()
```

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

---

## 6. Modes d’exécution [↑](#table-des-matières)

### 6.1 Déploiement complet

Le lancement principal se fait via :

```text
Run_Install.cmd
```

Les scripts sont exécutés automatiquement selon leur ordre numérique.

### 6.2 Déploiement sélectif

Le script :

```text
Run_Selective.ps1
```

permet :

- de sélectionner un ou plusieurs scripts ;
- de les lancer individuellement ;
- de réaliser des opérations de maintenance après déploiement ;
- de relancer facilement certaines actions sans exécuter toute la chaîne.

---

## 7. Gestion réseau et Wi-Fi [↑](#table-des-matières)

### 7.1 Connectivité Internet

Avant certaines opérations nécessitant Internet, le projet vérifie la présence d’un accès réseau fonctionnel.

Exemples :

- WinGet ;
- TeamViewer ;
- mises à jour constructeur ;
- téléchargements externes.

### 7.2 Fichier wifi.secret

Le fichier :

```text
wifi.secret
```

contient :

```text
SSID
MotDePasse
```

Il permet une connexion automatique au Wi-Fi invité lorsqu’aucune connexion Internet n’est disponible.

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

```powershell
netsh wlan show profiles
```

Cette logique évite :

- les doublons ;
- les profils inutiles ;
- les erreurs lors d’exécutions successives.

Les profils créés sont configurés en mode :

```text
Connexion automatique
```

### 7.5 Nettoyage des profils invités

Lorsqu’un profil invité a été utilisé durant une session, une confirmation utilisateur est affichée en fin de traitement.

Choix possibles :

- conserver le profil ;
- supprimer le profil.

La suppression utilise :

```powershell
netsh wlan delete profile
```

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
| `18_AssociationsFichiers.ps1` | Gère les associations de fichiers. Script actuellement suspendu. |

### 9.3 Maintenance et support

| Script | Description |
|---|---|
| `19_MisesAJourConstructeur.ps1` | Gère les mises à jour constructeur Lenovo et Dell. |
| `85_RenommagePoste.ps1` | Renomme le poste. |
| `90_VerificationMotDePasseCompteLocal.ps1` | Vérifie la présence d’un mot de passe sur le compte local. |
| `99_FinDeploiement.ps1` | Termine la procédure de déploiement. |

---

## 10. Focus sur les scripts spécifiques [↑](#table-des-matières)

### 10.1 12_ConfigurerProfilParDefaut.ps1

Configure le profil utilisateur par défaut afin que les nouveaux comptes créés sur la machine héritent automatiquement des paramètres souhaités.

### 10.2 18_AssociationsFichiers.ps1

Le script est conservé dans le projet, mais considéré comme non fiable sur certaines versions récentes de Windows 11.

Son utilisation reste suspendue tant qu’une méthode pérenne n’est pas validée.

### 10.3 19_MisesAJourConstructeur.ps1

Le script prend en charge les outils constructeur suivants.

#### Lenovo

- Lenovo Vantage ;
- Lenovo System Update.

#### Dell

- Dell Command Update.

#### Choix utilisateur

```text
Oui     = Toutes les mises à jour
          BIOS / Firmware inclus

Non     = Mises à jour sans redémarrage forcé

Annuler = Retour au menu
```

Le comportement est identique pour Lenovo et Dell.

### 10.4 Run_Selective.ps1 + Run_Selective.cmd

- `Run_Selective.cmd` : batch d'entrée (vérifie les droits admin, synchronise la clé USB, lance le PS1)
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
- suppression optionnelle du profil Wi-Fi invité en fin d’exécution.

#### Gestion DPI-Aware et 4K

Le module `CGLOBAL.Common.psm1` active la prise en charge DPI avant la création des contrôles Windows Forms.

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

```powershell
Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile
```

Niveaux couramment utilisés :

```powershell
Write-Log "Message d'information" "INFO"
Write-Log "Opération réussie" "OK"
Write-Log "Avertissement" "WARN"
Write-Log "Erreur" "ERROR"
```

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

- Réactivation éventuelle du script 18 lorsqu’une méthode fiable sera disponible.
- Harmonisation continue des scripts avec le module commun.
- Extension des contrôles de cohérence avant exécution.
- Renforcement de la documentation fonctionnelle de chaque script.
- Maintien de la compatibilité avec Windows 11 25H2 et les versions ultérieures.

---
