#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

try {
    Write-Log "=== ASSOCIATIONS DE FICHIERS PAR DEFAUT ===" "INFO"

    $ModificationFaite = $false

    # ============================================================
    # 1. LOCALISER ADOBE READER (via App Paths)
    # ============================================================
    Write-Log "Recherche Adobe Reader..." "INFO"

    $acrobatExe = $null
    foreach ($name in @('Acrobat.exe', 'AcroRd32.exe')) {
        $key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$name"
        if (Test-Path $key) {
            $acrobatExe = (Get-ItemProperty $key).'(default)'
            break
        }
    }

    if (-not $acrobatExe) {
        # Fallback chemins directs
        $fallbackPaths = @(
            "${env:ProgramFiles}\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe",
            "${env:ProgramFiles(x86)}\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe",
            "${env:ProgramFiles}\Adobe\Acrobat DC\Acrobat\Acrobat.exe",
            "${env:ProgramFiles(x86)}\Adobe\Acrobat DC\Acrobat\Acrobat.exe"
        )
        foreach ($p in $fallbackPaths) {
            if (Test-Path $p) {
                $acrobatExe = $p
                break
            }
        }
    }

    if (-not $acrobatExe) {
        Write-Log "Adobe Reader introuvable, association PDF ignoree" "WARN"
    }
    else {
        Write-Log "Adobe Reader trouve : $acrobatExe" "OK"
    }

    # ============================================================
    # 2. LOCALISER 7-ZIP (via App Paths)
    # ============================================================
    Write-Log "Recherche 7-Zip..." "INFO"

    $sevenZipFM = $null
    $key7z = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\7zFM.exe"
    if (Test-Path $key7z) {
        $sevenZipFM = (Get-ItemProperty $key7z).'(default)'
    }
    if (-not $sevenZipFM) {
        $fallback7z = @(
            "${env:ProgramFiles}\7-Zip\7zFM.exe",
            "${env:ProgramFiles(x86)}\7-Zip\7zFM.exe"
        )
        foreach ($p in $fallback7z) {
            if (Test-Path $p) {
                $sevenZipFM = $p
                break
            }
        }
    }

    if (-not $sevenZipFM) {
        Write-Log "7-Zip introuvable, associations archives ignorees" "WARN"
    }
    else {
        Write-Log "7-Zip trouve : $sevenZipFM" "OK"
    }

    # ============================================================
    # 3. RECUPERER LE ProgID PDF EXISTANT
    # ============================================================
    $pdfProgId = $null
    if ($acrobatExe) {
        $candidatePaths = @(
            "Registry::HKEY_CLASSES_ROOT\.pdf\OpenWithProgids",
            "HKCU:\Software\Classes\.pdf\OpenWithProgids"
        )
        foreach ($p in $candidatePaths) {
            if (Test-Path $p) {
                $names = (Get-Item $p).Property
                $match = $names | Where-Object { $_ -match 'Acro' } | Select-Object -First 1
                if ($match) { $pdfProgId = $match; break }
            }
        }

        if (-not $pdfProgId) {
            # Fallback ProgID canonique
            $pdfProgId = "Acrobat.Document.DC"
            Write-Log "ProgID PDF force par defaut : $pdfProgId" "WARN"
        }
        else {
            Write-Log "ProgID PDF detecte : $pdfProgId" "OK"
        }
    }

    # ============================================================
    # 4. CREER LES ProgID 7-ZIP (si 7-Zip est installe)
    # ============================================================
    $archiveExtensions = @()
    if ($sevenZipFM) {
        $archiveExtensions = @('.zip', '.7z', '.rar', '.iso', '.tar', '.gz', '.bz2', '.cab')

        Write-Log "Creation des ProgID 7-Zip..." "INFO"
        foreach ($ext in $archiveExtensions) {
            $progId = "7-Zip$ext"
            $cmdPath = "Registry::HKEY_CLASSES_ROOT\$progId\shell\open\command"
            $iconPath = "Registry::HKEY_CLASSES_ROOT\$progId\DefaultIcon"

            try {
                New-Item -Path $cmdPath -Force -ErrorAction Stop | Out-Null
                Set-ItemProperty -Path $cmdPath -Name '(Default)' -Value "`"$sevenZipFM`" `"%1`"" -ErrorAction Stop
                Set-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\$progId" -Name '(Default)' -Value "Archive $ext" -ErrorAction Stop
                New-Item -Path $iconPath -Force -ErrorAction Stop | Out-Null
                Set-ItemProperty -Path $iconPath -Name '(Default)' -Value "$sevenZipFM,0" -ErrorAction Stop
                Write-Log "  ProgID cree : $progId" "OK"
            }
            catch {
                Write-Log "  Echec creation ProgID $progId : $($_.Exception.Message)" "WARN"
            }
        }
    }

    # ============================================================
    # 5. GENERER LE XML ET IMPORTER VIA DISM
    # ============================================================
    if ($acrobatExe -or $sevenZipFM) {
        Write-Log "Generation du XML DefaultAppAssociations..." "INFO"

        $assocLines = New-Object System.Collections.Generic.List[string]

        if ($acrobatExe -and $pdfProgId) {
            $assocLines.Add("  <Association Identifier=`.pdf` ProgId=`$pdfProgId` ApplicationName=`Adobe Acrobat Reader` />")
        }

        if ($sevenZipFM) {
            foreach ($ext in $archiveExtensions) {
                $progId = "7-Zip$ext"
                $assocLines.Add("  <Association Identifier=`$ext` ProgId=`$progId` ApplicationName=`7-Zip` />")
            }
        }

        if ($assocLines.Count -gt 0) {
            $xmlContent = "<?xml version=`"1.0`" encoding=`"UTF-8`"?>`r`n<DefaultAssociations>`r`n" + ($assocLines -join "`r`n") + "`r`n</DefaultAssociations>"
            $xmlPath = Join-Path $env:TEMP "CGLOBAL_AppAssociations.xml"
            Set-Content -Path $xmlPath -Value $xmlContent -Encoding UTF8 -Force
            Write-Log "Fichier XML genere : $xmlPath" "OK"

            # Import DISM
            Write-Log "Import via DISM..." "INFO"
            $dismArgs = "/online /Import-DefaultAppAssociations:`"$xmlPath`""
            $proc = Start-Process -FilePath "dism.exe" -ArgumentList $dismArgs -Wait -PassThru -NoNewWindow

            if ($proc.ExitCode -eq 0) {
                Write-Log "Import DISM reussi" "OK"
                $ModificationFaite = $true
            }
            else {
                Write-Log "DISM a renvoye le code $($proc.ExitCode)" "WARN"
            }
        }
    }

    # ============================================================
    # 6. SUPPRESSION SILENCIEUSE UserChoice (utilisateur courant)
    # ============================================================
    Write-Log "Nettoyage UserChoice pour l utilisateur courant..." "INFO"

    $allExts = @('.pdf')
    if ($sevenZipFM) { $allExts += $archiveExtensions }

    foreach ($ext in $allExts) {
        # Redirection geree entierement par cmd.exe (>nul 2>&1) : PowerShell ne voit
        # jamais le flux d'erreur de reg.exe, donc $ErrorActionPreference = 'Stop'
        # ne peut pas transformer un "Acces refuse" (cle protegee UCPD/hash) en exception.
        cmd.exe /c "reg.exe delete `"HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$ext\UserChoice`" /f >nul 2>&1"
    }
    Write-Log "UserChoice nettoyes (erreurs silencieusement ignorees)" "OK"

    # ============================================================
    # 7. REDEMARRAGE EXPLORER
    # ============================================================
    if ($ModificationFaite) {
        Write-Log "Redemarrage de l Explorateur pour prise en compte..." "INFO"
        Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-Process "explorer.exe"
        Write-Log "Explorateur redemarre" "OK"
    }
    else {
        Write-Log "Aucune association modifiee" "WARN"
    }

    Write-Log "=== ASSOCIATIONS TERMINEES ===" "OK"
    Write-Log "Note : un redemarrage complet de la session est recommande pour que Windows applique bien les nouveaux choix sur le profil courant." "INFO"
    exit 0
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    exit 1
}
