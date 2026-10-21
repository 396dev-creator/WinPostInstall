@echo off
title WinPostInstall v4.1.0 - Launcher
echo.
echo  ============================================
echo   WinPostInstall v4.1.0 - Portable Launcher
echo  ============================================
echo.
echo  Starting local server...
echo.

:: Use PowerShell's built-in HTTP listener (no install needed)
:: This starts a tiny web server on port 8080 serving the app files

:: Find an available port
set PORT=8080

:: Kill any existing server on this port
netstat -ano | findstr ":%PORT% " | findstr "LISTENING" >nul 2>&1
if %ERRORLEVEL%==0 (
    echo  Port %PORT% is in use, trying 8081...
    set PORT=8081
)

:: Start the HTTP server using PowerShell (built into Windows)
start /b powershell -NoProfile -ExecutionPolicy Bypass -Command "& { $root = '%~dp0'; $port = %PORT%; $listener = [System.Net.HttpListener]::new(); $listener.Prefixes.Add('http://localhost:' + $port + '/'); $listener.Start(); Write-Host \"Server running at http://localhost:$port/\"; while ($listener.IsListening) { $ctx = $listener.GetContext(); $url = $ctx.Request.Url.LocalPath; if ($url -eq '/') { $url = '/index.html' }; $file = Join-Path $root ($url.TrimStart('/')); if (Test-Path $file -PathType Leaf) { $buf = [System.IO.File]::ReadAllBytes($file); $ext = [System.IO.Path]::GetExtension($file); $mime = switch ($ext) { '.html' { 'text/html' } '.js' { 'application/javascript' } '.css' { 'text/css' } '.json' { 'application/json' } '.svg' { 'image/svg+xml' } '.png' { 'image/png' } '.ico' { 'image/x-icon' } '.txt' { 'text/plain' } default { 'application/octet-stream' } }; $ctx.Response.ContentType = $mime; $ctx.Response.ContentLength64 = $buf.Length; $ctx.Response.OutputStream.Write($buf, 0, $buf.Length) } else { $ctx.Response.StatusCode = 404; $buf = [System.Text.Encoding]::UTF8.GetBytes('Not Found'); $ctx.Response.OutputStream.Write($buf, 0, $buf.Length) }; $ctx.Response.Close() } }"

:: Wait a moment for server to start
timeout /t 2 /nobreak >nul

:: Open the app in the default browser
echo  Opening WinPostInstall in your browser...
echo.
echo  When done, close this window to stop the server.
echo.
start http://localhost:%PORT%/

:: Keep the window open
pause
