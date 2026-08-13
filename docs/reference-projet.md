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

## 1. Contexte général

Projet d’automatisation post-installation pour des postes Windows 11, principalement validé sur Windows 11 25H2, dans un contexte MSP.

### Objectifs

- Standardiser la préparation des postes clients.
- Automatiser les réglages Windows post-installation.
- Automatiser l’installation et la mise à jour des applications.
- Utiliser en priorité les installateurs conservés localement.
- Maintenir automatiquement à jour le dépôt d’installation présent sur la clé USB.
- Permettre plusieurs exécutions sans effets de bord inutiles.
- Continuer le déploiement lorsque l’échec d’un script n’est pas critique.
- Produire un fichier de log indépendant pour chaque script.
- Préparer les paramètres par défaut des futurs profils utilisateurs.

---

## 2. Principes techniques retenus

### Scripts PowerShell

- Compatibilité Windows PowerShell 5.1.
- Scripts modulaires et indépendants.
- Scripts relançables autant que possible.
- Une fonction `Write-Log` homogène par script.
- Niveaux de log utilisés :
  - `INFO`
  - `OK`
  - `WARN`
  - `ERROR`
- Les erreurs non critiques doivent être journalisées en `WARN` sans interrompre le script.
- Les erreurs critiques peuvent retourner un code d’erreur, mais le batch principal poursuit l’exécution des scripts suivants.

### Encodage

Des problèmes d’affichage des caractères accentués ont été constatés dans la console et certains fichiers de log sous Windows PowerShell 5.1.

Décision actuelle :

- conserver les scripts fonctionnels en l’état ;
- utiliser si nécessaire des messages sans accents dans les scripts sensibles ;
- conserver `chcp 65001` dans le batch principal ;
- utiliser `Add-Content -Encoding UTF8` pour les logs.

### Redémarrage d’Explorer

Décision retenue :

- ne pas redémarrer Explorer après chaque script de personnalisation ;
- prévoir éventuellement un seul redémarrage d’Explorer en fin de séquence une fois tous les scripts d’interface validés.

---

## Glossaire

### UCPD
User Choice Protection Driver. Pilote de protection de la sélection utilisateur, connu pour bloquer certaines modifications du registre ou de l’interface de Windows 11, notamment sur des valeurs liées à la barre des tâches et aux widgets.

### WinGet
Outil de gestion des paquets Microsoft pour installer, mettre à jour et désinstaller des applications de manière standardisée à partir de manifests et de sources configurées.

### C2R
Click-to-Run. Modèle d’installation des applications Microsoft 365 / Office via le mécanisme C2R, souvent observé avec des installations OEM ou Microsoft 365.

### MSI
Windows Installer. Format d’installation Windows utilisé par de nombreuses applications, exploité via la commande `msiexec.exe`.

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
Fichier de trace produit par chaque script afin de conserver les opérations, avertissements et erreurs dans un journal distinct par script.

### Profil par défaut
Modèle de configuration utilisé pour les futurs profils créés sur le poste. Les paramètres appliqués ici doivent être conservés sans dépendre de l’état d’un profil existant.

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

Le dossier `Temp` peut être créé temporairement par certains scripts, puis supprimé lorsqu’il est vide.

---

## 4. Batch principal : Run_Install.cmd

### Fonctions principales

- Vérifie les droits administrateur.
- Se relance en administrateur si nécessaire.
- Détecte automatiquement le chemin de la clé USB.
- Synchronise `_CGLOBAL` vers `C:\_CGLOBAL` avec Robocopy.
- Supprime et recrée `C:\_CGLOBAL\Logs` à chaque lancement.
- Lance les scripts PowerShell stockés dans `C:\_CGLOBAL\PS1`.
- Utilise une sous-routine `:RunPS` afin d’éviter de répéter la logique d’appel.
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

En cas d’échec :

```text
[WARN] Le script a retourné une erreur
```

Le déploiement continue.

### Contrôle Internet

Un contrôle Internet doit être effectué avant les scripts nécessitant un accès en ligne, notamment :

- WinGet ;
- TeamViewer QuickSupport.

Comportement souhaité :

