@echo off
:: ============================================================
::  WinPostInstall.ps1 Launcher
::  Double-click this file to run the script with admin rights
::  and execution policy bypass automatically.
:: ============================================================

:: Check if already running as Administrator
net session >nul 2>&1

if %errorlevel% == 0 (
    :: Already admin - just run the script
    echo Running WinPostInstall.ps1 ...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0WinPostInstall.ps1" %*
) else (
    :: Not admin - request UAC elevation
    echo Requesting administrator privileges ...
    powershell.exe -NoProfile -Command "Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0WinPostInstall.ps1\" %*' -Verb RunAs"
)

echo.
pause
