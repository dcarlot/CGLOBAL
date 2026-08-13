#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$LogFolder = "C:\_CGLOBAL\Logs"
$LogFile   = "$LogFolder\Log16_TeamViewerQS.txt"

$LocalFile = "C:\_CGLOBAL\TeamViewerQS.exe"

$TempFolder = "C:\_CGLOBAL\Temp"
$TempFile   = Join-Path $TempFolder "TeamViewerQS_New.exe"

$TeamViewerConfigId = "u6dx34t"
$TeamViewerVersion  = "15"

$TeamViewerPageUrl = "https://get.teamviewer.com/cglobal"
$TeamViewerApiUrl  = "https://get.teamviewer.com/api/CustomDesign"

$MinValidSizeBytes = 1048576

if (-not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}

if (-not (Test-Path $TempFolder)) {
    New-Item -Path $TempFolder -ItemType Directory -Force | Out-Null
}

function Write-Log {

    param(
        [string]$Message,

        [ValidateSet('INFO','OK','WARN','ERROR')]
        [string]$Level = 'INFO'
    )

    $Line = "[{0}] [{1,-5}] {2}" -f `
        (Get-Date -Format "HH:mm:ss"), `
        $Level, `
        $Message

    Add-Content -Path $LogFile -Value $Line -Encoding UTF8

    $Color = @{
        INFO  = 'Cyan'
        OK    = 'Green'
        WARN  = 'Yellow'
        ERROR = 'Red'
    }

    Write-Host $Line -ForegroundColor $Color[$Level]
}

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
        throw "Réponse vide depuis l API TeamViewer"
    }

    $DownloadUrl = $Response.ToString().Trim()

    if ($DownloadUrl -eq "") {
        throw "URL de téléchargement TeamViewer vide"
    }

    if ($DownloadUrl -notmatch "^https://customdesignservice\.teamviewer\.com/download/windows/v15/$TeamViewerConfigId/TeamViewerQS\.exe\?") {
        throw "URL TeamViewer inattendue : $DownloadUrl"
    }

    Write-Log "Lien réel détecté"
    Write-Log $DownloadUrl

    return $DownloadUrl
}

function Test-DownloadedTeamViewerFile {

    param(
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath)) {
        throw "Fichier télécharge introuvable"
    }

    $File = Get-Item -Path $FilePath

    Write-Log "Taille fichier télécharge : $($File.Length) octets"

    if ($File.Length -lt $MinValidSizeBytes) {
        throw "Fichier télécharge invalide : taille anormalement faible"
    }

    $Signature = Get-AuthenticodeSignature -FilePath $FilePath

    Write-Log "Signature Authenticode : $($Signature.Status)"

    if ($null -ne $Signature.SignerCertificate) {
        Write-Log "Signataire : $($Signature.SignerCertificate.Subject)"
    }

    if ($Signature.Status -ne "Valid") {
        throw "Signature Authenticode invalide"
    }

    if ($null -eq $Signature.SignerCertificate) {
        throw "Certificat signataire introuvable"
    }

    if ($Signature.SignerCertificate.Subject -notmatch "TeamViewer") {
        throw "Le signataire ne semble pas être TeamViewer"
    }

    Write-Log "Fichier TeamViewer téléchargé valide" "OK"
}

function Copy-TeamViewerFile {

    param(
        [string]$SourceFile,
        [string]$DestinationFile,
        [string]$Label
    )

    Copy-Item `
        -Path $SourceFile `
        -Destination $DestinationFile `
        -Force

    $SourceHash = (
        Get-FileHash `
            -Path $SourceFile `
            -Algorithm SHA256
    ).Hash

    $DestinationHash = (
        Get-FileHash `
            -Path $DestinationFile `
            -Algorithm SHA256
    ).Hash

    if ($SourceHash -ne $DestinationHash) {
        throw "Vérification hash échouée après copie : $Label"
    }

    Write-Log "$Label OK" "OK"
}

function Create-TeamViewerShortcut {

    $ShortcutPath = "C:\Users\Public\Desktop\Assistance CGLOBAL.lnk"

    $TargetPath = "C:\_CGLOBAL\TeamViewerQS.exe"

    if (-not (Test-Path $TargetPath)) {

        Write-Log "TeamViewerQS.exe introuvable : impossible de creer le raccourci" "WARN"

        return
    }

    $WshShell = New-Object -ComObject WScript.Shell

    $Shortcut = $WshShell.CreateShortcut($ShortcutPath)

    $Shortcut.TargetPath = $TargetPath
    $Shortcut.WorkingDirectory = Split-Path $TargetPath
    $Shortcut.IconLocation = $TargetPath
    $Shortcut.Description = "Assistance a distance CGLOBAL"

    $Shortcut.Save()

    Write-Log "Raccourci Assistance CGLOBAL cree ou mis a jour" "OK"
}

