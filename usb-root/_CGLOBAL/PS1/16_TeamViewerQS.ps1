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
            Write-Log "Cle USB detectee : $Candidate" "OK"
            return $Candidate
        }
    }

    Write-Log "Cle USB _CGLOBAL introuvable" "WARN"
    return $null
}

# ------------------------------------------------------------------
# Vérification signature TeamViewer
# ------------------------------------------------------------------

function Test-TeamViewerSignature {
    param(
        [string]$FilePath
    )

    Write-Log "Verification de la signature numerique"

    $Signature = Get-AuthenticodeSignature $FilePath

    if ($Signature.Status -ne 'Valid') {
        throw "Signature numerique invalide"
    }

    if ($null -eq $Signature.SignerCertificate) {
        throw "Certificat numerique absent"
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
    Write-Log "Recherche du lien reel de telechargement TeamViewer"

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
        throw "Reponse vide depuis l'API TeamViewer"
    }

    $DownloadUrl = $Response.ToString().Trim()

    if ($DownloadUrl -eq "") {
        throw "URL de telechargement TeamViewer vide"
    }

    Write-Log "Lien reel detecte"
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

    Write-Log "Raccourci public cree ou mis a jour" "OK"
}

# ------------------------------------------------------------------
# Copie vers la clé USB
# ------------------------------------------------------------------

function Copy-ToUsb {
    param(
        [string]$UsbCGlobalPath
    )

    Write-Log "Copie du fichier vers la cle USB..."

    $UsbFile = Join-Path $UsbCGlobalPath "TeamViewerQS.exe"

    try {
        Copy-Item -Path $LocalFile -Destination $UsbFile -Force
        Write-Log "Fichier copie vers $UsbFile" "OK"
    }
    catch {
        Write-Log "Echec copie vers USB: $($_.Exception.Message)" "WARN"
    }
}

# ------------------------------------------------------------------
# Programme principal
# ------------------------------------------------------------------

try {
    Write-Log "Debut mise a jour TeamViewerQS"

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

        Write-Log "Fichier local detecte"
        Write-Log "Date derniere modification: $($File.LastWriteTime)"
        Write-Log "Age: $($FileAge.Days) jours"

        if ($FileAge.TotalDays -le $CacheMaxAgeDays) {
            Write-Log "Fichier valide (moins de $CacheMaxAgeDays jours)" "OK"

            # Vérifier la taille
            if ($File.Length -lt $MinValidSizeBytes) {
                Write-Log "Fichier trop petit, telechargement requis" "WARN"
            }
            else {
                # Vérifier la signature
                try {
                    Test-TeamViewerSignature -FilePath $LocalFile
                    $DownloadNeeded = $false
                    Write-Log "Utilisation du fichier en cache" "OK"
                }
                catch {
                    Write-Log "Signature invalide, telechargement requis" "WARN"
                }
            }
        }
        else {
            Write-Log "Fichier trop ancien (plus de $CacheMaxAgeDays jours)" "WARN"
        }
    }
    else {
        Write-Log "Fichier non present, telechargement requis" "WARN"
    }

    # ------------------------------------------------------------------
    # Étape 2 : Télécharger si nécessaire
    # ------------------------------------------------------------------

    if ($DownloadNeeded) {
        Write-Log "Telechargement de TeamViewerQS..." "INFO"

        # Récupérer l'URL de téléchargement
        $DownloadUrl = Get-TeamViewerDownloadUrl

        # Supprimer l'ancien fichier
        if (Test-Path $LocalFile) {
            Remove-Item -Path $LocalFile -Force -ErrorAction SilentlyContinue
        }

        # Télécharger
        Write-Log "Telechargement depuis $DownloadUrl"
        Invoke-WebRequest `
            -Uri $DownloadUrl `
            -OutFile $LocalFile `
            -UseBasicParsing

        # Vérifier le fichier téléchargé
        if (-not (Test-Path $LocalFile)) {
            throw "Le fichier n'a pas ete telecharge"
        }

        $File = Get-Item $LocalFile
        Write-Log "Taille fichier telecharge : $($File.Length) octets"

        if ($File.Length -lt $MinValidSizeBytes) {
            throw "Fichier telecharge invalide : taille anormalement faible"
        }

        $SizeMB = [Math]::Round($File.Length / 1MB, 2)
        Write-Log "Fichier telecharge : $SizeMB Mo" "OK"

        # Vérifier la signature
        Test-TeamViewerSignature -FilePath $LocalFile

        # Copier vers la clé USB (si détectée)
        if ($UsbCGlobalPath) {
            Copy-ToUsb -UsbCGlobalPath $UsbCGlobalPath
        }
        else {
            Write-Log "Impossible de copier vers USB (non detectee)" "WARN"
        }
    }

    # ------------------------------------------------------------------
    # Étape 3 : Créer le raccourci
    # ------------------------------------------------------------------

    New-TeamViewerShortcut

    Write-Log "TeamViewerQS mis a jour avec succes" "OK"

    exit 0
}
catch {
    Write-Log $_.Exception.Message "ERROR"

    if (Test-Path $LocalFile) {
        Remove-Item -Path $LocalFile -Force -ErrorAction SilentlyContinue
    }

    exit 1
}