@echo off
setlocal EnableDelayedExpansion

:: ============================================================
:: Run_Selective.cmd
:: Lance l'interface de sélection des scripts CGLOBAL
:: ============================================================
:: Ordre : 1) élévation (une seule fois) 2) minimisation (une seule fois)
:: Blocs explicitement parenthèses partout, pour que start/exit ne
:: s'exécutent QUE si la condition est vraie (évite toute fenêtre
:: résiduelle en cas d'ambiguite de parsing du IF).

:: --- Étape 1 : Vérification des droits administrateur ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] Relance en tant qu administrateur...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: --- Étape 2 : Minimisation (une seule fois, on est déjà élevé ici) ---
if /I not "%~1"=="min" (
    start "" /min "%~f0" min
    exit /b
)

chcp 65001 >nul
title CGLOBAL - Mode Selectif

:: --- Détection du support source ---
set "USBPath=%~dp0"
set "USBPath=%USBPath:~0,-1%"

if not exist "C:\_CGLOBAL" mkdir "C:\_CGLOBAL"

:: --- Étape 3 : Copie des dossiers Installers et PS1 en /MIR ---
echo [1/3] Copie des installateurs vers C:\_CGLOBAL\Installers ...
robocopy "%USBPath%\_CGLOBAL\Installers" "C:\_CGLOBAL\Installers" /E /MIR /NFL /NDL
echo [2/3] Copie des scripts vers C:\_CGLOBAL\PS1 ...
robocopy "%USBPath%\_CGLOBAL\PS1" "C:\_CGLOBAL\PS1" /E /MIR /NFL /NDL

:: --- Étape 4 : Copie du reste SANS /MIR (ne supprime pas) ---
echo [3/3] Copie des fichiers restants vers C:\_CGLOBAL ...
robocopy "%USBPath%\_CGLOBAL" "C:\_CGLOBAL" /E /XD Installers PS1 /XF wifi.secret /NFL /NDL

echo Copie terminée.

if %errorlevel% geq 8 (
    exit /b 1
)

:: --- Nettoyage des anciens logs ---
if exist "C:\_CGLOBAL\Logs" rd /s /q "C:\_CGLOBAL\Logs"
mkdir "C:\_CGLOBAL\Logs"

:: --- Lancement de l'interface PowerShell ---
powershell.exe -ExecutionPolicy Bypass -File "C:\_CGLOBAL\PS1\Run_Selective.ps1" -USBPath "%USBPath%"

exit /b
