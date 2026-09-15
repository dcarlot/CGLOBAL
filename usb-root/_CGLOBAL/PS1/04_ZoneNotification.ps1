#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

try {

    Write-Log "Configuration de la zone de notification"

    $NotifyRoot = "HKCU:\Control Panel\NotifyIconSettings"

    if (-not (Test-Path $NotifyRoot)) {

        Write-Log "Cle NotifyIconSettings absente" "WARN"
        Write-Log "Aucune icône connue à traiter" "WARN"
        exit 0
    }

    $Keys = Get-ChildItem -Path $NotifyRoot

    if ($Keys.Count -eq 0) {

        Write-Log "Aucune icône détectée" "WARN"
        exit 0
    }

    Write-Log "$($Keys.Count) icône(s) trouvée(s)"

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

    Write-Log "$SuccessCount icône(s) activée(s)" "OK"

    #
    # Vérification
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

        throw "$Failed vérification(s) en échec"
    }

    Write-Log "Vérification OK" "OK"

    Write-Log "Configuration terminée" "OK"
}
catch {

    Write-Log $_.Exception.Message "ERROR"
    exit 1
}