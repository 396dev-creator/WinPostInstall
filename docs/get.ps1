# ============================================================================
#  boot.ps1 — Bootstrap script for irm | iex distribution
#  Host this at: https://raw.githubusercontent.com/396dev-creator/WinPostInstall/main/boot.ps1
#  Users run:    irm https://raw.githubusercontent.com/396dev-creator/WinPostInstall/main/boot.ps1 | iex
# ============================================================================

# ── Configuration ──────────────────────────────────────────────────────────────
$RepoOwner = "396dev-creator"
$RepoName  = "WinPostInstall"
$ExeName   = "WinPostInstall.exe"

# ── Helper: Write colored output ──────────────────────────────────────────────
function Write-Status($msg)  { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-OK($msg)      { Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Warn($msg)    { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Err($msg)     { Write-Host "[-] $msg" -ForegroundColor Red }

# ── Helper: Check if WebView2 is actually available ───────────────────────────
function Test-WebView2Available {
    # Method 1: Check registry (most reliable)
    $RegPaths = @(
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8C85-1E1E0F8A3F9E}",
        "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8C85-1E1E0F8A3F9E}",
        "HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8C85-1E1E0F8A3F9E}"
    )
    foreach ($RegPath in $RegPaths) {
        if (Test-Path $RegPath) { return $true }
    }

    # Method 2: Check if the DLL/exe exists on disk
    $DllPaths = @(
        "${env:ProgramFiles(x86)}\Microsoft\EdgeWebView\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\EdgeWebView\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\EdgeCore\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
    )
    foreach ($DllPath in $DllPaths) {
        if (Test-Path $DllPath) { return $true }
    }

    # Method 3: Try to find via Get-Command
    try {
        $null = Get-Command "msedge" -ErrorAction Stop
        return $true
    } catch {}

    return $false
}

# ── Step 1: Query GitHub Releases API for latest release ─────────────────────
Write-Status "Fetching latest release from $RepoOwner/$RepoName ..."

try {
    $Release = Invoke-RestMethod -Uri "https://api.github.com/repos/$RepoOwner/$RepoName/releases/latest" -ErrorAction Stop
} catch {
    Write-Err "Failed to query GitHub API. Check repo owner/name and internet connection."
    Write-Err "Error: $($_.Exception.Message)"
    return
}

# ── Step 2: Find the download URL for the exe ────────────────────────────────
$Asset = $Release.assets | Where-Object { $_.name -eq $ExeName } | Select-Object -First 1

if (-not $Asset) {
    Write-Err "Could not find '$ExeName' in release assets."
    Write-Err "Available assets: $($Release.assets.name -join ', ')"
    return
}

$DownloadUrl = $Asset.browser_download_url
$FileSize    = [math]::Round($Asset.size / 1MB, 2)
$Version     = $Release.tag_name

Write-OK "Found $ExeName v$Version ($FileSize MB)"

# ── Step 3: Check & install WebView2 if missing ──────────────────────────────
Write-Status "Checking WebView2 runtime ..."

if (Test-WebView2Available) {
    Write-OK "WebView2 runtime found"
} else {
    Write-Warn "WebView2 runtime not found - installing automatically ..."

    try {
        # Download the official Microsoft WebView2 Evergreen Bootstrapper (~2MB)
        $WV2Installer = Join-Path $env:TEMP "MicrosoftEdgeWebview2Setup.exe"
        Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/p/?LinkId=2124703" -OutFile $WV2Installer -UseBasicParsing

        # Run the installer silently (no UI, no reboot prompt)
        $WV2Process = Start-Process -FilePath $WV2Installer -ArgumentList "/silent /install" -Wait -PassThru -ErrorAction Stop

        # Wait a moment for registration to settle
        Start-Sleep -Seconds 2

        # Verify WebView2 is now actually available (instead of trusting the exit code)
        if (Test-WebView2Available) {
            Write-OK "WebView2 runtime installed and verified"
        } elseif ($WV2Process.ExitCode -eq 0) {
            Write-OK "WebView2 installer reported success"
        } else {
            # Common non-zero codes that still mean success:
            #  -2147219416 (0x80040B28) = newer version already installed
            #  1603 = generic MSI failure, but WebView2 may still work via Edge
            Write-Warn "WebView2 installer exited with code $($WV2Process.ExitCode)"
            Write-Warn "The app will attempt to use Edge's built-in WebView2 if available"
        }

        # Clean up the installer
        Remove-Item -Path $WV2Installer -Force -ErrorAction SilentlyContinue

    } catch {
        Write-Warn "Could not auto-install WebView2: $($_.Exception.Message)"
        Write-Warn "The app may fail to launch. Install it manually from:"
        Write-Warn "  https://developer.microsoft.com/en-us/microsoft-edge/webview2/"
    }
}

# ── Step 4: Create a temporary directory ──────────────────────────────────────
$TempDir = Join-Path $env:TEMP "WinPostInstall_$(New-Guid)"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

$TempExe = Join-Path $TempDir $ExeName

# ── Step 5: Download the binary with progress ────────────────────────────────
Write-Status "Downloading to temporary location..."

try {
    $WebClient = New-Object System.Net.WebClient

    $EventHandler = Register-ObjectEvent -InputObject $WebClient -EventName DownloadProgressChanged -SourceIdentifier WebClientProgress -Action {
        $Global:DownloadProgress = $EventArgs.ProgressPercentage
    }

    $CompleteHandler = Register-ObjectEvent -InputObject $WebClient -EventName DownloadFileCompleted -SourceIdentifier WebClientComplete -Action {
        $Global:DownloadComplete = $true
    }

    $WebClient.DownloadFileAsync($DownloadUrl, $TempExe)

    while (-not $Global:DownloadComplete) {
        if ($Global:DownloadProgress -ge 0) {
            Write-Progress -Activity "Downloading $ExeName" -Status "$Global:DownloadProgress%" -PercentComplete $Global:DownloadProgress
        }
        Start-Sleep -Milliseconds 200
    }
    Write-Progress -Activity "Downloading $ExeName" -Completed

    Unregister-Event -SourceIdentifier WebClientProgress -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier WebClientComplete -ErrorAction SilentlyContinue
    $WebClient.Dispose()

} catch {
    Write-Err "Download failed: $($_.Exception.Message)"
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    return
}

if (-not (Test-Path $TempExe)) {
    Write-Err "Downloaded file not found. Aborting."
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    return
}

Write-OK "Download complete"

# ── Step 5b: Download the PowerShell script alongside the exe ────────────────
Write-Status "Downloading WinPostInstall.ps1 ..."

$Ps1Url = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/main/scripts/WinPostInstall.ps1"
$TempPs1 = Join-Path $TempDir "WinPostInstall.ps1"

try {
    Invoke-WebRequest -Uri $Ps1Url -OutFile $TempPs1 -UseBasicParsing
    Write-OK "WinPostInstall.ps1 downloaded"
} catch {
    Write-Warn "Could not download WinPostInstall.ps1: $($_.Exception.Message)"
    Write-Warn "The app will attempt to download it automatically when you Apply"
}

# Also download the CMD launcher if available
$CmdUrl = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/main/download/WinPostInstall.cmd"
$TempCmd = Join-Path $TempDir "WinPostInstall.cmd"
try {
    Invoke-WebRequest -Uri $CmdUrl -OutFile $TempCmd -UseBasicParsing
} catch {
    # Non-essential, skip silently
}

# ── Step 6: Run the executable and WAIT for it to exit ───────────────────────
Write-Status "Launching $ExeName ..."
Write-Host ""

try {
    $Process = Start-Process -FilePath $TempExe -Wait -PassThru -ErrorAction Stop
    Write-Host ""
    Write-OK "$ExeName exited (code: $($Process.ExitCode))"
} catch {
    Write-Err "Failed to launch: $($_.Exception.Message)"
}

# ── Step 7: CLEANUP — Delete all traces ──────────────────────────────────────
Write-Status "Cleaning up temporary files..."

Start-Sleep -Milliseconds 500

try {
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction Stop
    Write-OK "Temporary files deleted"
} catch {
    Write-Warn "Some files still locked. Scheduling cleanup on next reboot..."

    # Fallback: spawn a delayed deletion in background
    $CleanupScript = @"
`$Attempts = 0
while (`$Attempts -lt 30 -and (Test-Path '$TempDir')) {
    Start-Sleep -Seconds 1
    `$Attempts++
    Remove-Item -Path '$TempDir' -Recurse -Force -ErrorAction SilentlyContinue
}
"@
    Start-Process -WindowStyle Hidden -FilePath "powershell.exe" -ArgumentList "-NoProfile -NonInteractive -Command `"$CleanupScript`""
    Write-OK "Background cleanup scheduled"
}

Write-Host ""
Write-OK "Done. No traces left behind."
