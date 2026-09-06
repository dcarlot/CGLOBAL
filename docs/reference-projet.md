## Sommaire

- 1\. Contexte général
- 2\. Principes techniques retenus
- 3\. Arborescence du kit
- 4\. Mode sélectif : Run_Selective.cmd + Run_Selective.ps1
- 5\. Ordre des scripts
- Glossaire
- Tableau récapitulatif des scripts
- 6\. État détaillé des scripts
- 7\. Particularités Windows 11 25H2 observées
- 8\. Décisions validées
- 9\. Points restant à traiter ou à valider
- 10\. Démarrage d'un nouveau chat

## 1\. Contexte général

Projet d'automatisation post-installation pour des postes Windows 11, principalement validé sur Windows 11 25H2, dans un contexte MSP.

### Objectifs

- Standardiser la préparation des postes clients.
- Automatiser les réglages Windows post-installation.
- Automatiser l'installation et la mise à jour des applications.
- Utiliser en priorité les installateurs conservés localement.
- Maintenir automatiquement à jour le dépôt d'installation présent sur la clé USB.
- Permettre plusieurs exécutions sans effets de bord inutiles.
- Continuer le déploiement lorsque l'échec d'un script n'est pas critique.
- Produire un fichier de log indépendant pour chaque script.
- Préparer les paramètres par défaut des futurs profils utilisateurs.

---

## 2\. Principes techniques retenus

### Scripts PowerShell

- Compatibilité Windows PowerShell 5.1.
- Scripts modulaires et indépendants.
- Scripts relançables autant que possible.

#### Module centralisé : CGLOBAL.Common.psm1

Un module PowerShell partagé centralise les fonctionnalités communes :

- **`Get-CGlobalLogFile`** : génère automatiquement le chemin du fichier log en fonction du nom du script courant ;
- **`Initialize-CGlobalLog`** : initialise la journalisation (crée dossiers et fichier log si nécessaire) ;
- **`Write-Log`** : enregistre les messages de log avec timestamp, niveau et couleur console ;
- **`Show-CGlobalPopup`** : affiche une popup graphique pour les interactions utilisateur ;
- **`Show-CGlobalInputBox`** : affiche une boîte de dialogue de saisie texte (OK/Annuler), utilisée notamment pour la saisie d'un nouveau nom de poste.

#### En-tête standardisé des scripts actifs

Tous les scripts actifs utilisent le même en-tête :

```
#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile
```

Cet en-tête garantit :

- une génération automatique du chemin log (pas de redondance entre scripts) ;
- la disponibilité de `Write-Log` sans réimplémentation locale ;
- une cohérence sur la gestion des erreurs via `$ErrorActionPreference` ;
- une vérification automatique des prérequis (version PowerShell et droits administrateur).

#### Niveaux de log

La fonction `Write-Log` du module supporte les niveaux suivants :

- `INFO` : information générale (couleur cyan)
- `OK` : opération réussie (couleur verte)
- `WARN` : avertissement, opération partiellement réussie (couleur jaune)
- `ERROR` : erreur critique (couleur rouge)

Les erreurs non critiques doivent être journalisées en `WARN` sans interrompre le script. Les erreurs critiques peuvent retourner un code d'erreur, mais le batch principal poursuit l'exécution des scripts suivants.

#### Interactions utilisateur : popups graphiques

Depuis août 2026, les interactions avec l'utilisateur utilisent des popups graphiques via la fonction `Show-CGlobalPopup` du module `CGLOBAL.Common.psm1`, remplaçant les saisies console (`Read-Host`) et les messages `Write-Host`.

**Fonction `Show-CGlobalPopup` :**

- Paramètres : `-Message`, `-Title`, `-Buttons`, `-Icon`
- Boutons disponibles : `OK`, `OKCancel`, `YesNo`, `YesNoCancel`
- Icônes disponibles : `None`, `Question`, `Exclamation`, `Stop`, `Information`
- Retour : `[System.Windows.Forms.DialogResult]` (ex: `Yes`, `No`, `OK`, `Cancel`)

**Scripts utilisant des popups :**

- Script 14 : Confirmation de désinstallation Office
- Script 16 : Contrôle Internet (via le batch)
- Script 17 : Confirmation de désinstallation OneDrive
- Script 90 : Confirmation + saisie du mot de passe (formulaire personnalisé)
- Script 99 : Confirmation de restauration des paramètres

**Avantages :**

- Interface plus professionnelle et lisible
- Cohérence entre tous les scripts
- Meilleure expérience utilisateur (boutons clairs, pas de saisie texte)
- Popups toujours au premier plan (`TopMost`)

### Encodage

Des problèmes d'affichage des caractères accentués ont été constatés dans la console et certains fichiers de log sous Windows PowerShell 5.1.

Décision actuelle :

- conserver les scripts fonctionnels en l'état ;
- utiliser si nécessaire des messages sans accents dans les scripts sensibles ;
- conserver `chcp 65001` dans le batch principal ;
- le module utilise `Add-Content -Encoding UTF8` pour les logs afin d'assurer une cohérence des encodages.

### Redémarrage d'Explorer

Décision retenue :

- ne pas redémarrer Explorer après chaque script de personnalisation ;
- le script 08 redémarre Explorer après désinstallation du package Widgets (nécessaire pour refléter la suppression) ;
- le script 09 redémarre Explorer après suppression du raccourci Microsoft Store ou modification du registre ;
- prévoir éventuellement un seul redémarrage d'Explorer en fin de séquence une fois tous les scripts d'interface validés.

---

## Glossaire

### UCPD

User Choice Protection Driver. Pilote de protection de la sélection utilisateur, connu pour bloquer certaines modifications du registre ou de l'interface de Windows 11, notamment sur des valeurs liées à la barre des tâches et aux widgets.

