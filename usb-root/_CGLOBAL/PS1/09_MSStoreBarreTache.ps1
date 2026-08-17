#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

try {
    Write-Log "=== SUPPRESSION MICROSOFT STORE BARRE DES TACHES ===" "INFO"

    # ------------------------------------------------------------------
    # 1. DÉPINNAGE POUR L'UTILISATEUR ACTUEL (COM)
    # ------------------------------------------------------------------
    
    Write-Log "Depinning Microsoft Store pour l'utilisateur actuel..." "INFO"
    
    try {
        $Shell = New-Object -ComObject Shell.Application
        $PinnedItems = $Shell.Namespace("shell:::{4234d49b-0245-4df3-b780-3893943456e1}").Items()
        
        foreach ($Item in $PinnedItems) {
            if ($Item.Name -match "Microsoft Store|Store") {
                $Verb = $Item.Verbs() | Where-Object { $_.Name.Replace('&','') -match 'Unpin from taskbar|Désépingler de la barre des tâches' }
                
                if ($Verb) {
                    $Verb.DoIt()
                    Write-Log "Microsoft Store depinne avec succes" "OK"
                }
            }
        }
    }
    catch {
        Write-Log "Echec depinning COM: $($_.Exception.Message)" "WARN"
    }

    # ------------------------------------------------------------------
    # 2. LAYOUT XML POUR FUTURS UTILISATEURS (APPEND)
    # ------------------------------------------------------------------
    
    Write-Log "Configuration LayoutModification.xml pour futurs utilisateurs..." "INFO"
    
    try {
        $TaskbarXml = @'
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification" xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout" xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout" xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout" Version="1">
<CustomTaskbarLayoutCollection PinListPlacement="Append">
<defaultlayout:TaskbarLayout>
<taskbar:TaskbarPinList>
<taskbar:DesktopApp DesktopApplicationLinkPath="%APPDATA%\Microsoft\Windows\Start Menu\Programs\System Tools\File Explorer.lnk" />
<taskbar:DesktopApp DesktopApplicationLinkPath="%APPDATA%\Microsoft\Windows\Start Menu\Programs\Accessories\Internet Explorer.lnk" />
</taskbar:TaskbarPinList>
</defaultlayout:TaskbarLayout>
</CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
'@
        
        $XmlPath = "$env:SystemDrive\Users\Default\AppData\Local\Microsoft\Windows\Shell"
        
        if (-not (Test-Path $XmlPath)) {
            New-Item -Path $XmlPath -ItemType Directory -Force | Out-Null
        }
        
        $TaskbarXml | Set-Content -Path "$XmlPath\LayoutModification.xml" -Encoding UTF8 -Force
        Write-Log "LayoutModification.xml cree avec succes" "OK"
    }
    catch {
        Write-Log "Echec LayoutModification.xml: $($_.Exception.Message)" "WARN"
    }

    # ------------------------------------------------------------------
    # 3. BLOCAGE VIA REGISTRE
    # ------------------------------------------------------------------
    
    Write-Log "Blocage via registre..." "INFO"
    
    try {
        $RegPath = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
        
        if (-not (Test-Path $RegPath)) {
            New-Item -Path $RegPath -Force -ErrorAction SilentlyContinue | Out-Null
        }
        
        New-ItemProperty -Path $RegPath -Name "NoPinningStoreToTaskbar" -Value 1 -PropertyType DWORD -Force -ErrorAction Stop
        Write-Log "Registre bloque avec succes" "OK"
    }
    catch {
        Write-Log "Echec registre: $($_.Exception.Message)" "WARN"
    }

    # ------------------------------------------------------------------
    # 4. MESSAGE DE SUCCÈS
    # ------------------------------------------------------------------
    
    Write-Log "=== SUPPRESSION MICROSOFT STORE TERMINE ===" "OK"
    
    exit 0
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    Write-Log $_.ScriptStackTrace "ERROR"
    exit 1
}
