# ============================================================================
#  publish-release.ps1 — Build & publish a GitHub Release with your .exe
#  Run this from your project root after building the executable
# ============================================================================

param(
    [string]$Version = "",          # e.g. "v1.2.0" — auto-detected if empty
    [string]$ExePath = "",          # Path to the built .exe — defaults to standard location
    [string]$Changelog = ""         # Release notes
)

# ── Configuration ──────────────────────────────────────────────────────────────
$RepoOwner = "396dev-creator"
$RepoName  = "WinPostInstall"
$ExeName   = "WinPostInstall.exe"

# ── Validate ───────────────────────────────────────────────────────────────────
if (-not $ExePath) {
    # Default: look in src-tauri/target/release/
    $ExePath = "src-tauri/target/release/$ExeName"
}

if (-not (Test-Path $ExePath)) {
    Write-Host "[-] Executable not found at: $ExePath" -ForegroundColor Red
    Write-Host "    Build it first with:  cargo tauri build" -ForegroundColor Yellow
    exit 1
}

# Auto-detect version from Cargo.toml if not specified
if (-not $Version) {
    $CargoToml = Get-Content "src-tauri/Cargo.toml" -Raw
    if ($CargoToml -match 'version\s*=\s*"([^"]+)"') {
        $Version = "v$($Matches[1])"
    } else {
        $Version = "v1.0.0"
    }
}

if (-not $Changelog) {
    $Changelog = "Release $Version"
}

# ── Check for GitHub CLI ──────────────────────────────────────────────────────
$GhCli = Get-Command "gh" -ErrorAction SilentlyContinue
if (-not $GhCli) {
    Write-Host "[-] GitHub CLI (gh) not found." -ForegroundColor Red
    Write-Host "    Install from: https://cli.github.com/" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    Alternative: Create release manually at:" -ForegroundColor Yellow
    Write-Host "    https://github.com/$RepoOwner/$RepoName/releases/new" -ForegroundColor Yellow
    exit 1
}

# ── Verify authentication ─────────────────────────────────────────────────────
try {
    $AuthStatus = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[-] Not authenticated with GitHub CLI." -ForegroundColor Red
        Write-Host "    Run:  gh auth login" -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-Host "[-] GitHub CLI auth check failed." -ForegroundColor Red
    exit 1
}

# ── Create release and upload asset ───────────────────────────────────────────
Write-Host "[*] Creating release $Version ..." -ForegroundColor Cyan

gh release create $Version `
    $ExePath `
    --repo "$RepoOwner/$RepoName" `
    --title "WinPostInstall $Version" `
    --notes $Changelog

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "[+] Release published successfully!" -ForegroundColor Green
    Write-Host "    URL: https://github.com/$RepoOwner/$RepoName/releases/tag/$Version" -ForegroundColor White
    Write-Host ""
    Write-Host "    Users can now run:" -ForegroundColor Cyan
    Write-Host "    irm https://raw.githubusercontent.com/$RepoOwner/$RepoName/main/boot.ps1 | iex" -ForegroundColor White
} else {
    Write-Host "[-] Release creation failed." -ForegroundColor Red
    exit 1
}
