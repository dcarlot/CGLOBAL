#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

# ------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------

$LocalFolder = "C:\_CGLOBAL"
$LocalFile   = Join-Path $LocalFolder "TeamViewerQS.exe"

$CacheMaxAgeDays = 30  # Validité du cache en jours

# TeamViewer Custom Design
$TeamViewerConfigId = "u6dx34t"
$TeamViewerVersion  = "15"
$TeamViewerApiUrl   = "https://get.teamviewer.com/api/CustomDesign"

$MinValidSizeBytes = 1048576  # 1 MB

# ------------------------------------------------------------------
# Détection de la clé USB
# ------------------------------------------------------------------

function Get-UsbCGlobalPath {
    $UsbDrives = Get-CimInstance Win32_LogicalDisk |
        Where-Object {
            $_.DriveType -eq 2
        }

    foreach ($Drive in $UsbDrives) {
        $Candidate = Join-Path $Drive.DeviceID "_CGLOBAL"

        if (Test-Path $Candidate) {
            Write-Log "Clé USB détectée : $Candidate" "OK"
            return $Candidate
        }
    }

    Write-Log "Clé USB _CGLOBAL introuvable" "WARN"
    return $null
}

# ------------------------------------------------------------------
# Vérification signature TeamViewer
# ------------------------------------------------------------------

function Test-TeamViewerSignature {
    param(
        [string]$FilePath
    )

    Write-Log "Vérification de la signature numérique"

    $Signature = Get-AuthenticodeSignature $FilePath

    if ($Signature.Status -ne 'Valid') {
        throw "Signature numérique invalide"
    }

    if ($null -eq $Signature.SignerCertificate) {
        throw "Certificat numérique absent"
    }

    if ($Signature.SignerCertificate.Subject -notmatch 'TeamViewer') {
        throw "Le signataire n'est pas TeamViewer"
    }

    Write-Log "Signature TeamViewer valide" "OK"
}

# ------------------------------------------------------------------
# Récupération URL de téléchargement
# ------------------------------------------------------------------

function Get-TeamViewerDownloadUrl {
    Write-Log "Recherche du lien réel de téléchargement TeamViewer"

    $RequestBody = @{
        ConfigId       = $TeamViewerConfigId
        Version        = $TeamViewerVersion
        IsCustomModule = $true
        Subdomain      = "1"
        ConnectionId   = ""
    } | ConvertTo-Json -Compress

    $Response = Invoke-RestMethod `
        -Uri $TeamViewerApiUrl `
        -Method Post `
        -ContentType "application/json; charset=utf-8" `
        -Body $RequestBody `
        -UseBasicParsing

    if ($null -eq $Response) {
        throw "Réponse vide depuis l'API TeamViewer"
    }

    $DownloadUrl = $Response.ToString().Trim()

    if ($DownloadUrl -eq "") {
        throw "URL de téléchargement TeamViewer vide"
    }

    Write-Log "Lien réel détecté"
    Write-Log $DownloadUrl

    return $DownloadUrl
}

# ------------------------------------------------------------------
# Création du raccourci public
# ------------------------------------------------------------------

function New-TeamViewerShortcut {
    $DesktopPath = "C:\Users\Public\Desktop"

    if (-not (Test-Path $DesktopPath)) {
        New-Item `
            -Path $DesktopPath `
            -ItemType Directory `
            -Force | Out-Null
    }

    $ShortcutPath = Join-Path `
        $DesktopPath `
        "Assistance CGLOBAL.lnk"

    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($ShortcutPath)

    $Shortcut.TargetPath       = $LocalFile
    $Shortcut.WorkingDirectory = $LocalFolder
    $Shortcut.IconLocation     = $LocalFile
    $Shortcut.Description      = "Assistance distante CGLOBAL"

    $Shortcut.Save()

    Write-Log "Raccourci public créé ou mis à jour" "OK"
}

# ------------------------------------------------------------------
# Copie vers la clé USB
# ------------------------------------------------------------------

