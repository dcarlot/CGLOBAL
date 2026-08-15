#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

try {
    Write-Log "=== SUPPRESSION MICROSOFT STORE BARRE DES TACHES ===" "INFO"

    # ------------------------------------------------------------------
    # 1. DÉPINNAGE POUR L'UTILISATEUR ACTUEL
    # ------------------------------------------------------------------
    
    Write-Log "Depinning Microsoft Store pour l'utilisateur actuel..." "INFO"
    
    try {
        $appname = "Store"
        $shell = New-Object -Com Shell.Application
        $namespace = $shell.NameSpace('shell:::{4234d49b-0245-4df3-b780-3893943456e1}')
        $items = $namespace.Items() | Where-Object { $_.Name -eq $appname }
        
        if ($items) {
            $items.Verbs() | Where-Object { $_.Name.replace('&','') -match 'Unpin from taskbar' } | ForEach-Object { $_.DoIt() }
            Write-Log "Microsoft Store depinne avec succes" "OK"
        }
        else {
            Write-Log "Microsoft Store pas epingle ou deja supprime" "OK"
        }
    }
    catch {
        Write-Log "Echec depinning: $($_.Exception.Message)" "WARN"
    }

    # ------------------------------------------------------------------
    # 2. BLOCAGE VIA REGISTRE (TOUS UTILISATEURS)
    # ------------------------------------------------------------------
    
    Write-Log "Blocage via registre..." "INFO"
    
    try {
        $RegPath = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
        
        if (-not (Test-Path $RegPath)) {
            New-Item -Path $RegPath -Force -ErrorAction SilentlyContinue | Out-Null
        }
        
        New-ItemProperty -Path $RegPath -Name "NoPinningStoreToTaskbar" -Value 1 -PropertyType DWORD -Force -ErrorAction Stop
        Write-Log "Registre bloque avec succes" "OK"
    }
    catch {
        Write-Log "Echec registre: $($_.Exception.Message)" "WARN"
    }

    # ------------------------------------------------------------------
    # 3. MESSAGE DE SUCCÈS
    # ------------------------------------------------------------------
    
    Write-Log "=== SUPPRESSION MICROSOFT STORE TERMINE ===" "OK"
    
    exit 0
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    Write-Log $_.ScriptStackTrace "ERROR"
    exit 1
}