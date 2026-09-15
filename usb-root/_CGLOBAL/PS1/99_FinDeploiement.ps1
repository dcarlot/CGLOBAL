#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Initialisation
# ---------------------------------------------------------------------------

$CommonModule = "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1"

if (-not (Test-Path -LiteralPath $CommonModule)) {
    Write-Error "Module commun introuvable : $CommonModule"
    exit 1
}

Import-Module $CommonModule -Force

$LogFile = Get-CGlobalLogFile -ScriptPath $PSCommandPath
Initialize-CGlobalLog -LogFile $LogFile
Write-Log "Début de la sortie du mode déploiement" "INFO"

# ---------------------------------------------------------------------------
# Confirmation de sortie du mode déploiement
# ---------------------------------------------------------------------------

$DisableDeploymentMode = Show-CGlobalPopup `
    -Title "Mode déploiement" `
    -Message "Voulez-vous désactiver le mode déploiement et réactiver le fonctionnement normal de Windows Update ?" `
    -Buttons "YesNo" `
    -Icon "Question"

if ($DisableDeploymentMode -ne "Yes") {
    Write-Log "Mode déploiement conservé à la demande de l'utilisateur" "INFO"
    exit 0
}

# ---------------------------------------------------------------------------
# Paramètres
# ---------------------------------------------------------------------------

$WUKey     = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$WUAutoKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
$UXKey     = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"

# ---------------------------------------------------------------------------
# Restauration des paramètres d'alimentation
# ---------------------------------------------------------------------------

try {
    Write-Log "Restauration des paramètres d'alimentation" "INFO"

    # Écran sur secteur : 5 minutes
    & powercfg.exe /change monitor-timeout-ac 5 | Out-Null

    # Veille sur secteur : jamais
    & powercfg.exe /change standby-timeout-ac 0 | Out-Null

    # Écran sur batterie : 5 minutes
    & powercfg.exe /change monitor-timeout-dc 5 | Out-Null

    # Veille sur batterie : 30 minutes
    & powercfg.exe /change standby-timeout-dc 30 | Out-Null

    Write-Log "Paramètres d'alimentation restaurés" "OK"
}
catch {
    Write-Log "Erreur lors de la restauration de l'alimentation : $($_.Exception.Message)" "ERROR"
}

# ---------------------------------------------------------------------------
# Réactivation de Windows Update automatique
# ---------------------------------------------------------------------------

