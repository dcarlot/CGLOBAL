#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------

$LogFile = "C:\_CGLOBAL\Logs\Log16_TeamViewerQS.txt"

$LocalFolder = "C:\_CGLOBAL"
$LocalFile   = Join-Path $LocalFolder "TeamViewerQS.exe"

# TeamViewer Custom Design
$ApiUrl = "https://get.teamviewer.com/api/CustomDesign/Download?id=8m5m8u4"

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
Initialize-CGlobalLog -LogFile $LogFile

if (-not (Test-Path $LocalFolder)) {
    New-Item `
        -Path $LocalFolder `
        -ItemType Directory `
        -Force | Out-Null
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
# Création du raccourci public
# ------------------------------------------------------------------

function Create-TeamViewerShortcut {

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
# Programme principal
# ------------------------------------------------------------------

try {

    Write-Log "Debut mise a jour TeamViewerQS"

    Write-Log "Recuperation URL TeamViewer"

    $ApiResponse = Invoke-RestMethod `
        -Uri $ApiUrl `
        -Method Get

    if (-not $ApiResponse.downloadUrl) {
        throw "URL de telechargement absente"
    }

    $DownloadUrl = $ApiResponse.downloadUrl

    Write-Log "Telechargement de TeamViewerQS"

    if (Test-Path $LocalFile) {
        Remove-Item `
            -Path $LocalFile `
            -Force `
            -ErrorAction SilentlyContinue
    }

    Invoke-WebRequest `
        -Uri $DownloadUrl `
        -OutFile $LocalFile `
        -UseBasicParsing

    if (-not (Test-Path $LocalFile)) {
        throw "Le fichier n'a pas ete telecharge"
    }

    $SizeMB = [Math]::
        ((Get-Item $LocalFile).Length / 1MB),
        2
    )

    Write-Log "Fichier telecharge : $SizeMB Mo" "OK"

    Test-TeamViewerSignature `
        -FilePath $LocalFile

    Create-TeamViewerShortcut

    Write-Log "TeamViewerQS mis a jour avec succes" "OK"

    exit 0
}
catch {

    Write-Log $_.Exception.Message "ERROR"

    exit 1
}