1. Tester l’accès Internet.
2. Si aucun accès n’est détecté, afficher un avertissement.
3. Demander à l’utilisateur de connecter le poste.
4. Proposer :
   - Oui : refaire le test ;
   - Non : interrompre le batch.
5. Tant que l’utilisateur choisit Oui et que l’accès reste indisponible, refaire le test et reposer la question.

Statut : contrôle à stabiliser dans le batch.

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
08_DesactiverWidgets.ps1             à développer/valider

10_DesactiverReprendre.ps1

11_ConfidentialiteLocalisation.ps1   désactivé

12_ConfigurerProfilParDefaut.ps1
13_NumLockDemarrage.ps1
14_DesinstallationOffice.ps1

[contrôle Internet]

15_ApplicationsWinget.ps1
16_TeamViewerQS.ps1
17_VerificationMotDePasseCompteLocal.ps1

99_FinDeploiement.ps1
```

Le script 17 reste volontairement le dernier script fonctionnel avant le script 99 de fin de déploiement, afin de ne pas imposer la saisie d’un mot de passe entre plusieurs redémarrages et relances du batch pendant la préparation du poste.

---

## Tableau récapitulatif des scripts

| Script | Fichier | Objectif principal | État | Commentaire |
|---|---|---|---|---|
| 00 | `00_ModeDeploiement.ps1` | Préparer le poste avant le déploiement | À VALIDER | Paramétrage énergie / Windows Update |
| 01 | `01_Bureau.ps1` | Affichage des icônes système sur le bureau | VALIDÉ | Reste limité sur la position exacte |
| 02 | `02_MenuContextuelClassique.ps1` | Restauration du menu contextuel classique | VALIDÉ POUR L’UTILISATEUR COURANT | Non hérité dans le profil par défaut |
| 03 | `03_Explorateur.ps1` | Ouvrir l’Explorateur sur Ce PC / extensions visibles | VALIDÉ | Paramètres Explorer validés |
| 04 | `04_ZoneNotification.ps1` | Affichage des icônes déjà connues dans la zone de notification | VALIDÉ | Les nouvelles icônes restent gérées manuellement |
| 05 | `05_BarreTachesGauche.ps1` | Alignement de la barre des tâches à gauche | VALIDÉ | Option de suppression de Store non implémentée |
| 06 | `06_RechercheBarreTaches.ps1` | Affichage uniquement de l’icône recherche | VALIDÉ | Concerne l’interface de recherche |
| 07 | `07_MasquerVueTaches.ps1` | Masquage du bouton Vue des tâches | VALIDÉ | Valeur enregistrée dans le registre |
| 08 | `08_MasquerWidgets.ps1` | Masquage du bouton Widgets | À REPRENDRE | Blocage probable par UCPD |
| 10 | `10_DesactiverReprendre.ps1` | Désactivation de l’option Reprendre | VALIDÉ | Vérifié sur Windows 11 25H2 |
| 11 | `11_ConfidentialiteLocalisation.ps1` | Paramètres de confidentialité / localisation | VALIDÉ AVEC GESTION DE CLÉ ABSENTE | Gère le cas clé absente |
| 12 | `12_ConfigurerProfilParDefaut.ps1` | Configuration des futurs profils utilisateurs | VALIDÉ AVEC LIMITATION | Menu contextuel classique non hérité |
| 13 | `13_NumLockDemarrage.ps1` | Forcer NumLock au démarrage | FIGÉ / COMPORTEMENT ACCEPTÉ | Comportement variable selon le poste |
| 14 | `14_DesinstallationOffice.ps1` | Détection et désinstallation d’Office | VALIDÉ SUR LES CAS TESTÉS | Gestion MSI / C2R désinstallation |
| 15 | `15_ApplicationsWinget.ps1` | Installation et mise à jour des applications via WinGet | VALIDÉ, AVEC FIREFOX FR ET NETTOYAGE MIROIR À CONSERVER | Gestion du cache local et synchronisation |
| 16 | `16_TeamViewerQS.ps1` | Téléchargement et mise à jour de TeamViewer QS | À VALIDER | Conformité de l’API TeamViewer à confirmer |
| 17 | `17_VerificationMotDePasseCompteLocal.ps1` | Vérifier un mot de passe local | À VALIDER | À confirmer selon les profils Microsoft / Entra |
| 99 | `99_FinDeploiement.ps1` | Restauration du mode déploiement | À VALIDER | Détermine la fin du cycle de préparation |

> Le tableau ci-dessus synthétise l’état actuel des scripts du dépôt.

---

## 6. État détaillé des scripts

## Script 00 : Mode déploiement

### Nom

```text
00_ModeDeploiement.ps1
```
### Fonction

Préparer le poste avant le lancement du déploiement afin d’éviter :

- la mise en veille ;
- l’extinction automatique de l’écran ;
- les redémarrages automatiques provoqués par Windows Update.

### Alimentation

Désactive temporairement :

- veille secteur ;
- veille batterie ;
- extinction écran secteur ;
- extinction écran batterie.

### Windows Update

Crée ou modifie :

```text
HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU
```

Valeur :

```text
NoAutoRebootWithLoggedOnUsers = 1
```

### Effet recherché

Pendant le déploiement :

- aucune mise en veille automatique ;
- aucun écran noir dû à l’extinction automatique ;
- aucun redémarrage automatique Windows Update tant qu’une session est ouverte.

### État

```text
À VALIDER
```

## Script 01 : Bureau

### Nom

```text
01_Bureau.ps1
```

### Fonction

Affiche les icônes système souhaitées sur le Bureau :

- Ce PC ;
- dossier utilisateur si présent dans la version retenue du script ;
- Réseau ;
- Corbeille ;
- Panneau de configuration.

### Registre

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel
```

