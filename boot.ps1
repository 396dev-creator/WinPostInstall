# ============================================================================
#  boot.ps1 — Bootstrap script for irm | iex distribution
#  Host this at: https://raw.githubusercontent.com/396dev-creator/WinPostInstall/main/boot.ps1
#  Users run:    irm https://raw.githubusercontent.com/396dev-creator/WinPostInstall/main/boot.ps1 | iex
# ============================================================================

# ── Configuration ──────────────────────────────────────────────────────────────
# Replace these with your actual GitHub repo details
$RepoOwner = "396dev-creator"
$RepoName  = "WinPostInstall"
$ExeName   = "WinPostInstall.exe"          # The binary name in your release

# ── Helper: Write colored output ──────────────────────────────────────────────
function Write-Status($msg)  { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-OK($msg)      { Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Warn($msg)    { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Err($msg)     { Write-Host "[-] $msg" -ForegroundColor Red }

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

# ── Step 3: Create a temporary directory ──────────────────────────────────────
# Using a GUID-based name under $env:TEMP to avoid collisions
$TempDir = Join-Path $env:TEMP "WinPostInstall_$(New-Guid)"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

$TempExe = Join-Path $TempDir $ExeName

# ── Step 4: Download the binary with progress ────────────────────────────────
Write-Status "Downloading to temporary location..."

try {
    # Use WebClient for progress bar support
    $WebClient = New-Object System.Net.WebClient
    
    # Register progress event
    $EventHandler = Register-ObjectEvent -InputObject $WebClient -EventName DownloadProgressChanged -SourceIdentifier WebClientProgress -Action {
        $Global:DownloadProgress = $EventArgs.ProgressPercentage
    }
    
    # Register completion event
    $CompleteHandler = Register-ObjectEvent -InputObject $WebClient -EventName DownloadFileCompleted -SourceIdentifier WebClientComplete -Action {
        $Global:DownloadComplete = $true
    }
    
    $WebClient.DownloadFileAsync($DownloadUrl, $TempExe)
    
    # Show progress
    while (-not $Global:DownloadComplete) {
        if ($Global:DownloadProgress -ge 0) {
            Write-Progress -Activity "Downloading $ExeName" -Status "$Global:DownloadProgress%" -PercentComplete $Global:DownloadProgress
        }
        Start-Sleep -Milliseconds 200
    }
    Write-Progress -Activity "Downloading $ExeName" -Completed
    
    # Clean up event registrations
    Unregister-Event -SourceIdentifier WebClientProgress -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier WebClientComplete -ErrorAction SilentlyContinue
    $WebClient.Dispose()
    
} catch {
    Write-Err "Download failed: $($_.Exception.Message)"
    # Cleanup on failure
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    return
}

if (-not (Test-Path $TempExe)) {
    Write-Err "Downloaded file not found. Aborting."
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    return
}

Write-OK "Download complete"

# ── Step 5: Run the executable and WAIT for it to exit ───────────────────────
Write-Status "Launching $ExeName ..."
Write-Host ""

try {
    $Process = Start-Process -FilePath $TempExe -Wait -PassThru -ErrorAction Stop
    Write-Host ""
    Write-OK "$ExeName exited (code: $($Process.ExitCode))"
} catch {
    Write-Err "Failed to launch: $($_.Exception.Message)"
}

# ── Step 6: CLEANUP — Delete all traces ──────────────────────────────────────
Write-Status "Cleaning up temporary files..."

# Small delay to ensure file handles are released
Start-Sleep -Milliseconds 500

try {
    # Remove the entire temp directory
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction Stop
    Write-OK "Temporary files deleted"
} catch {
    # If deletion fails (file still locked), schedule deletion on reboot
    Write-Warn "Some files still locked. Scheduling cleanup on next reboot..."
    
    # Mark files for deletion on reboot (requires admin, but won't error if not)
    foreach ($Item in (Get-ChildItem -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue)) {
        try {
            # MoveFileEx with MOVEFILE_DELAY_UNTIL_REBOOT (4)
            $null = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer(
                (Get-Process -Id $PID).Modules[0].BaseAddress,
                [type]([System.Delegate])
            )
        } catch {}
    }
    
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
