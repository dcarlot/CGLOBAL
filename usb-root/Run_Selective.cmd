@echo off
setlocal EnableDelayedExpansion

:: ============================================================
:: Run_Selective.cmd
:: Lance l'interface de sélection des scripts CGLOBAL
:: ============================================================
:: Modifications :
:: - Fenêtre visible pendant la copie des fichiers
:: - Minimisation automatique juste avant le lancement PowerShell
:: - Affichage détaillé de la progression des copies

:: --- Étape 1 : Vérification des droits administrateur ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] Relance en tant qu'administrateur...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: --- Étape 2 : Détection du support source ---
set "USBPath=%~dp0"
set "USBPath=%USBPath:~0,-1%"

chcp 65001 >nul
title CGLOBAL - Préparation en cours...

:: --- Affichage initial ---
cls
echo ============================================================
echo   CGLOBAL - Post-Installation Windows 11
echo ============================================================
echo.
echo   Préparation du poste en cours...
echo   Veuillez patienter pendant la copie des fichiers.
echo.
echo ============================================================
echo.

if not exist "C:\_CGLOBAL" mkdir "C:\_CGLOBAL"

:: --- Étape 3 : Copie des dossiers Installers et PS1 en /MIR ---
echo [1/3] Copie des installateurs...
echo       Source      : %USBPath%\_CGLOBAL\Installers
echo       Destination : C:\_CGLOBAL\Installers
echo.
robocopy "%USBPath%\_CGLOBAL\Installers" "C:\_CGLOBAL\Installers" /E /MIR /NP /NDL /NFL
echo.

echo [2/3] Copie des scripts PowerShell...
echo       Source      : %USBPath%\_CGLOBAL\PS1
echo       Destination : C:\_CGLOBAL\PS1
echo.
robocopy "%USBPath%\_CGLOBAL\PS1" "C:\_CGLOBAL\PS1" /E /MIR /NP /NDL /NFL
echo.

:: --- Étape 4 : Copie du reste SANS /MIR (ne supprime pas) ---
echo [3/3] Copie des fichiers complémentaires...
echo       Source      : %USBPath%\_CGLOBAL
echo       Destination : C:\_CGLOBAL
echo.
robocopy "%USBPath%\_CGLOBAL" "C:\_CGLOBAL" /E /XD Installers PS1 /XF wifi.secret /NP /NDL /NFL
echo.

:: --- Vérification des erreurs ---
if %errorlevel% geq 8 (
    echo.
    echo [ERREUR] La copie des fichiers a échoué.
    echo          Code erreur : %errorlevel%
    echo.
    pause
    exit /b 1
)

echo ============================================================
echo   Copie terminée avec succès !
echo   Lancement de l'interface de sélection...
echo ============================================================
echo.

:: --- Nettoyage des anciens logs ---
if exist "C:\_CGLOBAL\Logs" rd /s /q "C:\_CGLOBAL\Logs"
mkdir "C:\_CGLOBAL\Logs"

:: --- Minimisation de la fenêtre avant PowerShell ---
powershell -NoProfile -Command "Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class Win32 { [DllImport(\"kernel32.dll\")] public static extern IntPtr GetConsoleWindow(); [DllImport(\"user32.dll\")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow); }'; $hwnd = [Win32]::GetConsoleWindow(); if ($hwnd -ne [IntPtr]::Zero) { [Win32]::ShowWindow($hwnd, 6) }"

:: --- Lancement de l'interface PowerShell ---
powershell.exe -ExecutionPolicy Bypass -File "C:\_CGLOBAL\PS1\Run_Selective.ps1" -USBPath "%USBPath%"

exit /b