### État

```text
VALIDÉ
```

### Limite connue

La position exacte des icônes n’est pas automatisée. L’icône Ce PC peut être affichée, mais sa position en haut à gauche n’est pas forcée.

---

## Script 02 : Menu contextuel classique

### Nom

```text
02_MenuContextuelClassique.ps1
```

### Fonction

Restaure le menu contextuel classique de Windows 11.

### Registre

```text
HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32
```

La valeur par défaut doit être vide.

### État

```text
VALIDÉ POUR L’UTILISATEUR COURANT
```

### Limite connue

Ce réglage n’est pas repris lors de la création d’un nouveau profil à partir de `C:\Users\Default\NTUSER.DAT` sur les postes Windows 11 25H2 testés.

Dans le nouveau profil, la clé `{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}` est absente.

### Décision

- Le script 02 reste la méthode fiable.
- Il doit être exécuté une fois dans chaque session utilisateur nécessitant le menu contextuel classique.
- Le réglage correspondant peut être retiré du script 12, car il n’est pas hérité.

---

## Script 03 : Explorateur

### Nom

```text
03_Explorateur.ps1
```

### Fonctions

- Ouvre l’Explorateur sur Ce PC.
- Affiche les extensions de fichiers connues.

### Registre

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced
```

Valeurs :

```text
LaunchTo = 1
HideFileExt = 0
```

### État

```text
VALIDÉ
```

---

## Script 04 : Zone de notification

### Nom

```text
04_ZoneNotification.ps1
```

### Fonction

Affiche dans la zone de notification toutes les icônes déjà connues par le profil au moment du passage du script.

### Registre

```text
HKCU\Control Panel\NotifyIconSettings\<ID application>\IsPromoted
```

Valeur :

```text
IsPromoted = 1
```

### Comportement

- Les icônes déjà enregistrées sont affichées.
- Les futures icônes ne sont pas automatiquement forcées.
- L’utilisateur pourra gérer manuellement les nouvelles icônes.

### État

```text
VALIDÉ
```

### Profil par défaut

Ce réglage n’est pas repris dans le script 12, car les sous-clés `NotifyIconSettings` n’existent qu’après l’enregistrement des applications dans un profil donné.

---

## Script 05 : Barre des tâches à gauche

### Nom

```text
05_BarreTachesGauche.ps1
```

### Fonction

Aligne les icônes de la barre des tâches à gauche.

### Registre

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced
```

Valeur :

```text
TaskbarAl = 0
```

### État

```text
VALIDÉ
```

### Microsoft Store épinglé