try {
    Write-Log "Réactivation de Windows Update automatique" "INFO"

    # Suppression des blocages posés par 00_ModeDeploiement.ps1
    if (Test-Path -LiteralPath $WUAutoKey) {
        Remove-ItemProperty `
            -Path $WUAutoKey `
            -Name "NoAutoUpdate" `
            -ErrorAction SilentlyContinue

        Remove-ItemProperty `
            -Path $WUAutoKey `
            -Name "NoAutoRebootWithLoggedOnUsers" `
            -ErrorAction SilentlyContinue
    }

    # Suppression d'une éventuelle stratégie de blocage résiduelle
    if (Test-Path -LiteralPath $WUKey) {
        Remove-ItemProperty `
            -Path $WUKey `
            -Name "NoAutoUpdate" `
            -ErrorAction SilentlyContinue
    }

    Write-Log "Blocages Windows Update supprimés" "OK"
}
catch {
    Write-Log "Erreur lors de la réactivation de Windows Update : $($_.Exception.Message)" "ERROR"
}

# ---------------------------------------------------------------------------
# Réactivation des mises à jour pour les autres produits Microsoft
# ---------------------------------------------------------------------------

try {
    Write-Log "Activation des mises à jour pour les autres produits Microsoft" "INFO"

    New-Item -Path $UXKey -Force | Out-Null

    # Réglage utilisé par l'interface Windows Update
    New-ItemProperty `
        -Path $UXKey `
        -Name "AllowMUUpdateService" `
        -PropertyType DWord `
        -Value 1 `
        -Force | Out-Null

    # Enregistrement du service Microsoft Update si nécessaire
    try {
        $UpdateServiceManager = New-Object -ComObject "Microsoft.Update.ServiceManager"

        $MicrosoftUpdateService = $UpdateServiceManager.Services |
            Where-Object {
                $_.ServiceID -eq "7971f918-a847-4430-9279-4a52d1efe18d"
            }

        if (-not $MicrosoftUpdateService) {
            $UpdateServiceManager.AddService2(
                "7971f918-a847-4430-9279-4a52d1efe18d",
                7,
                ""
            ) | Out-Null

            Write-Log "Service Microsoft Update enregistré" "OK"
        }
        else {
            Write-Log "Service Microsoft Update déjà enregistré" "INFO"
        }
    }
    catch {
        Write-Log "Le service Microsoft Update n'a pas pu être enregistré : $($_.Exception.Message)" "WARN"
    }

    Write-Log "Mises à jour des autres produits Microsoft activées" "OK"
}
catch {
    Write-Log "Erreur lors de l'activation de Microsoft Update : $($_.Exception.Message)" "ERROR"
}

# ---------------------------------------------------------------------------
# Activation des dernières mises à jour disponibles
# ---------------------------------------------------------------------------

try {
    Write-Log "Activation de la réception des dernières mises à jour disponibles" "INFO"

    New-Item -Path $WUKey -Force | Out-Null

    # 1 = réception automatique des mises à jour facultatives,
    # notamment les mises à jour de fonctionnalités diffusées progressivement.
    #
    # Attention : cette valeur peut également entraîner l'installation
    # automatique de certaines mises à jour facultatives.
    New-ItemProperty `
        -Path $WUKey `
        -Name "AllowOptionalContent" `
        -PropertyType DWord `
        -Value 1 `
        -Force | Out-Null

    # Préférence complémentaire utilisée par certaines versions de Windows 11
    New-Item -Path $UXKey -Force | Out-Null

    New-ItemProperty `
        -Path $UXKey `
        -Name "IsContinuousInnovationOptedIn" `
        -PropertyType DWord `
        -Value 1 `
        -Force | Out-Null

    Write-Log "Réception des dernières mises à jour activée" "OK"
}
catch {
    Write-Log "Erreur lors de l'activation des dernières mises à jour : $($_.Exception.Message)" "ERROR"
}

# ---------------------------------------------------------------------------
# Notification lorsqu'un redémarrage est requis
# ---------------------------------------------------------------------------

try {
    Write-Log "Activation de la notification de redémarrage Windows Update" "INFO"

    New-Item -Path $UXKey -Force | Out-Null

    # Cette écriture est volontairement effectuée après les autres réglages.
    New-ItemProperty `
        -Path $UXKey `
        -Name "RestartNotificationsAllowed2" `
        -PropertyType DWord `
        -Value 1 `
        -Force | Out-Null

    $RestartNotificationValue = Get-ItemPropertyValue `
        -Path $UXKey `
        -Name "RestartNotificationsAllowed2" `
        -ErrorAction Stop

    if ($RestartNotificationValue -eq 1) {
        Write-Log "Notification de redémarrage activée" "OK"
    }
    else {
        Write-Log "La notification de redémarrage n'a pas été correctement activée" "WARN"
    }
}
catch {
    Write-Log "Erreur lors de l'activation de la notification de redémarrage : $($_.Exception.Message)" "ERROR"
}

# ---------------------------------------------------------------------------
# Actualisation des stratégies
# ---------------------------------------------------------------------------

try {
    Write-Log "Actualisation des stratégies ordinateur" "INFO"

    & gpupdate.exe /target:computer /force | Out-Null

    Write-Log "Stratégies ordinateur actualisées" "OK"
}
catch {
    Write-Log "Impossible d'actualiser les stratégies : $($_.Exception.Message)" "WARN"
}

# ---------------------------------------------------------------------------
# Proposition de lancement immédiat de Windows Update
# ---------------------------------------------------------------------------

$LaunchUpdates = Show-CGlobalPopup `
    -Title "Windows Update" `
    -Message "Voulez-vous rechercher et installer immédiatement les mises à jour Windows disponibles ?" `
    -Buttons "YesNo" `
    -Icon "Question"

if ($LaunchUpdates -eq "Yes") {
    try {
        Write-Log "Lancement forcé de Windows Update demandé par l'utilisateur" "INFO"

        $UsoClient = "$env:SystemRoot\System32\UsoClient.exe"

        if (Test-Path -LiteralPath $UsoClient) {
            Start-Process -FilePath $UsoClient -ArgumentList "StartScan" -WindowStyle Hidden
            Start-Sleep -Seconds 5

            Start-Process -FilePath $UsoClient -ArgumentList "StartDownload" -WindowStyle Hidden
            Start-Sleep -Seconds 5

            Start-Process -FilePath $UsoClient -ArgumentList "StartInstall" -WindowStyle Hidden

            Write-Log "Commandes Windows Update lancées" "OK"
        }
        else {
            Write-Log "UsoClient.exe introuvable : lancement impossible" "ERROR"
        }
    }
    catch {
        Write-Log "Erreur lors du lancement de Windows Update : $($_.Exception.Message)" "ERROR"
    }
}
else {
    Write-Log "Lancement immédiat de Windows Update refusé par l'utilisateur" "INFO"
}

# ---------------------------------------------------------------------------
# Fin
# ---------------------------------------------------------------------------

Write-Log "Mode déploiement désactivé" "OK"

Show-CGlobalPopup `
    -Title "Fin du déploiement" `
    -Message "Le mode déploiement est désactivé. Windows Update automatique est réactivé. Vous pouvez fermer cette fenêtre." `
    -Buttons "OK" `
    -Icon "Information"

exit 0