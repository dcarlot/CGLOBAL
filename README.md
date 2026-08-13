# Projet CGLOBAL - Post-installation Windows 11

Automatisation de la personnalisation de postes Windows 11 (25H2) en contexte MSP.

## 📖 Documentation

- **Référence complète** : [docs/reference-projet.md](docs/reference-projet.md)
- **Guide d'installation** : [docs/installation.md](docs/installation.md)

## 🚀 Démarrage rapide

1. Copiez le contenu de `usb-root/` sur une clé USB
2. Lancez `Run_Install.cmd` en tant qu'administrateur
3. Suivez les instructions à l'écran

## 📁 Structure
usb-root/
├── Run_Install.cmd # Point d'entrée
└── _CGLOBAL/
├── PS1/ # Scripts PowerShell
├── installers/ # Cache WinGet
└── TeamViewerQS.exe # Assistance

## 🛠️ Développement

Pour modifier les scripts :

1. Ouvrez ce projet dans VS Code
2. Modifiez les fichiers dans `usb-root/_CGLOBAL/PS1/`
3. Testez sur un poste pilote
4. Commitez les modifications : `git commit -m "description"`

## 📊 État des scripts

| Script | Statut | Description |
|--------|--------|-------------|
| 00 | ✅ Validé | Mode déploiement |
| 01-07 | ✅ Validés | Interface Bureau |
| 08 | ⚠️ À reprendre | Widgets (UCPD) |
| 10-14 | ✅ Validés | Confidentialité, Office |
| 15 | ✅ Validé | Applications WinGet |
| 16 | ⏳ À valider | TeamViewer QS |
| 17 | ⏳ À valider | Mot de passe local |
| 99 | ⏳ À valider | Fin déploiement |

## 📝 Changelog

Voir [CHANGELOG.md](CHANGELOG.md) pour l'historique des versions.

---

**Dernière mise à jour** : 2026-08-13  
**Auteur** : Votre MSP