### WinGet

Outil de gestion des paquets Microsoft pour installer, mettre à jour et désinstaller des applications de manière standardisée à partir de manifests et de sources configurées.

### C2R

Click-to-Run. Modèle d'installation des applications Microsoft 365 / Office via le mécanisme C2R, souvent observé avec des installations OEM ou Microsoft 365.

### MSI

Windows Installer. Format d'installation Windows utilisé par de nombreuses applications, exploité via la commande `msiexec.exe`.

### HKCU / HKLM / HKU

Racines du registre Windows :

- `HKCU` : paramètres du compte utilisateur courant ;
- `HKLM` : paramètres système pour le poste ;
- `HKU` : profil utilisateur chargés / hives utilisateur.

### NTUSER.DAT

Fichier du profil utilisateur par défaut, utilisé comme modèle pour les futurs profils utilisateurs sur un poste Windows.

### HKEY_USERS.DEFAULT

Hive du profil par défaut dans le registre du système. À distinguer du fichier `C:\Users\Default\NTUSER.DAT` utilisé pour les nouveaux profils.

### TeamViewer QS

TeamViewer QuickSupport. Version légère de TeamViewer destinée au support client et au téléchargement depuis une URL dynamique de configuration CGLOBAL.

### Robocopy

Outil de synchronisation de fichiers intégré à Windows, utilisé pour recopier et maintenir le dépôt `_CGLOBAL` depuis la clé USB vers le poste cible.

### Log / journalisation

Fichier de trace produit par chaque script, stocké dans `C:\_CGLOBAL\Logs\` avec un nom dérivé automatiquement du nom du script (ex. : `Log01_Bureau.txt` pour le script `01_Bureau.ps1`). Les opérations, avertissements et erreurs y sont enregistrées dans un journal distinct par script via la fonction `Write-Log` du module centralisé.

### Profil par défaut

Modèle de configuration utilisé pour les futurs profils créés sur le poste. Les paramètres appliqués ici doivent être conservés sans dépendre de l'état d'un profil existant.

---

## 3\. Arborescence du kit

### Sur la clé USB

```
X:\
└── _CGLOBAL
    ├── PS1
    ├── installers
    └── autres fichiers du kit
```

Le fichier `Run_Install.cmd` est lancé depuis la clé USB et détecte automatiquement son propre emplacement.

### Sur le poste cible

```
C:\_CGLOBAL
├── Logs
├── PS1
├── installers
```

Le dossier `Temp` peut être créé temporairement par certains scripts, puis supprimé lorsqu'il est vide.

---

## 4\. Mode sélectif : Run_Selective.cmd + Run_Selective.ps1

### Objectif

Permettre de choisir manuellement les scripts à exécuter, plutôt que de lancer la séquence complète automatiquement.

### Fichiers

- `Run_Selective.cmd` : batch d'entrée (vérifie les droits admin, synchronise la clé USB, lance le PS1)
- `Run_Selective.ps1` : interface graphique PowerShell (formulaire Windows Forms avec cases à cocher)

### Interface

- Liste des scripts dans l'ordre de numérotation, avec description
- Cases à cocher individuelles pour chaque script
- Scripts nécessitant Internet (15, 16, 19) affichés en **orange**
- Bouton **"Tous"** : coche tous les scripts
- Bouton **"Aucun"** : décoche tous les scripts
- Bouton **"Exécuter"** : lance les scripts cochés dans l'ordre
- Barre de progression pendant l'exécution

### Logique d'exécution

1. Vérification qu'au moins un script est coché
   - Si aucun : popup "Attention, aucun script coché" avec choix **Revenir** (retour à la sélection) ou **Quitter** (fermeture)
2. Si un script Internet est coché : test de connexion Internet (même logique que `Run_Install.cmd`)
3. Exécution séquentielle des scripts cochés, dans l'ordre de numérotation
4. Chaque script est lancé via `powershell.exe -ExecutionPolicy Bypass -File`
5. Log global dans `C:\_CGLOBAL\Logs\LogRun_Selective.txt`

### Fonctionnalites

- **Info-bulles (ToolTips)** : survoler un script affiche sa description complete
- **Resultat visuel** : couleur de fond des cases apres execution
  - 🟢 Vert = succes (exit code 0)
  - 🟡 Jaune = avertissement (exit code != 0)
  - 🔴 Rouge = erreur ou script introuvable
- **Memorisation** : sauvegarde dans `C:\_CGLOBAL\Run_Selective.sel` (format texte simple `Num=0/1`, pas de JSON)
  - Chargement automatique au demarrage
  - Bouton **Sauvegarder** pour sauvegarder manuellement
  - Bouton **Charger** pour restaurer une selection
  - Sauvegarde automatique a la fermeture
- **Test Internet** : identique a `Run_Install.cmd` (`Test-NetConnection` sur download.microsoft.com et get.teamviewer.com)

### Cas d'usage

- Tester un script isolé sans relancer toute la séquence
- Relancer un script qui a echoue lors d'un deploiement precedent
- Deboguer un nouveau script en phase de developpement
- Personnaliser le deploiement selon le contexte client

**Lancement :** `Run_Selective.cmd` se lance minimisé (`start /min`) dès le début pour ne pas occuper l'écran. Seule la fenêtre graphique PowerShell est visible.

**Fenêtre déplaçable pendant l'exécution :** La boucle d'attente des scripts appelle `[System.Windows.Forms.Application]::DoEvents()` toutes les 200 ms, ce qui maintient la fenêtre réactive et déplaçable même pendant l'exécution d'un script long.

**État :** ✅ VALIDÉ

---

## 5\. Ordre des scripts

### Ordre cible des scripts

```
00_ModeDeploiement.ps1

