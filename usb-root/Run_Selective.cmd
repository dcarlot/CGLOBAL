@echo off
if not "%1"=="min" start /min "" "%~f0" min & exit

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

if not exist "C:\_CGLOBAL" mkdir "C:\_CGLOBAL"

:: --- Etape 1 : Copie des dossiers Installers et PS1 en /MIR ---
robocopy "%USBPath%\_CGLOBAL\Installers" "C:\_CGLOBAL\Installers" /E /MIR /NFL /NDL /NJH /NJS >nul
robocopy "%USBPath%\_CGLOBAL\PS1" "C:\_CGLOBAL\PS1" /E /MIR /NFL /NDL /NJH /NJS >nul

:: --- Etape 2 : Copie du reste SANS /MIR (ne supprime pas) ---
robocopy "%USBPath%\_CGLOBAL" "C:\_CGLOBAL" /E /XD Installer PS1 /NFL /NDL /NJH /NJS >nul

if %errorlevel% geq 8 (
    exit /b 1
)

:: --- Nettoyage des anciens logs ---
if exist "C:\_CGLOBAL\Logs" rd /s /q "C:\_CGLOBAL\Logs"
mkdir "C:\_CGLOBAL\Logs"

:: --- Lancement de l'interface PowerShell ---
powershell.exe -ExecutionPolicy Bypass -File "C:\_CGLOBAL\PS1\Run_Selective.ps1" -USBPath "%USBPath%"

exit /b
