@echo off
:: ============================================================
::  WinRepair-Toolkit — One-Click Launcher
::  Double-click this. It handles Admin elevation automatically.
:: ============================================================

:: Capture the full path to this .bat file immediately
set "SELF=%~f0"
set "MYDIR=%~dp0"
set "PS1=%~dp0WindowsRepair.ps1"

:: Check if already Admin
net session >nul 2>&1
if %errorLevel% == 0 goto :AlreadyAdmin

:: Not Admin — use PowerShell to elevate and run the PS1 directly
:: This avoids the self-re-launch loop entirely
powershell -NoProfile -Command "Start-Process powershell.exe -ArgumentList '-NoProfile -NoLogo -ExecutionPolicy Bypass -File ""%PS1%""' -Verb RunAs -Wait"
goto :EOF

:AlreadyAdmin
:: Already running as Admin — go straight to the script
cd /d "%MYDIR%"
title WinRepair-Toolkit v4.7
cls

if not exist "%PS1%" (
    echo.
    echo  ERROR: WindowsRepair.ps1 not found.
    echo  Make sure these 3 files are in the same folder:
    echo.
    echo    WindowsRepair.ps1
    echo    run.bat
    echo    Launch.html
    echo.
    echo  Current folder: %MYDIR%
    echo.
    pause
    exit /b 1
)

powershell.exe -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%PS1%"

echo.
echo  Script finished. Press any key to close...
pause >nul
