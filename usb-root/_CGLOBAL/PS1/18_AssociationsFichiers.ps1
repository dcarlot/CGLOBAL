#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

# ============================================================
# FONCTIONS AUXILIAIRES
# ============================================================

function Set-UserAssociation {
    param(
        [string]$Extension,
        [string]$ProgID
    )
    # Supprimer UserChoice (contourne UCPD)
    & reg.exe delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\UserChoice" /f 2>$null | Out-Null
    # Definir le ProgID
    & reg.exe add "HKCU\Software\Classes\$Extension" /ve /d "$ProgID" /f | Out-Null
}

function Set-DefaultUserAssociation {
    param(
        [string]$Extension,
        [string]$ProgID,
        [string]$TempHive = "CGLOBAL_DefaultUser_Assoc"
    )
    $DefaultUserPath = "C:\Users\Default\NTUSER.DAT"

    if (-not (Test-Path $DefaultUserPath)) {
        Write-Log "NTUSER.DAT par defaut introuvable" "WARN"
        return $false
    }

    # Charger la ruche
    $LoadResult = & reg.exe load "HKLM\$TempHive" "$DefaultUserPath" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Echec chargement NTUSER.DAT : $LoadResult" "WARN"
        return $false
    }

    try {
        $KeyPath = "HKLM\$TempHive\Software\Classes\$Extension"
        & reg.exe add "$KeyPath" /ve /d "$ProgID" /f | Out-Null
        Write-Log "Association $Extension -> $ProgID ecrite dans le profil par defaut" "OK"
        return $true
    }
    catch {
        Write-Log "Erreur ecriture profil par defaut pour $Extension : $($_.Exception.Message)" "WARN"
        return $false
    }
    finally {
        # Decharger proprement
        [gc]::Collect()
        [gc]::WaitForPendingFinalizers()
        Start-Sleep -Milliseconds 500
        & reg.exe unload "HKLM\$TempHive" 2>&1 | Out-Null
    }
}

# ============================================================
# SCRIPT PRINCIPAL
# ============================================================

try {
    Write-Log "=== ASSOCIATIONS DE FICHIERS PAR DEFAUT ===" "INFO"

    $ModificationFaite = $false

    # ============================================================
    # ADOBE READER -> PDF
    # ============================================================
    Write-Log "Configuration Adobe Reader pour les PDF..." "INFO"

    $AdobePaths = @(
        "${env:ProgramFiles}\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe",
        "${env:ProgramFiles(x86)}\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe",
        "${env:ProgramFiles}\Adobe\Acrobat DC\Acrobat\Acrobat.exe",
        "${env:ProgramFiles(x86)}\Adobe\Acrobat DC\Acrobat\Acrobat.exe"
    )

    $AdobeFound = $false
    foreach ($Path in $AdobePaths) {
        if (Test-Path $Path) {
            Write-Log "Adobe detecte : $Path" "OK"
            $AdobeFound = $true
            break
        }
    }

    if ($AdobeFound) {
        $PdfProgID = $null
        $PossibleProgIDs = @("AcroExch.Document.DC", "Acrobat.Document.DC", "AcroExch.Document")

        foreach ($PID in $PossibleProgIDs) {
            if (Test-Path "HKLM:\SOFTWARE\Classes\$PID") {
                $PdfProgID = $PID
                Write-Log "ProgID PDF trouve : $PdfProgID" "OK"
                break
            }
        }

        if ($PdfProgID) {
            # Utilisateur courant
            Set-UserAssociation -Extension ".pdf" -ProgID $PdfProgID
            Write-Log "Association .pdf -> $PdfProgID (utilisateur courant)" "OK"

            # Profil par defaut (futurs utilisateurs)
            $DefaultOk = Set-DefaultUserAssociation -Extension ".pdf" -ProgID $PdfProgID
            if ($DefaultOk) {
                Write-Log "Association .pdf -> $PdfProgID (profil par defaut)" "OK"
            }

            $ModificationFaite = $true
        }
        else {
            Write-Log "Aucun ProgID Adobe trouve dans le registre" "WARN"
        }
    }
    else {
        Write-Log "Adobe Reader non detecte, association PDF ignoree" "WARN"
    }

    # ============================================================
    # 7-ZIP -> ARCHIVES
    # ============================================================
    Write-Log "Configuration 7-Zip pour les archives..." "INFO"

    $7zipPaths = @(
        "${env:ProgramFiles}\7-Zip\7zFM.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7zFM.exe"
    )

    $7zipFound = $false
    foreach ($Path in $7zipPaths) {
        if (Test-Path $Path) {
            Write-Log "7-Zip detecte : $Path" "OK"
            $7zipFound = $true
            break
        }
    }

    if ($7zipFound) {
        $ArchiveExts = @('.zip', '.7z', '.rar', '.tar', '.gz', '.bz2', '.xz', '.iso', '.cab', '.wim')

        foreach ($Ext in $ArchiveExts) {
            $ExtClean = $Ext.TrimStart('.')
            $ProgID = "7-Zip.$ExtClean"

            if (Test-Path "HKLM:\SOFTWARE\Classes\$ProgID") {
                # Utilisateur courant
                Set-UserAssociation -Extension $Ext -ProgID $ProgID
                Write-Log "Association $Ext -> $ProgID (utilisateur courant)" "OK"

                # Profil par defaut
                $DefaultOk = Set-DefaultUserAssociation -Extension $Ext -ProgID $ProgID
                if ($DefaultOk) {
                    Write-Log "Association $Ext -> $ProgID (profil par defaut)" "OK"
                }

                $ModificationFaite = $true
            }
            else {
                Write-Log "ProgID $ProgID non trouve, $Ext ignore" "WARN"
            }
        }
    }
    else {
        Write-Log "7-Zip non detecte, associations archives ignorees" "WARN"
    }

    # ============================================================
    # REDEMARRAGE EXPLORER
    # ============================================================
    if ($ModificationFaite) {
        Write-Log "Redemarrage de l'Explorateur pour appliquer les associations..." "INFO"
        Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Write-Log "Explorateur redemarre" "OK"
    }
    else {
        Write-Log "Aucune association modifiee" "WARN"
    }

    Write-Log "=== ASSOCIATIONS TERMINEES ===" "OK"
    exit 0
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    exit 1
}
