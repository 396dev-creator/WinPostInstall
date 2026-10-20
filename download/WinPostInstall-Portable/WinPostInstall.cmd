@echo off
chcp 65001 >nul 2>&1
title WinPostInstall v4.1.0
cls
echo.
echo   ╔═══════════════════════════════════════════════╗
echo   ║  WinPostInstall v4.1.0                        ║
echo   ║  Windows Post-Installation Configurator        ║
echo   ╚═══════════════════════════════════════════════╝
echo.
echo   This is a portable tool. No installation required.
echo   It will NOT leave any software on the client PC.
echo.

:: Set the app directory (where this .cmd file lives)
set "APPDIR=%~dp0"

:: Find a free port (try 8080, 8081, 8082)
set PORT=8080
for /L %%i in (0,1,2) do (
    netstat -ano 2>nul | findstr ":%PORT% " | findstr "LISTENING" >nul 2>&1
    if errorlevel 1 goto :found_port
    set /a PORT+=1
)
echo   ERROR: Could not find a free port. Close other apps and retry.
pause
exit /b 1
:found_port

echo   Starting local server on port %PORT%...
echo.

:: Start PowerShell HTTP server in background
:: This uses ONLY built-in Windows components - nothing to install
start /b powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -Command ^
 "& { ^
    try { ^
      $root = '%APPDIR%'; ^
      $port = '%PORT%'; ^
      $listener = [System.Net.HttpListener]::new(); ^
      $listener.Prefixes.Add('http://localhost:' + $port + '/'); ^
      $listener.Start(); ^
      while ($listener.IsListening) { ^
        $ctx = $listener.GetContext(); ^
        $url = $ctx.Request.Url.LocalPath; ^
        if ($url -eq '/') { $url = '/index.html' }; ^
        $file = Join-Path $root ($url.TrimStart('/').Replace('/', '\')); ^
        if (Test-Path $file -PathType Leaf) { ^
          $buf = [System.IO.File]::ReadAllBytes($file); ^
          $ext = [System.IO.Path]::GetExtension($file); ^
          $mime = switch ($ext) { ^
            '.html' { 'text/html; charset=utf-8' } ^
            '.js'   { 'application/javascript' } ^
            '.css'  { 'text/css; charset=utf-8' } ^
            '.json' { 'application/json; charset=utf-8' } ^
            '.svg'  { 'image/svg+xml' } ^
            '.png'  { 'image/png' } ^
            '.ico'  { 'image/x-icon' } ^
            '.woff2'{ 'font/woff2' } ^
            '.woff' { 'font/woff' } ^
            '.txt'  { 'text/plain' } ^
            default { 'application/octet-stream' } ^
          }; ^
          $ctx.Response.ContentType = $mime; ^
          $ctx.Response.ContentLength64 = $buf.Length; ^
          $ctx.Response.OutputStream.Write($buf, 0, $buf.Length) ^
        } else { ^
          $ctx.Response.StatusCode = 404; ^
          $notFound = [System.Text.Encoding]::UTF8.GetBytes('Not Found: ' + $url); ^
          $ctx.Response.OutputStream.Write($notFound, 0, $notFound.Length) ^
        }; ^
        $ctx.Response.Close() ^
      } ^
    } catch { ^
      Write-Host $_.Exception.Message ^
    } ^
  }"

:: Wait for server to be ready
timeout /t 3 /nobreak >nul

:: Open in default browser
echo   Opening WinPostInstall in your browser...
echo.
start "" "http://localhost:%PORT%/"

echo   ═══════════════════════════════════════════════
echo.
echo   HOW TO USE:
echo.
echo   1. Choose a scenario (Privacy ^& Security or App Setup)
echo   2. Customize settings as needed
echo   3. Click "Apply" to download the config JSON
echo   4. Run WinPostInstall.ps1 with the config:
echo.
echo      powershell -ExecutionPolicy Bypass ^
echo        -File WinPostInstall.ps1 ^
echo        -ConfigFile WinPostInstall-Config.json
echo.
echo   Or double-click WinPostInstall.cmd (if present)
echo.
echo   ═══════════════════════════════════════════════
echo.
echo   Press any key to STOP the server and exit...
echo   (This will NOT undo any changes already applied)
echo.

pause >nul

:: Clean up: kill the PowerShell server process
for /f "tokens=5" %%a in ('netstat -ano 2^>nul ^| findstr ":%PORT% " ^| findstr "LISTENING"') do (
    taskkill /PID %%a /F >nul 2>&1
)

echo.
echo   Server stopped. Safe to remove USB drive.
echo.
timeout /t 2 /nobreak >nul