01_Bureau.ps1
02_MenuContextuelClassique.ps1
03_Explorateur.ps1
04_ZoneNotification.ps1
05_BarreTachesGauche.ps1
06_RechercheBarreTaches.ps1
07_MasquerVueTaches.ps1
08_MasquerWidgets.ps1
09_MSStoreBarreTache.ps1

10_DesactiverReprendre.ps1

11_ConfidentialiteLocalisation.ps1

12_ConfigurerProfilParDefaut.ps1
13_NumLockDemarrage.ps1
14_DesinstallationOffice.ps1

[contrôle Internet] ← Popup graphique via Show-CGlobalPopup

15_ApplicationsWinget.ps1
16_TeamViewerQS.ps1
17_DesinstallationOneDrive.ps1
18_AssociationsFichiers.ps1  [SUSPENDU]
19_MisesAJourConstructeur.ps1

85_RenommagePoste.ps1

90_VerificationMotDePasseCompteLocal.ps1

99_FinDeploiement.ps1
```

Le script 90 reste volontairement le dernier script fonctionnel avant le script 99 de fin de déploiement, afin de ne pas imposer la saisie d'un mot de passe entre plusieurs redémarrages et relances du batch pendant la préparation du poste.

---

## Tableau récapitulatif des scripts

| Script | Fichier | Objectif principal | État | Commentaire |
| --- | --- | --- | --- | --- |
| 00 | `00_ModeDeploiement.ps1` | Préparer le poste avant le déploiement | ✅ VALIDÉ | Paramétrage énergie / Windows Update |
| 01 | `01_Bureau.ps1` | Affichage des icônes système sur le bureau | ✅ VALIDÉ | Reste limité sur la position exacte |
| 02 | `02_MenuContextuelClassique.ps1` | Restauration du menu contextuel classique | ✅ VALIDÉ POUR L'UTILISATEUR COURANT | Non hérité dans le profil par défaut |
| 03 | `03_Explorateur.ps1` | Ouvrir l'Explorateur sur Ce PC / extensions visibles | ✅ VALIDÉ | Paramètres Explorer validés |
| 04 | `04_ZoneNotification.ps1` | Affichage des icônes déjà connues dans la zone de notification | ✅ VALIDÉ | Les nouvelles icônes restent gérées manuellement |
| 05 | `05_BarreTachesGauche.ps1` | Alignement de la barre des tâches à gauche | ✅ VALIDÉ | Option de suppression de Store non implémentée |
| 06 | `06_RechercheBarreTaches.ps1` | Affichage uniquement de l'icône recherche | ✅ VALIDÉ | Concerne l'interface de recherche |
| 07 | `07_MasquerVueTaches.ps1` | Masquage du bouton Vue des tâches | ✅ VALIDÉ | Valeur enregistrée dans le registre |
| 08 | `08_MasquerWidgets.ps1` | Désinstallation complète du package Widgets | À VALIDER | Suppression AppxPackage + provisioning + restart Explorer |
| 09 | `09_MSStoreBarreTache.ps1` | Supprimer Microsoft Store de la barre des tâches | À VALIDER | Suppression .lnk + registre HKCU/HKLM + restart Explorer |
| 10 | `10_DesactiverReprendre.ps1` | Désactivation de l'option Reprendre | ✅ VALIDÉ | Vérifié sur Windows 11 25H2 |
| 11 | `11_ConfidentialiteLocalisation.ps1` | Paramètres de confidentialité / localisation | ✅ VALIDÉ | Gère le cas clé absente |
| 12 | `12_ConfigurerProfilParDefaut.ps1` | Configuration des futurs profils utilisateurs | ✅ VALIDÉ | Menu contextuel classique corrigé (Set-ItemProperty) |
| 13 | `13_NumLockDemarrage.ps1` | Forcer NumLock au démarrage | FIGÉ / COMPORTEMENT ACCEPTÉ | Comportement variable selon le poste |
| 14 | `14_DesinstallationOffice.ps1` | Détection et désinstallation d'Office / OneNote | ✅ VALIDÉ | Popup confirmation + gestion MSI/C2R + OneNote |
| 15 | `15_ApplicationsWinget.ps1` | Installation et mise à jour des applications via WinGet | ✅ VALIDÉ | Gestion du cache local et synchronisation |
| 16 | `16_TeamViewerQS.ps1` | Téléchargement et mise à jour de TeamViewer QS | ✅ VALIDÉ | API TeamViewer + téléchargement direct |
| 17 | `17_DesinstallationOneDrive.ps1` | Détection et désinstallation de OneDrive | ✅ VALIDÉ | UninstallString + AppX provisionné + gestion erreurs gracieuse |
| 18 | `18_AssociationsFichiers.ps1` | Associations de fichiers par défaut | ⛔ SUSPENDU | Algorithme UserChoice obsolète sur Windows 11 24H2/25H2 ; méthodes DISM et ProgID insuffisantes pour l'utilisateur courant. À réétudier avec SetUserFTA ou une approche GPO/MDM. |
| 19 | `19_MisesAJourConstructeur.ps1` | Mises à jour pilotes, BIOS, firmwares et applications constructeur | À VALIDER | Lenovo et Dell pris en charge ; popup pour autoriser ou empêcher le redémarrage constructeur |
| 85 | `85_RenommagePoste.ps1` | Renommer le poste après vérification de compatibilité | À VALIDER | Popup Oui/Non/Annuler puis saisie avec contrôle lettre/chiffre/trait d'union, boucle de ressaisie, warning redémarrage |
| 90 | `90_VerificationMotDePasseCompteLocal.ps1` | Vérifier un mot de passe local | ✅ VALIDÉ | API Windows LogonUser — détection fiable du mot de passe vide |
| 99 | `99_FinDeploiement.ps1` | Restauration du mode déploiement | ✅ VALIDÉ | Popup confirmation + restauration paramètres |

> Le tableau ci-dessus synthétise l'état actuel des scripts du dépôt.

---

## 6\. État détaillé des scripts

### Script 00 : Mode déploiement

**Nom :** `00_ModeDeploiement.ps1`

**Fonction :** Préparer le poste avant le lancement du déploiement afin d'éviter :

- la mise en veille ;
- l'extinction automatique de l'écran ;
- les redémarrages automatiques provoqués par Windows Update.

**État :** ✅ VALIDÉ

---

### Script 01 : Bureau

**Nom :** `01_Bureau.ps1`

**Fonction :** Affiche les icônes système souhaitées sur le Bureau : Ce PC, dossier utilisateur, Réseau, Corbeille, Panneau de configuration.

**État :** ✅ VALIDÉ

---

### Script 02 : Menu contextuel classique

**Nom :** `02_MenuContextuelClassique.ps1`

**Fonction :** Restaure le menu contextuel classique de Windows 11.

**État :** ✅ VALIDÉ POUR L'UTILISATEUR COURANT

---

### Script 03 : Explorateur

**Nom :** `03_Explorateur.ps1`

**Fonction :** Ouvre l'Explorateur sur Ce PC et affiche les extensions de fichiers connues.

**État :** ✅ VALIDÉ

---

### Script 04 : Zone de notification

**Nom :** `04_ZoneNotification.ps1`

**Fonction :** Affiche dans la zone de notification toutes les icônes déjà connues par le profil.

**État :** ✅ VALIDÉ

---

### Script 05 : Barre des tâches à gauche

**Nom :** `05_BarreTachesGauche.ps1`

**Fonction :** Aligne les icônes de la barre des tâches à gauche.

**État :** ✅ VALIDÉ

---

### Script 06 : Recherche

**Nom :** `06_RechercheBarreTaches.ps1`

**Fonction :** Affiche uniquement l'icône de recherche.

**État :** ✅ VALIDÉ

---

### Script 07 : Vue des tâches

**Nom :** `07_MasquerVueTaches.ps1`

**Fonction :** Masque le bouton Vue des tâches.

**État :** ✅ VALIDÉ

---

### Script 08 : Widgets

**Nom :** `08_MasquerWidgets.ps1`

**Fonction :** Désinstalle complètement le package Windows Web Experience Pack (Widgets) pour tous les utilisateurs existants et supprime le provisioning pour les futurs utilisateurs.

**Procédure :**

1. Arrêt des processus Widgets
2. Détection du package `*WebExperience*` (utilisateurs + provisionné)
3. Désinstallation via `Remove-AppxPackage -AllUsers`
4. Suppression du provisioning via `Remove-AppxProvisionedPackage -Online`
5. Redémarrage de l'Explorateur

**État :** À VALIDER

---

### Script 09 : Supprimer Microsoft Store de la barre des tâches

**Nom :** `09_MSStoreBarreTache.ps1`

**Fonction :** Supprime l'épingle Microsoft Store de la barre des tâches pour l'utilisateur courant et bloque son retour.

**Procédure :**

1. **Suppression physique du raccourci `.lnk`** dans `%APPDATA%\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar` — recherche précise sur le nom "Microsoft Store"
2. **Fallback COM** si le `.lnk` n'est pas trouvé (désépinglage via `Shell.Application`)
3. **Registre** `NoPinningStoreToTaskbar` en `HKCU` et `HKLM` pour bloquer l'épinglage futur
4. **Redémarrage d'Explorer** si une modification a été apportée (suppression `.lnk` OU modification registre)

**Corrections appliquées (août 2026) :**

- Suppression du `LayoutModification.xml` qui en mode `Replace` supprimait toutes les épingles par défaut (Edge, Explorer) pour les futurs utilisateurs
- Le redémarrage d'Explorer est désormais déclenché aussi en cas de modification du registre (pas seulement suppression de `.lnk`)
- Recherche du `.lnk` affinée pour éviter les faux positifs (`Microsoft Store` au lieu de `Store` seul)

**État :** À VALIDER

---

### Script 10 : Reprendre

**Nom :** `10_DesactiverReprendre.ps1`

**Fonction :** Désactive l'option Reprendre.

**État :** ✅ VALIDÉ

---

### Script 11 : Confidentialité et localisation

**Nom :** `11_ConfidentialiteLocalisation.ps1`

**Fonction :** Désactive les notifications de localisation et le remplacement de localisation.

**État :** ✅ VALIDÉ

---

### Script 12 : Profil utilisateur par défaut

**Nom :** `12_ConfigurerProfilParDefaut.ps1`

**Fonction :** Configure les réglages initiaux des futurs utilisateurs en modifiant `C:\Users\Default\NTUSER.DAT`.

**Procédure :**

1. Chargement de `NTUSER.DAT` via `reg.exe LOAD`
2. Application des réglages dans la ruche temporaire :
   - Icônes Bureau (Ce PC, Panneau de configuration, Corbeille, Réseau)
   - Menu contextuel classique
   - Explorateur sur Ce PC + extensions visibles
   - Barre des tâches à gauche
   - Recherche en mode icône
   - Vue des tâches masquée
   - Reprendre désactivé
   - Confidentialité localisation
   - NumLock au démarrage
3. Déchargement propre de la ruche

**Correction appliquée (août 2026) :**

- **Problème :** Le menu contextuel classique n'était pas hérité par les futurs utilisateurs. La fonction `Set-DefaultUserString` utilisait `New-ItemProperty` qui crée une valeur **nommée** `(Default)` au lieu de modifier la **valeur par défaut** native de la clé.
- **Correction :** Remplacement de `New-ItemProperty` par `Set-ItemProperty` dans `Set-DefaultUserString` (et `Set-DefaultUserDWord` pour cohérence). `Set-ItemProperty` interprète correctement `(Default)` comme la valeur par défaut de la clé.

**État :** ✅ VALIDÉ

---

### Script 13 : NumLock

**Nom :** `13_NumLockDemarrage.ps1`

**Fonction :** Configure NumLock au démarrage.

**État :** FIGÉ / COMPORTEMENT ACCEPTÉ

---

### Script 14 : Désinstallation Office / OneNote

**Nom :** `14_DesinstallationOffice.ps1`

**Fonction :** Détecte et propose la désinstallation de toutes les versions Office et OneNote présentes (C2R, MSI, OEM).

**Procédure :**

1. Recherche dans les clés de registre Uninstall (HKLM, HKCU, HKU)
2. Détection des produits : Microsoft Office, 365, Project, Visio, **OneNote**
3. Exclusion des mises à jour, MUI, redistribuables, runtime, licensing, proofing, help, language packs
4. Déduplication des entrées 32/64 bits
5. Popup de confirmation avec la liste des produits détectés
6. Désinstallation via `UninstallString` (C2R ou MSI)

**Interaction utilisateur :**

- Popup de confirmation : "Voulez-vous desinstaller TOUTES ces versions d'Office / OneNote ?"
- Boutons : Oui / Non
- Si Non : journalisation WARN et sortie sans action

**Modification appliquée (août 2026) :**

- Ajout de **OneNote** dans la détection (FR-FR, EN-US, etc.)
- Le regex `DisplayName` inclut désormais `Microsoft OneNote`
- Exclusion élargie pour éviter les faux positifs (Proofing, Help, Language, Font, Theme, Visual Studio)

**État :** ✅ VALIDÉ

---

### Script 15 : Applications WinGet

**Nom :** `15_ApplicationsWinget.ps1`

**Fonction :** Installation et mise à jour des applications via WinGet depuis cache local : 7-Zip, Adobe Acrobat Reader 64 bits, Google Chrome, Mozilla Firefox.

**État :** ✅ VALIDÉ

---

### Script 16 : TeamViewer QuickSupport

**Nom :** `16_TeamViewerQS.ps1`

**Fonction :** Téléchargement et mise à jour de TeamViewer QS via l'API TeamViewer.

**Procédure :**

1. Appel API TeamViewer pour obtenir l'URL de téléchargement
2. Téléchargement direct vers `C:\_CGLOBAL\TeamViewerQS.exe`
3. Vérification de la signature numérique
4. Création du raccourci "Assistance CGLOBAL" sur le Bureau public

**État :** ✅ VALIDÉ

---

### Script 17 : Désinstallation OneDrive

**Nom :** `17_DesinstallationOneDrive.ps1`

**Fonction :** Détecte et propose la désinstallation complète de OneDrive, avec blocage pour les futurs profils utilisateurs.

**Procédure :**

01. Détection multi-couches :
    - Package AppX utilisateur (`Get-AppxPackage`)
    - Package AppX provisionné (`Get-AppxProvisionedPackage`)
    - Exécutable (`OneDrive.exe`)
    - Registre (Programmes et fonctionnalités)
    - Dossiers d'installation
02. Popup de confirmation : "OneDrive est installe sur ce poste. Voulez-vous le desinstaller ?"
03. Arrêt des processus OneDrive
04. Désinstallation via registre (`UninstallString`) en premier — méthode la plus propre
05. Si échec ou fichier introuvable : fallback sur `OneDrive.exe /uninstall`
06. Suppression de la clé de registre Uninstall :
    - Si présente → suppression manuelle
    - Si déjà absente (supprimée par le désinstalleur) → log OK
07. Désinstallation AppX :
    - Package utilisateur via `Remove-AppxPackage`
    - Package provisionné via `Remove-AppxProvisionedPackage`
    - Erreur `0x80073CF1` (package introuvable) gérée gracieusement
08. Nettoyage des dossiers résiduels
09. Blocage pour les futurs profils :
    - `HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive\DisableFileSyncNGSC = 1`
    - Application au profil par défaut via montage `NTUSER.DAT` (`reg.exe LOAD/ADD/UNLOAD`)
10. Suppression des raccourcis (Menu Démarrer, Bureau public)
11. Popup de confirmation finale

**Corrections appliquées (août 2026) :**

- **Ordre d'exécution inversé :** le `UninstallString` du registre est exécuté AVANT `OneDrive.exe /uninstall`.
- **Parsing du UninstallString corrigé :** gestion robuste des guillemets.
- **Suppression de la clé Uninstall :** gère le cas où OneDriveSetup.exe a déjà supprimé la clé.
- **AppX provisionné :** détection et suppression via `Remove-AppxProvisionedPackage` en plus de `Remove-AppxPackage`.
- **Erreur 0x80073CF1 :** gérée gracieusement (package déjà supprimé ou non installé pour l'utilisateur).

**État :** ✅ VALIDÉ

---

### Script 18 : Associations de fichiers par défaut

**Nom :** `18_AssociationsFichiers.ps1`

**Fonction :** Définit les applications par défaut pour les fichiers PDF (Adobe Reader) et les archives (7-Zip), pour l'utilisateur courant **et** les futurs utilisateurs.

**Position :** À exécuter **après** le script 15 (`15_ApplicationsWinget.ps1`) car il dépend de la présence d'Adobe Reader et 7-Zip.

**Procédure :**

1. **Détection d'Adobe Reader** : recherche dans `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\` (Acrobat.exe / AcroRd32.exe) + fallback chemins directs
2. **Détection de 7-Zip** : recherche dans `App Paths\7zFM.exe` + fallback chemins directs
3. **Récupération du ProgID PDF** : lecture dans `HKEY_CLASSES_ROOT\.pdf\OpenWithProgids` ou `HKCU\Software\Classes\.pdf\OpenWithProgids`
4. **Création des ProgID 7-Zip** : `7-Zip.zip`, `7-Zip.7z`, etc. dans `HKEY_CLASSES_ROOT` avec commande d'ouverture, icône et description
5. **Génération du XML DefaultAppAssociations** : fichier temporaire listant toutes les associations
6. **Import via DISM** : `dism.exe /online /Import-DefaultAppAssociations:"fichier.xml"` — méthode officielle Microsoft, appliquée au niveau machine
7. **Nettoyage silencieux de UserChoice** : suppression des clés `UserChoice` pour l'utilisateur courant (erreurs ignorées)
8. **Redémarrage d'Explorer**

**Méthode DISM :**

Depuis Windows 10 1903, Microsoft a verrouillé `UserChoice` avec un hash anti-détournement. La seule méthode officielle et supportée pour forcer une association est l'import XML via DISM (`Import-DefaultAppAssociations`). Cette méthode s'applique de façon garantie aux **nouveaux profils** et fonctionne souvent sur le profil courant après un redémarrage complet.

**Problème identifié (septembre 2026) :**

L'algorithme de hash `UserChoice` utilisé dans le script (issu du projet PS-SFTA de 2022) n'est plus reconnu comme valide par Windows 11 24H2/25H2. Windows ignore silencieusement la clé `UserChoice` si le hash ne correspond pas à sa version interne actuelle. Les symptômes observés :
- Le script affiche « OK (vérifié) » car il vérifie seulement l'écriture dans le registre, pas l'acceptation par Windows.
- Les fichiers `.zip` restent associés à l'Explorateur.
- L'interface Options de 7-Zip ne voit aucune association.

**Suspension :**

Le script 18 est **suspendu** en attendant une solution viable (SetUserFTA, approche GPO/MDM, ou nouvelle méthode Microsoft). Il ne doit pas être exécuté en production.

**État :** ⛔ SUSPENDU

---

### Script 19 : Mises à jour constructeur

**Nom :** `19_MisesAJourConstructeur.ps1`

**Fonction :** Détecte le constructeur du poste et pilote les outils officiels de mise à jour pour installer les pilotes, applications, BIOS et firmwares disponibles.

**Position :** Après le script 18 et avant le script 90. Le script nécessite Internet et doit être déclaré avec `Net=$true` dans `Run_Selective.ps1`.

**Constructeurs :**
- **Lenovo** : vérification ou installation de Lenovo Commercial Vantage depuis le Microsoft Store, puis de Lenovo System Update ;
- **Dell** : vérification ou installation de Dell Command Update via WinGet ;
- **HP** : détecté et journalisé, mais HP Image Assistant n'est pas encore automatisé ;
- **ASUS** : détecté et journalisé, mais l'automatisation de MyASUS n'est pas implémentée ;
- **autre constructeur** : aucune action, log `WARN` et sortie normale.

**Popup de choix sur Lenovo et Dell :**
- **Oui** : autorise toutes les mises à jour, BIOS et firmwares inclus, ainsi que le redémarrage constructeur si nécessaire. Le poste peut redémarrer avant la fin de CGLOBAL ;
- **Non** : installe les mises à jour sans redémarrage forcé pendant la séquence CGLOBAL ;
- **Annuler** : ignore uniquement le script 19, retourne `0` et laisse `Run_Selective.ps1` poursuivre les scripts suivants.

**Lenovo :**
- détection AppX de Lenovo Vantage ou Lenovo Commercial Vantage ;
- installation Microsoft Store avec l'identifiant `9NR5B8GVVM13` si nécessaire ;
- installation de `Lenovo.SystemUpdate` via WinGet si `tvsu.exe` est absent ;
- configuration de `AdminCommandLine` dans les stratégies Lenovo 32 et 64 bits ;
- désactivation de la planification automatique (`SchedulerAbility = NO`) ;
- mode complet : types de redémarrage `1,3,4,5` ;
- mode sans redémarrage forcé : types `1,3` avec `-noreboot`, types `4,5` exclus.

**Dell :**
- détection de `dcu-cli.exe` sous Program Files 64 ou 32 bits ;
- installation de `Dell.CommandUpdate` via WinGet si nécessaire ;
- catégories traitées : BIOS, firmware, pilote, application et autres ;
- mode complet : `-reboot=enable` ;
- mode sans redémarrage forcé : `-reboot=disable` ;
- journal Dell : `C:\_CGLOBAL\Logs\DellCommandUpdate.log`.

**Journal principal :** `C:\_CGLOBAL\Logs\Log19_MisesAJourConstructeur.txt`

**Codes retour :**
- `0` : réussite, annulation utilisateur ou constructeur non pris en charge ;
- `1` : erreur empêchant le traitement d'un constructeur reconnu.

**État :** À VALIDER sur postes Lenovo et Dell, notamment pour les mises à jour BIOS/firmware et les codes retour constructeurs.

---

### Script 85 : Renommage du poste

**Nom :** `85_RenommagePoste.ps1`

**Fonction :** Affiche le nom actuel du poste, propose de le modifier, vérifie la compatibilité du nouveau nom avec les règles Windows/NetBIOS, puis effectue le renommage si le nom est valide.

**Position :** Après le script 19 et avant le script 90. Le script ne nécessite pas Internet (`Net=$false`).

**Déroulement :**
1. Popup **Oui/Non/Annuler** affichant le nom actuel et demandant s'il faut le modifier.
   - **Non** ou **Annuler** : le script se termine normalement (`0`), sans aucune action.
2. Si **Oui** : saisie du nouveau nom via `Show-CGlobalInputBox` (champ pré-rempli avec le nom actuel rappelé dans le message).
   - Si l'utilisateur clique sur **Annuler** dans la saisie : fin normale du script (`0`).
   - Si le nom saisi est identique au nom actuel (insensible à la casse) : popup d'information, aucune action, fin normale (`0`).
3. **Contrôle de compatibilité** du nom saisi :
   - lettres, chiffres et trait d'union uniquement (`^[A-Za-z0-9-]+$`) ;
   - pas de trait d'union en première ou dernière position ;
   - pas un nom composé uniquement de chiffres ;
   - longueur maximale de 15 caractères (limite historique NetBIOS toujours appliquée par Windows).
   - Si le nom est invalide : popup **OK/Annuler** avec le motif du refus — **OK** relance une nouvelle saisie, **Annuler** abandonne (`0`).
4. **Renommage** via `Rename-Computer -NewName ... -Force`, sans l'option `-Restart` (le redémarrage n'est jamais déclenché automatiquement par CGLOBAL).
   - En cas d'échec (nom déjà pris sur le domaine, etc.) : popup **OK/Annuler** — **OK** relance une nouvelle saisie, **Annuler** abandonne.
5. En cas de succès : popup d'avertissement indiquant que le redémarrage est **obligatoire** pour que le nouveau nom soit pris en compte, puis fin normale (`0`).

**Nouvelle fonction commune :** `Show-CGlobalInputBox` a été ajoutée à `CGLOBAL.Common.psm1` pour la saisie de texte (boîte de dialogue WinForms avec boutons OK/Annuler ; retourne `$null` en cas d'annulation, ce qui lève toute ambiguïté avec une saisie vide validée par OK).

**Journal principal :** `C:\_CGLOBAL\Logs\Log85_RenommagePoste.txt`

**Codes retour :**
- `0` : réussite, refus de l'utilisateur ou abandon volontaire à n'importe quelle étape ;
- `1` : erreur inattendue (module introuvable, exception non gérée).

**État :** À VALIDER — le script n'a pas encore été testé sur un poste réel (comportement de `Rename-Computer` en environnement domaine/AD notamment).

---

### Script 90 : Vérification du mot de passe local

**Nom :** `90_VerificationMotDePasseCompteLocal.ps1`

**Fonction :** Vérifie si le compte local courant possède un mot de passe et propose d'en définir un.

**Contexte :** Le poste est configuré avec un compte local (poste neuf ou réinstallé).

**Procédure :**

1. Vérification du mot de passe via l'API Windows `LogonUser` (advapi32) avec un mot de passe vide :
   - Authentification réussie → mot de passe vide (popup de saisie)
   - Échec avec `ERROR_LOGON_FAILURE` (1326) → mot de passe non vide (sortie)
2. Si mot de passe vide : popup de confirmation "Le compte local n'a pas de mot de passe. Souhaitez-vous definir un mot de passe ?"
3. Si Oui : formulaire de saisie avec 2 champs masqués (mot de passe + confirmation)
4. Validation : les 2 mots de passe doivent correspondre
5. Application : `Set-LocalUser -Password`

**Historique des corrections :**

- **Problème initial :** `PasswordRequired` utilisé seul retournait `$false` pour les comptes Microsoft/EntraID même avec un mot de passe défini → popup intempestif.
- **Correction 1 :** Ajout de `PasswordLastSet` comme méthode de secours.
- **Correction 2 :** `PasswordLastSet` garde la date même si le MDP est supprimé → faux négatif.
- **Correction 3 :** `net user` retournait "Mot de passe requis Non" même avec MDP défini sur certains comptes locaux Windows 11.
- **Correction finale (août 2026) :** Utilisation de l'API Windows `LogonUser` (advapi32) avec un mot de passe vide comme méthode principale. C'est une API Windows native qui teste directement l'authentification. `net user` et `Get-LocalUser` sont conservés comme fallbacks historiques.
- **Correction boucle MDP vide (août 2026) :** La vérification du mot de passe vide était placée après la boucle `do…while` avec un `exit 0` brutal. Elle est désormais à l'intérieur de la boucle avec un `continue`, permettant à l'utilisateur de ressaisir un mot de passe valide au lieu de devoir relancer le script.

**État :** ✅ VALIDÉ

---

### Script 99 : Fin de déploiement

**Nom :** `99_FinDeploiement.ps1`

**Fonction :** Permet à l'opérateur de restaurer ou non les paramètres modifiés par le script 00.

**Interaction utilisateur :**

- Popup d'information : liste des paramètres actifs (veille, écran, Windows Update)
- Popup de confirmation : "Restaurer les parametres standards CGLOBAL ?"
- Boutons : Oui / Non
- Si Oui : restauration via `powercfg.exe` et suppression clé Windows Update
- Popup de confirmation finale : "Parametres standards CGLOBAL appliques avec succes."

**État :** ✅ VALIDÉ

---

## 7\. Particularités Windows 11 25H2 observées

- **UCPD :** Le pilote User Choice Protection Driver peut bloquer l'écriture de certaines valeurs (ex. : `TaskbarDa` pour le bouton Widgets). Le script 08 contourne ce problème en désinstallant complètement le package plutôt qu'en tentant une modification registre.
- **Profil par défaut :** Toutes les valeurs du script 12 sont héritées correctement, y compris le menu contextuel classique (corrigé via `Set-ItemProperty`). Le script 17 applique également le blocage OneDrive au profil par défaut via montage `NTUSER.DAT`.
- **NumLock :** La valeur HKCU peut être réinitialisée au premier logon sur certains postes.
- **Différences de mise à jour :** Deux postes Windows 11 25H2 peuvent présenter des clés différentes selon les mises à jour installées.
- **Barre des tâches Windows 11 :** Les épingles ne sont plus gérées de la même manière que sous Windows 10. La méthode COM (`Shell.Application`) est fragile pour les applications modernes (UWP). La suppression du fichier `.lnk` dans `User Pinned\TaskBar` + redémarrage d'Explorer est plus fiable (script 09).

---

## 8\. Décisions validées

- Les scripts PowerShell sont stockés dans `_CGLOBAL\PS1`.
- Les logs sont stockés dans `C:\_CGLOBAL\Logs`.
- Les anciens logs sont supprimés à chaque lancement du batch.
- La génération automatique des chemins de log est centralisée dans le module `CGLOBAL.Common.psm1`.
- Chaque script actif utilise `Get-CGlobalLogFile` pour obtenir son chemin de log automatiquement.
- Aucune redondance de déclaration de `$LogFile` n'existe entre les scripts.
- Tous les scripts actifs utilisent le même en-tête standardisé avec appel au module commun.
- Les interactions utilisateur utilisent des popups graphiques via `Show-CGlobalPopup`.
- Le mode sélectif utilise un test de connexion Internet avant de lancer les scripts nécessitant le réseau.
- Le script 90 utilise un formulaire Windows personnalisé pour la saisie du mot de passe.
- Toutes les popups sont configurées avec `TopMost` pour rester au premier plan.
- Le script 90 est renommé et positionné en fin de séquence (avant le 99) pour éviter d'imposer la saisie d'un mot de passe entre plusieurs redémarrages.
- Le script 90 utilise l'API Windows `LogonUser` (advapi32) avec un mot de passe vide comme méthode principale pour détecter l'état actuel du mot de passe. Si l'authentification réussit, le mot de passe est vide. Si elle échoue avec `ERROR_LOGON_FAILURE` (1326), le mot de passe est non vide.
- Le script 08 contourne le blocage UCPD en désinstallant le package Widgets plutôt qu'en modifiant le registre.
- Le script 09 supprime uniquement le raccourci `.lnk` du Store (recherche précise sur "Microsoft Store") et redémarre Explorer si une modification est apportée (suppression `.lnk` OU modification registre). Le `LayoutModification.xml` a été supprimé car il supprimait toutes les épingles par défaut (Edge, Explorer) en mode `Replace`.
- Le script 17 exécute le `UninstallString` du registre en premier (méthode propre), avec fallback sur `OneDrive.exe /uninstall`. La clé de registre Uninstall est supprimée si elle existe encore, ou considérée comme déjà nettoyée si absente. Les packages AppX provisionnés sont également supprimés via `Remove-AppxProvisionedPackage`.
- Le script 12 utilise `Set-ItemProperty` au lieu de `New-ItemProperty` pour modifier la valeur `(Default)` du registre dans le profil par défaut, car `New-ItemProperty` crée une valeur nommée au lieu de modifier la valeur par défaut native.
- Le mode sélectif est le seul mode d'exécution retenu. `Run_Install.cmd` est abandonné au profit de `Run_Selective.cmd`.
- `Run_Selective.cmd` se lance minimisé (`start /min`) pour ne pas occuper l'écran pendant la synchronisation Robocopy.
- La fenêtre du mode sélectif (`Run_Selective.ps1`) reste déplaçable pendant l'exécution des scripts grâce à `[System.Windows.Forms.Application]::DoEvents()` appelé régulièrement dans la boucle d'attente des processus.
- **Le script 18 est suspendu** (septembre 2026) : l'algorithme UserChoice (PS-SFTA) n'est plus valide sur Windows 11 24H2/25H2. Le script ne doit pas être exécuté en production. Une solution alternative (SetUserFTA, GPO/MDM) est à l'étude.
- Le script 19 centralise les mises à jour constructeur. Lenovo et Dell sont pris en charge ; HP et ASUS restent détectés mais non automatisés.
- Le script 19 propose par popup toutes les mises à jour, les mises à jour sans redémarrage forcé, ou l'annulation du seul script 19 avec retour `0`.

---

## 9\. Points restant à traiter ou à valider

### Prioritaires

- Valider les scripts 08 et 09 sur les cas de déploiement réel.
- Valider le script 19 sur des postes Lenovo et Dell, avec et sans redémarrage constructeur autorisé.
- Trouver une solution viable pour les associations de fichiers (remplacement du script 18 suspendu).

### Reportés

- Intégrer HP Image Assistant au script 19.
- Réévaluer l’automatisation ASUS si une interface de commande officielle devient disponible.
- Désactivation complète des Widgets (au-delà de la suppression du package).
- Exécution automatique du script 02 au premier logon de chaque nouvel utilisateur (optionnel, le script 12 corrige maintenant le menu contextuel pour les futurs profils).
- Éventuel redémarrage unique d'Explorer après les scripts d'interface.
- Remplacer les `Read-Host` restants par des popups (si nécessaire).

---

## 10\. Démarrage d'un nouveau chat

Utiliser le message suivant :

```
Je poursuis le projet CGLOBAL de post-installation Windows 11 25H2.
Voici le fichier de référence du projet. Utilise-le comme contexte et tiens compte des scripts validés, des limitations connues et des décisions déjà prises.
```

Puis joindre ou coller ce fichier : `reference-projet.md`

Lorsqu'une nouvelle modification est validée, mettre à jour ce document afin qu'il reste la source de référence du projet.

```
