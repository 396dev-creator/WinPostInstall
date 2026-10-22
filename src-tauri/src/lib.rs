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

/// Save the generated config JSON to a file next to the exe/PS1 script
#[tauri::command]
fn save_config(config_json: String, filename: String) -> Result<String, String> {
    let exe_dir = std::env::current_exe()
        .map_err(|e| format!("Cannot find exe path: {}", e))?;
    let dir = exe_dir.parent()
        .ok_or("Cannot determine exe directory")?;
    
    let config_path = dir.join(&filename);
    fs::write(&config_path, &config_json)
        .map_err(|e| format!("Failed to write config: {}", e))?;
    
    Ok(config_path.to_string_lossy().to_string())
}

/// Run WinPostInstall.ps1 with the given config file path
#[tauri::command]
async fn run_script(config_path: String) -> Result<ApplyResult, String> {
    let exe_dir = std::env::current_exe()
        .map_err(|e| format!("Cannot find exe path: {}", e))?;
    let dir = exe_dir.parent()
        .ok_or("Cannot determine exe directory")?;
    
    // Look for the PowerShell script next to the exe
    let ps1_path = dir.join("WinPostInstall.ps1");
    let cmd_path = dir.join("WinPostInstall.cmd");
    
    let script_path = if ps1_path.exists() {
        ps1_path.to_string_lossy().to_string()
    } else if cmd_path.exists() {
        cmd_path.to_string_lossy().to_string()
    } else {
        return Err("WinPostInstall.ps1 not found. Place it next to WinPostInstall.exe".to_string());
    };

    let output = std::process::Command::new("powershell")
        .args([
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", &script_path,
            "-ConfigFile", &config_path,
            "-Silent",
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
async fn apply_config(config_json: String, create_restore_point: bool) -> Result<ApplyResult, String> {
    let exe_dir = std::env::current_exe()
        .map_err(|e| format!("Cannot find exe path: {}", e))?;
    let dir = exe_dir.parent()
        .ok_or("Cannot determine exe directory")?;

    // 1. Save config file next to the exe
    let config_path = dir.join("WinPostInstall-Config.json");
    fs::write(&config_path, &config_json)
        .map_err(|e| format!("Failed to write config: {}", e))?;
    let config_path_str = config_path.to_string_lossy().to_string();

    // 2. Look for the PowerShell script next to the exe
    let ps1_path = dir.join("WinPostInstall.ps1");
    let cmd_path = dir.join("WinPostInstall.cmd");
    
    let script_path = if ps1_path.exists() {
        ps1_path.to_string_lossy().to_string()
    } else if cmd_path.exists() {
        cmd_path.to_string_lossy().to_string()
    } else {
        return Ok(ApplyResult {
            success: false,
            message: "WinPostInstall.ps1 not found. Place it next to WinPostInstall.exe".to_string(),
            config_path: config_path_str,
            stdout: String::new(),
            stderr: "WinPostInstall.ps1 not found next to executable".to_string(),
        });
    };

    // 3. Build the PowerShell command
    // Optionally create a restore point first
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
        "{}\n& \"{}\" -ConfigFile \"{}\" -Silent",
        restore_script, script_path, config_path_str
    );

    let output = std::process::Command::new("powershell")
        .args([
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-NonInteractive",
            "-Command", &full_script,
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

/// Get the directory where the exe is located (for saving configs)
#[tauri::command]
fn get_app_dir() -> Result<String, String> {
    let exe_dir = std::env::current_exe()
        .map_err(|e| format!("Cannot find exe path: {}", e))?;
    let dir = exe_dir.parent()
        .ok_or("Cannot determine exe directory")?;
    Ok(dir.to_string_lossy().to_string())
}

/// Open a file dialog to choose where to save the config
#[tauri::command]
async fn save_config_dialog(config_json: String) -> Result<String, String> {
    // This will be handled by the frontend using the File System Access API
    // or by the shell plugin. For now, save to app dir.
    save_config(config_json, "WinPostInstall-Config.json".to_string())
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
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
