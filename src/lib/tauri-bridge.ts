/**
 * Tauri Shell Bridge
 * Provides functions to execute PowerShell commands via the Tauri shell plugin.
 * When running in Tauri desktop mode, commands execute directly on the host.
 * When running in web/browser mode, falls back to config file download.
 */

import { sections } from "@/data/settings";

// Check if we're running inside Tauri
export function isTauriApp(): boolean {
  return typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
}

// Dynamic import of Tauri API (only available in desktop mode)
async function getTauriShell() {
  if (!isTauriApp()) return null;
  try {
    const { Command } = await import("@tauri-apps/plugin-shell");
    return { Command };
  } catch {
    return null;
  }
}

export interface ExecutionResult {
  success: boolean;
  stdout: string;
  stderr: string;
  code: number | null;
}

/**
 * Encode a PowerShell script for the -EncodedCommand parameter.
 * PowerShell expects Base64 of the script encoded as UTF-16LE.
 *
 * WHY: -Command with multi-line scripts and embedded quotes is fragile on
 * Windows (quoting/newline corruption => "A command must follow -Command").
 * -EncodedCommand carries the script as opaque Base64 — zero quoting issues.
 * JS strings are already UTF-16 code units, so charCodeAt gives us the
 * UTF-16LE bytes directly (surrogate pairs handled naturally).
 */
function encodePsCommand(script: string): string {
  const bytes: number[] = [];
  for (let i = 0; i < script.length; i++) {
    const code = script.charCodeAt(i);
    bytes.push(code & 0xff, (code >> 8) & 0xff);
  }
  let binary = "";
  const CHUNK = 0x8000; // avoid arg-length limits in String.fromCharCode.apply
  for (let i = 0; i < bytes.length; i += CHUNK) {
    binary += String.fromCharCode(...bytes.slice(i, i + CHUNK));
  }
  return btoa(binary);
}

/**
 * Execute a PowerShell command via Tauri shell
 */
export async function executePowerShell(script: string): Promise<ExecutionResult> {
  const shell = await getTauriShell();
  if (!shell) {
    return {
      success: false,
      stdout: "",
      stderr: "Not running in Tauri desktop mode. Use the web version to download config.",
      code: -1,
    };
  }

  try {
    // Wrap user script with a UTF-8 console encoding preamble (try/catch: the
    // [Console] API can throw when stdout is redirected with no console).
    const fullScript = `try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }\n${script}`;

    const command = shell.Command.create("powershell", [
      "-NoProfile",
      "-NonInteractive",
      "-ExecutionPolicy", "Bypass",
      "-EncodedCommand", encodePsCommand(fullScript),
    ]);

    const result = await command.execute();
    return {
      success: result.code === 0,
      stdout: result.stdout,
      stderr: result.stderr,
      code: result.code,
    };
  } catch (error) {
    return {
      success: false,
      stdout: "",
      stderr: String(error),
      code: -1,
    };
  }
}

/**
 * Create a system restore point
 */
export async function createRestorePoint(description: string = "WinPostInstall Pre-Apply"): Promise<ExecutionResult> {
  const script = `
    try {
      # Enable System Restore
      Enable-ComputerRestore -Drive "C:\\" -ErrorAction SilentlyContinue
      
      # Create restore point
      Checkpoint-Computer -Description "${description}" -RestorePointType "MODIFY_SETTINGS"
      
      Write-Output "Restore point created successfully: ${description}"
    } catch {
      Write-Error "? Failed to create restore point: $_"
      exit 1
    }
  `;
  return executePowerShell(script);
}

/**
 * Apply the WinPostInstall script with a config file
 */
export async function applyWithConfig(configPath: string, scriptPath: string): Promise<ExecutionResult> {
  const script = `
    try {
      # Run WinPostInstall.ps1 with the config file
      # NOTE: -Silent is a valid script param; -NonInteractive is NOT and would
      # cause a parameter binding error.
      & '${scriptPath.replace(/'/g, "''")}' -ConfigFile '${configPath.replace(/'/g, "''")}' -Silent
      Write-Output "WinPostInstall applied successfully"
    } catch {
      Write-Error "Failed to apply: $_"
      exit 1
    }
  `;
  return executePowerShell(script);
}

