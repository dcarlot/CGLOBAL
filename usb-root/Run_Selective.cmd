@echo off
chcp 65001 >nul
title CGLOBAL - Mode Selectif
setlocal EnableDelayedExpansion

:: ============================================================
:: Run_Selective.cmd
:: Lance l'interface de selection des scripts CGLOBAL
:: ============================================================

:: --- Verification des droits administrateur ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] Relance en tant qu administrateur...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: --- Detection du support source ---
set "USBPath=%~dp0"
set "USBPath=%USBPath:~0,-1%"

echo.
echo ============================================
echo Cle USB detectee : %USBPath%
echo Synchronisation de _CGLOBAL vers C:
echo ============================================
echo.

if not exist "C:\_CGLOBAL" mkdir "C:\_CGLOBAL"

:: --- Etape 1 : Copie des dossiers Installers et PS1 en /MIR ---
echo.
echo --- Copie de Installers (avec miroir) ---
robocopy "%USBPath%\_CGLOBAL\Installers" "C:\_CGLOBAL\Installers" /E /MIR /NFL /NDL /NJH /NJS

echo.
echo --- Copie de PS1 (avec miroir) ---
robocopy "%USBPath%\_CGLOBAL\PS1" "C:\_CGLOBAL\PS1" /E /MIR /NFL /NDL /NJH /NJS

:: --- Etape 2 : Copie du reste SANS /MIR (ne supprime pas) ---
echo.
echo --- Copie des autres dossiers (sans miroir) ---
robocopy "%USBPath%\_CGLOBAL" "C:\_CGLOBAL" /E /XD Installer PS1 /NFL /NDL /NJH /NJS

if %errorlevel% geq 8 (
    echo.
    echo ============================================
    echo ERREUR LORS DE LA COPIE
    echo Code : %errorlevel%
    echo ============================================
    pause
    exit /b 1
)

:: --- Nettoyage des anciens logs ---
if exist "C:\_CGLOBAL\Logs" rd /s /q "C:\_CGLOBAL\Logs"
mkdir "C:\_CGLOBAL\Logs"

echo.
echo ============================================
echo Synchronisation terminee
echo Lancement du mode selectif
echo ============================================
echo.

:: --- Lancement de l'interface PowerShell ---
powershell.exe -ExecutionPolicy Bypass -File "C:\_CGLOBAL\PS1\Run_Selective.ps1" -USBPath "%USBPath%"

exit /b
