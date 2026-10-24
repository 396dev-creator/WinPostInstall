use tauri::Manager;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

#[derive(Serialize, Deserialize, Clone)]
struct ApplyResult {
    success: bool,
    message: String,
    config_path: String,
    stdout: String,
    stderr: String,
}

/// Get the exe directory
fn get_exe_dir() -> Result<PathBuf, String> {
    let exe_path = std::env::current_exe()
        .map_err(|e| format!("Cannot find exe path: {}", e))?;
    let dir = exe_path.parent()
        .ok_or("Cannot determine exe directory")?
        .to_path_buf();
    Ok(dir)
}

/// Resolve the path to the WinPostInstall.ps1 script.
/// Search order:
///   1. Next to the exe
///   2. In the Tauri resource directory (when bundled via NSIS installer)
///   3. Download from GitHub and place next to the exe
fn resolve_script(app_handle: Option<&tauri::AppHandle>) -> Result<String, String> {
    let dir = get_exe_dir()?;

    // 1. Check next to the exe
    let ps1_path = dir.join("WinPostInstall.ps1");
    let cmd_path = dir.join("WinPostInstall.cmd");

    if ps1_path.exists() {
        return Ok(ps1_path.to_string_lossy().to_string());
    }
    if cmd_path.exists() {
        return Ok(cmd_path.to_string_lossy().to_string());
    }

    // 2. Check Tauri resource directory (when installed via NSIS)
    if let Some(app) = app_handle {
        if let Ok(resource_dir) = app.path().resource_dir() {
            let res_ps1 = resource_dir.join("WinPostInstall.ps1");
            let res_cmd = resource_dir.join("WinPostInstall.cmd");
            if res_ps1.exists() {
                // Copy to exe dir for future use
                let _ = fs::copy(&res_ps1, &ps1_path);
                return Ok(ps1_path.to_string_lossy().to_string());
            }
            if res_cmd.exists() {
                let _ = fs::copy(&res_cmd, &cmd_path);
                return Ok(cmd_path.to_string_lossy().to_string());
            }
        }
    }

    // 3. Also check common subdirectories that the NSIS installer might create
    let subdirs = ["resources", "scripts", "bin"];
    for sub in &subdirs {
        let sub_ps1 = dir.join(sub).join("WinPostInstall.ps1");
        let sub_cmd = dir.join(sub).join("WinPostInstall.cmd");
        if sub_ps1.exists() {
            let _ = fs::copy(&sub_ps1, &ps1_path);
            return Ok(ps1_path.to_string_lossy().to_string());
        }
        if sub_cmd.exists() {
            let _ = fs::copy(&sub_cmd, &cmd_path);
            return Ok(cmd_path.to_string_lossy().to_string());
        }
    }

    // 4. Fallback: download from GitHub and place next to the exe
    eprintln!("[WinPostInstall] PS1 script not found locally, downloading from GitHub...");
    let github_url = "https://raw.githubusercontent.com/396dev-creator/WinPostInstall/main/scripts/WinPostInstall.ps1";

    let download_result = std::process::Command::new("powershell")
        .args([
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-NonInteractive",
            "-Command",
            &format!("Invoke-WebRequest -Uri '{}' -OutFile '{}' -UseBasicParsing", github_url, ps1_path.to_string_lossy()),
        ])
        .output();

    match download_result {
        Ok(output) if output.status.success() && ps1_path.exists() => {
            eprintln!("[WinPostInstall] PS1 script downloaded successfully");
            Ok(ps1_path.to_string_lossy().to_string())
        }
        _ => {
            Err(format!(
                "WinPostInstall.ps1 not found locally and could not be downloaded.\n\
                 Searched: {}\n\
                 Also tried Tauri resources and GitHub download.\n\
                 Please place WinPostInstall.ps1 next to WinPostInstall.exe",
                dir.to_string_lossy()
            ))
        }
    }
}

/// Save the generated config JSON to a file next to the exe/PS1 script
#[tauri::command]
fn save_config(config_json: String, filename: String) -> Result<String, String> {
    let dir = get_exe_dir()?;
    let config_path = dir.join(&filename);
    fs::write(&config_path, &config_json)
        .map_err(|e| format!("Failed to write config: {}", e))?;
    Ok(config_path.to_string_lossy().to_string())
}

