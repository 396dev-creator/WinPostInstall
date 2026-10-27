# ============================================================================
#  Update-Script.ps1
#  Pulls the latest WinPostInstall.ps1 from GitHub main branch and drops it
#  into the temp folder where WinPostInstall.exe caches it.
#
#  Run this BEFORE launching the Tauri app (WinPostInstall.exe) to test
#  fixes that haven't been baked into a new .exe release yet.
#
#  Usage:  powershell -ExecutionPolicy Bypass -File .\Update-Script.ps1
# ============================================================================

$ErrorActionPreference = 'Stop'
$GitHubUrl = 'https://raw.githubusercontent.com/396dev-creator/WinPostInstall/main/scripts/WinPostInstall.ps1'

function Write-OK($m)   { Write-Host "[+] $m" -ForegroundColor Green }
function Write-Warn($m) { Write-Host "[!] $m" -ForegroundColor Yellow }
function Write-Err($m)  { Write-Host "[-] $m" -ForegroundColor Red }
function Write-Status($m) { Write-Host "[*] $m" -ForegroundColor Cyan }

# --- Step 1: Find the temp folder where the .exe caches the .ps1 ------------
Write-Status "Looking for WinPostInstall temp folder ..."

$tempDirs = @(
    Get-ChildItem "$env:LOCALAPPDATA\Temp\WinPostInstall_*" -Directory -ErrorAction SilentlyContinue
) | Sort-Object LastWriteTime -Descending

if ($tempDirs.Count -eq 0) {
    Write-Warn "No temp folder found yet."
    Write-Warn "This means the .exe hasn't been run before (or its temp folder was cleaned)."
    Write-Warn ""
    Write-Warn "Options:"
    Write-Warn "  1. Launch WinPostInstall.exe once so it creates the temp folder + caches v4.1.2,"
    Write-Warn "     then re-run this script to overwrite with the GitHub version."
    Write-Warn "  2. Skip this script and just run WinPostInstall.exe — it will download v4.1.6"
    Write-Warn "     automatically on first run (since no cached .ps1 exists yet)."
    exit 0
}

# Use the most recent temp folder
$targetDir = $tempDirs[0].FullName
$targetFile = Join-Path $targetDir 'WinPostInstall.ps1'
Write-OK "Target folder: $targetDir"

# --- Step 2: Read the current version (if any) ------------------------------
if (Test-Path $targetFile) {
    $oldVersionLine = Select-String -Path $targetFile -Pattern '^\$ScriptVersion = ' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($oldVersionLine) {
        Write-Status "Current cached version: $($oldVersionLine.Line.Trim())"
    }
} else {
    Write-Status "No cached .ps1 in target folder yet."
}

# --- Step 3: Download the latest from GitHub main ---------------------------
Write-Status "Downloading latest from GitHub ..."
try {
    Invoke-WebRequest -Uri $GitHubUrl -OutFile $targetFile -UseBasicParsing -ErrorAction Stop
} catch {
    Write-Err "Download failed: $_"
    exit 1
}

# --- Step 4: Verify the new version ------------------------------------------
$newVersionLine = Select-String -Path $targetFile -Pattern '^\$ScriptVersion = ' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($newVersionLine) {
    Write-OK "Updated to: $($newVersionLine.Line.Trim())"
}

# --- Step 5: Sanity-check that v4.1.6 fixes are present ---------------------
$checks = @(
    @{ Name = 'HKCR/HKU PSDrive mount';     Pattern = 'Mount HKCR: and HKU: PSDrives' },
    @{ Name = 'reg.exe fallback for HKCR';  Pattern = 'HKCR\|HKU\|HKCC\|HKPD' },
    @{ Name = 'ConvertFrom-JsonToHashtable'; Pattern = 'function ConvertFrom-JsonToHashtable' },
    @{ Name = 'Backup dir preserved in Disk Cleanup'; Pattern = 'Preserve the PostInstall_RegBackup' }
)

Write-Status "Verifying v4.1.6 fixes are present in the downloaded file ..."
$allPresent = $true
foreach ($check in $checks) {
    $found = Select-String -Path $targetFile -Pattern $check.Pattern -Quiet -ErrorAction SilentlyContinue
    if ($found) {
        Write-OK "  [PRESENT] $($check.Name)"
    } else {
        Write-Err "  [MISSING] $($check.Name)"
        $allPresent = $false
    }
}

if ($allPresent) {
    Write-Host ""
    Write-OK "All v4.1.6 fixes confirmed in: $targetFile"
    Write-OK "You can now launch WinPostInstall.exe — it will use this updated .ps1."
} else {
    Write-Host ""
    Write-Warn "Some fixes are missing. The .ps1 may be an older or newer version."
    Write-Warn "Inspect: $targetFile"
    exit 1
}
