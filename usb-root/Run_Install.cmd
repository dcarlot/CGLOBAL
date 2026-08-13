@echo off
chcp 65001 >nul
title Post-Installation PC
setlocal EnableDelayedExpansion

:: =====================================================
:: Vérification des droits administrateur
:: =====================================================

net session >nul 2>&1

if %errorlevel% neq 0 (
    echo ============================================
    echo Droits administrateur requis
    echo Relancement en tant qu administrateur...
    echo ============================================

    timeout /t 2 >nul

    powershell -Command "Start-Process '%~f0' -Verb RunAs"

    exit /b
)

:: =====================================================
:: Détection du support source
:: =====================================================

set "USBPath=%~dp0"
set "USBPath=%USBPath:~0,-1%"

echo.
echo ============================================
echo Cle USB detectee : %USBPath%
echo Synchronisation de _CGLOBAL vers C:
echo ============================================
echo.

if not exist "C:\_CGLOBAL" mkdir "C:\_CGLOBAL"

robocopy "%USBPath%\_CGLOBAL" "C:\_CGLOBAL" /E /XO /R:1 /W:1 /NFL /NDL /NJH /NJS

if %errorlevel% geq 8 (
    echo.
    echo ============================================
    echo ERREUR LORS DE LA COPIE
    echo Code : %errorlevel%
    echo ============================================
    pause
    exit /b 1
)

:: =====================================================
:: Nettoyage des anciens logs
:: =====================================================

if exist "C:\_CGLOBAL\Logs" rd /s /q "C:\_CGLOBAL\Logs"

mkdir "C:\_CGLOBAL\Logs"

echo.
echo ============================================
echo Synchronisation terminee
echo Demarrage des scripts
echo ============================================
echo.

:: =====================================================
:: Lancement des scripts
:: =====================================================

call :RunPS "00_ModeDeploiement.ps1"

call :RunPS "01_Bureau.ps1"
call :RunPS "02_MenuContextuelClassique.ps1"
call :RunPS "03_Explorateur.ps1"
call :RunPS "04_ZoneNotification.ps1"
call :RunPS "05_BarreTachesGauche.ps1"
call :RunPS "06_RechercheBarreTaches.ps1"
call :RunPS "07_MasquerVueTaches.ps1"
call :RunPS "10_DesactiverReprendre.ps1"
::call :RunPS "11_ConfidentialiteLocalisation.ps1"
call :RunPS "12_ConfigurerProfilParDefaut.ps1"
call :RunPS "13_NumLockDemarrage.ps1"
call :RunPS "14_DesinstallationOffice.ps1"

call :CheckInternet

if errorlevel 1 (
    pause
    exit /b 1
)

call :RunPS "15_ApplicationsWinget.ps1"
call :RunPS "16_TeamViewerQS.ps1"
call :RunPS "17_VerificationMotDePasseCompteLocal.ps1"

call :RunPS "99_FinDeploiement.ps1"

echo.
echo ============================================
echo DEPLOIEMENT TERMINE
echo ============================================
echo.
echo Consulter les logs si necessaire :
echo C:\_CGLOBAL\Logs
echo.

pause
exit /b 0

:: =====================================================
:: Sous-routine PowerShell
:: =====================================================

:RunPS

echo.
echo ----------------------------------------------------
echo Lancement %~1
echo ----------------------------------------------------

powershell.exe -ExecutionPolicy Bypass -File "C:\_CGLOBAL\PS1\%~1"

if errorlevel 1 (
    echo [WARN] Le script %~1 a retourné une erreur
    echo.
)

exit /b

:CheckInternet

:InternetLoop

echo.
echo ============================================
echo Verification de l acces Internet...
echo ============================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"if ((Test-NetConnection download.microsoft.com -InformationLevel Quiet) -and (Test-NetConnection get.teamviewer.com -InformationLevel Quiet)) { exit 0 } else { exit 1 }"

if %errorlevel% equ 0 (

    echo [OK] Acces Internet detecte.
    exit /b 0
)

echo.
echo ============================================
echo [WARN] Pas d acces Internet detecte
echo.
echo Winget et TeamViewer necessitent Internet.
echo.
echo Connectez le PC au reseau puis choisissez :
echo.
echo O = Reessayer
echo N = Quitter le deploiement
echo ============================================
echo.

choice /C ON /N /M "Votre choix : "

if errorlevel 2 (
    echo.
    echo Deploiement interrompu.
    exit /b 1
)

goto :InternetLoop