Besoin identifié : retirer uniquement l’icône Microsoft Store de la barre des tâches, sans désinstaller Microsoft Store.

AppID détecté :

```text
Microsoft.WindowsStore_8wekyb3d8bbwe!App
```

### Décision actuelle

Non implémenté pour le moment, car les épinglages sont gérés par des données de barre des tâches plus fragiles que les valeurs simples du registre.

Sujet reporté à une future normalisation complète de la barre des tâches.

---

## Script 06 : Recherche

### Nom

```text
06_RechercheBarreTaches.ps1
```

### Fonction

Affiche uniquement l’icône de recherche.

### Registre

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Search
```

Valeur :

```text
SearchboxTaskbarMode = 1
```

### État

```text
VALIDÉ
```

---

## Script 07 : Vue des tâches

### Nom

```text
07_MasquerVueTaches.ps1
```

### Fonction

Masque le bouton Vue des tâches.

### Registre

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced
```

Valeur :

```text
ShowTaskViewButton = 0
```

### État

```text
VALIDÉ
```

---

## Script 08 : Widgets

### Nom prévu

```text
08_MasquerWidgets.ps1
```

### Besoin

Masquer uniquement le bouton Widgets de la barre des tâches.

### Registre identifié sur Windows 11 25H2

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced
```

Valeur :

```text
TaskbarDa = 0
```

### Tests effectués

- Le réglage manuel crée ou modifie bien `TaskbarDa`.
- `TaskbarDa = 1` lorsque Widgets est activé.
- `TaskbarDa = 0` lorsque Widgets est désactivé.
- L’écriture par PowerShell ou Registre a renvoyé une opération non autorisée sur certains postes Windows 11 25H2.

### Cause probable

Protection UCPD, User Choice Protection Driver.

### État

```text
À REPRENDRE
```

### Décision

Ne pas intégrer pour le moment un contournement qui désactive temporairement UCPD sans validation complémentaire.

---

## Script 09 : Désactivation complète des Widgets

### État

```text
NON DÉVELOPPÉ
```

### Objectif éventuel

Désactiver complètement le composant Widgets, distinct du simple masquage du bouton.

---

## Script 10 : Reprendre

### Nom

```text
10_DesactiverReprendre.ps1
```

### Fonction

Désactive l’option Reprendre présente dans :

```text
Paramètres > Personnalisation > Barre des tâches
```

### Registre identifié sur Windows 11 25H2

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced
```

Valeur :

```text
IsEnabled = 0
```

Correspondance vérifiée :

```text
Reprendre ON  -> IsEnabled = 1
Reprendre OFF -> IsEnabled = 0
```

### État

```text
VALIDÉ
```

---

## Script 11 : Confidentialité et localisation

### Nom

```text
11_ConfidentialiteLocalisation.ps1
```

### Fonctions

Désactive :

- Autoriser le remplacement de la localisation.
- Notifier lorsque les applications demandent l’emplacement.

### Registre : notifications

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location
```

Valeur :

```text
ShowGlobalPrompts = 0
```

### Registre : remplacement de localisation

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\CPSS\Store\UserLocationOverridePrivacySetting
```

Valeur :

```text
Value = 0
```

### Compatibilité entre postes 25H2

La clé `UserLocationOverridePrivacySetting` peut être absente sur certains postes selon leur niveau de mise à jour ou leur état d’initialisation.

### Comportement retenu

- Si la clé existe : appliquer et vérifier la valeur.
- Si la clé n’existe pas : écrire un `WARN`, ignorer ce réglage et continuer.
- Ne pas tenter ensuite d’écrire ou de vérifier une clé déclarée absente.

### État

```text
VALIDÉ AVEC GESTION DE CLÉ ABSENTE
```

---

## Script 12 : Profil utilisateur par défaut

### Nom

```text
12_ConfigurerProfilParDefaut.ps1
```

### Fonction

Configure les réglages initiaux des futurs utilisateurs en modifiant :

```text
C:\Users\Default\NTUSER.DAT
```

### Principe

1. Charge la ruche du profil par défaut sous un nom temporaire.
2. Applique les valeurs de registre validées.
3. Ferme les handles.
4. Décharge impérativement la ruche.

