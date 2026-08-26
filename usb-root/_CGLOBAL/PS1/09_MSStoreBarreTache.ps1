#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

try {
    Write-Log "=== SUPPRESSION MICROSOFT STORE BARRE DES TACHES ===" "INFO"

    $StoreUnpinned = $false

    # ------------------------------------------------------------------
    # 1. SUPPRESSION DU RACCOURCI .LNK DANS LE DOSSIER DES EPINGLES
    #    C'est la methode la plus fiable sur Windows 11.
    # ------------------------------------------------------------------
    $PinnedFolder = "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"

    if (Test-Path $PinnedFolder) {
        $StoreLinks = Get-ChildItem -Path $PinnedFolder -Filter "*.lnk" -ErrorAction SilentlyContinue |
            Where-Object { $_.BaseName -match "Microsoft Store|Store" }

        if ($StoreLinks) {
            foreach ($Link in $StoreLinks) {
                try {
                    Remove-Item -Path $Link.FullName -Force -ErrorAction Stop
                    Write-Log "Raccourci supprime : $($Link.Name)" "OK"
                    $StoreUnpinned = $true
                }
                catch {
                    Write-Log "Echec suppression raccourci $($Link.Name) : $($_.Exception.Message)" "WARN"
                }
            }
        }
        else {
            Write-Log "Aucun raccourci Microsoft Store trouve dans les epingles" "INFO"
        }
    }

    # ------------------------------------------------------------------
    # 2. DEPINNING VIA COM (FALLBACK SI PAS DE .LNK)
    # ------------------------------------------------------------------
    if (-not $StoreUnpinned) {
        Write-Log "Tentative de depinning via COM..." "INFO"

        try {
            $Shell = New-Object -ComObject Shell.Application
            $Folder = $Shell.Namespace("shell:::{4234d49b-0245-4df3-b780-3893943456e1}")

            if ($Folder) {
                $Items = $Folder.Items()

                foreach ($Item in $Items) {
                    if ($Item.Name -match "Microsoft Store|Store") {
                        $Verbs = $Item.Verbs()

                        foreach ($Verb in $Verbs) {
                            $VerbName = $Verb.Name.Replace('&','')

                            if ($VerbName -match 'Unpin from taskbar|Désépingler de la barre des tâches|Von Taskleiste lösen') {
                                $Verb.DoIt()
                                Write-Log "Microsoft Store depinne via COM" "OK"
                                $StoreUnpinned = $true
                                break
                            }
                        }
                    }
                }
            }
        }
        catch {
            Write-Log "Echec depinning COM : $($_.Exception.Message)" "WARN"
        }
    }

    # ------------------------------------------------------------------
    # 3. LAYOUT XML POUR FUTURS UTILISATEURS (REPLACE, PAS APPEND)
    #    Append ajoute des epingles ; Replace remplace le layout par defaut.
    #    On ne garde que l'Explorateur de fichiers.
    # ------------------------------------------------------------------
    Write-Log "Configuration LayoutModification.xml pour futurs utilisateurs..." "INFO"

    try {
        $TaskbarXml = @'
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate
    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"
    xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout"
    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
    Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Replace">
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
        <taskbar:DesktopApp DesktopApplicationLinkPath="%APPDATA%\Microsoft\Windows\Start Menu\Programs\System Tools\File Explorer.lnk" />
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
        Write-Log "LayoutModification.xml cree avec succes (mode Replace)" "OK"
    }
    catch {
        Write-Log "Echec LayoutModification.xml : $($_.Exception.Message)" "WARN"
    }

    # ------------------------------------------------------------------
    # 4. BLOCAGE VIA REGISTRE (HKCU + HKLM)
    # ------------------------------------------------------------------
    Write-Log "Blocage via registre..." "INFO"

    try {
        # Utilisateur courant
        $RegPathCu = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
        if (-not (Test-Path $RegPathCu)) {
            New-Item -Path $RegPathCu -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Set-ItemProperty -Path $RegPathCu -Name "NoPinningStoreToTaskbar" -Value 1 -Type DWord -Force -ErrorAction Stop
        Write-Log "Registre HKCU bloque avec succes" "OK"

        # Machine (futurs profils + politique systeme)
        $RegPathLm = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
        if (-not (Test-Path $RegPathLm)) {
            New-Item -Path $RegPathLm -Force | Out-Null
        }
        Set-ItemProperty -Path $RegPathLm -Name "NoPinningStoreToTaskbar" -Value 1 -Type DWord -Force
        Write-Log "Registre HKLM bloque avec succes" "OK"
    }
    catch {
        Write-Log "Echec registre : $($_.Exception.Message)" "WARN"
    }

    # ------------------------------------------------------------------
    # 5. REDEMARRAGE EXPLORER POUR APPLIQUER LES CHANGEMENTS
    # ------------------------------------------------------------------
    if ($StoreUnpinned) {
        Write-Log "Redemarrage de l'Explorateur pour appliquer..." "INFO"
        Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Write-Log "Explorateur redemarre" "OK"
    }

    # ------------------------------------------------------------------
    # 6. MESSAGE DE SUCCES
    # ------------------------------------------------------------------
    Write-Log "=== SUPPRESSION MICROSOFT STORE TERMINE ===" "OK"

    exit 0
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    Write-Log $_.ScriptStackTrace "ERROR"
    exit 1
}
