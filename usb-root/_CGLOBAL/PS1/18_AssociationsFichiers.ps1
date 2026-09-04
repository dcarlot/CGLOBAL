#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
    Associations de fichiers d'archives (.zip, .7z, .rar, ...) vers 7-Zip.

    Le forcage de l'association pour l'utilisateur DEJA CONNECTE utilise
    l'algorithme de hash UserChoice (reverse engineering documente et
    largement utilise en entreprise). Les fonctions Get-Hash, Get-HexDateTime,
    Get-UserExperience et Get-UserSid ci-dessous sont reprises telles quelles
    du projet open source PS-SFTA :

        https://github.com/DanysysTeam/PS-SFTA
        Auteurs   : Danyfirex & Dany3j
        Licence   : MIT License - Copyright (c) 2022 Danysys.

    Volontairement, ce script NE traite PAS le .pdf : sur Windows 10 1903+/11,
    le driver UCPD.sys bloque au niveau noyau toute ecriture programmatique de
    UserChoice pour .pdf (et http/https), quelle que soit la methode utilisee
    (SetUserFTA, DISM, ou cet algorithme). Voir le suivi du projet CGLOBAL.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

# ============================================================
# Algorithme UserChoice (MIT - PS-SFTA - voir en-tete du fichier)
# ============================================================
function local:Get-HexDateTime {
    [OutputType([string])]
    $now = [DateTime]::Now
    $dateTime = [DateTime]::New($now.Year, $now.Month, $now.Day, $now.Hour, $now.Minute, 0)
    $fileTime = $dateTime.ToFileTime()
    $hi = ($fileTime -shr 32)
    $low = ($fileTime -band 0xFFFFFFFFL)
    $dateTimeHex = ($hi.ToString("X8") + $low.ToString("X8")).ToLower()
    Write-Output $dateTimeHex
}

