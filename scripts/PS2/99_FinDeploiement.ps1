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
Initialize-CGlobalLog -LogFile $LogFile | Out-Null

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
# Chemins de registre
# ---------------------------------------------------------------------------

$WUKey     = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$WUAutoKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
$UXKey     = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"

# ---------------------------------------------------------------------------
# Restauration des paramètres d'alimentation
# ---------------------------------------------------------------------------

try {
    Write-Log "Restauration des paramètres d'alimentation" "INFO"

    & powercfg.exe /change monitor-timeout-ac 5 | Out-Null
    & powercfg.exe /change standby-timeout-ac 0 | Out-Null
    & powercfg.exe /change monitor-timeout-dc 5 | Out-Null
    & powercfg.exe /change standby-timeout-dc 30 | Out-Null

    Write-Log "Paramètres d'alimentation restaurés" "OK"
}
catch {
    Write-Log `
        "Erreur lors de la restauration de l'alimentation : $($_.Exception.Message)" `
        "ERROR"
}

# ---------------------------------------------------------------------------
# Suppression des blocages Windows Update
# ---------------------------------------------------------------------------

try {
    Write-Log "Suppression des blocages Windows Update" "INFO"

    # Valeurs ajoutees par le mode deploiement dans la sous-cle AU.
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

    # Nettoyage de la valeur qui peut griser les options de l'interface.
    # Cette valeur ne doit pas être recréée par le script 99.
    if (Test-Path -LiteralPath $WUKey) {
        Remove-ItemProperty `
            -Path $WUKey `
            -Name "AllowOptionalContent" `
            -ErrorAction SilentlyContinue

        # Nettoyage préventif de valeurs de blocage éventuelles.
        Remove-ItemProperty `
            -Path $WUKey `
            -Name "NoAutoUpdate" `
            -ErrorAction SilentlyContinue

        Remove-ItemProperty `
            -Path $WUKey `
            -Name "DisableWindowsUpdateAccess" `
            -ErrorAction SilentlyContinue

        Remove-ItemProperty `
            -Path $WUKey `
            -Name "SetDisableUXWUAccess" `
            -ErrorAction SilentlyContinue

        Remove-ItemProperty `
            -Path $WUKey `
            -Name "DoNotConnectToWindowsUpdateInternetLocations" `
            -ErrorAction SilentlyContinue
    }

    Write-Log "Blocages Windows Update supprimés" "OK"
}
catch {
    Write-Log `
        "Erreur lors de la suppression des blocages Windows Update : $($_.Exception.Message)" `
        "ERROR"
}

# ---------------------------------------------------------------------------
# Activation de Microsoft Update
# ---------------------------------------------------------------------------

try {
    Write-Log "Activation des mises à jour pour les autres produits Microsoft" "INFO"

    $UpdateServiceManager = New-Object -ComObject "Microsoft.Update.ServiceManager"

    $MicrosoftUpdateServiceId = "7971f918-a847-4430-9279-4a52d1efe18d"

    $MicrosoftUpdateService = $UpdateServiceManager.Services |
        Where-Object {
            $_.ServiceID -eq $MicrosoftUpdateServiceId
        }

    if (-not $MicrosoftUpdateService) {
        $UpdateServiceManager.AddService2(
            $MicrosoftUpdateServiceId,
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
    Write-Log `
        "Impossible d'activer Microsoft Update : $($_.Exception.Message)" `
        "WARN"
}

# ---------------------------------------------------------------------------
# Activation de la notification de redémarrage
# ---------------------------------------------------------------------------

try {
    Write-Log "Activation de la notification de redémarrage Windows Update" "INFO"

    New-Item -Path $UXKey -Force | Out-Null

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
        Write-Log "La notification de redémarrage n'a pas été activée" "WARN"
    }
}
catch {
    Write-Log `
        "Erreur lors de l'activation de la notification de redémarrage : $($_.Exception.Message)" `
        "ERROR"
}

# ---------------------------------------------------------------------------
# Actualisation des strategies ordinateur
# ---------------------------------------------------------------------------

try {
    Write-Log "Actualisation des stratégies ordinateur" "INFO"

    & gpupdate.exe /target:computer /force | Out-Null

    Write-Log "Stratégies ordinateur actualisées" "OK"
}
catch {
    Write-Log `
        "Impossible d'actualiser les stratégies ordinateur : $($_.Exception.Message)" `
        "WARN"
}

# ---------------------------------------------------------------------------
# Demande de lancement immediat de Windows Update
# ---------------------------------------------------------------------------

$LaunchUpdates = Show-CGlobalPopup `
    -Title "Windows Update" `
    -Message "Voulez-vous rechercher et installer immediatement les mises à jour Windows disponibles ?" `
    -Buttons "YesNo" `
    -Icon "Question"

if ($LaunchUpdates -eq "Yes") {
    try {
        Write-Log "Lancement forcé de Windows Update demandé par l'utilisateur" "INFO"

        $UsoClient = "$env:SystemRoot\System32\UsoClient.exe"

        if (Test-Path -LiteralPath $UsoClient) {
            Start-Process `
                -FilePath $UsoClient `
                -ArgumentList "StartScan" `
                -WindowStyle Hidden

            Start-Sleep -Seconds 5

            Start-Process `
                -FilePath $UsoClient `
                -ArgumentList "StartDownload" `
                -WindowStyle Hidden

            Start-Sleep -Seconds 5

            Start-Process `
                -FilePath $UsoClient `
                -ArgumentList "StartInstall" `
                -WindowStyle Hidden

            Write-Log "Commandes Windows Update lancées" "OK"
        }
        else {
            Write-Log "UsoClient.exe introuvable : lancement impossible" "ERROR"
        }
    }
    catch {
        Write-Log `
            "Erreur lors du lancement de Windows Update : $($_.Exception.Message)" `
            "ERROR"
    }
}
else {
    Write-Log `
        "Lancement immediat de Windows Update refusé par l'utilisateur" `
        "INFO"
}

# ---------------------------------------------------------------------------
# Fin du traitement
# ---------------------------------------------------------------------------

Write-Log "Mode déploiement désactivé" "OK"

Show-CGlobalPopup `
    -Title "Fin du déploiement" `
    -Message "Le mode déploiement est désactivé. Windows Update automatique est réactivé. Vous pouvez fermer cette fenêtre." `
    -Buttons "OK" `
    -Icon "Information"

exit 0