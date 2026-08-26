# Projet CGLOBAL

## Sommaire

- [1. Contexte général](#1-contexte-général)
- [2. Principes techniques retenus](#2-principes-techniques-retenus)
- [3. Arborescence du kit](#3-arborescence-du-kit)
- [4. Batch principal : Run_Install.cmd](#4-batch-principal--run_installcmd)
- [5. Ordre des scripts](#5-ordre-des-scripts)
- [Glossaire](#glossaire)
- [Tableau récapitulatif des scripts](#tableau-récapitulatif-des-scripts)
- [6. État détaillé des scripts](#6-état-détaillé-des-scripts)
- [7. Particularités Windows 11 25H2 observées](#7-particularités-windows-11-25h2-observées)
- [8. Décisions validées](#8-décisions-validées)
- [9. Points restant à traiter ou à valider](#9-points-restant-à-traiter-ou-à-valider)
- [10. Démarrage d'un nouveau chat](#10-démarrage-dun-nouveau-chat)

## 1. Contexte général

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

## 2. Principes techniques retenus

### Scripts PowerShell

- Compatibilité Windows PowerShell 5.1.
- Scripts modulaires et indépendants.
- Scripts relançables autant que possible.

#### Module centralisé : CGLOBAL.Common.psm1

Un module PowerShell partagé centralise les fonctionnalités communes :

- **`Get-CGlobalLogFile`** : génère automatiquement le chemin du fichier log en fonction du nom du script courant ;
- **`Initialize-CGlobalLog`** : initialise la journalisation (crée dossiers et fichier log si nécessaire) ;
- **`Write-Log`** : enregistre les messages de log avec timestamp, niveau et couleur console ;
- **`Show-CGlobalPopup`** : affiche une popup graphique pour les interactions utilisateur.

#### En-tête standardisé des scripts actifs

Tous les scripts actifs utilisent le même en-tête :

```powershell
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

### HKEY_USERS\.DEFAULT
Hive du profil par défaut dans le registre du système. À distinguer du fichier `C:\Users\Default\NTUSER.DAT` utilisé pour les nouveaux profils.

### TeamViewer QS
TeamViewer QuickSupport. Version légère de TeamViewer destinée au support client et au téléchargement depuis une URL dynamique de configuration CGLOBAL.

### Robocopy
Outil de synchronisation de fichiers intégré à Windows, utilisé pour recopier et maintenir le dépôt `_CGLOBAL` depuis la clé USB vers le poste cible.

### Log / journalisation
Fichier de trace produit par chaque script, stocké dans `C:\_CGLOBAL\Logs\` avec un nom dérivé automatiquement du nom du script (ex. : `Log01_Bureau.txt` pour le script `01_Bureau.ps1`). Les opérations, avertissements et erreurs y sont enregistrés dans un journal distinct par script via la fonction `Write-Log` du module centralisé.

### Profil par défaut
Modèle de configuration utilisé pour les futurs profils créés sur le poste. Les paramètres appliqués ici doivent être conservés sans dépendre de l'état d'un profil existant.

---

## 3. Arborescence du kit

### Sur la clé USB

```text
X:\
└── _CGLOBAL
    ├── PS1
    ├── installers
    └── autres fichiers du kit
```

Le fichier `Run_Install.cmd` est lancé depuis la clé USB et détecte automatiquement son propre emplacement.

### Sur le poste cible

```text
C:\_CGLOBAL
├── Logs
├── PS1
├── installers
```

Le dossier `Temp` peut être créé temporairement par certains scripts, puis supprimé lorsqu'il est vide.

---

## 4. Batch principal : Run_Install.cmd

### Fonctions principales

- Vérifie les droits administrateur.
- Se relance en administrateur si nécessaire.
- Détecte automatiquement le chemin de la clé USB.
- Synchronise `_CGLOBAL` vers `C:\_CGLOBAL` avec Robocopy.
- Supprime et recrée `C:\_CGLOBAL\Logs` à chaque lancement.
- Lance les scripts PowerShell stockés dans `C:\_CGLOBAL\PS1`.
- Utilise une sous-routine `:RunPS` afin d'éviter de répéter la logique d'appel.
- Si un script retourne une erreur, affiche un avertissement puis continue avec le script suivant.

### Principe de la sous-routine

```bat
call :RunPS "01_Bureau.ps1"
call :RunPS "02_MenuContextuelClassique.ps1"
```

La sous-routine appelle :

```bat
powershell.exe -ExecutionPolicy Bypass -File "C:\_CGLOBAL\PS1\%~1"
```

En cas d'échec :

```text
[WARN] Le script a retourné une erreur
```

Le déploiement continue.

### Contrôle Internet

Un contrôle Internet doit être effectué avant les scripts nécessitant un accès en ligne, notamment :
- WinGet ;
- TeamViewer QuickSupport.

**Statut :** ✅ VALIDÉ

**Implémentation :** Le batch utilise une popup graphique via `Show-CGlobalPopup` (module `CGLOBAL.Common.psm1`) pour demander à l'utilisateur de réessayer ou d'interrompre le déploiement.

**Comportement :**
1. Test automatique au lancement (download.microsoft.com + get.teamviewer.com)
2. Si échec : popup "Aucun acces Internet detecte. Winget et TeamViewer necessitent une connexion Internet. Voulez-vous reessayer ?"
3. Boutons : Oui (réessayer) / Non (interrompre)
4. Boucle jusqu'à succès ou interruption utilisateur

---

## 4b. Mode sélectif : Run_Selective.cmd + Run_Selective.ps1

### Objectif
Permettre de choisir manuellement les scripts à exécuter, plutôt que de lancer la séquence complète automatiquement.

### Fichiers
- `Run_Selective.cmd` : batch d'entrée (vérifie les droits admin, synchronise la clé USB, lance le PS1)
- `Run_Selective.ps1` : interface graphique PowerShell (formulaire Windows Forms avec cases à cocher)

### Interface
- Liste des 20 scripts dans l'ordre de numérotation, avec description
- Cases à cocher individuelles pour chaque script
- Scripts nécessitant Internet (15, 16) affichés en **orange**
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
- Relancer un script qui a échoue lors d'un deploiement precedent
- Deboguer un nouveau script en phase de developpement
- Personnaliser le deploiement selon le contexte client

**État :** ✅ VALIDÉ

---

## 5. Ordre des scripts

### Ordre cible des scripts

```text
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

90_VerificationMotDePasseCompteLocal.ps1

99_FinDeploiement.ps1
```

Le script 90 reste volontairement le dernier script fonctionnel avant le script 99 de fin de déploiement, afin de ne pas imposer la saisie d'un mot de passe entre plusieurs redémarrages et relances du batch pendant la préparation du poste.

---

## Tableau récapitulatif des scripts

| Script | Fichier | Objectif principal | État | Commentaire |
|---|---|---|---|---|
| 00 | `00_ModeDeploiement.ps1` | Préparer le poste avant le déploiement | À VALIDER | Paramétrage énergie / Windows Update |
| 01 | `01_Bureau.ps1` | Affichage des icônes système sur le bureau | VALIDÉ | Reste limité sur la position exacte |
| 02 | `02_MenuContextuelClassique.ps1` | Restauration du menu contextuel classique | VALIDÉ POUR L'UTILISATEUR COURANT | Non hérité dans le profil par défaut |
| 03 | `03_Explorateur.ps1` | Ouvrir l'Explorateur sur Ce PC / extensions visibles | VALIDÉ | Paramètres Explorer validés |
| 04 | `04_ZoneNotification.ps1` | Affichage des icônes déjà connues dans la zone de notification | VALIDÉ | Les nouvelles icônes restent gérées manuellement |
| 05 | `05_BarreTachesGauche.ps1` | Alignement de la barre des tâches à gauche | VALIDÉ | Option de suppression de Store non implémentée |
| 06 | `06_RechercheBarreTaches.ps1` | Affichage uniquement de l'icône recherche | VALIDÉ | Concerne l'interface de recherche |
| 07 | `07_MasquerVueTaches.ps1` | Masquage du bouton Vue des tâches | VALIDÉ | Valeur enregistrée dans le registre |
| 08 | `08_MasquerWidgets.ps1` | Désinstallation complète du package Widgets | À VALIDER | Suppression AppxPackage + provisioning + restart Explorer |
| 09 | `09_MSStoreBarreTache.ps1` | Masquer le bouton MS Store de la barre des tâches | EN TEST | Masquage du bouton Microsoft Store |
| 10 | `10_DesactiverReprendre.ps1` | Désactivation de l'option Reprendre | VALIDÉ | Vérifié sur Windows 11 25H2 |
| 11 | `11_ConfidentialiteLocalisation.ps1` | Paramètres de confidentialité / localisation | VALIDÉ | Gère le cas clé absente |
| 12 | `12_ConfigurerProfilParDefaut.ps1` | Configuration des futurs profils utilisateurs | VALIDÉ | Menu contextuel classique corrigé (Set-ItemProperty) |
| 13 | `13_NumLockDemarrage.ps1` | Forcer NumLock au démarrage | FIGÉ / COMPORTEMENT ACCEPTÉ | Comportement variable selon le poste |
| 14 | `14_DesinstallationOffice.ps1` | Détection et désinstallation d'Office / OneNote | VALIDÉ | Popup confirmation + gestion MSI/C2R + OneNote |
| 15 | `15_ApplicationsWinget.ps1` | Installation et mise à jour des applications via WinGet | VALIDÉ | Gestion du cache local et synchronisation |
| 16 | `16_TeamViewerQS.ps1` | Téléchargement et mise à jour de TeamViewer QS | VALIDÉ | API TeamViewer + téléchargement direct |
| 17 | `17_DesinstallationOneDrive.ps1` | Détection et désinstallation de OneDrive | VALIDÉ | UninstallString + AppX provisionne + gestion erreurs gracieuse |
| 90 | `90_VerificationMotDePasseCompteLocal.ps1` | Vérifier un mot de passe local | À VALIDER | LogonUser API Windows (test authentification MDP vide) |
| 99 | `99_FinDeploiement.ps1` | Restauration du mode déploiement | VALIDÉ | Popup confirmation + restauration paramètres |

> Le tableau ci-dessus synthétise l'état actuel des scripts du dépôt.

---

## 6. État détaillé des scripts

### Script 00 : Mode déploiement

**Nom :** `00_ModeDeploiement.ps1`

**Fonction :** Préparer le poste avant le lancement du déploiement afin d'éviter :
- la mise en veille ;
- l'extinction automatique de l'écran ;
- les redémarrages automatiques provoqués par Windows Update.

**État :** À VALIDER

---

### Script 01 : Bureau

**Nom :** `01_Bureau.ps1`

**Fonction :** Affiche les icônes système souhaitées sur le Bureau : Ce PC, dossier utilisateur, Réseau, Corbeille, Panneau de configuration.

**État :** VALIDÉ

---

### Script 02 : Menu contextuel classique

**Nom :** `02_MenuContextuelClassique.ps1`

**Fonction :** Restaure le menu contextuel classique de Windows 11.

**État :** VALIDÉ POUR L'UTILISATEUR COURANT

---

### Script 03 : Explorateur

**Nom :** `03_Explorateur.ps1`

**Fonction :** Ouvre l'Explorateur sur Ce PC et affiche les extensions de fichiers connues.

**État :** VALIDÉ

---

### Script 04 : Zone de notification

**Nom :** `04_ZoneNotification.ps1`

**Fonction :** Affiche dans la zone de notification toutes les icônes déjà connues par le profil.

**État :** VALIDÉ

---

### Script 05 : Barre des tâches à gauche

**Nom :** `05_BarreTachesGauche.ps1`

**Fonction :** Aligne les icônes de la barre des tâches à gauche.

**État :** VALIDÉ

---

### Script 06 : Recherche

**Nom :** `06_RechercheBarreTaches.ps1`

**Fonction :** Affiche uniquement l'icône de recherche.

**État :** VALIDÉ

---

### Script 07 : Vue des tâches

**Nom :** `07_MasquerVueTaches.ps1`

**Fonction :** Masque le bouton Vue des tâches.

**État :** VALIDÉ

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

### Script 09 : Masquer le bouton Chat Teams

**Nom :** `09_MasquerBoutonChatTeams.ps1`

**Fonction :** Masque le bouton Chat (Microsoft Teams) de la barre des tâches.

**Procédure :**
1. Masquage du bouton Chat via registre

**État :** EN TEST

---

### Script 10 : Reprendre

**Nom :** `10_DesactiverReprendre.ps1`

**Fonction :** Désactive l'option Reprendre.

**État :** VALIDÉ

---

### Script 11 : Confidentialité et localisation

**Nom :** `11_ConfidentialiteLocalisation.ps1`

**Fonction :** Désactive les notifications de localisation et le remplacement de localisation.

**État :** VALIDÉ

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

**Fonction :** Installation et mise à jour des applications via WinGet depuis cache local : 7-Zip, Adobe Acrobat Reader 64 bits, Google Chrome, Mozilla Firefox français.

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
1. Détection multi-couches :
   - Package AppX utilisateur (`Get-AppxPackage`)
   - Package AppX provisionné (`Get-AppxProvisionedPackage`)
   - Exécutable (`OneDrive.exe`)
   - Registre (Programmes et fonctionnalités)
   - Dossiers d'installation
2. Popup de confirmation : "OneDrive est installe sur ce poste. Voulez-vous le desinstaller ?"
3. Arrêt des processus OneDrive
4. Désinstallation via registre (`UninstallString`) en premier — méthode la plus propre
5. Si échec ou fichier introuvable : fallback sur `OneDrive.exe /uninstall`
6. Suppression de la clé de registre Uninstall :
   - Si présente → suppression manuelle
   - Si déjà absente (supprimée par le désinstalleur) → log OK
7. Désinstallation AppX :
   - Package utilisateur via `Remove-AppxPackage`
   - Package provisionné via `Remove-AppxProvisionedPackage`
   - Erreur `0x80073CF1` (package introuvable) gérée gracieusement
8. Nettoyage des dossiers résiduels
9. Blocage pour les futurs profils :
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

### Script 90 : Vérification du mot de passe local

**Nom :** `90_VerificationMotDePasseCompteLocal.ps1`

**Fonction :** Vérifie si le compte local courant possède un mot de passe et propose d'en définir un.

**Contexte :** Le poste est configuré avec un compte local (poste neuf ou réinstallé).

**Procédure :**
1. Vérification du mot de passe via `[ADSI]` avec `PasswordAge` (méthode principale)
   - `PasswordAge > 0` → mot de passe défini (sortie)
   - `PasswordAge = 0` → aucun mot de passe (popup)
2. Fallback sur `net user` via `cmd /c` + fichier temporaire :
   - Parse la ligne "Mot de passe requis" / "Password required" (FR/EN)
3. Dernier fallback sur `Get-LocalUser` :
   - `PasswordRequired = $true` → MDP présent (sortie)
   - `PasswordLastSet = $null` → jamais de MDP (popup)

**Interaction utilisateur :**
- Popup de confirmation : "Le compte local n'a pas de mot de passe. Souhaitez-vous definir un mot de passe ?"
- Si Oui : formulaire de saisie avec 2 champs masqués (mot de passe + confirmation)
- Boutons : Valider / Annuler
- Validation : les 2 mots de passe doivent correspondre
- Application : `Set-LocalUser -Password`

**Corrections appliquées (août 2026) :**
- **Problème initial :** `PasswordRequired` utilisé seul retournait `$false` pour les comptes Microsoft/EntraID même avec un mot de passe défini → popup intempestif.
- **Correction 1 :** Ajout de `PasswordLastSet` comme méthode de secours.
- **Correction 2 :** `PasswordLastSet` garde la date même si le MDP est supprimé → faux négatif.
- **Correction 3 :** `net user` retournait "Mot de passe requis Non" même avec MDP défini sur certains comptes locaux Windows 11.
- **Correction finale :** Utilisation de `[ADSI]` avec `PasswordAge` comme méthode principale. C'est une API Windows native qui retourne l'âge du mot de passe en secondes (0 = pas de MDP). `net user` et `Get-LocalUser` sont conservés comme fallbacks.

**État :** À VALIDER (correction v8)

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

## 7. Particularités Windows 11 25H2 observées

- **UCPD :** Le pilote User Choice Protection Driver peut bloquer l'écriture de certaines valeurs (ex. : `TaskbarDa` pour le bouton Widgets). Le script 08 contourne ce problème en désinstallant complètement le package plutôt qu'en tentant une modification registre.
- **Profil par défaut :** Toutes les valeurs du script 12 sont héritées correctement, y compris le menu contextuel classique (corrigé via `Set-ItemProperty`). Le script 17 applique également le blocage OneDrive au profil par défaut via montage `NTUSER.DAT`.
- **NumLock :** La valeur HKCU peut être réinitialisée au premier logon sur certains postes.
- **Différences de mise à jour :** Deux postes Windows 11 25H2 peuvent présenter des clés différentes selon les mises à jour installées.

---

## 8. Décisions validées

- Les scripts PowerShell sont stockés dans `_CGLOBAL\PS1`.
- Les logs sont stockés dans `C:\_CGLOBAL\Logs`.
- Les anciens logs sont supprimés à chaque lancement du batch.
- Le batch continue après l'échec d'un script.
- La génération automatique des chemins de log est centralisée dans le module `CGLOBAL.Common.psm1`.
- Chaque script actif utilise `Get-CGlobalLogFile` pour obtenir son chemin de log automatiquement.
- Aucune redondance de déclaration de `$LogFile` n'existe entre les scripts.
- Tous les scripts actifs utilisent le même en-tête standardisé avec appel au module commun.
- Les interactions utilisateur utilisent des popups graphiques via `Show-CGlobalPopup`.
- Le batch utilise une popup pour le contrôle Internet.
- Le script 90 utilise un formulaire Windows personnalisé pour la saisie du mot de passe.
- Toutes les popups sont configurées avec `TopMost` pour rester au premier plan.
- Le script 90 est renommé et positionné en fin de séquence (avant le 99) pour éviter d'imposer la saisie d'un mot de passe entre plusieurs redémarrages.
- Le script 90 utilise l'API Windows `LogonUser` (advapi32) avec un mot de passe vide comme méthode principale pour détecter l'état actuel du mot de passe. Si l'authentification réussit, le mot de passe est vide. Si elle échoue avec `ERROR_LOGON_FAILURE` (1326), le mot de passe est non vide.
- Le script 08 contourne le blocage UCPD en désinstallant le package Widgets plutôt qu'en modifiant le registre.
- Le script 17 exécute le `UninstallString` du registre en premier (méthode propre), avec fallback sur `OneDrive.exe /uninstall`. La clé de registre Uninstall est supprimée si elle existe encore, ou considérée comme déjà nettoyée si absente. Les packages AppX provisionnés sont également supprimés via `Remove-AppxProvisionedPackage`.
- Le script 12 utilise `Set-ItemProperty` au lieu de `New-ItemProperty` pour modifier la valeur `(Default)` du registre dans le profil par défaut, car `New-ItemProperty` crée une valeur nommée au lieu de modifier la valeur par défaut native.

---

## 9. Points restant à traiter ou à valider

### Prioritaires

- ✅ Contrôle Internet du batch : VALIDÉ (popup graphique)
- Valider les scripts 00, 08, 09, 17 sur les cas de déploiement réel.
- Vérifier la cycle complet du script 15 avec Firefox FR lors d'une future mise à jour.

### Reportés

- Script 09 : finaliser le désépinglage de Microsoft Store et valider le blocage registre sur plusieurs postes.
- Désactivation complète des Widgets (au-delà de la suppression du package).
- Exécution automatique du script 02 au premier logon de chaque nouvel utilisateur (optionnel, le script 12 corrige maintenant le menu contextuel pour les futurs profils).
- Éventuel redémarrage unique d'Explorer après les scripts d'interface.
- Remplacer les `Read-Host` restants par des popups (si nécessaire).

---

# 10. Démarrage d'un nouveau chat

Utiliser le message suivant :

```
Je poursuis le projet CGLOBAL de post-installation Windows 11 25H2.
Voici le fichier de référence du projet. Utilise-le comme contexte et tiens compte des scripts validés, des limitations connues et des décisions déjà prises.
```

Puis joindre ou coller ce fichier : `reference-projet.md`

Lorsqu'une nouvelle modification est validée, mettre à jour ce document afin qu'il reste la source de référence du projet.