function Copy-ToUsb {
    param(
        [string]$UsbCGlobalPath
    )

    Write-Log "Copie du fichier vers la clé USB..."

    $UsbFile = Join-Path $UsbCGlobalPath "TeamViewerQS.exe"

    try {
        Copy-Item -Path $LocalFile -Destination $UsbFile -Force
        Write-Log "Fichier copié vers $UsbFile" "OK"
    }
    catch {
        Write-Log "Échec de la copie vers USB: $($_.Exception.Message)" "WARN"
    }
}

# ------------------------------------------------------------------
# Programme principal
# ------------------------------------------------------------------

try {
    Write-Log "Début de la mise à jour TeamViewerQS"

    # ------------------------------------------------------------------
    # Étape 0 : Détecter la clé USB
    # ------------------------------------------------------------------

    $UsbCGlobalPath = Get-UsbCGlobalPath

    # ------------------------------------------------------------------
    # Étape 1 : Vérifier si le fichier existe et est récent
    # ------------------------------------------------------------------

    $DownloadNeeded = $true

    if (Test-Path $LocalFile) {
        $File = Get-Item $LocalFile
        $FileAge = (Get-Date) - $File.LastWriteTime

        Write-Log "Fichier local détecté"
        Write-Log "Date dernière modification: $($File.LastWriteTime)"
        Write-Log "Age: $($FileAge.Days) jours"

        if ($FileAge.TotalDays -le $CacheMaxAgeDays) {
            Write-Log "Fichier valide (moins de $CacheMaxAgeDays jours)" "OK"

            # Vérifier la taille
            if ($File.Length -lt $MinValidSizeBytes) {
                Write-Log "Fichier trop petit, téléchargement requis" "WARN"
            }
            else {
                # Vérifier la signature
                try {
                    Test-TeamViewerSignature -FilePath $LocalFile
                    $DownloadNeeded = $false
                    Write-Log "Utilisation du fichier en cache" "OK"
                }
                catch {
                    Write-Log "Signature invalide, téléchargement requis" "WARN"
                }
            }
        }
        else {
            Write-Log "Fichier trop ancien (plus de $CacheMaxAgeDays jours)" "WARN"
        }
    }
    else {
        Write-Log "Fichier non présent, téléchargement requis" "WARN"
    }

    # ------------------------------------------------------------------
    # Étape 2 : Télécharger si nécessaire
    # ------------------------------------------------------------------

    if ($DownloadNeeded) {
        Write-Log "Téléchargement de TeamViewerQS..." "INFO"

        # Récupérer l'URL de téléchargement
        $DownloadUrl = Get-TeamViewerDownloadUrl

        # Supprimer l'ancien fichier
        if (Test-Path $LocalFile) {
            Remove-Item -Path $LocalFile -Force -ErrorAction SilentlyContinue
        }

        # Télécharger
        Write-Log "Téléchargement depuis $DownloadUrl"
        Invoke-WebRequest `
            -Uri $DownloadUrl `
            -OutFile $LocalFile `
            -UseBasicParsing

        # Vérifier le fichier téléchargé
        if (-not (Test-Path $LocalFile)) {
            throw "Le fichier n'a pas été téléchargé"
        }

        $File = Get-Item $LocalFile
        Write-Log "Taille fichier téléchargé : $($File.Length) octets"

        if ($File.Length -lt $MinValidSizeBytes) {
            throw "Fichier téléchargé invalide : taille anormalement faible"
        }

        $SizeMB = [Math]::Round($File.Length / 1MB, 2)
        Write-Log "Fichier téléchargé : $SizeMB Mo" "OK"

        # Vérifier la signature
        Test-TeamViewerSignature -FilePath $LocalFile

        # Copier vers la clé USB (si détectée)
        if ($UsbCGlobalPath) {
            Copy-ToUsb -UsbCGlobalPath $UsbCGlobalPath
        }
        else {
            Write-Log "Impossible de copier vers USB (non détectée)" "WARN"
        }
    }

    # ------------------------------------------------------------------
    # Étape 3 : Créer le raccourci
    # ------------------------------------------------------------------

    New-TeamViewerShortcut

    Write-Log "TeamViewerQS mis à jour avec succès" "OK"

    exit 0
}
catch {
    Write-Log $_.Exception.Message "ERROR"

    if (Test-Path $LocalFile) {
        Remove-Item -Path $LocalFile -Force -ErrorAction SilentlyContinue
    }

    exit 1
}