/**
 * Scan the current system registry state
 */
export async function scanRegistryState(): Promise<ExecutionResult> {
  const script = `
    $results = @{}
    
    # Check telemetry
    try {
      $val = (Get-ItemProperty -Path "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\DataCollection" -Name "AllowTelemetry" -ErrorAction Stop).AllowTelemetry
      $results["Priv_1"] = ($val -ne 3)
    } catch { $results["Priv_1"] = $false }
    
    # Check advertising ID
    try {
      $val = (Get-ItemProperty -Path "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\AdvertisingInfo" -Name "Enabled" -ErrorAction Stop).Enabled
      $results["Priv_5"] = ($val -ne 1)
    } catch { $results["Priv_5"] = $false }
    
    # Check Cortana/Bing
    try {
      $val = (Get-ItemProperty -Path "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Search" -Name "BingSearchEnabled" -ErrorAction Stop).BingSearchEnabled
      $results["Priv_2"] = ($val -ne 1)
    } catch { $results["Priv_2"] = $false }
    
    # Check activity history
    try {
      $val = (Get-ItemProperty -Path "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System" -Name "EnableActivityHistory" -ErrorAction Stop).EnableActivityHistory
      $results["Priv_3"] = ($val -eq 0)
    } catch { $results["Priv_3"] = $false }
    
    $results | ConvertTo-Json -Compress
  `;
  return executePowerShell(script);
}

/**
 * Generate and save config, then optionally execute via Tauri
 */
export async function liveApply(
  settings: Record<string, boolean>,
  selectedSoftware: string[],
  createRestorePoint: boolean,
  activeProfileId: string | null
): Promise<ExecutionResult> {
  if (!isTauriApp()) {
    return {
      success: false,
      stdout: "",
      stderr: "Not running in Tauri desktop mode. Use 'Download Config' to get the JSON file.",
      code: -1,
    };
  }

  // Build config
  const configSections: Record<string, Record<string, boolean>> = {};
  sections.forEach((section) => {
    const sectionSettings: Record<string, boolean> = {};
    section.settings.forEach((s) => {
      sectionSettings[s.id] = settings[s.id] ?? false;
    });
    configSections[section.id] = sectionSettings;
  });

  const config = {
    version: "4.1.6",
    generatedAt: new Date().toISOString(),
    createRestorePoint,
    sections: configSections,
    software: selectedSoftware,
    activeProfile: activeProfileId,
  };

  const configJson = JSON.stringify(config, null, 2);

  // Write config to temp file, then execute the PS1 script
  const script = `
    $configPath = [System.IO.Path]::Combine($env:TEMP, 'WinPostInstall-Config.json')
    @'
${configJson}
'@ | Out-File -FilePath $configPath -Encoding UTF8
    
    ${createRestorePoint ? `
    # Create restore point
    try {
      Enable-ComputerRestore -Drive "C:\\" -ErrorAction SilentlyContinue
      Checkpoint-Computer -Description "WinPostInstall Pre-Apply" -RestorePointType "MODIFY_SETTINGS"
      Write-Output "[OK] Restore point created"
    } catch {
      Write-Warning "[WARN] Could not create restore point: $_"
    }
    ` : ""}
    
    # Find the script
    $scriptPath = Join-Path $env:TEMP "WinPostInstall.ps1"
    if (-not (Test-Path $scriptPath)) {
      # Try current directory
      $scriptPath = ".\\WinPostInstall.ps1"
    }
    
    if (Test-Path $scriptPath) {
      Write-Output "[OK] Executing WinPostInstall.ps1 with config..."
      & $scriptPath -ConfigFile $configPath -Silent
      Write-Output "[OK] Application complete"
    } else {
      Write-Error "[ERROR] WinPostInstall.ps1 not found. Please ensure it is in the temp directory or current path."
      Write-Output "Config saved to: $configPath"
      exit 1
    }
  `;

  return executePowerShell(script);
}
