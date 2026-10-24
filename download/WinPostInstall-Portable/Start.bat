@echo off
title WinPostInstall v4.1.2
echo.
echo  ============================================
echo   WinPostInstall v4.1.2
echo   Windows Post-Installation Configurator
echo  ============================================
echo.
echo  Opening WinPostInstall...
echo.

:: Open the app directly in the default browser
start "" "%~dp0index.html"

echo  When done configuring, use the "Apply" button
echo  to download your config, then run:
echo.
echo    WinPostInstall.ps1 -ConfigFile WinPostInstall-Config.json
echo.
echo  Or double-click WinPostInstall.cmd to apply.
echo.
pause
