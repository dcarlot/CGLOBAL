#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

try {
    Write-Log "=== MASQUAGE DES WIDGETS ===" "INFO"

    # ------------------------------------------------------------------
    # 1. ARRÊT DU PROCESSUS WIDGETS
    # ------------------------------------------------------------------
    
    Write-Log "Arrêt des processus Widgets..." "INFO"
    
    Get-Process *Widget* -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    
    Write-Log "Processus Widgets arrêtés" "OK"

    # ------------------------------------------------------------------
    # 2. DÉTECTION DU PACKAGE WIDGETS
    # ------------------------------------------------------------------
    
    Write-Log "Recherche du package Windows Web Experience Pack..." "INFO"
    
    $WidgetsPackage = Get-AppxPackage *WebExperience* -ErrorAction SilentlyContinue
    $WidgetsProvisioned = Get-AppxProvisionedPackage -Online | Where-Object { $_.PackageName -like "*WebExperience*" }
    
    if ($null -eq $WidgetsPackage -and $null -eq $WidgetsProvisioned) {
        Write-Log "Package Widgets non installé ou déjà supprimé" "OK"
        exit 0
    }
    
    if ($null -ne $WidgetsPackage) {
        Write-Log "Package détecté: $($WidgetsPackage.Name)" "WARN"
    }
    if ($null -ne $WidgetsProvisioned) {
        Write-Log "Package provisionné détecté: $($WidgetsProvisioned.PackageName)" "WARN"
    }

    # ------------------------------------------------------------------
    # 3. DÉSINSTALLATION POUR TOUS LES UTILISATEURS EXISTANTS
    # ------------------------------------------------------------------
    
    if ($null -ne $WidgetsPackage) {
        Write-Log "Désinstallation pour tous les utilisateurs existants..." "INFO"
        
        try {
            Get-AppxPackage -AllUsers *WebExperience* | Remove-AppxPackage -AllUsers -ErrorAction Stop
            Write-Log "Package désinstallé pour tous les utilisateurs" "OK"
        }
        catch {
            Write-Log "Échec de la désinstallation: $($_.Exception.Message)" "ERROR"
            exit 1
        }
    }

    # ------------------------------------------------------------------
    # 4. SUPPRESSION DU PROVISIONING (FUTURS UTILISATEURS)
    # ------------------------------------------------------------------
    
    if ($null -ne $WidgetsProvisioned) {
        Write-Log "Suppression du provisioning pour les futurs utilisateurs..." "INFO"
        
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $WidgetsProvisioned.PackageName -ErrorAction Stop
            Write-Log "Provisioning supprimé avec succès" "OK"
        }
        catch {
            Write-Log "Échec de la suppression du provisioning: $($_.Exception.Message)" "WARN"
        }
    }

    # ------------------------------------------------------------------
    # 5. RESTART EXPLORER
    # ------------------------------------------------------------------
    
    Write-Log "Redémarrage de l'Explorateur..." "INFO"
    
    try {
        Stop-Process -Name "explorer" -Force -ErrorAction Stop
        Write-Log "Explorateur redémarré" "OK"
    }
    catch {
        Write-Log "Échec du redémarrage de l'Explorateur: $($_.Exception.Message)" "WARN"
    }

    # ------------------------------------------------------------------
    # 6. MESSAGE DE SUCCÈS
    # ------------------------------------------------------------------
    
    Write-Log "=== MASQUAGE DES WIDGETS TERMINÉ ===" "OK"
    
    exit 0
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    Write-Log $_.ScriptStackTrace "ERROR"
    exit 1
}