### Important

Ne pas confondre :

```text
HKEY_USERS\.DEFAULT
```

avec :

```text
C:\Users\Default\NTUSER.DAT
```

- `HKEY_USERS\.DEFAULT` concerne principalement le contexte système et l’écran de connexion.
- `C:\Users\Default\NTUSER.DAT` sert de modèle aux futurs profils utilisateurs.

### Réglages hérités validés

- Icônes du Bureau.
- Explorateur ouvert sur Ce PC.
- Extensions visibles.
- Barre des tâches à gauche.
- Recherche en mode icône.
- Vue des tâches masquée.
- Reprendre désactivé.
- Paramètres de confidentialité et localisation.
- InitialKeyboardIndicators pour les futurs profils.

### Limite connue

Le menu contextuel classique n’est pas hérité.

### État

```text
VALIDÉ AVEC LIMITATION
```

### Sécurité

La ruche doit être déchargée même en cas d’erreur. Une ruche laissée chargée peut verrouiller `NTUSER.DAT` et empêcher la création normale de futurs profils.

---

## Script 13 : NumLock

### Nom

```text
13_NumLockDemarrage.ps1
```

### Fonction

Configure :

```text
HKCU\Control Panel\Keyboard\InitialKeyboardIndicators = "2"
```

et :

```text
HKEY_USERS\.DEFAULT\Control Panel\Keyboard\InitialKeyboardIndicators = "2"
```

Le script 12 applique aussi la valeur `2` dans le fichier `NTUSER.DAT` du profil par défaut pour les futurs utilisateurs.

### Tests

- La valeur passe bien à `2` à la fin du script.
- Sur certains postes Windows 11 25H2 avec connexion automatique d’un compte local sans mot de passe, HKCU repasse à `0` après redémarrage ou reconnexion.
- Après activation manuelle de NumLock, l’état reste ensuite mémorisé.

### Décision

Ne pas ajouter de tâche planifiée, de SendKeys ou de contournement supplémentaire.

### État

```text
FIGÉ / COMPORTEMENT ACCEPTÉ
```

---

## Script 14 : Désinstallation Office

### Nom

```text
14_DesinstallationOffice.ps1
```

### Objectif

Détecter et proposer la désinstallation de toutes les versions Office présentes, notamment :

- Microsoft 365 ;
- Office Click-to-Run ;
- Office Famille ;
- Office Petite Entreprise / Small Business ;
- Office Home and Business ;
- Office ProPlus ;
- Office 2019 ;
- Office 2021 ;
- Office 2024 ;
- Project ;
- Visio ;
- installations MSI ;
- préinstallations OEM sous des profils utilisateurs.

### Détection

Le script analyse :

```text
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall
HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall
HKU\<SID>\Software\Microsoft\Windows\CurrentVersion\Uninstall
```

La ruche HKU est montée comme lecteur PowerShell si nécessaire.

### Cause importante identifiée

Certaines préinstallations OEM Microsoft 365 sont enregistrées dans HKCU ou dans la ruche d’un autre profil utilisateur chargé, et pas uniquement dans HKLM.

### Désinstallation

Le script réutilise directement la valeur :

```text
UninstallString
```

enregistrée par Windows.

#### Click-to-Run

- Détecté via `OfficeClickToRun.exe` ou `OfficeC2RClient.exe`.
- Ajout de `DisplayLevel=False` si absent.
- Séparation de l’exécutable et des arguments.
- Exécution avec `Start-Process -Wait`.

#### MSI

- Extraction du GUID MSI.
- Exécution :

```text
msiexec.exe /x {GUID} /quiet /norestart
```

### Confirmation

Le script affiche toutes les versions détectées et demande :

```text
Voulez-vous désinstaller TOUTES ces versions d’Office ? O/N
```

- Oui : désinstalle toutes les entrées reconnues.
- Non : ne fait rien et retourne `0` afin que le batch continue.

### Diagnostic si aucune entrée n’est trouvée

Le script vérifie l’existence d’une configuration Click-to-Run sous :

```text
HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration
```

Cela permet de signaler un éventuel stub OEM ou une préinstallation à la demande.

### Logs