function local:Get-UserExperience {
    [OutputType([string])]
    $hardcodedExperience = "User Choice set via Windows User Experience {D18B6DD5-6124-4341-9318-804003BAFA0B}"
    $userExperienceSearch = "User Choice set via Windows User Experience"
    $userExperienceString = ""
    $user32Path = [Environment]::GetFolderPath([Environment+SpecialFolder]::SystemX86) + "\Shell32.dll"
    $fileStream = [System.IO.File]::Open($user32Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $binaryReader = New-Object System.IO.BinaryReader($fileStream)
    [Byte[]] $bytesData = $binaryReader.ReadBytes(5mb)
    $fileStream.Close()
    $dataString = [Text.Encoding]::Unicode.GetString($bytesData)
    $position1 = $dataString.IndexOf($userExperienceSearch)
    $position2 = $dataString.IndexOf("}", $position1)
    try {
        $userExperienceString = $dataString.Substring($position1, $position2 - $position1 + 1)
    }
    catch {
        $userExperienceString = $hardcodedExperience
    }
    Write-Output $userExperienceString
}

function local:Get-UserSid {
    [OutputType([string])]
    $userSid = ((New-Object System.Security.Principal.NTAccount([Environment]::UserName)).Translate([System.Security.Principal.SecurityIdentifier]).value).ToLower()
    Write-Output $userSid
}

function local:Get-Hash {
    [CmdletBinding()]
    param (
        [Parameter( Position = 0, Mandatory = $True )]
        [string]
        $BaseInfo
    )

    function local:Get-ShiftRight {
        [CmdletBinding()]
        param (
            [Parameter( Position = 0, Mandatory = $true)]
            [long] $iValue,

            [Parameter( Position = 1, Mandatory = $true)]
            [int] $iCount
        )

        if ($iValue -band 0x80000000) {
            Write-Output (( $iValue -shr $iCount) -bxor 0xFFFF0000)
        }
        else {
            Write-Output  ($iValue -shr $iCount)
        }
    }

    function local:Get-Long {
        [CmdletBinding()]
        param (
            [Parameter( Position = 0, Mandatory = $true)]
            [byte[]] $Bytes,

            [Parameter( Position = 1)]
            [int] $Index = 0
        )

        Write-Output ([BitConverter]::ToInt32($Bytes, $Index))
    }

    function local:Convert-Int32 {
        param (
            [Parameter( Position = 0, Mandatory = $true)]
            [long] $Value
        )

        [byte[]] $bytes = [BitConverter]::GetBytes($Value)
        return [BitConverter]::ToInt32( $bytes, 0)
    }

    [Byte[]] $bytesBaseInfo = [System.Text.Encoding]::Unicode.GetBytes($baseInfo)
    $bytesBaseInfo += 0x00, 0x00

    $MD5 = New-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
    [Byte[]] $bytesMD5 = $MD5.ComputeHash($bytesBaseInfo)

    $lengthBase = ($baseInfo.Length * 2) + 2
    $length = (($lengthBase -band 4) -le 1) + (Get-ShiftRight $lengthBase  2) - 1
    $base64Hash = ""

    if ($length -gt 1) {

        $map = @{PDATA = 0; CACHE = 0; COUNTER = 0 ; INDEX = 0; MD51 = 0; MD52 = 0; OUTHASH1 = 0; OUTHASH2 = 0;
            R0 = 0; R1 = @(0, 0); R2 = @(0, 0); R3 = 0; R4 = @(0, 0); R5 = @(0, 0); R6 = @(0, 0); R7 = @(0, 0)
        }

        $map.CACHE = 0
        $map.OUTHASH1 = 0
        $map.PDATA = 0
        $map.MD51 = (((Get-Long $bytesMD5) -bor 1) + 0x69FB0000L)
        $map.MD52 = ((Get-Long $bytesMD5 4) -bor 1) + 0x13DB0000L
        $map.INDEX = Get-ShiftRight ($length - 2) 1
        $map.COUNTER = $map.INDEX + 1

        while ($map.COUNTER) {
            $map.R0 = Convert-Int32 ((Get-Long $bytesBaseInfo $map.PDATA) + [long]$map.OUTHASH1)
            $map.R1[0] = Convert-Int32 (Get-Long $bytesBaseInfo ($map.PDATA + 4))
            $map.PDATA = $map.PDATA + 8
            $map.R2[0] = Convert-Int32 (($map.R0 * ([long]$map.MD51)) - (0x10FA9605L * ((Get-ShiftRight $map.R0 16))))
            $map.R2[1] = Convert-Int32 ((0x79F8A395L * ([long]$map.R2[0])) + (0x689B6B9FL * (Get-ShiftRight $map.R2[0] 16)))
            $map.R3 = Convert-Int32 ((0xEA970001L * $map.R2[1]) - (0x3C101569L * (Get-ShiftRight $map.R2[1] 16) ))
            $map.R4[0] = Convert-Int32 ($map.R3 + $map.R1[0])
            $map.R5[0] = Convert-Int32 ($map.CACHE + $map.R3)
            $map.R6[0] = Convert-Int32 (($map.R4[0] * [long]$map.MD52) - (0x3CE8EC25L * (Get-ShiftRight $map.R4[0] 16)))
            $map.R6[1] = Convert-Int32 ((0x59C3AF2DL * $map.R6[0]) - (0x2232E0F1L * (Get-ShiftRight $map.R6[0] 16)))
            $map.OUTHASH1 = Convert-Int32 ((0x1EC90001L * $map.R6[1]) + (0x35BD1EC9L * (Get-ShiftRight $map.R6[1] 16)))
            $map.OUTHASH2 = Convert-Int32 ([long]$map.R5[0] + [long]$map.OUTHASH1)
            $map.CACHE = ([long]$map.OUTHASH2)
            $map.COUNTER = $map.COUNTER - 1
        }

        [Byte[]] $outHash = @(0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
        [byte[]] $buffer = [BitConverter]::GetBytes($map.OUTHASH1)
        $buffer.CopyTo($outHash, 0)
        $buffer = [BitConverter]::GetBytes($map.OUTHASH2)
        $buffer.CopyTo($outHash, 4)

        $map = @{PDATA = 0; CACHE = 0; COUNTER = 0 ; INDEX = 0; MD51 = 0; MD52 = 0; OUTHASH1 = 0; OUTHASH2 = 0;
            R0 = 0; R1 = @(0, 0); R2 = @(0, 0); R3 = 0; R4 = @(0, 0); R5 = @(0, 0); R6 = @(0, 0); R7 = @(0, 0)
        }

        $map.CACHE = 0
        $map.OUTHASH1 = 0
        $map.PDATA = 0
        $map.MD51 = ((Get-Long $bytesMD5) -bor 1)
        $map.MD52 = ((Get-Long $bytesMD5 4) -bor 1)
        $map.INDEX = Get-ShiftRight ($length - 2) 1
        $map.COUNTER = $map.INDEX + 1

        while ($map.COUNTER) {
            $map.R0 = Convert-Int32 ((Get-Long $bytesBaseInfo $map.PDATA) + ([long]$map.OUTHASH1))
            $map.PDATA = $map.PDATA + 8
            $map.R1[0] = Convert-Int32 ($map.R0 * [long]$map.MD51)
            $map.R1[1] = Convert-Int32 ((0xB1110000L * $map.R1[0]) - (0x30674EEFL * (Get-ShiftRight $map.R1[0] 16)))
            $map.R2[0] = Convert-Int32 ((0x5B9F0000L * $map.R1[1]) - (0x78F7A461L * (Get-ShiftRight $map.R1[1] 16)))
            $map.R2[1] = Convert-Int32 ((0x12CEB96DL * (Get-ShiftRight $map.R2[0] 16)) - (0x46930000L * $map.R2[0]))
            $map.R3 = Convert-Int32 ((0x1D830000L * $map.R2[1]) + (0x257E1D83L * (Get-ShiftRight $map.R2[1] 16)))
            $map.R4[0] = Convert-Int32 ([long]$map.MD52 * ([long]$map.R3 + (Get-Long $bytesBaseInfo ($map.PDATA - 4))))
            $map.R4[1] = Convert-Int32 ((0x16F50000L * $map.R4[0]) - (0x5D8BE90BL * (Get-ShiftRight $map.R4[0] 16)))
            $map.R5[0] = Convert-Int32 ((0x96FF0000L * $map.R4[1]) - (0x2C7C6901L * (Get-ShiftRight $map.R4[1] 16)))
            $map.R5[1] = Convert-Int32 ((0x2B890000L * $map.R5[0]) + (0x7C932B89L * (Get-ShiftRight $map.R5[0] 16)))
            $map.OUTHASH1 = Convert-Int32 ((0x9F690000L * $map.R5[1]) - (0x405B6097L * (Get-ShiftRight ($map.R5[1]) 16)))
            $map.OUTHASH2 = Convert-Int32 ([long]$map.OUTHASH1 + $map.CACHE + $map.R3)
            $map.CACHE = ([long]$map.OUTHASH2)
            $map.COUNTER = $map.COUNTER - 1
        }

        $buffer = [BitConverter]::GetBytes($map.OUTHASH1)
        $buffer.CopyTo($outHash, 8)
        $buffer = [BitConverter]::GetBytes($map.OUTHASH2)
        $buffer.CopyTo($outHash, 12)

        [Byte[]] $outHashBase = @(0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
        $hashValue1 = ((Get-Long $outHash 8) -bxor (Get-Long $outHash))
        $hashValue2 = ((Get-Long $outHash 12) -bxor (Get-Long $outHash 4))

        $buffer = [BitConverter]::GetBytes($hashValue1)
        $buffer.CopyTo($outHashBase, 0)
        $buffer = [BitConverter]::GetBytes($hashValue2)
        $buffer.CopyTo($outHashBase, 4)
        $base64Hash = [Convert]::ToBase64String($outHashBase)
    }

    Write-Output $base64Hash
}

function local:Remove-UserChoiceKey {
    # Suppression via l'API registre directe : contourne les cas ou
    # Remove-Item echoue sur cette cle (ACL particuliere).
    param (
        [Parameter( Position = 0, Mandatory = $True )]
        [String]
        $Key
    )

    $code = @'
    using System;
    using System.Runtime.InteropServices;
    namespace CGlobalRegistry {
      public class Utils {
        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern int RegOpenKeyEx(UIntPtr hKey, string subKey, int ulOptions, int samDesired, out UIntPtr hkResult);

        [DllImport("advapi32.dll", SetLastError=true, CharSet = CharSet.Unicode)]
        private static extern uint RegDeleteKey(UIntPtr hKey, string subKey);

        public static void DeleteKey(string key) {
          UIntPtr hKey = UIntPtr.Zero;
          RegOpenKeyEx((UIntPtr)0x80000001u, key, 0, 0x20019, out hKey);
          RegDeleteKey((UIntPtr)0x80000001u, key);
        }
      }
    }
'@

    if (-not ("CGlobalRegistry.Utils" -as [type])) {
        Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue
    }

    try { [CGlobalRegistry.Utils]::DeleteKey($Key) } catch {}
}

function local:Update-RegistryChanges {
    # Notifie le Shell qu'une association a change (evite d'avoir a
    # redemarrer explorer.exe dans la majorite des cas).
    $code = @'
    [System.Runtime.InteropServices.DllImport("Shell32.dll")]
    private static extern int SHChangeNotify(int eventId, int flags, IntPtr item1, IntPtr item2);
    public static void Refresh() {
        SHChangeNotify(0x8000000, 0, IntPtr.Zero, IntPtr.Zero);
    }
'@

    if (-not ("CGlobalSHChange.Notify" -as [type])) {
        Add-Type -MemberDefinition $code -Namespace CGlobalSHChange -Name Notify -ErrorAction SilentlyContinue
    }

    try { [CGlobalSHChange.Notify]::Refresh() } catch {}
}

function local:Set-CGlobalFileAssociation {
    <#
        Force l'association ProgId <-> Extension pour l'UTILISATEUR COURANT
        en ecrivant directement une cle UserChoice avec un hash valide.
        Fonctionne pour les extensions NON protegees par UCPD.sys
        (.zip, .7z, .rar, etc. - pas .pdf/http/https).
    #>
    param (
        [Parameter(Mandatory = $true)] [String] $Extension,
        [Parameter(Mandatory = $true)] [String] $ProgId
    )

    $userSid = Get-UserSid
    $userExperience = Get-UserExperience
    $userDateTime = Get-HexDateTime

    $baseInfo = "$Extension$userSid$ProgId$userDateTime$userExperience".ToLower()
    $progHash = Get-Hash $baseInfo

    if ([string]::IsNullOrEmpty($progHash)) {
        throw "Calcul du hash UserChoice vide pour $Extension"
    }

    # Signale l'app comme "ne pas notifier" pour cette extension (evite le
    # toast Windows "vous avez change d'application par defaut")
    try {
        [Microsoft.Win32.Registry]::SetValue(
            "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts",
            "$ProgId" + "_" + "$Extension", 0x0)
    }
    catch {}

    $keyPath = "Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\UserChoice"
    Remove-UserChoiceKey $keyPath

    $keyPathFull = "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\UserChoice"
    [Microsoft.Win32.Registry]::SetValue($keyPathFull, "Hash", $progHash)
    [Microsoft.Win32.Registry]::SetValue($keyPathFull, "ProgId", $ProgId)

    # Verification immediate : on relit ce qu'on vient d'ecrire.
    $verif = (Get-ItemProperty "HKCU:\$keyPath" -ErrorAction SilentlyContinue).ProgId
    if ($verif -ne $ProgId) {
        throw "Verification post-ecriture echouee pour $Extension (lu : '$verif', attendu : '$ProgId')"
    }
}

# ============================================================
# SCRIPT PRINCIPAL
# ============================================================
try {
    Write-Log "=== ASSOCIATIONS DE FICHIERS ARCHIVES (7-Zip) ===" "INFO"

    $ModificationFaite = $false

    # ------------------------------------------------------------
    # 1. LOCALISER 7-ZIP (via App Paths)
    # ------------------------------------------------------------
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
        Write-Log "=== ASSOCIATIONS TERMINEES (rien a faire) ===" "OK"
        exit 0
    }

    Write-Log "7-Zip trouve : $sevenZipFM" "OK"

    # ------------------------------------------------------------
    # 2. CREER LES ProgID 7-ZIP
    # ------------------------------------------------------------
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

    # ------------------------------------------------------------
    # 3. FORCER L'ASSOCIATION POUR L'UTILISATEUR COURANT
    # ------------------------------------------------------------
    Write-Log "Application des associations pour l utilisateur courant..." "INFO"

    foreach ($ext in $archiveExtensions) {
        $progId = "7-Zip$ext"
        try {
            Set-CGlobalFileAssociation -Extension $ext -ProgId $progId
            Write-Log "  $ext -> $progId : OK (verifie)" "OK"
            $ModificationFaite = $true
        }
        catch {
            Write-Log "  $ext -> $progId : ECHEC - $($_.Exception.Message)" "ERROR"
        }
    }

    Update-RegistryChanges

    # ------------------------------------------------------------
    # 4. REDEMARRAGE EXPLORER
    # ------------------------------------------------------------
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
    exit 0
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    exit 1
}
