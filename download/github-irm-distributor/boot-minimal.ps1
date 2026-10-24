# ============================================================================
#  boot-minimal.ps1  -  Minimal bootstrap (no progress bar, simpler cleanup)
#  For users who prefer a lean, fast loader
# ============================================================================

$RepoOwner = "396dev-creator"
$RepoName  = "WinPostInstall"
$ExeName   = "WinPostInstall.exe"

# Get latest release info
$Release = Invoke-RestMethod "https://api.github.com/repos/$RepoOwner/$RepoName/releases/latest"
$Asset   = $Release.assets | Where-Object { $_.name -eq $ExeName } | Select-Object -First 1

if (-not $Asset) { Write-Host "[-] $ExeName not found in latest release" -ForegroundColor Red; return }

# Create temp dir & download
$TempDir = Join-Path $env:TEMP "WPI_$(New-Guid)"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
$TempExe = Join-Path $TempDir $ExeName

Write-Host "[*] Downloading $($Release.tag_name) ..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $TempExe -UseBasicParsing

# Run and wait
Write-Host "[*] Running ..." -ForegroundColor Cyan
$proc = Start-Process -FilePath $TempExe -Wait -PassThru

# Cleanup (with retry)
Start-Sleep -Milliseconds 300
1..5 | ForEach-Object {
    if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force -EA SilentlyContinue; Start-Sleep -Seconds 1 }
}
if (-not (Test-Path $TempDir)) { Write-Host "[+] Cleaned up" -ForegroundColor Green }
