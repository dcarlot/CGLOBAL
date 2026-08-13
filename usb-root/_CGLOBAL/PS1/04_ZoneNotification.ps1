#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

$LogFile = "C:\_CGLOBAL\Logs\Log04_ZoneNotification.txt"

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
Initialize-CGlobalLog -LogFile $LogFile

try {

    Write-Log "Configuration de la zone de notification"

    $NotifyRoot = "HKCU:\Control Panel\NotifyIconSettings"

    if (-not (Test-Path $NotifyRoot)) {

        Write-Log "Cle NotifyIconSettings absente" "WARN"
        Write-Log "Aucune icone connue a traiter" "WARN"
        exit 0
    }

    $Keys = Get-ChildItem -Path $NotifyRoot

    if ($Keys.Count -eq 0) {

        Write-Log "Aucune icone detectee" "WARN"
        exit 0
    }

    Write-Log "$($Keys.Count) icone(s) trouvee(s)"

    $SuccessCount = 0

    foreach ($Key in $Keys) {

        try {

            New-ItemProperty `
                -Path $Key.PSPath `
                -Name "IsPromoted" `
                -Value 1 `
                -PropertyType DWord `
                -Force | Out-Null

            $SuccessCount++
        }
        catch {

            Write-Log "Impossible de modifier : $($Key.PSChildName)" "WARN"
        }
    }

    Write-Log "$SuccessCount icone(s) activee(s)" "OK"

    #
    # Verification
    #

    $Failed = 0

    foreach ($Key in $Keys) {

        try {

            $Value = (
                Get-ItemProperty `
                -Path $Key.PSPath `
                -Name IsPromoted `
                -ErrorAction Stop
            ).IsPromoted

            if ($Value -ne 1) {
                $Failed++
            }

        }
        catch {
            $Failed++
        }
    }

    if ($Failed -gt 0) {

        throw "$Failed verification(s) en echec"
    }

    Write-Log "Verification OK" "OK"

    Write-Log "Configuration terminee" "OK"
}
catch {

    Write-Log $_.Exception.Message "ERROR"
    exit 1
}