```text
C:\_CGLOBAL\Logs\Log14_DesinstallationOffice.txt
```

Les logs indiquent aussi la clé source de chaque produit détecté.

### Corrections importantes

- La fonction `Invoke-OfficeUninstall` doit impérativement rester dans le script.
- Le résultat de `Get-OfficeInstalls` doit être forcé en tableau :

```powershell
$officeInstalls = @(Get-OfficeInstalls)
```

ou équivalent afin que `.Count` fonctionne même avec une seule entrée.

### État

```text
VALIDÉ SUR LES CAS TESTÉS
```

---

## Script 15 : Applications WinGet

### Nom

```text
15_ApplicationsWinget.ps1
```

### Applications gérées

- 7-Zip : `7zip.7zip`
- Adobe Acrobat Reader 64 bits : `Adobe.Acrobat.Reader.64-bit`
- Google Chrome : `Google.Chrome`
- Mozilla Firefox français : `Mozilla.Firefox.fr`

### Firefox

Ancien package abandonné :

```text
Mozilla.Firefox
```

Package retenu :

```text
Mozilla.Firefox.fr
```

Les anciens postes de test avec Firefox US seront corrigés manuellement. Aucune logique automatique de migration US vers FR n’est ajoutée afin de ne pas complexifier le script.

### Structure du cache

```text
C:\_CGLOBAL\installers\7zip.7zip
C:\_CGLOBAL\installers\Adobe.Acrobat.Reader.64-bit
C:\_CGLOBAL\installers\Google.Chrome
C:\_CGLOBAL\installers\Mozilla.Firefox.fr
```

Chaque dossier contient normalement :

- un installateur `.exe` ou `.msi` ;
- un manifeste `.yaml` de même base de nom.

### Fonctionnement

Pour chaque application :

1. Met à jour les sources WinGet.
2. Récupère la version en ligne.
3. Lit la version du manifeste local.
4. Compare la version locale et la version en ligne.
5. Si le cache est obsolète, télécharge dans le sous-dossier correspondant au PackageId.
6. Supprime les anciens fichiers de version du sous-dossier.
7. Détecte la version installée.
8. Si l’application est absente, installe depuis le cache local.
9. Si une version plus ancienne est installée, la met à jour depuis le cache local.
10. Si la version installée est déjà identique au cache, ne fait rien.

### Installation locale

- EXE : arguments silencieux spécifiques par application.
- MSI : `msiexec.exe /i ... /qn /norestart`.

WinGet est utilisé pour :

- la recherche de version ;
- le téléchargement ;
- le fallback éventuel.

L’installation prioritaire se fait directement avec le fichier local afin d’éviter que `winget install --manifest` ne retélécharge l’installeur depuis Internet.

### Nettoyage des anciennes versions

Lorsqu’une nouvelle version est téléchargée, l’ancienne version doit être supprimée du sous-dossier local.

Cas important : le batch initial peut recopier une ancienne version depuis la clé vers C: si le nom de fichier est différent. Le script doit donc nettoyer le cache même si une version à jour est déjà présente sur le disque.

### Synchronisation retour vers la clé USB

La détection de la clé USB utilise une fonction `Get-UsbCGlobalPath` qui cherche un lecteur amovible contenant `_CGLOBAL`.

La synchronisation retour doit être déclenchée si :

- une mise à jour a été téléchargée ;
- ou un ancien fichier a été supprimé du cache local.

La copie retour doit utiliser une logique miroir :

```text
/MIR
```

et non uniquement `/E /XO`, afin de supprimer aussi les anciennes versions présentes sur la clé.

### Attention au Robocopy initial du batch

Le `robocopy USB -> C:` avec `/E /XO` peut recopier un ancien fichier lorsqu’il porte un nom différent du fichier récent. Le nettoyage du script 15 doit donc rester actif pour remettre le dépôt local en état cohérent avant la synchronisation miroir vers la clé.

### Logs

```text
C:\_CGLOBAL\Logs\Log15_ApplicationsWinget.txt
```

### État

```text
VALIDÉ, AVEC FIREFOX FR ET NETTOYAGE MIROIR À CONSERVER
```

---

## Script 16 : TeamViewer QuickSupport