/// Run WinPostInstall.ps1 with the given config file path
#[tauri::command]
async fn run_script(app_handle: tauri::AppHandle, config_path: String) -> Result<ApplyResult, String> {
    let script_path = resolve_script(Some(&app_handle))?;

    // Wrap with UTF-8 encoding preamble + chcp 65001 so PowerShell output
    // is UTF-8 and Rust can decode it losslessly via String::from_utf8_lossy
    let wrapped_command = format!(
        "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; & \"{}\" -ConfigFile \"{}\" -Silent",
        script_path, config_path
    );
    let output = std::process::Command::new("cmd")
        .args([
            "/C",
            "chcp 65001 >nul 2>&1 & powershell -NoProfile -ExecutionPolicy Bypass -NonInteractive -Command",
            &wrapped_command,
        ])
        .output()
        .map_err(|e| format!("Failed to run script: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    let success = output.status.success();

    Ok(ApplyResult {
        success,
        message: if success { "Script completed successfully".to_string() } else { "Script failed".to_string() },
        config_path: config_path.clone(),
        stdout,
        stderr,
    })
}

/// Save config JSON and immediately run the script — single-step "Apply" workflow
#[tauri::command]
async fn apply_config(app_handle: tauri::AppHandle, config_json: String, create_restore_point: bool) -> Result<ApplyResult, String> {
    let dir = get_exe_dir()?;

    // 1. Save config file next to the exe
    let config_path = dir.join("WinPostInstall-Config.json");
    fs::write(&config_path, &config_json)
        .map_err(|e| format!("Failed to write config: {}", e))?;
    let config_path_str = config_path.to_string_lossy().to_string();

    // 2. Resolve the PS1 script (searches multiple locations, downloads if needed)
    let script_path = match resolve_script(Some(&app_handle)) {
        Ok(path) => path,
        Err(msg) => {
            return Ok(ApplyResult {
                success: false,
                message: "WinPostInstall.ps1 not found".to_string(),
                config_path: config_path_str,
                stdout: String::new(),
                stderr: msg,
            });
        }
    };

    // 3. Build the PowerShell command with UTF-8 encoding preamble
    let encoding_preamble = r#"
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        [Console]::InputEncoding  = [System.Text.Encoding]::UTF8
        $OutputEncoding = [System.Text.Encoding]::UTF8
    "#;

    // Self-elevation check: if not admin, warn (the PS1 script has its own
    // self-elevation, and the app manifest should also request elevation)
    let elevation_check = r#"
        if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Warning "[WARN] Not running as Administrator. Restore point and some settings may fail."
        }
    "#;

    let restore_script = if create_restore_point {
        r#"
        try {
            Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
            Checkpoint-Computer -Description "WinPostInstall Pre-Apply" -RestorePointType "MODIFY_SETTINGS"
            Write-Output "[OK] Restore point created"
        } catch {
            Write-Warning "[WARN] Could not create restore point: $_"
        }
        "#
    } else {
        ""
    };

    let full_script = format!(
        "{}\n{}\n{}\n& \"{}\" -ConfigFile \"{}\" -Silent",
        encoding_preamble, elevation_check, restore_script, script_path, config_path_str
    );

    // Set console codepage to UTF-8 (65001) BEFORE launching PowerShell
    let output = std::process::Command::new("cmd")
        .args([
            "/C",
            "chcp 65001 >nul 2>&1 & powershell -NoProfile -ExecutionPolicy Bypass -NonInteractive -Command",
            &full_script,
        ])
        .output()
        .map_err(|e| format!("Failed to run script: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    let success = output.status.success();

    Ok(ApplyResult {
        success,
        message: if success { "Settings applied successfully".to_string() } else { "Script execution failed".to_string() },
        config_path: config_path_str,
        stdout,
        stderr,
    })
}

/// Get the directory where the exe is located
#[tauri::command]
fn get_app_dir() -> Result<String, String> {
    let dir = get_exe_dir()?;
    Ok(dir.to_string_lossy().to_string())
}

/// Open a file dialog to choose where to save the config
#[tauri::command]
async fn save_config_dialog(config_json: String) -> Result<String, String> {
    save_config(config_json, "WinPostInstall-Config.json".to_string())
}

// ═══════════════════════════════════════════════════════════════════
// AMNESIC CLEANUP — "burn after reading" / leave no trace
// ═══════════════════════════════════════════════════════════════════

/// Wipe all artifacts from the client machine:
///   - Config JSON files (WinPostInstall-Config*.json) in exe dir, %TEMP%, Downloads, and OneDrive Downloads
///   - PowerShell script (WinPostInstall.ps1, .cmd)
///   - PS1 log files in %TEMP% and C:\Temp
///   - The exe itself (via detached cmd process)
///   - The app directory (if empty after cleanup)
fn cleanup_artifacts() {
    if let Ok(dir) = get_exe_dir() {
        // 1. Delete all config JSON files in the app directory
        if let Ok(entries) = fs::read_dir(&dir) {
            for entry in entries.flatten() {
                if let Some(name) = entry.file_name().to_str() {
                    if name.starts_with("WinPostInstall-Config") && name.ends_with(".json") {
                        let _ = fs::remove_file(entry.path());
                    }
                }
            }
        }

        // 2. Delete the PowerShell script and CMD launcher
        let _ = fs::remove_file(dir.join("WinPostInstall.ps1"));
        let _ = fs::remove_file(dir.join("WinPostInstall.cmd"));

        // 3. Clean up PS1 log files from %TEMP% and C:\Temp
        if let Ok(temp_dir) = std::env::var("TEMP") {
            let temp_path = PathBuf::from(&temp_dir);
            if let Ok(entries) = fs::read_dir(&temp_path) {
                for entry in entries.flatten() {
                    if let Some(name) = entry.file_name().to_str() {
                        // WinPostInstall configs/logs in user temp
                        if name.starts_with("WinPostInstall") || name.starts_with("PostInstall_") {
                            let _ = fs::remove_file(entry.path());
                        }
                    }
                }
            }
        }
        // Also check C:\Temp for PostInstall_*.log
        let system_temp = PathBuf::from(r"C:\Temp");
        if system_temp.exists() {
            if let Ok(entries) = fs::read_dir(&system_temp) {
                for entry in entries.flatten() {
                    if let Some(name) = entry.file_name().to_str() {
                        if name.starts_with("PostInstall_") && name.ends_with(".log") {
                            let _ = fs::remove_file(entry.path());
                        }
                    }
                }
            }
        }

        // 4. Clean up downloaded config JSON files from the user's Downloads folder
        //    (the JS downloadConfig() function saves timestamped copies there)
        if let Ok(user_profile) = std::env::var("USERPROFILE") {
            let downloads_path = PathBuf::from(&user_profile).join("Downloads");
            if downloads_path.exists() {
                if let Ok(entries) = fs::read_dir(&downloads_path) {
                    for entry in entries.flatten() {
                        if let Some(name) = entry.file_name().to_str() {
                            if name.starts_with("WinPostInstall-Config") && name.ends_with(".json") {
                                let _ = fs::remove_file(entry.path());
                            }
                        }
                    }
                }
            }
        }
        // Also check OneDrive Downloads if present
        if let Ok(user_profile) = std::env::var("USERPROFILE") {
            let onedrive_downloads = PathBuf::from(&user_profile).join("OneDrive").join("Downloads");
            if onedrive_downloads.exists() {
                if let Ok(entries) = fs::read_dir(&onedrive_downloads) {
                    for entry in entries.flatten() {
                        if let Some(name) = entry.file_name().to_str() {
                            if name.starts_with("WinPostInstall-Config") && name.ends_with(".json") {
                                let _ = fs::remove_file(entry.path());
                            }
                        }
                    }
                }
            }
        }

        // 5. Self-delete the exe (Windows: a process can't delete its own exe while running)
        //    Spawn a detached `cmd /c` that waits ~3 seconds, then force-deletes the exe.
        if let Ok(exe_path) = std::env::current_exe() {
            let exe_str = exe_path.to_string_lossy().to_string();
            // ping -n 3 127.0.0.1 ≈ 2-3 second delay, then del /f /q
            let delete_cmd = format!(
                "ping -n 3 127.0.0.1 >nul 2>&1 & del /f /q \"{}\"",
                exe_str
            );
            #[cfg(target_os = "windows")]
            {
                use std::os::windows::process::CommandExt;
                const DETACHED_PROCESS: u32 = 0x00000008;
                const CREATE_NO_WINDOW: u32 = 0x08000000;
                let _ = std::process::Command::new("cmd")
                    .args(["/C", &delete_cmd])
                    .creation_flags(DETACHED_PROCESS | CREATE_NO_WINDOW)
                    .spawn();
            }
            #[cfg(not(target_os = "windows"))]
            {
                // Non-Windows fallback: just try to remove directly
                // (on Linux/macOS a process CAN unlink its own exe)
                let _ = fs::remove_file(&exe_path);
            }
        }

        // 6. If the app directory is now empty (and not a system dir), remove it too
        if let Ok(entries) = fs::read_dir(&dir) {
            let remaining: Vec<_> = entries.flatten().collect();
            if remaining.is_empty() {
                let _ = fs::remove_dir(&dir);
            }
        }
    }
}

/// Explicit Tauri command for the frontend to trigger cleanup + exit
#[tauri::command]
fn cleanup_and_exit(app: tauri::AppHandle) {
    cleanup_artifacts();
    app.exit(0);
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .invoke_handler(tauri::generate_handler![
            save_config,
            run_script,
            apply_config,
            get_app_dir,
            save_config_dialog,
            cleanup_and_exit,
        ])
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                // Prevent the default close — we need to clean up first
                api.prevent_close();

                // Clone the app handle so we can use it in the thread
                let app_handle = window.app_handle().clone();

                // Spawn a thread: cleanup artifacts, then exit the process
                std::thread::spawn(move || {
                    cleanup_artifacts();
                    app_handle.exit(0);
                });
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
