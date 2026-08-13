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
$TeamViewerConfigId = "u6dx34t"
$TeamViewerVersion  = "15"
$TeamViewerApiUrl   = "https://get.teamviewer.com/api/CustomDesign"

$MinValidSizeBytes = 1048576  # 1 MB

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

    # Étape 1 : Récupérer l'URL de téléchargement
    $DownloadUrl = Get-TeamViewerDownloadUrl

    # Étape 2 : Télécharger directement
    Write-Log "Telechargement de TeamViewerQS depuis $DownloadUrl"

    if (Test-Path $LocalFile) {
        Remove-Item -Path $LocalFile -Force -ErrorAction SilentlyContinue
    }

    Invoke-WebRequest `
        -Uri $DownloadUrl `
        -OutFile $LocalFile `
        -UseBasicParsing

    # Étape 3 : Vérifier le fichier téléchargé
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

    # Étape 4 : Vérifier la signature
    Test-TeamViewerSignature -FilePath $LocalFile

    # Étape 5 : Créer le raccourci
    Create-TeamViewerShortcut

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