#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

# ------------------------------------------------------------------
# Fonctions
# ------------------------------------------------------------------

function Invoke-PowerCfg {
    param(
        [string[]]$Arguments,
        [string]$Description
    )

    try {
        & powercfg.exe @Arguments | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-Log $Description "OK"
        }
        else {
            Write-Log "$Description (code $LASTEXITCODE)" "WARN"
        }
    }
    catch {
        Write-Log "$Description : $($_.Exception.Message)" "WARN"
    }
}

function Remove-RegistryValueIfPresent {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Description
    )

    if (Test-Path $Path) {

        $Property = Get-ItemProperty `
            -Path $Path `
            -Name $Name `
            -ErrorAction SilentlyContinue

        if ($null -ne $Property) {

            Remove-ItemProperty `
                -Path $Path `
                -Name $Name `
                -ErrorAction SilentlyContinue

            Write-Log $Description "OK"
        }
        else {
            Write-Log "$Description : valeur absente" "INFO"
        }
    }
}

function Invoke-WindowsUpdate {
    Write-Log "Demarrage force de Windows Update"

    # Les commandes UsoClient sont natives a Windows 10/11.
    # Leur comportement peut varier selon la version de Windows.
    $UsoClient = "$env:SystemRoot\System32\UsoClient.exe"

    if (-not (Test-Path $UsoClient)) {
        Write-Log "UsoClient.exe introuvable" "WARN"
        return
    }

    try {

        # Recherche des mises a jour
        Start-Process `
            -FilePath $UsoClient `
            -ArgumentList "StartScan" `
            -WindowStyle Hidden `
            -Wait

        Write-Log "Recherche Windows Update declenchee" "OK"

        Start-Sleep -Seconds 5

        # Tentative de telechargement
        Start-Process `
            -FilePath $UsoClient `
            -ArgumentList "StartDownload" `
            -WindowStyle Hidden `
            -Wait

        Write-Log "Demande de telechargement Windows Update envoyee" "OK"

        Start-Sleep -Seconds 5

        # Tentative d'installation
        Start-Process `
            -FilePath $UsoClient `
            -ArgumentList "StartInstall" `
            -WindowStyle Hidden `
            -Wait

        Write-Log "Demande d'installation Windows Update envoyee" "OK"

        Write-Log "Windows Update a ete sollicite. Les operations peuvent continuer en arriere-plan." "INFO"
    }
    catch {
        Write-Log "Echec du lancement Windows Update : $($_.Exception.Message)" "WARN"
    }
}

# ------------------------------------------------------------------
# Programme principal
# ------------------------------------------------------------------