### Nom

```text
16_TeamViewerQS.ps1
```

### Fichier géré

```text
C:\_CGLOBAL\TeamViewerQS.exe
```

### URL stable

```text
https://get.teamviewer.com/cglobal
```

Cette page ne pointe pas directement vers l’exécutable. Elle appelle l’API :

```text
https://get.teamviewer.com/api/CustomDesign
```

avec les informations :

```text
ConfigId = u6dx34t
Version = 15
IsCustomModule = true
```

L’API retourne une URL temporaire signée vers le vrai `TeamViewerQS.exe`.

### Ne pas coder en dur

L’URL complète de `customdesignservice.teamviewer.com` contient une date d’expiration et une signature temporaire. Elle change entre les téléchargements.

### Fonctionnement

- Internet est supposé disponible, le contrôle ayant lieu dans le batch avant le script.
- Interroger dynamiquement l’API TeamViewer de configuration CGLOBAL.
- Récupérer l’URL temporaire signée du véritable `TeamViewerQS.exe`.
- Télécharger directement le fichier vers :

```text
C:\_CGLOBAL\TeamViewerQS.exe
```

### Raccourci public

Lors de la création initiale du fichier local, le script crée :

```text
C:\Users\Public\Desktop\Assistance CGLOBAL.lnk
```

Cible :

```text
C:\_CGLOBAL\TeamViewerQS.exe
```

Le raccourci n’a pas besoin d’être recréé lors d’une simple mise à jour, car le nom et le chemin de la cible ne changent pas.

### Logs

```text
C:\_CGLOBAL\Logs\Log16_TeamViewerQS.txt
```

### État

```text
À VALIDER
```

---

## Script 17 : Vérification du mot de passe local

### Nom

```text
17_VerificationMotDePasseCompteLocal.ps1
```

### Objectif

Vérifier si le compte local courant possède un mot de passe.

### Comportement souhaité

- Compte Microsoft : ignorer.
- Compte Entra ID : ignorer.
- Compte local protégé : ne rien faire.
- Compte local sans mot de passe : proposer de définir un mot de passe.
- Si l’utilisateur refuse : journaliser un `WARN` et continuer.
- Si l’utilisateur accepte : demander deux fois le mot de passe en saisie sécurisée, vérifier la correspondance puis appliquer le mot de passe.

### Logs

```text
C:\_CGLOBAL\Logs\Log17_VerificationMotDePasseCompteLocal.txt
```

### Point de vigilance

La propriété `PasswordRequired` de `Get-LocalUser` peut ne pas être suffisante dans tous les cas pour confirmer qu’un mot de passe non vide est effectivement défini.

### État

```text
À VALIDER
```

---

## Script 99 : Fin de déploiement

**Nom :** `99_FinDeploiement.ps1`  
**État :** À VALIDER

### Fonction

Permet à l’opérateur de restaurer ou non les paramètres modifiés par le script 00.

### Question affichée

```text
Le mode déploiement est actuellement actif.

Souhaitez-vous restaurer les paramètres standards CGLOBAL ?

O = Oui
N = Non
```

### Si l'utilisateur répond O

#### Batterie

```text
Écran : 5 minutes
Veille : 30 minutes
```

#### Secteur

```text
Écran : 5 minutes
Veille : Jamais
```

#### Windows Update

Suppression de :

```text
NoAutoRebootWithLoggedOnUsers
```

### Si l'utilisateur répond N

Aucune modification.

Le poste conserve le mode déploiement actif afin de permettre :

- plusieurs passages du batch ;
- des vérifications complémentaires ;
- un redémarrage manuel avant validation finale.

### Logs

```text
C:\_CGLOBAL\Logs\Log99_FinDeploiement.txt
```

## 7. Particularités Windows 11 25H2 observées

## UCPD

Le pilote User Choice Protection Driver peut bloquer l’écriture de certaines valeurs depuis PowerShell, Regedit ou `reg.exe`.

Cas observé :

```text
TaskbarDa
```

pour le bouton Widgets.

## Profil par défaut

La majorité des valeurs du script 12 sont héritées correctement, mais la branche du menu contextuel classique sous `Software\Classes\CLSID` n’est pas reprise.

