# ============================================================================
#  publish-release.ps1  -  One-command release publisher
#  Just run:  .\publish-release.ps1
#  Everything is auto-detected: version, exe path, changelog
# ============================================================================

# -- Configuration --------------------------------------------------------------
$RepoOwner = "396dev-creator"
$RepoName  = "WinPostInstall"
$ExeName   = "WinPostInstall.exe"

# -- Helper functions ----------------------------------------------------------
function Write-Status($msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-OK($msg)     { Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Err($msg)    { Write-Host "[-] $msg" -ForegroundColor Red }

# -- Step 1: Auto-detect version from tauri.conf.json -------------------------
Write-Status "Detecting version ..."

$Version = ""
$TauriConf = "src-tauri/tauri.conf.json"
$CargoToml = "src-tauri/Cargo.toml"

if (Test-Path $TauriConf) {
    $Content = Get-Content $TauriConf -Raw
    if ($Content -match '"version"\s*:\s*"([^"]+)"') {
        $Version = "v$($Matches[1])"
    }
}

if (-not $Version -and (Test-Path $CargoToml)) {
    $Content = Get-Content $CargoToml -Raw
    if ($Content -match 'version\s*=\s*"([^"]+)"') {
        $Version = "v$($Matches[1])"
    }
}

if (-not $Version) {
    Write-Err "Could not detect version from tauri.conf.json or Cargo.toml"
    exit 1
}

Write-OK "Version: $Version (auto-detected from $(if (Test-Path $TauriConf) { 'tauri.conf.json' } else { 'Cargo.toml' }))"

# -- Step 2: Auto-find the built executable -----------------------------------
Write-Status "Locating built executable ..."

$ExePath = ""
$SearchPaths = @(
    "src-tauri/target/release/$ExeName"
    "src-tauri/target/release/bundle/nsis/$ExeName"
    "$ExeName"
)

foreach ($Path in $SearchPaths) {
    if (Test-Path $Path) {
        $ExePath = (Resolve-Path $Path).Path
        break
    }
}

if (-not $ExePath) {
    Write-Err "Built executable not found."
    Write-Err "Build it first with:  cargo tauri build"
    exit 1
}

$FileSize = [math]::Round((Get-Item $ExePath).Length / 1MB, 2)
Write-OK "Found: $ExePath ($FileSize MB)"

# -- Step 3: Auto-generate changelog from recent git log ----------------------
Write-Status "Generating changelog ..."

$Changelog = ""
try {
    $RecentCommits = git log --oneline -10 --pretty=format:"- %s" 2>$null
    if ($RecentCommits) {
        $Changelog = "What's new in $Version:`n`n$RecentCommits"
    }
} catch {}

if (-not $Changelog) {
    $Changelog = "Release $Version"
}

# -- Step 4: Check GitHub CLI --------------------------------------------------
$GhCli = Get-Command "gh" -ErrorAction SilentlyContinue
if (-not $GhCli) {
    Write-Err "GitHub CLI (gh) not found."
    Write-Err "Install from: https://cli.github.com/"
    exit 1
}

try {
    gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Not authenticated with GitHub CLI. Run: gh auth login"
        exit 1
    }
} catch {
    Write-Err "GitHub CLI auth check failed."
    exit 1
}

Write-OK "GitHub CLI authenticated"

# -- Step 5: Check if tag already exists --------------------------------------
$ExistingRelease = gh release view $Version --repo "$RepoOwner/$RepoName" 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Err "Release $Version already exists!"
    Write-Err "If you want to replace it, delete it first:"
    Write-Err "  gh release delete $Version --repo $RepoOwner/$RepoName --yes"
    Write-Err ""
    Write-Err "Or bump the version in tauri.conf.json and re-run."
    exit 1
}

# -- Step 6: Create the release ------------------------------------------------
Write-Status "Publishing release $Version ..."

$TempChangelog = [System.IO.Path]::GetTempFileName()
$Changelog | Out-File -FilePath $TempChangelog -Encoding utf8

gh release create $Version `
    $ExePath `
    --repo "$RepoOwner/$RepoName" `
    --title "WinPostInstall $Version" `
    --notes-file $TempChangelog

Remove-Item $TempChangelog -Force -ErrorAction SilentlyContinue

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-OK "Release published successfully!"
    Write-Host ""
    Write-Host "    Release:  https://github.com/$RepoOwner/$RepoName/releases/tag/$Version" -ForegroundColor White
    Write-Host "    Download: https://github.com/$RepoOwner/$RepoName/releases/latest" -ForegroundColor White
    Write-Host ""
    Write-Host "    Users can now run:" -ForegroundColor Cyan
    Write-Host "    irm https://raw.githubusercontent.com/$RepoOwner/$RepoName/main/boot.ps1 | iex" -ForegroundColor White
} else {
    Write-Err "Release creation failed."
    exit 1
}