try {

    Write-Log "Fin de deploiement"

    # --------------------------------------------------------------
    # Confirmation de sortie du mode deploiement
    # --------------------------------------------------------------

    $Choice = Show-CGlobalPopup `
        -Message "Le mode deploiement est actuellement actif.`n`n- Veille desactivee`n- Extinction ecran desactivee`n- Mises a jour automatiques Windows Update bloquees`n- Redemarrage automatique Windows Update bloque`n`nRestaurer les parametres standards CGLOBAL ?" `
        -Title "Fin de deploiement" `
        -Buttons "YesNo" `
        -Icon "Question"

    if ($Choice -ne 'Yes') {

        Write-Log "Mode deploiement conserve" "WARN"

        exit 0
    }

    Write-Log "Restauration des parametres standards"

    # --------------------------------------------------------------
    # Restauration alimentation
    # --------------------------------------------------------------

    Invoke-PowerCfg `
        -Arguments @("/change", "monitor-timeout-ac", "5") `
        -Description "Ecran secteur : 5 minutes"

    Invoke-PowerCfg `
        -Arguments @("/change", "standby-timeout-ac", "0") `
        -Description "Veille secteur : jamais"

    Invoke-PowerCfg `
        -Arguments @("/change", "monitor-timeout-dc", "5") `
        -Description "Ecran batterie : 5 minutes"

    Invoke-PowerCfg `
        -Arguments @("/change", "standby-timeout-dc", "30") `
        -Description "Veille batterie : 30 minutes"

    # --------------------------------------------------------------
    # Windows Update - restauration des strategies de blocage
    # --------------------------------------------------------------

    $WUKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"

    Remove-RegistryValueIfPresent `
        -Path $WUKey `
        -Name "NoAutoUpdate" `
        -Description "Blocage des mises a jour automatiques supprime"

    Remove-RegistryValueIfPresent `
        -Path $WUKey `
        -Name "NoAutoRebootWithLoggedOnUsers" `
        -Description "Blocage du redemarrage automatique supprime"

    # Cette valeur est supprimee uniquement si elle existe.
    # On ne supprime pas la cle AU elle-meme afin de ne pas effacer
    # d'autres parametres de strategie eventuellement presents.

    # --------------------------------------------------------------
    # Restauration des options Windows Update
    # --------------------------------------------------------------

    # Autoriser les mises a jour d'autres produits Microsoft.
    # Cette valeur est une strategie Windows Update.
    $WUKeyRoot = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"

    if (-not (Test-Path $WUKeyRoot)) {
        New-Item -Path $WUKeyRoot -Force | Out-Null
    }

    Set-ItemProperty `
        -Path $WUKeyRoot `
        -Name "AllowMUUpdateService" `
        -Type DWord `
        -Value 1

    Write-Log "Mises a jour des autres produits Microsoft activees" "OK"

    # --------------------------------------------------------------
    # Options UX Windows Update
    # --------------------------------------------------------------

    $UXKey = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"

    if (-not (Test-Path $UXKey)) {
        New-Item -Path $UXKey -Force | Out-Null
    }

    # "Recevez les dernieres mises a jour des qu'elles sont
    # disponibles" : option d'innovation continue de Windows Update.
    Set-ItemProperty `
        -Path $UXKey `
        -Name "IsContinuousInnovationOptedIn" `
        -Type DWord `
        -Value 1

    Write-Log "Reception des dernieres mises a jour activee" "OK"

    # Notification lorsqu'un redemarrage est necessaire.
    # Cette valeur est utilisee par certaines versions de Windows 11.
    Set-ItemProperty `
        -Path $UXKey `
        -Name "RestartNotificationsAllowed2" `
        -Type DWord `
        -Value 1

    Write-Log "Notification de redemarrage Windows Update activee" "OK"

    # --------------------------------------------------------------
    # Actualisation des strategies
    # --------------------------------------------------------------

    & gpupdate.exe /target:computer /force | Out-Null

    Write-Log "Strategies Windows actualisees" "OK"

    # --------------------------------------------------------------
    # Verification
    # --------------------------------------------------------------

    $AutoUpdate = Get-ItemProperty `
        -Path $WUKey `
        -Name "NoAutoUpdate" `
        -ErrorAction SilentlyContinue

    $AutoReboot = Get-ItemProperty `
        -Path $WUKey `
        -Name "NoAutoRebootWithLoggedOnUsers" `
        -ErrorAction SilentlyContinue

    if (
        $null -eq $AutoUpdate -and
        $null -eq $AutoReboot
    ) {
        Write-Log "Verification : blocages Windows Update supprimes" "OK"
    }
    else {
        Write-Log "Verification : certaines valeurs de blocage existent encore" "WARN"
    }

    # --------------------------------------------------------------
    # Demande de lancement immediat des mises a jour
    # --------------------------------------------------------------

    $UpdateChoice = Show-CGlobalPopup `
        -Message "Les parametres Windows Update ont ete restaures.`n`nSouhaitez-vous lancer maintenant une recherche, le telechargement et l'installation des mises a jour Windows ?`n`nOui : lancer Windows Update immediatement.`nNon : laisser Windows Update fonctionner automatiquement." `
        -Title "Windows Update" `
        -Buttons "YesNo" `
        -Icon "Question"

    if ($UpdateChoice -eq 'Yes') {

        Invoke-WindowsUpdate
    }
    else {

        Write-Log "Mises a jour Windows non lancees. Fonctionnement automatique conserve." "INFO"
    }

    # --------------------------------------------------------------
    # Fin
    # --------------------------------------------------------------

    Write-Log "Parametres standards CGLOBAL appliques" "OK"

    Show-CGlobalPopup `
        -Message "Parametres standards CGLOBAL appliques avec succes.`n`nLe deploiement est termine.`n`nWindows Update est active." `
        -Title "Deploiement termine" `
        -Buttons "OK" `
        -Icon "Information"

    exit 0
}
catch {

    Write-Log $_.Exception.Message "ERROR"

    exit 1
}