## NumLock

La valeur HKCU peut être réinitialisée au premier logon ou après redémarrage sur certains postes avec ouverture automatique de session.

## Différences de niveau de mise à jour

Deux postes Windows 11 25H2 peuvent présenter des clés ou comportements différents selon les mises à jour installées et l’état d’initialisation des composants.

Conséquence :

- une clé optionnelle absente doit souvent produire un `WARN` plutôt qu’un arrêt du déploiement ;
- les vérifications avant/après via export du registre ou ProcMon restent utiles pour les nouveaux réglages.

---

# 8. Décisions validées

- Les scripts PowerShell sont stockés dans `_CGLOBAL\PS1`.
- Les logs sont stockés dans `C:\_CGLOBAL\Logs`.
- Les anciens logs sont supprimés à chaque lancement du batch.
- Le batch continue après l’échec d’un script.
- Le menu contextuel classique reste géré par le script 02 dans chaque session concernée.
- Le script 12 configure uniquement les futurs profils.
- Firefox doit utiliser le package français `Mozilla.Firefox.fr`.
- Les installateurs WinGet sont installés depuis le cache local.
- Le dépôt `installers` local est nettoyé puis synchronisé en miroir vers la clé USB.
- TeamViewerQS est téléchargé dynamiquement via l’API TeamViewer.
- Le raccourci TeamViewer est placé sur le Bureau public et nommé `Assistance CGLOBAL`.
- Microsoft Store reste installé.
- Le désépinglage de Microsoft Store de la barre des tâches est reporté.
- Aucun contournement UCPD n’est intégré pour l’instant.
- Aucun contournement supplémentaire n’est ajouté pour NumLock.
- Le script 00_ModeDeploiement.ps1 est exécuté avant tous les autres scripts.
- La mise en veille est désactivée pendant le déploiement.
- L'extinction automatique de l'écran est désactivée pendant le déploiement.
- Les redémarrages automatiques Windows Update sont bloqués pendant le déploiement.
- Le script 99_FinDeploiement.ps1 est exécuté en fin de chaîne.
- L'utilisateur choisit de restaurer ou non les paramètres standards CGLOBAL.
- Le script 17 reste le dernier script fonctionnel avant le script 99 de clôture.
---

# 9. Points restant à traiter ou à valider

## Prioritaires

- Stabiliser définitivement le contrôle Internet du batch.
- Valider le script 17 sur :
  - compte local sans mot de passe ;
  - compte local avec mot de passe ;
  - compte Microsoft ;
  - compte Entra ID.
- Vérifier le script 14 sur plusieurs préinstallations OEM Office et plusieurs langues.
- Vérifier le cycle complet du script 15 avec Firefox FR lors d’une future mise à jour.

## Reportés

- Script 08 : masquage du bouton Widgets avec protection UCPD.
- Script 09 : désactivation complète des Widgets.
- Désépinglage du Microsoft Store de la barre des tâches.
- Exécution automatique du script 02 au premier logon de chaque nouvel utilisateur.
- Éventuel redémarrage unique d’Explorer après les scripts d’interface.

---

# 10. Méthode de validation des scripts

Pour chaque script :

1. Tester sur une installation Windows 11 25H2 propre.
2. Examiner le fichier de log dédié.
3. Vérifier les valeurs de registre finales.
4. Vérifier visuellement le comportement attendu.
5. Relancer le script pour vérifier son idempotence.
6. Tester le cas où la configuration est déjà appliquée.
7. Tester si possible un poste avec un niveau de mise à jour différent.
8. Ne figer le script qu’après validation des scénarios principaux.

---

# 11. Démarrage d’un nouveau chat

Utiliser le message suivant :

```text
Je poursuis le projet CGLOBAL de post-installation Windows 11 25H2.
Voici le fichier de référence du projet. Utilise-le comme contexte et tiens compte des scripts validés, des limitations connues et des décisions déjà prises.
```

Puis joindre ou coller ce fichier :

```text
Etat_Projet_CGLOBAL.md
```

Lorsqu’une nouvelle modification est validée, mettre à jour ce document afin qu’il reste la source de référence du projet.
