# Self-Deleting App Distribution via `irm | iex` from GitHub

## How the Pattern Works

```
irm https://get.activated.win | iex
```

| Step | Command | What Happens |
|------|---------|-------------|
| 1 | `irm` (Invoke-RestMethod) | Downloads the **text content** of the script at that URL |
| 2 | `\| iex` (Invoke-Expression) | Executes that text as PowerShell code **in the current session** |
| 3 | Inside the script | Downloads your `.exe` to `$env:TEMP`, runs it, waits, deletes everything |

The key insight: **the bootstrap script IS the distribution mechanism**. You host a `.ps1` file on GitHub, and the one-liner fetches + runs it.

---

## Architecture

```
User runs:  irm https://raw.githubusercontent.com/USER/REPO/main/boot.ps1 | iex
                                    │
                                    ▼
                          ┌─────────────────┐
                          │   boot.ps1      │  ← Your bootstrap script on GitHub
                          │                 │
                          │  1. Query GH    │
                          │     Releases API│
                          │  2. Download    │
                          │     latest .exe │
                          │  3. Run it      │
                          │  4. Wait        │
                          │  5. Delete all  │
                          └─────────────────┘
                                    │
                                    ▼
                    ┌───────────────────────────────┐
                    │  GitHub Releases               │
                    │                                │
                    │  v1.2.0  ── WinPostInstall.exe │  ← You upload built .exe here
                    │  v1.1.0  ── WinPostInstall.exe │
                    └───────────────────────────────┘
```

---

## Setup Steps

### Step 1: Host `boot.ps1` in Your Repo

Place `boot.ps1` at the **root** of your GitHub repository. Edit these variables at the top:

```powershell
$RepoOwner = "YourGitHubUsername"    # ← Your GitHub username
$RepoName  = "YourRepoName"          # ← Your repository name
$ExeName   = "WinPostInstall.exe"    # ← Your executable name
```

Commit and push. The script will be available at:
```
https://raw.githubusercontent.com/YourGitHubUsername/YourRepoName/main/boot.ps1
```

### Step 2: Build Your Executable

```bash
# From your Tauri project root
cargo tauri build

# The exe will be at:
# src-tauri/target/release/WinPostInstall.exe
```

### Step 3: Create a GitHub Release

**Option A — Using the provided script** (requires [GitHub CLI](https://cli.github.com/)):
```powershell
.\publish-release.ps1 -Version "v1.0.0"
```

**Option B — Using `gh` directly:**
```powershell
gh release create v1.0.0 src-tauri/target/release/WinPostInstall.exe --repo USER/REPO --title "WinPostInstall v1.0.0"
```

**Option C — Manual:**
1. Go to `https://github.com/USER/REPO/releases/new`
2. Tag: `v1.0.0`
3. Upload `WinPostInstall.exe` as an asset
4. Publish

### Step 4: Users Run the One-Liner

```powershell
irm https://raw.githubusercontent.com/USER/REPO/main/boot.ps1 | iex
```

---

## Making It Prettier — Custom Short URL

You can use a redirect service to get a shorter, cleaner URL:

| Service | Custom URL | Redirects To |
|---------|-----------|--------------|
| GitHub Pages | `https://USER.github.io/REPO/get` | Your raw boot.ps1 |
| jsDelivr CDN | `https://cdn.jsdelivr.net/gh/USER/REPO/boot.ps1` | Cached raw content |
| TinyURL / Bitly | `https://get.winpostinstall.app` | Your raw boot.ps1 |

### GitHub Pages Method (recommended — free, stays in your control):

1. Create `docs/get.ps1` that is a copy of `boot.ps1`
2. Enable GitHub Pages → Source: `docs/` folder
3. Users run:
```powershell
irm https://USER.github.io/REPO/get.ps1 | iex
```

---

## Two Provided Variants

| File | Description |
|------|-------------|
| `boot.ps1` | Full-featured: progress bar, colored output, robust cleanup with fallback |
| `boot-minimal.ps1` | Minimal: ~20 lines, fast, simple retry cleanup |

---

## Cleanup Mechanism Details

The bootstrap script handles cleanup in multiple layers:

```
Layer 1: Direct deletion (Remove-Item -Force)
    │
    ├─ Success → Done, no traces
    │
    └─ Fails (file still locked) →
         │
         Layer 2: Spawn hidden background PowerShell
         │         that retries deletion every 1 second
         │         for up to 30 seconds
         │
         └─ Still locked →
              │
              Layer 3: Mark for deletion on next reboot
              (Windows will delete the files at startup)
```

This ensures **no traces are ever left** regardless of timing or file locks.

---

## Security Considerations

| Concern | Mitigation |
|---------|-----------|
| **TLS/HTTPS** | GitHub raw URLs and API are always HTTPS — no MITM |
| **Release integrity** | Consider adding SHA256 hash check in boot.ps1 |
| **Code signing** | Sign your .exe with an Authenticode certificate to avoid SmartScreen warnings |
| **Repo impersonation** | Users should verify the URL is truly your GitHub account |
| **PowerShell execution policy** | `irm \| iex` bypasses execution policy (runs in memory) — this is intentional |

### Adding Hash Verification (optional enhancement):

Add this to `boot.ps1` after downloading:

```powershell
$ExpectedHash = "ABC123DEF456..."  # Update with each release
$ActualHash   = (Get-FileHash -Path $TempExe -Algorithm SHA256).Hash
if ($ActualHash -ne $ExpectedHash) {
    Write-Err "Hash mismatch! File may be corrupted or tampered."
    Remove-Item $TempDir -Recurse -Force -EA SilentlyContinue
    return
}
Write-OK "Integrity verified"
```

---

## Complete Workflow Summary

```
Developer side:
  1. Build .exe        →  cargo tauri build
  2. Create release    →  gh release create v1.0.0 ./path/to/WinPostInstall.exe
  3. Push boot.ps1     →  git add boot.ps1 && git commit && git push

User side:
  1. Open PowerShell
  2. Run one command   →  irm https://raw.githubusercontent.com/USER/REPO/main/boot.ps1 | iex
  3. App runs, closes
  4. Everything deleted →  No traces in temp, no install residue
```
