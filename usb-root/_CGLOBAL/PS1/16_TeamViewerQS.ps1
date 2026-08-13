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

# TeamViewer Custom Design
$ApiUrl = "https://get.teamviewer.com/api/CustomDesign/Download?id=8m5m8u4"

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

    $DownloadUrl = $null
    $maxAttempts = 3

    for ($i = 1; $i -le $maxAttempts; $i++) {
        try {
            $ApiResponse = Invoke-RestMethod -Uri $ApiUrl -Method Get -ErrorAction Stop
            if ($ApiResponse -and $ApiResponse.downloadUrl) {
                $DownloadUrl = $ApiResponse.downloadUrl
                break
            }
            else {
                Write-Log "API renvoyee mais sans 'downloadUrl'" "WARN"
                break
            }
        }
        catch {
            Write-Log "Tentative $i : erreur appel API - $($_.Exception.Message)" "WARN"
            if ($i -lt $maxAttempts) { Start-Sleep -Seconds (2 * $i) }
        }
    }

    if (-not $DownloadUrl) {
        Write-Log "API indisponible ou mal formee, tentative de fallback vers get.teamviewer.com/cglobal" "WARN"
        $FallbackUrl = 'https://get.teamviewer.com/cglobal'
        try {
            if (Test-Path $LocalFile) { Remove-Item -Path $LocalFile -Force -ErrorAction SilentlyContinue }
            Invoke-WebRequest -Uri $FallbackUrl -OutFile $LocalFile -UseBasicParsing -ErrorAction Stop
        }
        catch {
            throw "Impossible d'obtenir TeamViewer via API ou fallback : $($_.Exception.Message)"
        }
    }
    else {
        Write-Log "Telechargement de TeamViewerQS depuis $DownloadUrl"

        if (Test-Path $LocalFile) {
            Remove-Item -Path $LocalFile -Force -ErrorAction SilentlyContinue
        }

        Invoke-WebRequest -Uri $DownloadUrl -OutFile $LocalFile -UseBasicParsing -ErrorAction Stop
    }

    if (-not (Test-Path $LocalFile)) {
        throw "Le fichier n'a pas ete telecharge"
    }

    $SizeMB = [Math]::Round(
        (Get-Item $LocalFile).Length / 1MB,
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