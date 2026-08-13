#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Import-Module "C:\_CGLOBAL\PS1\CGLOBAL.Common.psm1" -Force
$LogFile = Get-CGlobalLogFile -ScriptPath $MyInvocation.MyCommand.Path
Initialize-CGlobalLog -LogFile $LogFile

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

    Add-Content `
        -Path $LogFile `
        -Value $Line `
        -Encoding UTF8

    $Color = @{
        INFO  = 'Cyan'
        OK    = 'Green'
        WARN  = 'Yellow'
        ERROR = 'Red'
    }

    Write-Host $Line -ForegroundColor $Color[$Level]
}

try {

    Write-Log "Verification du compte utilisateur courant"

    $CurrentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()

    $CurrentUserName = $CurrentIdentity.Name.Split('\')[-1]

    Write-Log "Utilisateur courant : $CurrentUserName"

    #
    # Recherche du compte local
    #
    $LocalUser = Get-LocalUser `
        -Name $CurrentUserName `
        -ErrorAction SilentlyContinue

    if ($null -eq $LocalUser) {

        Write-Log (
            "Le compte courant n'est pas un compte local (Microsoft ou Entra ID)"
        ) "OK"

        exit 0
    }

    Write-Log "Compte local detecte" "OK"

    #
    # Verification du mot de passe
    #
    if (-not $LocalUser.PasswordRequired) {

        Write-Log (
            "Le compte local ne possede pas de mot de passe"
        ) "WARN"

        Write-Host ""
        Write-Host "==================================================" -ForegroundColor Yellow
        Write-Host "Le compte local '$CurrentUserName' n'a pas de mot de passe." -ForegroundColor Yellow
        Write-Host "==================================================" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Souhaitez-vous definir un mot de passe ?" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "O = Oui"
        Write-Host "N = Non"
        Write-Host ""

        $Choice = Read-Host "Votre choix"

        if ($Choice.ToUpper() -ne "O") {

            Write-Log (
                "Creation du mot de passe refusee par l'utilisateur"
            ) "WARN"

            exit 0
        }

        do {

            $Password1 = Read-Host `
                "Entrez le mot de passe" `
                -AsSecureString

            $Password2 = Read-Host `
                "Confirmez le mot de passe" `
                -AsSecureString

            $Ptr1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password1)
            $Ptr2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password2)

            $Plain1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto($Ptr1)
            $Plain2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto($Ptr2)

            if ($Plain1 -ne $Plain2) {

                Write-Host ""
                Write-Host "Les mots de passe ne correspondent pas." -ForegroundColor Red
                Write-Host ""
            }

        } while ($Plain1 -ne $Plain2)

        Set-LocalUser `
            -Name $CurrentUserName `
            -Password $Password1

        Write-Log "Mot de passe defini avec succes" "OK"

        Write-Host ""
        Write-Host "Mot de passe applique." -ForegroundColor Green
        Write-Host ""
    }
    else {

        Write-Log (
            "Le compte local est deja protege par un mot de passe"
        ) "OK"
    }
}
catch {

    Write-Log $_.Exception.Message "ERROR"

    exit 1
}

Write-Log "Verification du mot de passe terminee" "OK"

exit 0