function Remove-TempFolderIfEmpty {

    if (-not (Test-Path $TempFolder)) {
        return
    }

    $RemainingItems = Get-ChildItem `
        -Path $TempFolder `
        -Force `
        -ErrorAction SilentlyContinue

    if ($RemainingItems.Count -eq 0) {

        Remove-Item `
            -Path $TempFolder `
            -Force `
            -ErrorAction SilentlyContinue

        Write-Log "Dossier Temp supprime" "OK"
    }
}

try {

    $UsbCGlobalPath = Get-UsbCGlobalPath

    Write-Log "Vérification de TeamViewer QuickSupport"

    if (Test-Path $TempFile) {
        Remove-Item `
            -Path $TempFile `
            -Force `
            -ErrorAction SilentlyContinue
    }

    $RealDownloadUrl = Get-TeamViewerDownloadUrl

    Write-Log "Téléchargement de la version en ligne"

    Invoke-WebRequest `
        -Uri $RealDownloadUrl `
        -OutFile $TempFile `
        -UseBasicParsing

    Test-DownloadedTeamViewerFile -FilePath $TempFile

    $OnlineHash = (
        Get-FileHash `
            -Path $TempFile `
            -Algorithm SHA256
    ).Hash

    Write-Log "Hash distant : $OnlineHash"

    if (-not (Test-Path $LocalFile)) {

        Write-Log "Fichier local absent : installation initiale" "WARN"

        Copy-TeamViewerFile `
            -SourceFile $TempFile `
            -DestinationFile $LocalFile `
            -Label "Copie vers C:\_CGLOBAL"
		
		Create-TeamViewerShortcut

        if ($null -ne $UsbCGlobalPath) {

            $UsbFile = Join-Path `
                $UsbCGlobalPath `
                "TeamViewerQS.exe"

            Copy-TeamViewerFile `
                -SourceFile $TempFile `
                -DestinationFile $UsbFile `
                -Label "Copie vers la clé USB"
        }
        else {

            Write-Log "Clé USB absente : copie USB ignorée" "WARN"
        }

        Remove-Item `
            -Path $TempFile `
            -Force `
            -ErrorAction SilentlyContinue

        Remove-TempFolderIfEmpty
		
		Write-Log "Installation initiale TeamViewerQS terminée" "OK"

        exit 0
    }

    Write-Log "Calcul de l empreinte locale"

    $LocalHash = (
        Get-FileHash `
            -Path $LocalFile `
            -Algorithm SHA256
    ).Hash

    Write-Log "Hash local   : $LocalHash"

    if ($LocalHash -eq $OnlineHash) {

        Write-Log "TeamViewerQS est déjà a jour" "OK"

        Remove-Item `
            -Path $TempFile `
            -Force `
            -ErrorAction SilentlyContinue

        Remove-TempFolderIfEmpty
		
		exit 0
    }

    Write-Log "Nouvelle version TeamViewerQS détectée" "WARN"

    Copy-TeamViewerFile `
        -SourceFile $TempFile `
        -DestinationFile $LocalFile `
        -Label "Mise a jour du fichier local"
	
    if ($null -ne $UsbCGlobalPath) {

        $UsbFile = Join-Path `
            $UsbCGlobalPath `
            "TeamViewerQS.exe"

        Copy-TeamViewerFile `
            -SourceFile $TempFile `
            -DestinationFile $UsbFile `
            -Label "Mise a jour de la clé USB"
    }
    else {

        Write-Log "Clé USB absente : mise a jour USB ignorée" "WARN"
    }

    Remove-Item `
        -Path $TempFile `
        -Force `
        -ErrorAction SilentlyContinue

    Remove-TempFolderIfEmpty
	
	Write-Log "Vérification TeamViewerQS terminée" "OK"
}

catch {

    Write-Log $_.Exception.Message "ERROR"

    if (Test-Path $TempFile) {

        Remove-Item `
            -Path $TempFile `
            -Force `
            -ErrorAction SilentlyContinue
    }

    Remove-TempFolderIfEmpty

    exit 1
}