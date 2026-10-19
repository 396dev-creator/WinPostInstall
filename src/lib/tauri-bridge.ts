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
    const command = shell.Command.create("powershell", [
      "-NoProfile",
      "-NonInteractive",
      "-ExecutionPolicy", "Bypass",
      "-Command", script,
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
      & "${scriptPath}" -ConfigFile "${configPath}" -NonInteractive
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
    version: "4.1.0",
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
      & $scriptPath -ConfigFile $configPath -NonInteractive
      Write-Output "[OK] Application complete"
    } else {
      Write-Error "[ERROR] WinPostInstall.ps1 not found. Please ensure it is in the temp directory or current path."
      Write-Output "Config saved to: $configPath"
      exit 1
    }
  `;

  return executePowerShell(script);
}
