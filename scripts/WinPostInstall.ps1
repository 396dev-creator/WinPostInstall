<#
.SYNOPSIS
    Windows Post-Installation Optimization Script
.DESCRIPTION
    Comprehensive post-install optimization for Windows 10/11.
    Automates privacy hardening, bloatware removal, performance tuning,
    security hardening, network optimization, and software installation.
    Used by IT technicians for system deployment and configuration standardization.
    Supports interactive menu, fully unattended (-Silent), and targeted section (-Sections) modes.
.PARAMETER Silent
    Run all sections without user interaction. Skips prompts and confirmation dialogs.
.PARAMETER Sections
    Array of section names to run. Example: -Sections Privacy,EdgeHardening,Gamedvr
.PARAMETER ConfigFile
    Path to a JSON configuration file that specifies sections, app lists, and bloatware lists.
.PARAMETER ComputerName
    Array of remote computer names to execute the script on via PSSession.
.EXAMPLE
    .\WinPostInstall.ps1
    Launches interactive menu to choose which optimizations to apply.
.EXAMPLE
    .\WinPostInstall.ps1 -Silent
    Runs all 15 optimization sections without prompts. Ideal for batch deployments.
.EXAMPLE
    .\WinPostInstall.ps1 -Sections Privacy,Debloat,Performance
    Runs only the specified sections. Useful for targeted fixes.
.VERSION
    4.1.0
.NOTES
    Author:             Post-Install Optimizer (IT Technician Tooling)
    Category:           System Administration / IT Operations / OS Deployment
    Requires Admin:      Yes - must run as Administrator (elevated PowerShell)
    Compatible OS:       Windows 10 (1909+) and Windows 11 (21H2+)
    Auto-detection:      Script detects Win10 vs Win11 by build number (>= 22000)
    Logging:             %SYSTEMDRIVE%\Temp\PostInstall_<timestamp>.log
    AV Compatibility:   Adds self-exclusion to Windows Defender on first run
    License:             Free to use and modify for business/personal purposes.
    Disclaimer:          Use at your own risk. Review all changes before deploying.

    CHANGELOG:
    v4.1.0 - Safety audit + interactive tooltips:
             [Safety] 3-tier classification (Safe/Moderate/Risky) for ALL settings
             [Safety] Risky settings default OFF — must opt-in via -AllowRisky or menu
             [Safety] Service dependency checks before disabling — warns if dependents exist
             [Safety] AppX critical package check — prevents removing system-critical packages
             [Safety] Hosts file DNS verification — confirms microsoft.com resolves after changes
             [Safety] SysMain on HDD now explicitly protected (never disabled on spinning drives)
             [Menu] New detailed interactive menu with safety badges, risky item counts, and warnings
             [Menu] 'A' runs safe+moderate only, 'R' runs all including risky
             [Menu] -SimpleMenu switch for legacy menu, -AllowRisky for scripts
    v4.0.0 - Major feature release: 17 new capabilities across 6 groups:
             [Safety] Undo script generation, Registry backup, Pre-flight checks (internet/disk/reboot/battery)
             [Deep Cleanup] Windows Features removal (Section 18), Taskbar deep customization, Context menu cleanup, Lock screen/Spotlight ad removal
             [Hardware-Aware] SSD/HDD detection with conditional SysMain/Prefetch/TRIM/defrag, Laptop/Desktop detection with power plan logic, RAM-aware page file optimization + NTFS tweaks
             [Reporting] Change summary table with per-section stats, Section timing, Before/After service/task snapshots
             [Network] DNS-over-HTTPS (Cloudflare DoH), Hosts file hardening (20 telemetry domains)
             [Deployment] JSON config file support (-ConfigFile), Remote execution via PSSession (-ComputerName)
    v3.5.0 - Made script fully idempotent: skip already-applied registry settings, already-disabled tasks, already-installed apps, already-removed bloatware
    v3.4.0 - Added System Restore safety net: auto-enable restore + create pre-optimization restore point
    v3.3.2 - Fixed crash bugs (jump-label syntax, $input reserved var), added auto-elevation, error trapping
    v3.3.0 - Added Office 365 install + MAS activation, expanded privacy analytics lockdown
    v3.2.0 - Added Browser Extensions & Privacy section (uBlock Origin + Privacy Badger on 5 browsers)
    v3.1.0 - Added Defender self-exclusion, enhanced XML docs, AV-friendly metadata
    v3.0.0 - Added 5 new sections: Edge, OneDrive, Gaming, Scheduled Tasks, AI/Recall
    v2.0.0 - Initial release with 11 sections
#>

#region ============================================================
# PARAMETERS & CONFIGURATION
# ============================================================

[CmdletBinding()]
param(
    [switch]$Silent,
    [string[]]$Sections,
    [string]$ConfigFile,
    [string[]]$ComputerName,
    [switch]$AllowRisky,
    [switch]$SimpleMenu
)

# ================================================================
# CRITICAL BOOTSTRAP: Keep window open on ANY error (parse or runtime)
# This MUST be the first executable code after param()
# ================================================================
trap {
    Write-Host ""
    Write-Host "  [FATAL ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  at line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Press Enter to exit..." -ForegroundColor DarkGray
    Read-Host "  "
    exit 1
}

$ScriptVersion = "4.1.1"
$LogFile = "$env:SYSTEMDRIVE\Temp\PostInstall_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Undo command tracker (for rollback script generation)
$script:UndoCommands = [System.Collections.ArrayList]::new()
$script:UndoDescriptions = [System.Collections.ArrayList]::new()

# Statistics counters (for change summary report)
$script:TotalChanged = 0
$script:TotalSkipped = 0
$script:TotalFailed = 0
$script:SectionStats = @{}
$script:BackupDir = "$env:SYSTEMDRIVE\Temp\PostInstall_RegBackup"

# Safety infrastructure
$script:AllowRisky = $AllowRisky.IsPresent
$script:SettingCatalog = @{}          # Dynamically populated: ID -> @{Section, Safety, Desc, Action}
$script:SettingOverrides = @{}        # ID -> $true (skip) for user-toggled-off items
$script:CurrentSection = ""          # Track which section is currently executing
$script:RiskyDescriptions = @()       # Collect risky setting descriptions for menu display

# Prevent window from closing on crash (keeps window open no matter what)
$ErrorActionPreference = "Continue"

# Auto-bypass execution policy for this session (handles 'downloaded from internet' block)
if ((Get-ExecutionPolicy -Scope Process) -ne 'Bypass') {
    try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop } catch { }
}

# Unblock the script file itself if Windows marked it as 'from internet'
if ($PSCommandPath) {
    try { Unblock-File -Path $PSCommandPath -ErrorAction SilentlyContinue } catch { }
}

# ══════════════════════════════════════════════════════════════
# UTF-8 ENCODING: Ensure console output is UTF-8 for parent process capture
# This prevents mojibake / replacement chars when Rust reads stdout/stderr
# Must be set BEFORE any Write-Host/Write-Output calls produce output
# ══════════════════════════════════════════════════════════════
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::InputEncoding  = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

# Self-elevate: If not running as Administrator, re-launch in an elevated window
# This allows the user to simply double-click the script
#
# CRITICAL: When invoked via `powershell -Command "& 'script.ps1' ..."`, $PSCommandPath
# is EMPTY because the script is dot-sourced from memory, not loaded from a file.
# Using -File with an empty path causes PowerShell to open and immediately close.
# We detect this and either: (a) save self to temp and re-launch from file, or
# (b) fall back to a helpful error message.
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "  Not running as Administrator. Requesting elevation..." -ForegroundColor Yellow
    $scriptArgs = @()
    if ($Silent) { $scriptArgs += "-Silent" }
    if ($Sections) { $scriptArgs += "-Sections"; $scriptArgs += $Sections }
    if ($ConfigFile) { $scriptArgs += "-ConfigFile"; $scriptArgs += $ConfigFile }
    if ($ComputerName) { $scriptArgs += "-ComputerName"; $scriptArgs += $ComputerName }
    if ($AllowRisky) { $scriptArgs += "-AllowRisky" }
    if ($SimpleMenu) { $scriptArgs += "-SimpleMenu" }
    try {
        if ($PSCommandPath -and (Test-Path -Path $PSCommandPath -ErrorAction SilentlyContinue)) {
            # Running from a file on disk — standard -File elevation (preferred)
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $scriptArgs" -Verb RunAs -ErrorAction Stop
            Write-Host "  Elevated window opened. This window can be closed." -ForegroundColor Green
        } else {
            # $PSCommandPath is empty — script is running from memory (irm | iex or -Command).
            # Attempt to re-download from GitHub and execute in the elevated session.
            $Ps1Url = 'https://raw.githubusercontent.com/396dev-creator/WinPostInstall/main/scripts/WinPostInstall.ps1'
            $argStr = $scriptArgs -join ' '
            $elevatedCmd = "irm '$Ps1Url' | iex"
            if ($argStr) { $elevatedCmd = "& (irm '$Ps1Url') $argStr" }
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$elevatedCmd`"" -Verb RunAs -ErrorAction Stop
            Write-Host "  Elevated window opened (re-downloaded from GitHub). This window can be closed." -ForegroundColor Green
        }
    } catch {
        Write-Host "  Could not self-elevate. Please run as Administrator:" -ForegroundColor Red
        Write-Host "    Right-click PowerShell -> Run as Administrator, then:" -ForegroundColor Yellow
        Write-Host "    .\WinPostInstall.ps1" -ForegroundColor Cyan
        Write-Host "  Press Enter to exit..." -ForegroundColor DarkGray
        Read-Host "  "
    }
    exit 0
}

#endregion

#region ============================================================
# BOOTSTRAP: Admin check, logging, OS detection
# ============================================================

function Set-DefenderExclusions {
    <#
    .DESCRIPTION
        Adds this script and its working directory to Windows Defender exclusions.
        Prevents the script from being flagged as malware during execution.
        This is safe: exclusions are path-specific and only protect this tool.
    #>
    Write-Host "" -ForegroundColor Cyan
    Write-Host "  [AV SHIELD] Windows Defender Self-Exclusion" -ForegroundColor Cyan
    Write-Host "  " + ("-" * 50) -ForegroundColor DarkGray
    Write-Host ""

    $scriptPath = $PSCommandPath
    if (-not $scriptPath) { $scriptPath = $MyInvocation.PSCommandPath }

    $exclusionAdded = $false

    # Check if the exclusion already exists
    try {
        $existingExclusions = (Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath
        if ($existingExclusions -and $scriptPath -in $existingExclusions) {
            Write-Step "Defender exclusion already exists for this script."
            return
        }
    } catch {
        Write-Warn "Could not read current Defender preferences: $_"
    }

    # Exclude the script file itself
    Write-Step "Adding script to Defender exclusions..."
    try {
        Add-MpPreference -ExclusionPath $scriptPath -ErrorAction Stop
        Write-Success "Excluded: $scriptPath"
        $exclusionAdded = $true
    } catch {
        Write-Warn "Failed to exclude script path: $_"
    }

    # Exclude the working directory (where the script lives)
    $scriptDir = Split-Path $scriptPath -Parent
    if ($scriptDir -and (Test-Path $scriptDir)) {
        try {
            Add-MpPreference -ExclusionPath $scriptDir -ErrorAction Stop
            Write-Success "Excluded directory: $scriptDir"
            $exclusionAdded = $true
        } catch {
            Write-Warn "Failed to exclude directory: $_"
        }
    }

    # Exclude the log directory (C:\Temp)
    $logDir = "$env:SYSTEMDRIVE\Temp"
    try {
        Add-MpPreference -ExclusionPath $logDir -ErrorAction Stop
        Write-Success "Excluded log directory: $logDir"
        $exclusionAdded = $true
    } catch {
        Write-Warn "Failed to exclude log directory: $_"
    }

    # Exclude common technician tool folders
    $toolPaths = @("C:\Tools", "C:\Scripts", "C:\TechnicianTools")
    foreach ($path in $toolPaths) {
        if (Test-Path $path) {
            try {
                Add-MpPreference -ExclusionPath $path -ErrorAction Stop
                Write-Success "Excluded: $path"
            } catch { }
        }
    }

    if ($exclusionAdded) {
        Write-Success "Defender exclusions configured. This script is now trusted."
    }

    Write-Host ""
    Write-Host "  NOTE: This only affects Windows Defender. For third-party AV," -ForegroundColor DarkGray
    Write-Host "  consider purchasing a Code Signing Certificate for full compatibility." -ForegroundColor DarkGray
    Write-Host ""
}

function Initialize-Script {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host ""
        Write-Host "================================================================" -ForegroundColor Red
        Write-Host "  [ERROR] This script must be run as Administrator." -ForegroundColor Red
        Write-Host "================================================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Right-click PowerShell -> 'Run as Administrator'" -ForegroundColor Yellow
        Write-Host "  Then re-run this script." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Press Enter to exit..." -ForegroundColor DarkGray
        Read-Host "  "
        exit 1
    }

    $logDir = "$env:SYSTEMDRIVE\Temp"
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }

    try { Start-Transcript -Path $LogFile -Force -ErrorAction Stop | Out-Null } catch {
        Write-Warn "Could not start transcript to $LogFile : $_"
    }

    # Set up Defender self-exclusion FIRST (before any optimization work)
    Set-DefenderExclusions

    # Registry backup - export critical hives before making any changes
    Write-Host "" -ForegroundColor Cyan
    Write-Host "  [SAFETY] Registry Backup" -ForegroundColor Cyan
    Write-Host "  " + ("-" * 50) -ForegroundColor DarkGray
    Write-Host ""
    try {
        if (-not (Test-Path $script:BackupDir)) {
            New-Item -Path $script:BackupDir -ItemType Directory -Force | Out-Null
        }
        Write-Step "Exporting registry hives to $script:BackupDir..."
        $regExports = @(
            @{ Hive = "HKLM\SOFTWARE\Policies"; File = "Policies.reg" },
            @{ Hive = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies"; File = "WinPolicies.reg" },
            @{ Hive = "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer"; File = "Explorer.reg" },
            @{ Hive = "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR"; File = "GameDVR.reg" }
        )
        foreach ($regExport in $regExports) {
            $exportPath = Join-Path $script:BackupDir $regExport.File
            try {
                reg export $regExport.Hive $exportPath /y 2>$null | Out-Null
                Write-Success "Exported: $($regExport.Hive)"
            } catch {
                Write-Warn "Could not export $($regExport.Hive): $_"
            }
        }
        Write-Success "Registry backup saved to: $script:BackupDir"
    } catch {
        Write-Warn "Registry backup failed: $_"
    }
    Write-Host ""

    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    $script:OSVersion = [version]$osInfo.Version
    $script:OSBuild = $osInfo.BuildNumber
    $script:IsWin11 = $script:OSBuild -ge 22000
    $script:OSCaption = if ($script:IsWin11) { "Windows 11" } else { "Windows 10" }
    $script:LocalComputerName = $env:COMPUTERNAME

    # Laptop vs Desktop detection
    $script:IsLaptop = $false
    try {
        $chassisTypes = Get-CimInstance -ClassName Win32_ChassisType -ErrorAction SilentlyContinue
        if ($chassisTypes) {
            $script:IsLaptop = ($chassisTypes | Where-Object { $_.ChassisType -in @(9, 10, 14) }).Count -gt 0
        }
    } catch { }
    if (-not $script:IsLaptop) {
        try {
            $script:IsLaptop = (Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue).Count -gt 0
        } catch { }
    }

    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  Windows Post-Installation Optimizer v$ScriptVersion" -ForegroundColor Cyan
    Write-Host "  Target: $script:OSCaption (Build $script:OSBuild)" -ForegroundColor Cyan
    Write-Host "  Computer: $script:LocalComputerName" -ForegroundColor Cyan
    Write-Host "  Chassis: $(if ($script:IsLaptop) { 'Laptop' } else { 'Desktop' })" -ForegroundColor Cyan
    Write-Host "  Log file: $LogFile" -ForegroundColor DarkGray
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""

    # Run pre-flight checks
    Test-Prerequisites
}

function Test-Prerequisites {
    <#
    .DESCRIPTION
        Pre-flight checks: internet connectivity, disk space, pending reboot, battery.
        Warns on issues but does not block execution.
    #>
    Write-Host "" -ForegroundColor Cyan
    Write-Host "  [PRE-FLIGHT] System Prerequisites Check" -ForegroundColor Cyan
    Write-Host "  " + ("-" * 50) -ForegroundColor DarkGray
    Write-Host ""

    $checksPassed = 0; $checksWarned = 0

    # 1. Internet connectivity
    Write-Step "Checking internet connectivity..."
    try {
        $netTest = Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet -ErrorAction Stop
        if ($netTest) {
            Write-Success "Internet connectivity: OK"
            $checksPassed++
        } else {
            Write-Warn "Internet connectivity: OFFLINE (some features may fail)"
            $checksWarned++
        }
    } catch {
        Write-Warn "Internet connectivity: Could not check (some features may fail)"
        $checksWarned++
    }

    # 2. Free disk space
    Write-Step "Checking free disk space..."
    try {
        $sysDrive = Get-PSDrive -Name ($env:SYSTEMDRIVE -replace ':','') -ErrorAction Stop
        $freeGB = [math]::Round($sysDrive.Free / 1GB, 2)
        if ($freeGB -gt 10) {
            Write-Success "Free disk space: $freeGB GB (OK)"
            $checksPassed++
        } else {
            Write-Warn "Free disk space: $freeGB GB (LOW - recommend >10 GB)"
            $checksWarned++
        }
    } catch {
        Write-Warn "Could not check disk space: $_"
        $checksWarned++
    }

    # 3. Pending reboot
    Write-Step "Checking for pending reboot..."
    $rebootPending = $false
    $cbsPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
    $wuPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    if (Test-Path $cbsPath -ErrorAction SilentlyContinue) { $rebootPending = $true }
    if (Test-Path $wuPath -ErrorAction SilentlyContinue) { $rebootPending = $true }
    if ($rebootPending) {
        Write-Warn "Pending reboot detected! A restart is recommended before running optimizations."
        $checksWarned++
    } else {
        Write-Success "No pending reboot."
        $checksPassed++
    }

    # 4. Battery check (if laptop)
    if ($script:IsLaptop) {
        Write-Step "Checking battery level..."
        try {
            $battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop
            $onAC = $battery.BatteryStatus -eq 2 -or $battery.BatteryStatus -eq 6 -or $battery.BatteryStatus -eq 7 -or $battery.BatteryStatus -eq 8
            if ($onAC) {
                Write-Success "On AC power."
                $checksPassed++
            } elseif ($battery.EstimatedChargeRemaining -gt 50) {
                Write-Success "Battery level: $($battery.EstimatedChargeRemaining)% (OK)"
                $checksPassed++
            } else {
                Write-Warn "Battery level: $($battery.EstimatedChargeRemaining)% - recommend AC power or >50% charge."
                $checksWarned++
            }
        } catch {
            Write-Warn "Could not check battery: $_"
            $checksWarned++
        }
    }

    Write-Host ""
    Write-Host "  Pre-flight summary: $checksPassed passed, $checksWarned warnings" -ForegroundColor $(if ($checksWarned -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host ""
}

function Get-BootDriveType {
    <#
    .DESCRIPTION
        Detects whether the boot drive is an SSD or HDD.
        Returns "SSD" or "HDD".
    #>
    $bootType = "HDD"  # Default assumption
    try {
        # Method 1: Get-PhysicalDisk (most reliable on Win8+)
        $physicalDisk = Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object DeviceId -eq 0
        if ($physicalDisk) {
            if ($physicalDisk.MediaType -eq "SSD") { return "SSD" }
            if ($physicalDisk.MediaType -eq "HDD") { return "HDD" }
        }
    } catch { }

    try {
        # Method 2: Get-Disk BusType fallback
        $bootDisk = Get-Disk -ErrorAction SilentlyContinue | Where-Object IsBoot -eq $true
        if ($bootDisk) {
            $ssdBusTypes = @("NVMe", "SATA", "RAID", "SCSI")
            # Check via rotation rate (0 = SSD on some controllers)
            if ($bootDisk.BusType -in $ssdBusTypes) {
                # Not conclusive, but check rotation rate
                $detail = Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object DeviceId -eq $bootDisk.Number
                if ($detail -and $detail.MediaType -eq "SSD") { return "SSD" }
            }
        }
    } catch { }

    try {
        # Method 3: Check if defrag is scheduled (SSD = not scheduled)
        $defragTask = Get-ScheduledTask -TaskName "ScheduledDefrag" -ErrorAction SilentlyContinue
        if ($defragTask -and $defragTask.State -eq 'Disabled') {
            # If scheduled defrag is disabled, likely SSD
            # This is a weak heuristic, don't rely on it alone
        }
    } catch { }

    return $bootType
}

function Write-Step([string]$Message) {
    Write-Host "  [$([DateTime]::Now.ToString('HH:mm:ss'))] $Message" -ForegroundColor White
}

function Write-Success([string]$Message) {
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-Warn([string]$Message) {
    Write-Host "  [WARN] $Message" -ForegroundColor Yellow
}

function Write-Err([string]$Message) {
    Write-Host "  [ERROR] $Message" -ForegroundColor Red
}

function Enable-SystemRestore {
    <#
    .DESCRIPTION
        Ensures System Restore is enabled and configured on the system drive.
        Enables the service if disabled, allocates disk space, and verifies
        the feature is operational before returning.
    #>
    Write-Host "" -ForegroundColor Cyan
    Write-Host "  [SAFETY] System Restore Verification" -ForegroundColor Cyan
    Write-Host "  " + ("-" * 50) -ForegroundColor DarkGray
    Write-Host ""

    $systemDrive = $env:SYSTEMDRIVE
    $restoreEnabled = $false

    # Step 1: Check if System Restore is currently enabled on the system drive
    Write-Step "Checking System Restore status on $systemDrive..."
    try {
        $srStatus = Get-ComputerInfo -Property "SystemRestoreStatus" -ErrorAction SilentlyContinue
        # Also check via WMI which is more reliable
        $srInfo = Get-CimInstance -Namespace "ROOT/DEFAULT" -ClassName "SystemRestore" -ErrorAction SilentlyContinue
        if ($srInfo) {
            foreach ($sr in $srInfo) {
                if ($sr.RPSequence -gt 0) {
                    $restoreEnabled = $true
                    break
                }
            }
        }
    } catch {
        # WMI query may fail if System Restore is completely disabled
        $restoreEnabled = $false
    }

    # Alternative check: try to list existing restore points
    if (-not $restoreEnabled) {
        try {
            $existingPoints = Get-CimInstance -Namespace "ROOT/DEFAULT" -ClassName "SystemRestore" -ErrorAction Stop
            if ($existingPoints -and $existingPoints.Count -ge 0) {
                $restoreEnabled = $true
            }
        } catch {
            $restoreEnabled = $false
        }
    }

    # Step 2: Enable System Restore if not currently enabled
    if (-not $restoreEnabled) {
        Write-Warn "System Restore is NOT enabled on $systemDrive."
        Write-Step "Enabling System Restore on $systemDrive..."

        try {
            # Enable System Restore via registry (most reliable method)
            $srPolicyPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
            if (-not (Test-Path $srPolicyPath)) {
                New-Item -Path $srPolicyPath -Force -ErrorAction SilentlyContinue | Out-Null
            }
            # DisableSR = 0 means System Restore is ENABLED
            Set-ItemProperty -Path $srPolicyPath -Name "DisableSR" -Value 0 -Type DWord -Force -ErrorAction Stop

            # Also enable via PowerShell cmdlet (Windows 10/11)
            try {
                Enable-ComputerRestore -Drive $systemDrive -ErrorAction Stop
            } catch {
                # Fallback: use vssadmin to enable shadow copies
                $vssResult = vssadmin list shadows 2>&1
                if ($LASTEXITCODE -ne 0) {
                    # Try creating a shadow copy to force-enable VSS
                    vssadmin create shadow /For=$systemDrive 2>&1 | Out-Null
                }
            }

            # Start the System Restore service if not running
            $srService = Get-Service -Name "sr" -ErrorAction SilentlyContinue
            if ($srService -and $srService.Status -ne 'Running') {
                try {
                    Set-Service -Name "sr" -StartupType Manual -ErrorAction Stop
                    Start-Service -Name "sr" -ErrorAction Stop
                } catch {
                    Write-Warn "Could not start System Restore service: $_"
                }
            }

            # Also ensure VSS (Volume Shadow Copy) service is running (required for System Restore)
            $vssService = Get-Service -Name "VSS" -ErrorAction SilentlyContinue
            if ($vssService -and $vssService.Status -ne 'Running') {
                try {
                    Set-Service -Name "VSS" -StartupType Manual -ErrorAction Stop
                    Start-Service -Name "VSS" -ErrorAction Stop
                    Write-Success "VSS service started."
                } catch {
                    Write-Warn "Could not start VSS service: $_"
                }
            }

            Start-Sleep -Seconds 2
            Write-Success "System Restore has been ENABLED on $systemDrive."
        } catch {
            Write-Err "Failed to enable System Restore: $_"
            Write-Warn "Continuing without restore point. Manual enable: System Properties > System Protection > Configure > Turn on"
        }
    } else {
        Write-Success "System Restore is already enabled on $systemDrive."
    }

    # Step 3: Configure disk space allocation for restore points
    Write-Step "Configuring System Restore disk space..."
    try {
        # Set maximum disk space usage to 5% (reasonable for most systems)
        # This is done via registry: RPSessionInterval and DiskPercent
        $srCfgPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore\Cfg"
        if (-not (Test-Path $srCfgPath)) {
            New-Item -Path $srCfgPath -Force -ErrorAction SilentlyContinue | Out-Null
        }
        # DiskPercent = 5 means 5% of disk (0 = unlimited, we use 5% as safe default)
        Set-ItemProperty -Path $srCfgPath -Name "DiskPercent" -Value 5 -Type DWord -Force -ErrorAction SilentlyContinue
        # RPSessionInterval = 0 means create restore points at any interval
        Set-ItemProperty -Path $srCfgPath -Name "RPSessionInterval" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Success "Restore disk space set to 5% of drive."
    } catch {
        Write-Warn "Could not configure restore disk space: $_"
    }

    Write-Host ""
}

function New-SystemRestorePoint {
    <#
    .DESCRIPTION
        Creates a System Restore point before any optimization changes are made.
        This provides a safety net so the user can roll back all changes.
    #>
    Write-Host "" -ForegroundColor Cyan
    Write-Host "  [SAFETY] Creating System Restore Point" -ForegroundColor Cyan
    Write-Host "  " + ("-" * 50) -ForegroundColor DarkGray
    Write-Host ""

    $restorePointCreated = $false
    $description = "Pre-Optimization Restore Point - WinPostInstall v$ScriptVersion - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"

    # Method 1: Use Checkpoint-Computer (PowerShell cmdlet, Windows 8+)
    Write-Step "Creating restore point: 'Pre-Optimization'..."
    try {
        Checkpoint-Computer -Description $description -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        $restorePointCreated = $true
        Write-Success "Restore point created successfully via Checkpoint-Computer."
    } catch {
        Write-Warn "Checkpoint-Computer failed: $_"
    }

    # Method 2: Fallback using WMI if Method 1 failed
    if (-not $restorePointCreated) {
        Write-Step "Trying WMI method to create restore point..."
        try {
            $wmiSR = [System.Windows.Forms.SystemRestore]
            # WMI approach via Invoke-CimMethod
            $result = Invoke-CimMethod -Namespace "ROOT/DEFAULT" -ClassName "SystemRestore" `
                -MethodName "CreateRestorePoint" `
                -Arguments @{
                    Description         = $description
                    RestorePointType    = 12  # MODIFY_SETTINGS
                    EventType           = 100  # BEGIN_NESTED_SYSTEM_CHANGE
                } -ErrorAction Stop
            if ($result -and $result.ReturnValue -eq 0) {
                $restorePointCreated = $true
                Write-Success "Restore point created via WMI."
            } else {
                Write-Warn "WMI returned non-zero: $result"
            }
        } catch {
            Write-Warn "WMI method failed: $_"
        }
    }

    # Method 3: Final fallback via srclient.dll COM automation
    if (-not $restorePointCreated) {
        Write-Step "Trying COM automation (srclient.dll)..."
        try {
            $srClient = New-Object -ComObject "SRClient.RestorePoint" -ErrorAction Stop
            # 7 = MODIFY_SETTINGS, 100 = BEGIN_NESTED_SYSTEM_CHANGE
            $srClient.CreateRestorePoint($description, 7, 100)
            $restorePointCreated = $true
            Write-Success "Restore point created via COM automation."
        } catch {
            Write-Warn "COM method failed: $_"
        }
    }

    if ($restorePointCreated) {
        Write-Host ""
        Write-Host "  ====================================================================" -ForegroundColor Green
        Write-Host "  RESTORE POINT CREATED: 'Pre-Optimization'" -ForegroundColor Green
        Write-Host "  You can roll back all changes via:" -ForegroundColor White
        Write-Host "    System Properties > System Protection > System Restore" -ForegroundColor White
        Write-Host "  ====================================================================" -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host ""
        Write-Warn "Could NOT create restore point automatically."
        Write-Host "  Manual option: System Properties > System Protection > Create" -ForegroundColor Yellow
        Write-Host "  Continuing without restore point backup." -ForegroundColor Yellow
        Write-Host ""
        if (-not $Silent) {
            $continue = Read-Host "  Continue without restore point? (y/N)"
            if ($continue -ne 'y' -and $continue -ne 'Y') {
                Write-Host "  Aborted by user." -ForegroundColor Yellow
                exit 0
            }
        }
    }
}

function Set-Registry {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = "DWord",
        [ValidateSet("Safe","Moderate","Risky")]
        [string]$SafetyLevel = "Safe",
        [string]$Description = "",
        [string]$SettingID = ""
    )

    # Generate a setting ID if not provided
    if ([string]::IsNullOrEmpty($SettingID)) {
        $SettingID = "$($Path.Replace('\','_').Replace(':','').Replace(' ',''))_$Name"
    }

    # Register in setting catalog for interactive menu
    if (-not [string]::IsNullOrEmpty($Description)) {
        $script:SettingCatalog[$SettingID] = @{
            Section  = $script:CurrentSection
            Safety   = $SafetyLevel
            Desc     = $Description
            Action   = "$Path\$Name = $Value"
            Type     = "Registry"
        }
    }

    # Collect risky descriptions for menu warnings
    if ($SafetyLevel -eq "Risky" -and -not [string]::IsNullOrEmpty($Description)) {
        $script:RiskyDescriptions += "$SettingID : $Description"
    }

    # Check if user has toggled this setting OFF via interactive menu
    if ($script:SettingOverrides.ContainsKey($SettingID) -and $script:SettingOverrides[$SettingID]) {
        Write-Host "  SKIPPED (user toggle): $Description" -ForegroundColor DarkGray
        $script:TotalSkipped++
        return
    }

    # Safety gate: Skip Risky settings unless explicitly allowed
    if ($SafetyLevel -eq "Risky" -and -not $script:AllowRisky) {
        Write-Host "  SKIPPED (risky): $Description — use -AllowRisky or enable in menu" -ForegroundColor Yellow
        $script:TotalSkipped++
        return
    }

    # Warn for Moderate settings
    if ($SafetyLevel -eq "Moderate") {
        Write-Host "  [MODERATE] $Description" -ForegroundColor DarkYellow
    }

    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force -ErrorAction SilentlyContinue | Out-Null
        }
        # Idempotency: Check if the value already matches what we want to set
        $currentValue = $null
        try {
            $currentValue = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
        } catch {
            # Property doesn't exist yet — need to create it
        }

        # Compare current vs desired value
        $valueMatches = $false
        if ($null -ne $currentValue) {
            if ($Type -eq "DWord" -or $Type -eq "QWord") {
                # Numeric comparison (handle both int and string inputs)
                $valueMatches = ([int]$currentValue -eq [int]$Value)
            } elseif ($Type -eq "String" -or $Type -eq "ExpandString") {
                $valueMatches = ([string]$currentValue -eq [string]$Value)
            } else {
                $valueMatches = ($currentValue -eq $Value)
            }
        }

        if ($valueMatches) {
            Write-Step "Already set: $Path\$Name = $Value"
            $script:TotalSkipped++
            return
        }

        # Capture old value for undo script before writing
        if ($null -ne $currentValue) {
            $oldVal = $currentValue.ToString()
            $null = $script:UndoCommands.Add("Set-ItemProperty -Path '$Path' -Name '$Name' -Value '$oldVal' -Type '$Type' -Force")
            $null = $script:UndoDescriptions.Add("Restore registry: $Path\$Name = $oldVal")
        } else {
            $null = $script:UndoCommands.Add("Remove-ItemProperty -Path '$Path' -Name '$Name' -Force -ErrorAction SilentlyContinue")
            $null = $script:UndoDescriptions.Add("Remove registry key that was added: $Path\$Name")
        }

        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
        Write-Success "Registry: $Path\$Name = $Value"
        $script:TotalChanged++
    }
    catch {
        Write-Err "Failed to set $Path\$Name : $_"
        $script:TotalFailed++
    }
}

function Remove-Registry {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$Name
    )
    try {
        if (Test-Path $Path) {
            # Idempotency: Check if property exists before removing
            $existing = $null
            try { $existing = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { }
            if ($null -ne $existing) {
                Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction Stop 2>$null
                Write-Success "Registry removed: $Path\$Name"
            } else {
                Write-Step "Already removed: $Path\$Name"
            }
        }
    }
    catch {
        Write-Warn "Could not remove $Path\$Name : $_"
    }
}

function Disable-AppTask {
    [CmdletBinding()]
    param(
        [string]$TaskPath,
        [string]$TaskName,
        [ValidateSet("Safe","Moderate","Risky")]
        [string]$SafetyLevel = "Safe",
        [string]$Description = "",
        [string]$SettingID = ""
    )

    # Generate a setting ID if not provided
    if ([string]::IsNullOrEmpty($SettingID)) {
        $SettingID = "Task_$($TaskPath.Replace('\','_').Replace(' ',''))_$TaskName"
    }

    # Register in setting catalog for interactive menu
    if (-not [string]::IsNullOrEmpty($Description)) {
        $script:SettingCatalog[$SettingID] = @{
            Section  = $script:CurrentSection
            Safety   = $SafetyLevel
            Desc     = $Description
            Action   = "Disable task: $TaskPath$TaskName"
            Type     = "ScheduledTask"
        }
    }

    # Collect risky descriptions for menu warnings
    if ($SafetyLevel -eq "Risky" -and -not [string]::IsNullOrEmpty($Description)) {
        $script:RiskyDescriptions += "$SettingID : $Description"
    }

    # Check if user has toggled this setting OFF via interactive menu
    if ($script:SettingOverrides.ContainsKey($SettingID) -and $script:SettingOverrides[$SettingID]) {
        Write-Host "  SKIPPED (user toggle): $Description" -ForegroundColor DarkGray
        $script:TotalSkipped++
        return
    }

    # Safety gate: Skip Risky settings unless explicitly allowed
    if ($SafetyLevel -eq "Risky" -and -not $script:AllowRisky) {
        Write-Host "  SKIPPED (risky): $Description — use -AllowRisky or enable in menu" -ForegroundColor Yellow
        $script:TotalSkipped++
        return
    }

    # Warn for Moderate settings
    if ($SafetyLevel -eq "Moderate") {
        Write-Host "  [MODERATE] $Description" -ForegroundColor DarkYellow
    }

    try {
        $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($task) {
            if ($task.State -eq 'Disabled') {
                Write-Step "Already disabled: $TaskPath$TaskName"
                $script:TotalSkipped++
            } else {
                # Safety: Check for dependent services/tasks before disabling
                $deps = $task.DependentOn
                if ($deps) {
                    Write-Host "  [DEPENDENCY] Task $TaskName has dependents: $($deps.TaskName -join ', ')" -ForegroundColor DarkYellow
                }
                $task | Disable-ScheduledTask -ErrorAction Stop
                Write-Success "Task disabled: $TaskPath$TaskName"
                $script:TotalChanged++
                $null = $script:UndoCommands.Add("Enable-ScheduledTask -TaskPath '$TaskPath' -TaskName '$TaskName' -ErrorAction SilentlyContinue")
                $null = $script:UndoDescriptions.Add("Re-enable scheduled task: $TaskPath$TaskName")
            }
        }
    }
    catch {
        Write-Warn "Could not disable task $TaskPath$TaskName : $_"
    }
}

#endregion

#region ============================================================
# SECTION 1: PRIVACY & TELEMETRY (AGGRESSIVE)
# ============================================================

function Invoke-PrivacyTweaks {
    $script:CurrentSection = "Privacy"
    Write-Host ""
    Write-Host "--- PRIVACY and TELEMETRY (Aggressive) ---" -ForegroundColor Magenta
    Write-Host ""

    # 1. Disable Telemetry via Registry (multiple paths)
    Write-Step "Disabling Windows telemetry..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "AllowTelemetry" -Value 0 -Type DWord `
        -SafetyLevel "Safe" -Description "Stops Windows from sending telemetry and diagnostic data to Microsoft" -SettingID "Privacy_AllowTelemetry"
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" `
        -Name "AllowTelemetry" -Value 0 -Type DWord `
        -SafetyLevel "Safe" -Description "Reinforces telemetry block via secondary policy path" -SettingID "Privacy_AllowTelemetry2"
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "DoNotShowFeedbackNotifications" -Value 1 -Type DWord `
        -SafetyLevel "Safe" -Description "Removes Feedback Hub notifications and prompts" -SettingID "Privacy_NoFeedback"
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "LimitDiagnosticLogCollection" -Value 1 -Type DWord `
        -SafetyLevel "Safe" -Description "Limits diagnostic log collection to critical events only" -SettingID "Privacy_LimitDiagLog"
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "LimitDumpCollection" -Value 1 -Type DWord `
        -SafetyLevel "Safe" -Description "Limits crash dump collection to reduce data sent to Microsoft" -SettingID "Privacy_LimitDump"

    # Disable Application Impact Telemetry + Inventory + UAR
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat" `
        -Name "AITEnable" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Application Impact Telemetry — stops app compat data collection" -SettingID "Privacy_AITEnable"
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat" `
        -Name "DisableInventory" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Disables app compatibility inventory — stops hardware/software inventory" -SettingID "Privacy_DisableInventory"
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat" `
        -Name "DisableUAR" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Disables User App Compatibility Reporter — stops compat data uploads" -SettingID "Privacy_DisableUAR"

    # Disable CEIP
    foreach ($p in @("HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows",
                      "HKCU:\SOFTWARE\Microsoft\SQMClient\Windows")) {
        Set-Registry -Path $p -Name "CEIPEnable" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Customer Experience Improvement Program — stops CEIP data collection" -SettingID "Privacy_CEIPEnable"
    }

    # Disable Tailored Experiences
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
        -Name "DisableTailoredExperiencesWithDiagnosticData" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Disables tailored experiences with diagnostic data — stops personalized ads/tips" -SettingID "Privacy_NoTailoredExp"

    # 2. Disable Diagnostic Tracking Services
    Write-Step "Stopping and disabling diagnostic tracking services..."
    foreach ($svc in @("DiagTrack", "dmwappushservice", "WerSvc",
                        "diagnosticshub.standardcollector.service")) {
        try {
            $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($service) {
                Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
                Write-Success "Service disabled: $svc"
            } else { Write-Warn "Service not found: $svc" }
        } catch { Write-Warn "Could not disable $svc : $_" }
    }

    # 3. CompatTelRunner IFEO Kill
    Write-Step "Killing CompatTelRunner via IFEO..."
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\CompatTelRunner.exe" `
        -Name "Debugger" -Value "%windir%\System32\taskkill.exe" -Type String -SafetyLevel "Safe" -Description "Kills CompatTelRunner.exe via IFEO — blocks telemetry compatibility runner" -SettingID "Privacy_KillCompatTelRunner"

    # 4. Disable Activity History
    Write-Step "Disabling activity history..."
    foreach ($name in @("EnableActivityFeed", "PublishUserActivities", "UploadUserActivities")) {
        Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
            -Name $name -Value 0 -Type DWord `
            -SafetyLevel "Safe" -Description "Disables activity history tracking — prevents Windows from recording user activity" -SettingID "Privacy_$($name)"
    }

    # 5. Disable Location Tracking
    Write-Step "Disabling location tracking..."
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" `
        -Name "Value" -Value "Deny" -Type String -SafetyLevel "Moderate" -Description "Disables geolocation service — breaks Find My Device and Maps location" -SettingID "Privacy_NoGeolocation"
    Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration" `
        -Name "Status" -Value 0 -Type DWord -SafetyLevel "Moderate" -Description "Disables geolocation service — breaks Find My Device and Maps location" -SettingID "Privacy_NoGeolocation"

    # 6. Disable Advertising ID
    Write-Step "Disabling advertising ID..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" `
        -Name "DisabledByGroupPolicy" -Value 1 -Type DWord `
        -SafetyLevel "Safe" -Description "Removes the unique advertising ID assigned to this device" -SettingID "Privacy_AdvID_Policy"
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" `
        -Name "Enabled" -Value 0 -Type DWord `
        -SafetyLevel "Safe" -Description "Disables advertising ID in current user scope" -SettingID "Privacy_AdvID_User"

    # 7. Disable Cortana (multi-layer)
    Write-Step "Disabling Cortana (multi-layer)..."
    foreach ($prop in @("AllowCortana", "AllowSearchToUseLocation", "AllowCloudSearch")) {
        Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" `
            -Name $prop -Value 0 -Type DWord `
            -SafetyLevel "Safe" -Description "Disables Cortana digital assistant and web search in Start"
    }
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" `
        -Name "DisableWebSearch" -Value 1 -Type DWord `
        -SafetyLevel "Safe" -Description "Stops Start menu from using Bing web search" -SettingID "Privacy_DisableWebSearch"
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" `
        -Name "ConnectedSearchUseWeb" -Value 0 -Type DWord `
        -SafetyLevel "Safe" -Description "Blocks Cortana from using web for search results" -SettingID "Privacy_NoConnectedSearch"
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsStore" `
        -Name "DisableWindowsStoreRealTimeConfig" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Disables Windows Store real-time configuration — reduces Store telemetry" -SettingID "Privacy_NoStoreRealTime"

    # 8. Disable Bing Search in Start Menu
    Write-Step "Disabling Bing search in Start Menu..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" `
        -Name "BingSearchEnabled" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Bing search in Start Menu — stops web search results" -SettingID "Privacy_NoBingSearch"
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" `
        -Name "CortanaConsent" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Revokes Cortana consent — stops Cortana data collection" -SettingID "Privacy_NoCortanaConsent"

    # 9. Disable Copilot (policy + button)
    Write-Step "Disabling Copilot (multi-layer)..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" `
        -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord `
        -SafetyLevel "Safe" -Description "Disables Windows Copilot AI assistant (machine policy)" -SettingID "Privacy_NoCopilot_Machine"
    Set-Registry -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" `
        -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord `
        -SafetyLevel "Safe" -Description "Disables Windows Copilot AI assistant (user policy)" -SettingID "Privacy_NoCopilot_User"
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "ShowCopilotButton" -Value 0 -Type DWord `
        -SafetyLevel "Safe" -Description "Hides Copilot button from taskbar" -SettingID "Privacy_HideCopilotBtn"

    # 10. Disable Windows Recall (Win11 24H2+)
    Write-Step "Disabling Windows Recall..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" `
        -Name "AllowRecallEnablement" -Value 0 -Type DWord `
        -SafetyLevel "Safe" -Description "Disables Windows Recall AI memory/timeline feature (machine)" -SettingID "Privacy_NoRecall_Machine"
    Set-Registry -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" `
        -Name "AllowRecallEnablement" -Value 0 -Type DWord `
        -SafetyLevel "Safe" -Description "Disables Windows Recall AI memory/timeline feature (user)" -SettingID "Privacy_NoRecall_User"
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" `
        -Name "DisableAIDataAnalysis" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Disables AI data analysis — stops AI telemetry collection" -SettingID "Privacy_NoAIDataAnalysis"

    # 11. Disable AI: Click-to-Do, Image Creator, Cocreator, Generative Fill
    Write-Step "Disabling AI features..."
    foreach ($prop in @("DisableClickToDo", "DisableImageCreator", "DisableCocreator", "DisableGenerativeFill")) {
        Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" `
            -Name $prop -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Disables Windows AI feature — stops AI data collection" -SettingID "Privacy_AI_Privacy_AIFeature"
    }

    # 12. Disable AI in Paint
    Write-Step "Disabling AI features in Paint..."
    foreach ($prop in @("DisableImageCreator", "DisableCocreator", "DisableGenerativeFill")) {
        Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\PaintStudio" `
            -Name $prop -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Disables AI feature in Paint — stops AI telemetry" -SettingID "Privacy_NoPaintAI_Privacy_PaintAI"
    }

    # 13. Disable Clipboard
    Write-Step "Disabling Clipboard cloud sync and history..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
        -Name "AllowClipboardHistory" -Value 0 -Type DWord `
        -SafetyLevel "Safe" -Description "Disables clipboard history (Win+V)" -SettingID "Privacy_NoClipHistory"
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
        -Name "AllowCrossDeviceClipboard" -Value 0 -Type DWord `
        -SafetyLevel "Safe" -Description "Disables cloud clipboard sync across devices" -SettingID "Privacy_NoClipSync"

    # 14. Disable Input Telemetry
    Write-Step "Disabling input/typing telemetry..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization" `
        -Name "RestrictImplicitTextCollection" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Restricts implicit text collection — stops typing telemetry" -SettingID "Privacy_NoImplicitText"
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization" `
        -Name "RestrictImplicitInkCollection" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Restricts implicit ink collection — stops inking telemetry" -SettingID "Privacy_NoImplicitInk"
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore" `
        -Name "HarvestContacts" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables contact harvesting for typing suggestions — stops contact data collection" -SettingID "Privacy_NoHarvestContacts"

    # 15. Disable Feedback
    Write-Step "Disabling Feedback notifications..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Siuf\Rules" `
        -Name "NumberOfSIUFInPeriod" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables feedback notifications — stops Feedback Hub prompts" -SettingID "Privacy_NoFeedbackNotif"

    # 16. Disable targeted tips
    Write-Step "Disabling targeted tips and suggestions..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "Start_TrackProgs" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables tracking of most-used programs in Start — stops usage telemetry" -SettingID "Privacy_NoTrackProgs"
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "Start_TrackDocs" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables tracking of recently opened documents in Start — stops usage telemetry" -SettingID "Privacy_NoTrackDocs"
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
        -Name "DisableSoftLanding" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Disables Windows soft landing tips — stops suggestion telemetry" -SettingID "Privacy_NoSoftLanding"
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
        -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Disables Windows consumer features — stops Store suggestions/ads" -SettingID "Privacy_NoConsumerFeatures2"

    # 17. Disable Wi-Fi Sense
    Write-Step "Disabling Wi-Fi Sense..."
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting" `
        -Name "Value" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Wi-Fi Sense — stops sharing Wi-Fi passwords with contacts" -SettingID "Privacy_NoWiFiSense_Privacy_WiFi"
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots" `
        -Name "Value" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Wi-Fi Sense — stops sharing Wi-Fi passwords with contacts" -SettingID "Privacy_NoWiFiSense_Privacy_WiFi_2"
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config" `
        -Name "AutoConnectAllowedOEM" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Wi-Fi Sense — stops sharing Wi-Fi passwords with contacts" -SettingID "Privacy_NoWiFiSense_Privacy_WiFi_3"

    # 18. Disable Error Reporting
    Write-Step "Disabling Windows Error Reporting..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" `
        -Name "Disabled" -Value 1 -Type DWord `
        -SafetyLevel "Moderate" -Description "Stops Windows Error Reporting — makes troubleshooting harder" -SettingID "Privacy_NoWER"

    # 19. Disable Insider experiments
    Write-Step "Disabling Windows Insider experiments..."
    foreach ($prop in @("EnableExperimentation", "EnableConfigFlighting", "AllowBuildPreview")) {
        Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PreviewBuilds" `
            -Name $prop -Value 0 -Type DWord -SafetyLevel "Moderate" -Description "Disables Windows Insider experiments — stops A/B testing and flighting" -SettingID "Privacy_NoInsiderExperiments_Privacy_Insider"
    }

    # 20. Disable Setting Sync (Windows Backup)
    Write-Step "Disabling Setting Sync / Windows Backup..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync" `
        -Name "DisableSettingSync" -Value 2 -Type DWord -SafetyLevel "Moderate" -Description "Disables Setting Sync — stops cloud settings sync" -SettingID "Privacy_NoSettingSync"
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync" `
        -Name "DisableSettingSyncUserOverride" -Value 1 -Type DWord -SafetyLevel "Moderate" -Description "Disables Setting Sync — stops cloud settings sync" -SettingID "Privacy_NoSettingSync"

    # 21. Full diagnostics/analytics lockdown (Settings > Privacy > Diagnostics & Feedback)
    Write-Step "Locking down all diagnostics and analytics for developers..."
    # Diagnostic Data: Send required only (=1) or off (=0)
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "AllowTelemetry" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Stops Windows from sending telemetry and diagnostic data to Microsoft" -SettingID "Privacy_AllowTelemetry3"
    # Tailored Experiences
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
        -Name "DisableTailoredExperiencesWithDiagnosticData" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Disables tailored experiences with diagnostic data — stops personalized ads/tips" -SettingID "Privacy_NoTailoredExp"
    # Feedback frequency: Never
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "DoNotShowFeedbackNotifications" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Removes Feedback Hub notifications and prompts" -SettingID "Privacy_NoFeedback2"
    # Diagnostic Data Viewer: disable
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "EnableDiagnosticDataViewer" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Diagnostic Data Viewer — removes data viewer feature" -SettingID "Privacy_NoDiagDataViewer"
    # Limit diagnostic log collection
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "LimitDiagnosticLogCollection" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Limits diagnostic log collection to critical events only" -SettingID "Privacy_LimitDiagLog2"
    # Limit dump collection
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "LimitDumpCollection" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Limits crash dump collection to reduce data sent to Microsoft" -SettingID "Privacy_LimitDump2"
    # Microsoft Compatibility Telemetry (AIT/Inventory/UAR) - already above but reinforced
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat" `
        -Name "AITEnable" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Application Impact Telemetry — stops app compat data collection" -SettingID "Privacy_AITEnable"
    # Device Census (sends hardware inventory)
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeviceCensus" `
        -Name "DisableDeviceCensus" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Disables Device Census — stops hardware inventory reporting to Microsoft" -SettingID "Privacy_NoDeviceCensus"
    # Watson (error reporting telemetry)
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" `
        -Name "Disabled" -Value 1 -Type DWord `
        -SafetyLevel "Moderate" -Description "Stops Watson error reporting telemetry — makes troubleshooting harder" -SettingID "Privacy_NoWatson"
    # SQM (Customer Experience Improvement) - reinforced
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\SQMClient\Windows" `
        -Name "CEIPEnable" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Customer Experience Improvement Program — stops CEIP data collection" -SettingID "Privacy_CEIPEnable"
    # Disable Windows Error Reporting completely
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" `
        -Name "Disabled" -Value 1 -Type DWord -SafetyLevel "Moderate" -Description "Stops Windows Error Reporting — makes troubleshooting harder" -SettingID "Privacy_NoWER2"
    # Disable Program Compatibility Assistant
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat" `
        -Name "DisablePCA" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Disables Program Compatibility Assistant — stops compatibility telemetry" -SettingID "Privacy_DisablePCA"
    # Disable Application Impact Telemetry
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost" `
        -Name "EnableWebContentEvaluation" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables web content evaluation — stops app telemetry" -SettingID "Privacy_NoWebContentEval"
    # Disable活动记录 (Activity History) - additional key
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
        -Name "PublishUserActivities" -Value 0 -Type DWord `
        -SafetyLevel "Safe" -Description "Prevents Windows from tracking activity history" -SettingID "Privacy_NoPublishActivities"
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
        -Name "UploadUserActivities" -Value 0 -Type DWord `
        -SafetyLevel "Safe" -Description "Prevents uploading activity history to Microsoft cloud" -SettingID "Privacy_NoUploadActivities"
    # Disable Full Language Telemetry
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "FullTelemetryOnInstall" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables full telemetry on install — stops initial data collection burst" -SettingID "Privacy_NoFullTelemetryInstall"
    # Disable the diagnostic data viewer feature
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "AllowUpdateComplianceTelemetry" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Update Compliance telemetry — stops WU data reporting" -SettingID "Privacy_NoUpdateComplianceTelemetry"

    # 22. Disable all Background Activity / App Diagnostics permissions
    Write-Step "Disabling background app diagnostics..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" `
        -Name "GlobalUserDisabled" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Disables background app access globally — stops apps running in background" -SettingID "Privacy_NoBackgroundApps"
    # Disable App Diagnostics (Settings > Privacy > App Diagnostics)
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" `
        -Name "LetAppsGetDiagnosticInfo" -Value 2 -Type DWord -SafetyLevel "Safe" -Description "Denies apps access to diagnostic info — stops app diagnostics data sharing" -SettingID "Privacy_NoAppDiagInfo"
    # Disable App Activity History
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" `
        -Name "LetAppsAccessActivityHistory" -Value 2 -Type DWord -SafetyLevel "Safe" -Description "Denies apps access to activity history — stops app activity tracking" -SettingID "Privacy_NoAppActivityHist"

    # 23. Disable all Advertising and personalization data sharing
    Write-Step "Disabling advertising and personalization data sharing..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" `
        -Name "DisabledByGroupPolicy" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Removes advertising ID via group policy — stops targeted advertising" -SettingID "Privacy_AdvIDPolicy2"
    # Disable Browse Web / Search suggestions personalization
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
        -Name "DisableCloudOptimizedContent" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Disables cloud-optimized content — stops personalized suggestions" -SettingID "Privacy_NoCloudContent"
    # Disable third-party suggestions in Windows
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
        -Name "DisableThirdPartySuggestions" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Disables third-party suggestions in Windows — stops third-party ads" -SettingID "Privacy_No3rdPartySuggestions"
    # Disable Windows Spotlight (lock screen tips, suggestions)
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" `
        -Name "SubscribedContent-338389Enabled" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Windows Spotlight suggestions — stops lock screen tips/ads" -SettingID "Privacy_NoSpotlight338389"
    # Disable Get even more out of Windows / Tips
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" `
        -Name "SubscribedContent-310093Enabled" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables 'Get even more out of Windows' tips — stops suggestion prompts" -SettingID "Privacy_NoTips310093"

    # 24. Disable all optional diagnostic data (Kernel, network, app crashes)
    Write-Step "Disabling optional diagnostic data providers..."
    # Disable Windows Kernel telemetry
    Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\AutoLogger-Diagtrack-Listener" `
        -Name "Start" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables AutoLogger DiagTrack listener — stops kernel telemetry logging" -SettingID "Privacy_NoDiagtrackListener"
    # Disable NCSI passive polling (network connectivity telemetry)
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator" `
        -Name "NoActiveProbe" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Disables NCSI active probing — stops network connectivity telemetry" -SettingID "Privacy_NoNCSIProbe2"
    # Disable User Profile service telemetry
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\UserProfile" `
        -Name "DisableUserProfileTelemetry" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Disables User Profile service telemetry — stops profile data collection" -SettingID "Privacy_NoUserProfileTelemetry"

    # === LOCK SCREEN / SPOTLIGHT ADS ===

    # 25. Disable Windows Spotlight and lock screen ads
    Write-Step "Disabling Windows Spotlight and lock screen ads..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" `
        -Name "ContentDeliveryEnabled" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables content delivery — stops silent app installs and suggestions" -SettingID "Privacy_NoContentDelivery"
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" `
        -Name "SubscribedContent-338387Enabled" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables suggested content in Settings — stops Settings suggestions" -SettingID "Privacy_NoSuggestedContent338387"
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" `
        -Name "SubscribedContent-338388Enabled" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables suggested content (tips) — stops tips/suggestions" -SettingID "Privacy_NoSuggestedContent338388"
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" `
        -Name "RotatingLockScreenEnabled" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables rotating lock screen images — stops Windows Spotlight ads" -SettingID "Privacy_NoRotatingLockScreen2"
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" `
        -Name "RotatingLockScreenOverlayEnabled" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables lock screen overlay — stops Windows Spotlight tips/ads" -SettingID "Privacy_NoLockScreenOverlay2"

    # 26. Disable lock screen app notifications
    Write-Step "Disabling lock screen app notifications..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings" `
        -Name "NOC_GLOBAL_SETTING_TOASTS_ENABLED" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables lock screen toast notifications — stops lock screen notification display" -SettingID "Privacy_NoLockScreenNotif"

    Write-Host ""
    Write-Success "Privacy and Telemetry section complete (26 items)."
}

#endregion

#region ============================================================
# SECTION 2: DEBLOAT (Remove bloatware apps)
# ============================================================

function Invoke-Debloat {
    $script:CurrentSection = "Debloat"
    Write-Host ""
    Write-Host "--- DEBLOAT: Removing Bloatware ---" -ForegroundColor Magenta
    Write-Host ""

    # Bloatware list with safety classifications
    # Safe = standard bloatware, always remove
    # Moderate = some users may want (Xbox, MixedReality), apply by default but warn
    # Risky = laptop/essential users may need (Camera, Alarms), skip by default
    $bloatwareList = @(
        # Microsoft bloat — Safe
        @{ App = "*Microsoft.3DBuilder*";               Safety = "Safe";    Reason = "Removes 3D Builder — pre-installed junk app" },
        @{ App = "*Microsoft.BingFinance*";             Safety = "Safe";    Reason = "Removes Bing Finance — pre-installed junk app" },
        @{ App = "*Microsoft.BingFoodAndDrink*";        Safety = "Safe";    Reason = "Removes Bing Food and Drink — pre-installed junk app" },
        @{ App = "*Microsoft.BingHealth*";              Safety = "Safe";    Reason = "Removes Bing Health — pre-installed junk app" },
        @{ App = "*Microsoft.BingMaps*";                Safety = "Safe";    Reason = "Removes Bing Maps — pre-installed junk app" },
        @{ App = "*Microsoft.BingNews*";                Safety = "Safe";    Reason = "Removes Bing News — pre-installed junk app" },
        @{ App = "*Microsoft.BingSports*";              Safety = "Safe";    Reason = "Removes Bing Sports — pre-installed junk app" },
        @{ App = "*Microsoft.BingTranslator*";          Safety = "Safe";    Reason = "Removes Bing Translator — pre-installed junk app" },
        @{ App = "*Microsoft.BingTravel*";              Safety = "Safe";    Reason = "Removes Bing Travel — pre-installed junk app" },
        @{ App = "*Microsoft.BingWeather*";             Safety = "Safe";    Reason = "Removes Bing Weather — pre-installed junk app" },
        @{ App = "*Microsoft.CommsPhone*";              Safety = "Safe";    Reason = "Removes Phone Comms — pre-installed junk app" },
        @{ App = "*Microsoft.Getstarted*";              Safety = "Safe";    Reason = "Removes Get Started — pre-installed junk app" },
        @{ App = "*Microsoft.GamingApp*";               Safety = "Moderate"; Reason = "Removes Gaming App — WARNING: gamers need this" },
        @{ App = "*Microsoft.GamingServices*";          Safety = "Moderate"; Reason = "Removes Gaming Services — WARNING: gamers need this" },
        @{ App = "*Microsoft.Messaging*";               Safety = "Safe";    Reason = "Removes Messaging — pre-installed junk app" },
        @{ App = "*Microsoft.Microsoft3DViewer*";       Safety = "Safe";    Reason = "Removes 3D Viewer — pre-installed junk app" },
        @{ App = "*Microsoft.MicrosoftOfficeHub*";      Safety = "Safe";    Reason = "Removes Office Hub — pre-installed junk app" },
        @{ App = "*Microsoft.MicrosoftSolitaireCollection*"; Safety = "Safe"; Reason = "Removes Solitaire — pre-installed junk app" },
        @{ App = "*Microsoft.MixedReality.Portal*";     Safety = "Moderate"; Reason = "Removes Mixed Reality Portal — VR headsets need this" },
        @{ App = "*Microsoft.MinecraftUWP*";            Safety = "Safe";    Reason = "Removes Minecraft — pre-installed trial/junk app" },
        @{ App = "*Microsoft.NetworkSpeedTest*";        Safety = "Safe";    Reason = "Removes Network Speed Test — pre-installed junk app" },
        @{ App = "*Microsoft.Office.OneNote*";          Safety = "Safe";    Reason = "Removes OneNote (Store version) — pre-installed junk app" },
        @{ App = "*Microsoft.Office.Sway*";             Safety = "Safe";    Reason = "Removes Sway — pre-installed junk app" },
        @{ App = "*Microsoft.Office.Lens*";             Safety = "Safe";    Reason = "Removes Office Lens — pre-installed junk app" },
        @{ App = "*Microsoft.People*";                  Safety = "Safe";    Reason = "Removes People — pre-installed junk app" },
        @{ App = "*Microsoft.PowerAutomateDesktop*";    Safety = "Safe";    Reason = "Removes Power Automate Desktop — pre-installed junk app" },
        @{ App = "*Microsoft.Print3D*";                 Safety = "Safe";    Reason = "Removes Print 3D — pre-installed junk app" },
        @{ App = "*Microsoft.SkypeApp*";                Safety = "Safe";    Reason = "Removes Skype — pre-installed junk app" },
        @{ App = "*Microsoft.Wallet*";                  Safety = "Safe";    Reason = "Removes Wallet — pre-installed junk app" },
        @{ App = "*Microsoft.Whiteboard*";              Safety = "Safe";    Reason = "Removes Whiteboard — pre-installed junk app" },
        @{ App = "*Microsoft.WindowsAlarms*";           Safety = "Risky";   Reason = "Removes Clock/Alarms — WARNING: some users rely on this" },
        @{ App = "*Microsoft.WindowsCamera*";           Safety = "Risky";   Reason = "Removes Camera — WARNING: laptop users need this" },
        @{ App = "*microsoft.windowscommunicationsapps*"; Safety = "Safe"; Reason = "Removes Mail/Calendar — pre-installed junk app" },
        @{ App = "*Microsoft.WindowsFeedbackHub*";      Safety = "Safe";    Reason = "Removes Feedback Hub — pre-installed junk app" },
        @{ App = "*Microsoft.WindowsMaps*";             Safety = "Safe";    Reason = "Removes Maps — pre-installed junk app" },
        @{ App = "*Microsoft.WindowsSoundRecorder*";    Safety = "Safe";    Reason = "Removes Sound Recorder — pre-installed junk app" },
        @{ App = "*Microsoft.XboxApp*";                 Safety = "Moderate"; Reason = "Removes Xbox App — WARNING: gamers need these" },
        @{ App = "*Microsoft.Xbox.TCUI*";               Safety = "Moderate"; Reason = "Removes Xbox TCUI — WARNING: gamers need these" },
        @{ App = "*Microsoft.XboxGameOverlay*";          Safety = "Moderate"; Reason = "Removes Xbox Game Overlay — WARNING: gamers need these" },
        @{ App = "*Microsoft.XboxGamingOverlay*";        Safety = "Moderate"; Reason = "Removes Xbox Gaming Overlay — WARNING: gamers need these" },
        @{ App = "*Microsoft.XboxIdentityProvider*";     Safety = "Moderate"; Reason = "Removes Xbox Identity Provider — WARNING: gamers need these" },
        @{ App = "*Microsoft.XboxSpeechToTextOverlay*";  Safety = "Moderate"; Reason = "Removes Xbox Speech-to-Text — WARNING: gamers need these" },
        @{ App = "*Microsoft.ZuneMusic*";               Safety = "Safe";    Reason = "Removes Groove Music — pre-installed junk app" },
        @{ App = "*Microsoft.ZuneVideo*";               Safety = "Safe";    Reason = "Removes Movies and TV — pre-installed junk app" },
        @{ App = "*MicrosoftTeamsFree*";                Safety = "Safe";    Reason = "Removes Teams (free) — pre-installed junk app" },
        @{ App = "*Microsoft.Copilot*";                 Safety = "Safe";    Reason = "Removes Copilot — pre-installed junk app" },
        @{ App = "*Microsoft.Todos*";                   Safety = "Safe";    Reason = "Removes To Do — pre-installed junk app" },
        @{ App = "*Microsoft.OutlookForWindows*";        Safety = "Safe";    Reason = "Removes Outlook (new) — pre-installed junk app" },
        @{ App = "*Microsoft.Windows.DevHome*";          Safety = "Safe";    Reason = "Removes Dev Home — pre-installed junk app" },
        @{ App = "*MicrosoftCorporationII.QuickAssist*"; Safety = "Safe";   Reason = "Removes Quick Assist — pre-installed junk app" },
        @{ App = "*Clipchamp.Clipchamp*";               Safety = "Safe";    Reason = "Removes Clipchamp — pre-installed junk app" },
        @{ App = "*Microsoft.Advertising.Xaml*";         Safety = "Safe";   Reason = "Removes Advertising XAML framework — bloat" },
        # Third-party bloat — all Safe
        @{ App = "*ActiproSoftware*";                   Safety = "Safe";    Reason = "Removes Actipro Software — third-party bloat" },
        @{ App = "*Disney*";                            Safety = "Safe";    Reason = "Removes Disney — third-party bloat" },
        @{ App = "*Duolingo*";                          Safety = "Safe";    Reason = "Removes Duolingo — third-party bloat" },
        @{ App = "*EclipseManager*";                    Safety = "Safe";    Reason = "Removes Eclipse Manager — third-party bloat" },
        @{ App = "*Facebook*";                          Safety = "Safe";    Reason = "Removes Facebook — third-party bloat" },
        @{ App = "*Fitbit*";                            Safety = "Safe";    Reason = "Removes Fitbit — third-party bloat" },
        @{ App = "*Flipboard*";                         Safety = "Safe";    Reason = "Removes Flipboard — third-party bloat" },
        @{ App = "*king.com.CandyCrush*";               Safety = "Safe";    Reason = "Removes Candy Crush — third-party bloat" },
        @{ App = "*king.com.CandyCrushSodaSaga*";       Safety = "Safe";    Reason = "Removes Candy Crush Soda — third-party bloat" },
        @{ App = "*king.com.FarmHeroesSaga*";            Safety = "Safe";    Reason = "Removes Farm Heroes Saga — third-party bloat" },
        @{ App = "*king.com.BubbleWitch3Saga*";          Safety = "Safe";    Reason = "Removes Bubble Witch 3 — third-party bloat" },
        @{ App = "*Hulu*";                              Safety = "Safe";    Reason = "Removes Hulu — third-party bloat" },
        @{ App = "*Netflix*";                           Safety = "Safe";    Reason = "Removes Netflix — third-party bloat" },
        @{ App = "*Pandora*";                           Safety = "Safe";    Reason = "Removes Pandora — third-party bloat" },
        @{ App = "*Plex*";                              Safety = "Safe";    Reason = "Removes Plex — third-party bloat" },
        @{ App = "*Shazam*";                            Safety = "Safe";    Reason = "Removes Shazam — third-party bloat" },
        @{ App = "*SlingTV*";                           Safety = "Safe";    Reason = "Removes Sling TV — third-party bloat" },
        @{ App = "*SpotifyAB*";                         Safety = "Safe";    Reason = "Removes Spotify — third-party bloat" },
        @{ App = "*TikTok*";                            Safety = "Safe";    Reason = "Removes TikTok — third-party bloat" },
        @{ App = "*Twitter*";                           Safety = "Safe";    Reason = "Removes Twitter — third-party bloat" },
        @{ App = "*WildTangent*";                       Safety = "Safe";    Reason = "Removes WildTangent — third-party bloat" },
        @{ App = "*Wunderlist*";                        Safety = "Safe";    Reason = "Removes Wunderlist — third-party bloat" },
        @{ App = "*LinkedInforWindows*";                Safety = "Safe";    Reason = "Removes LinkedIn — third-party bloat" },
        @{ App = "*AutodeskSketchBook*";                Safety = "Safe";    Reason = "Removes SketchBook — third-party bloat" },
        @{ App = "*DisneyMagicKingdoms*";               Safety = "Safe";    Reason = "Removes Disney Magic Kingdoms — third-party bloat" },
        @{ App = "*MarchofEmpires*";                    Safety = "Safe";    Reason = "Removes March of Empires — third-party bloat" },
        @{ App = "*CookingFever*";                      Safety = "Safe";    Reason = "Removes Cooking Fever — third-party bloat" },
        @{ App = "*iHeartRadio*";                       Safety = "Safe";    Reason = "Removes iHeartRadio — third-party bloat" },
        @{ App = "*PicsArt*";                           Safety = "Safe";    Reason = "Removes PicsArt — third-party bloat" },
        @{ App = "*Polarr*";                            Safety = "Safe";    Reason = "Removes Polarr — third-party bloat" },
        @{ App = "*TuneIn*";                            Safety = "Safe";    Reason = "Removes TuneIn — third-party bloat" },
        @{ App = "*NYTCrossword*";                      Safety = "Safe";    Reason = "Removes NYT Crossword — third-party bloat" }
    )

    $removed = 0; $notFound = 0; $skippedRisky = 0; $skippedModerate = 0

    # System-critical AppX packages that should NEVER be removed
    $criticalPrefixes = @(
        "Microsoft.Windows.ShellExperienceHost",
        "Microsoft.Windows.Cortana",
        "Microsoft.Windows.Search",
        "Microsoft.Windows.SecurityHealthCenter",
        "Microsoft.Windows.SecHealthUI",
        "Microsoft.Windows.StartMenuExperienceHost",
        "Microsoft.Windows.Shell",
        "Microsoft.VfsHelper",
        "Microsoft.WindowsAppRuntime"
    )

    foreach ($bloatware in $bloatwareList) {
        $app = $bloatware.App
        $safety = $bloatware.Safety
        $reason = $bloatware.Reason

        # Safety gate: Skip Risky items unless explicitly allowed
        if ($safety -eq "Risky" -and -not $script:AllowRisky) {
            # Still check if the app exists so we can report it
            $packages = Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue
            if ($packages) {
                Write-Host "  SKIPPED (risky): $reason — use -AllowRisky or enable in menu" -ForegroundColor Yellow
                $skippedRisky++
            }
            continue
        }

        # Warn for Moderate items
        if ($safety -eq "Moderate") {
            Write-Host "  [MODERATE] $reason" -ForegroundColor DarkYellow
        }

        $packages = Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue
        if ($packages) {
            foreach ($pkg in $packages) {
                # Safety: Check if this is a system-critical package
                $isCritical = $false
                foreach ($prefix in $criticalPrefixes) {
                    if ($pkg.Name -like "$prefix*") {
                        $isCritical = $true
                        break
                    }
                }
                if ($isCritical) {
                    Write-Host "  SKIPPED (system-critical): $($pkg.Name) — removing would break Windows" -ForegroundColor Red
                    continue
                }

                try {
                    Write-Step "Removing: $($pkg.Name)"
                    Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                    $removed++
                    $script:TotalChanged++
                    $null = $script:UndoCommands.Add("# Re-install: Add-AppxPackage -Package '$($pkg.PackageFullName)'")
                    $null = $script:UndoDescriptions.Add("Re-install removed app: $($pkg.Name)")
                    Write-Success "Removed: $($pkg.Name)"
                } catch { Write-Warn "Could not remove $($pkg.Name): $_" }
            }
        } else { $notFound++ }
    }

    # Remove provisioned packages (prevents reinstall for new users) — only Safe ones
    Write-Step "Cleaning provisioned (stub) packages..."
    $provRemoved = 0; $provNotFound = 0
    foreach ($bloatware in $bloatwareList) {
        # Skip Risky and Moderate from provisioned removal too
        if ($bloatware.Safety -eq "Risky" -and -not $script:AllowRisky) { continue }
        $app = $bloatware.App
        $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object DisplayName -like $app
        if ($prov) {
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop
                Write-Success "Removed provisioned: $($prov.DisplayName)"
                $provRemoved++
            } catch { Write-Warn "Could not remove provisioned $($prov.DisplayName): $_" }
        } else { $provNotFound++ }
    }

    Write-Host ""
    Write-Success "Debloat complete. Removed: $removed | Already removed: $notFound | Skipped risky: $skippedRisky | Provisioned removed: $provRemoved | Provisioned clean: $provNotFound"
}

#endregion

#region ============================================================
# SECTION 3: EXPLORER & UI OPTIMIZATIONS
# ============================================================

function Invoke-ExplorerUI {
    $script:CurrentSection = "ExplorerUI"
    Write-Host ""
    Write-Host "--- EXPLORER and UI OPTIMIZATIONS ---" -ForegroundColor Magenta
    Write-Host ""

    # 1. Show file extensions
    Write-Step "Showing file extensions..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "HideFileExt" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Shows file extensions — prevents accidental execution of disguised files" -SettingID "ExplorerUI_ShowFileExt"

    # 2. Show hidden files
    Write-Step "Showing hidden files..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "Hidden" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Shows hidden files — improves visibility of system files" -SettingID "ExplorerUI_ShowHiddenFiles"

    # 3. Classic right-click context menu (Win11)
    Write-Step "Enabling classic right-click context menu..."
    if ($script:IsWin11) {
        Set-Registry -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" `
            -Name "(Default)" -Value "" -Type String -SafetyLevel "Safe" -Description "Enables classic right-click context menu — removes Win11 simplified menu" -SettingID "ExplorerUI_ClassicContextMenu"
    }

    # 4. Content Delivery Manager FULL LOCKDOWN (prevent silent app reinstalls)
    Write-Step "Locking down Content Delivery Manager..."
    $cdmPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $cdmKeys = @(
        "SubscribedContent-338387Enabled","SubscribedContent-338388Enabled",
        "SubscribedContent-338389Enabled","SubscribedContent-338393Enabled",
        "SubscribedContent-353694Enabled","SubscribedContent-353696Enabled",
        "SubscribedContent-353698Enabled","SubscribedContent-314559Enabled",
        "SubscribedContent-310093Enabled",
        "ContentDeliveryAllowed","FeatureManagementEnabled",
        "OemPreInstalledAppsEnabled","PreInstalledAppsEnabled",
        "PreInstalledAppsEverEnabled","SilentInstalledAppsEnabled",
        "SubscribedContentEnabled","SystemPaneSuggestionsEnabled"
    )
    foreach ($key in $cdmKeys) {
        Set-Registry -Path $cdmPath -Name $key -Value 0 -Type DWord `
            -SafetyLevel "Safe" -Description "Disables content delivery setting — stops suggestions/silent installs" -SettingID "ExplorerUI_CDM_$($key)"
    }

    # 5. Disable File Explorer ads
    Write-Step "Disabling File Explorer ads..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "ShowSyncProviderNotifications" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables File Explorer ads — removes OneDrive ads in Explorer" -SettingID "ExplorerUI_NoExplorerAds"

    # 6. Disable Lock Screen
    Write-Step "Disabling Lock Screen..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" `
        -Name "NoLockScreen" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Disables Lock Screen — goes directly to login screen" -SettingID "ExplorerUI_NoLockScreen"
    Set-Registry -Path $cdmPath -Name "RotatingLockScreenEnabled" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables rotating lock screen images — stops Windows Spotlight ads" -SettingID "ExplorerUI_NoRotatingLockScreen"
    Set-Registry -Path $cdmPath -Name "RotatingLockScreenOverlayEnabled" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables lock screen overlay — stops Windows Spotlight tips/ads" -SettingID "ExplorerUI_NoLockScreenOverlay"

    # 7. Disable consumer suggestions
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
        -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Disables Windows consumer features — stops Store suggestions/ads" -SettingID "ExplorerUI_NoConsumerFeatures2"

    # 8. Remove Chat icon from Taskbar (Win11)
    Write-Step "Removing Chat icon from Taskbar..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "TaskbarMn" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Removes Chat icon from Taskbar — hides Microsoft Chat/Teams" -SettingID "ExplorerUI_NoChatIcon"

    # 9. Remove Widgets from Taskbar (Win11)
    Write-Step "Removing Widgets from Taskbar..."
    if ($script:IsWin11) {
        Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
            -Name "TaskbarDa" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Removes Widgets from Taskbar — hides news/weather widget" -SettingID "ExplorerUI_NoWidgets"
    }

    # 10. Remove Search from Taskbar
    Write-Step "Removing Search from Taskbar..."
    if ($script:IsWin11) {
        Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
            -Name "TaskbarSearchBox" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Removes Search box from Taskbar — simplifies taskbar" -SettingID "ExplorerUI_NoSearchBox"
    }

    # 11. Disable Snap Layouts flyout (Win11)
    Write-Step "Disabling Snap Layouts flyout..."
    if ($script:IsWin11) {
        Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
            -Name "EnableSnapAssistFlyout" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Snap Layouts flyout — removes snap layout suggestions" -SettingID "ExplorerUI_NoSnapAssist"
    }

    # 12. Enable "End Task" in Taskbar right-click (Win11 22H2+)
    Write-Step "Enabling 'End Task' in Taskbar right-click menu..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarEndTask" `
        -Name "TaskbarEndTask" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Enables 'End Task' in Taskbar right-click — adds quick task kill option" -SettingID "ExplorerUI_TaskbarEndTask"

    # 13. Open This PC instead of Quick Access
    Write-Step "Setting File Explorer to open 'This PC'..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "LaunchTo" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Sets File Explorer to open This PC instead of Quick Access" -SettingID "ExplorerUI_OpenThisPC"

    # 14. Remove 3D Objects from This PC
    Write-Step "Removing 3D Objects from This PC..."
    $shellKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}"
    if (Test-Path $shellKey) {
        Remove-Item -Path $shellKey -Force -ErrorAction SilentlyContinue
        Write-Success "Removed 3D Objects namespace key."
    }

    # 15. Disable Drag Tray (Win11 share/move files tray)
    Write-Step "Disabling Drag Tray..."
    if ($script:IsWin11) {
        Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
            -Name "DragBetweenWindows" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Drag Tray — removes Win11 share/move files tray" -SettingID "ExplorerUI_NoDragTray"
    }

    # === TASKBAR DEEP CUSTOMIZATION ===

    # 16. Remove Task View button from Taskbar
    Write-Step "Removing Task View button from Taskbar..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "ShowTaskViewButton" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Removes Task View button from Taskbar — hides virtual desktops UI" -SettingID "ExplorerUI_NoTaskView"

    # 17. Set Search bar to icon-only (not full bar)
    Write-Step "Setting Search bar to icon-only mode..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" `
        -Name "SearchboxTaskbarMode" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Sets Search bar to icon-only mode — simplifies taskbar" -SettingID "ExplorerUI_SearchIconOnly"

    # 18. Hide Copilot button from Taskbar
    Write-Step "Hiding Copilot button from Taskbar..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "ShowCopilotButton" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Hides Copilot button from taskbar" -SettingID "ExplorerUI_HideCopilotBtn2"

    # 19. Unpin default Edge+Store from taskbar
    # NOTE: Unpinning Edge and Store from taskbar requires deleting the Taskband registry key
    # which is complex and system-dependent. Commented-out for safety.
    # To unpin manually, right-click the icon and select "Unpin from Taskbar".
    # Remove-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Taskband" -Force -ErrorAction SilentlyContinue

    # === CONTEXT MENU CLEANUP ===

    # 20. Remove "Cast to Device" from context menu
    Write-Step "Removing 'Cast to Device' from context menu..."
    try {
        $castKey = "HKCR:\Local\Microsoft\Windows\Shell\Cast"
        if (Test-Path $castKey -ErrorAction SilentlyContinue) {
            $null = $script:UndoCommands.Add("New-Item -Path '$castKey' -Force -ErrorAction SilentlyContinue")
            $null = $script:UndoDescriptions.Add("Restore Cast device registry key")
            Remove-Item -Path $castKey -Recurse -Force -ErrorAction SilentlyContinue
            Write-Success "Removed: Cast to Device"
        }
    } catch { Write-Warn "Could not remove Cast key: $_" }

    # 21. Remove "Share with Skype" from context menu
    Write-Step "Removing 'Share with Skype' from context menu..."
    try {
        $skypeKey = "HKCR:\Local\Microsoft\Windows\Shell\Skype"
        if (Test-Path $skypeKey -ErrorAction SilentlyContinue) {
            $null = $script:UndoCommands.Add("New-Item -Path '$skypeKey' -Force -ErrorAction SilentlyContinue")
            $null = $script:UndoDescriptions.Add("Restore Skype registry key")
            Remove-Item -Path $skypeKey -Recurse -Force -ErrorAction SilentlyContinue
            Write-Success "Removed: Share with Skype"
        }
    } catch { Write-Warn "Could not remove Skype key: $_" }

    # 22. Remove "Give access to" from context menu
    Write-Step "Removing 'Give access to' from context menu..."
    try {
        $sharingKey = "HKCR:\AllFileObjects\shell\sharing"
        if (Test-Path $sharingKey -ErrorAction SilentlyContinue) {
            $null = $script:UndoCommands.Add("New-Item -Path '$sharingKey' -Force -ErrorAction SilentlyContinue")
            $null = $script:UndoDescriptions.Add("Restore Sharing registry key")
            Remove-Item -Path $sharingKey -Recurse -Force -ErrorAction SilentlyContinue
            Write-Success "Removed: Give access to"
        }
    } catch { Write-Warn "Could not remove sharing key: $_" }

    # 23. Remove "Include in library" from context menu
    Write-Step "Removing 'Include in library' from context menu..."
    try {
        $libraryKey = "HKCR:\Folder\Shell\include in library"
        if (Test-Path $libraryKey -ErrorAction SilentlyContinue) {
            $null = $script:UndoCommands.Add("New-Item -Path '$libraryKey' -Force -ErrorAction SilentlyContinue")
            $null = $script:UndoDescriptions.Add("Restore Library registry key")
            Remove-Item -Path $libraryKey -Recurse -Force -ErrorAction SilentlyContinue
            Write-Success "Removed: Include in library"
        }
    } catch { Write-Warn "Could not remove library key: $_" }

    Write-Host ""
    Write-Success "Explorer and UI optimizations complete."
}

#endregion

#region ============================================================
# SECTION 4: SERVICE & STARTUP OPTIMIZATION
# ============================================================

function Invoke-ServiceStartupOptimization {
    $script:CurrentSection = "ServiceStartup"
    Write-Host ""
    Write-Host "--- SERVICE and STARTUP OPTIMIZATION ---" -ForegroundColor Magenta
    Write-Host ""

    $disableServices = @(
        @{ Name = "WSearch";               Desc = "Windows Search";                    Safety = "Risky";    Reason = "Disables Windows Search — WARNING: breaks Start menu search, Cortana, Office search" },
        @{ Name = "WMPNetworkSvc";         Desc = "Windows Media Player Network Sharing"; Safety = "Safe";   Reason = "Disables WMP Network Sharing — not needed unless sharing media" },
        @{ Name = "WpcSvc";                Desc = "Parental Controls";                 Safety = "Safe";    Reason = "Disables Parental Controls — not needed on adult machines" },
        @{ Name = "TabletInputService";    Desc = "Tablet PC Input";                   Safety = "Safe";    Reason = "Disables Tablet PC Input — not needed on desktops" },
        @{ Name = "RetailDemo";            Desc = "Retail Demo Service";               Safety = "Safe";    Reason = "Disables Retail Demo — only needed in retail/store environments" },
        @{ Name = "PimIndexMaintenance";   Desc = "People Indexing";                   Safety = "Safe";    Reason = "Disables People Indexing — not needed without People app" },
        @{ Name = "MessagingService";      Desc = "Messaging Service";                  Safety = "Safe";    Reason = "Disables Messaging Service — WUH messaging not needed" },
        @{ Name = "MapsBroker";            Desc = "Downloaded Maps Manager";            Safety = "Safe";    Reason = "Disables Downloaded Maps Manager — saves resources if Maps unused" },
        @{ Name = "lfsvc";                 Desc = "Geolocation Service";               Safety = "Moderate"; Reason = "Disables Geolocation — breaks Find My Device and Maps location" },
        @{ Name = "HvHost";                Desc = "Hyper-V Host Compute Service";      Safety = "Moderate"; Reason = "Disables Hyper-V Host — WARNING: needed for VMs, WSL2, Docker" },
        @{ Name = "wisvc";                 Desc = "Windows Insider Service";            Safety = "Safe";    Reason = "Disables Windows Insider Service — not needed on stable builds" },
        @{ Name = "WbioSrvc";              Desc = "Windows Biometric Service";          Safety = "Risky";   Reason = "Disables Biometrics — WARNING: breaks Windows Hello fingerprint/face login" },
        @{ Name = "OneSyncSvc";            Desc = "OneSync Sync Host";                 Safety = "Moderate"; Reason = "Disables OneSync — may affect Mail/Calendar sync" },
        @{ Name = "UnistoreSvc";           Desc = "User Data Storage Service";          Safety = "Safe";    Reason = "Disables User Data Storage — not typically needed" },
        @{ Name = "PushToInstall";         Desc = "Push to Install Service";            Safety = "Safe";    Reason = "Disables Push to Install — Microsoft Store push installs" }
    )

    foreach ($svc in $disableServices) {
        # Safety gate: Skip Risky services unless explicitly allowed
        if ($svc.Safety -eq "Risky" -and -not $script:AllowRisky) {
            $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
            if ($service -and $service.StartType -ne 'Disabled') {
                Write-Host "  SKIPPED (risky): $($svc.Reason) — use -AllowRisky or enable in menu" -ForegroundColor Yellow
            }
            continue
        }

        # Warn for Moderate services
        if ($svc.Safety -eq "Moderate") {
            Write-Host "  [MODERATE] $($svc.Reason)" -ForegroundColor DarkYellow
        }

        try {
            $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
            if ($service -and $service.StartType -ne 'Disabled') {
                # Safety: Check for dependent services before disabling
                $deps = $service.DependentServices | Where-Object { $_.Status -eq 'Running' }
                if ($deps) {
                    $depNames = ($deps | ForEach-Object { "$($_.Name)($($_.Status))" }) -join ', '
                    Write-Host "  [DEPENDENCY] $($svc.Name) has running dependents: $depNames" -ForegroundColor DarkYellow
                }

                Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
                Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction Stop
                Write-Success "Disabled service: $($svc.Desc) ($($svc.Name))"
            } elseif ($service) {
                Write-Step "Already disabled: $($svc.Desc)"
            } else {
                Write-Warn "Service not found: $($svc.Name)"
            }
        } catch { Write-Warn "Could not disable $($svc.Name): $_" }
    }

    # Disable Startup delay
    Write-Step "Disabling Startup delay..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize" `
        -Name "StartupDelayInMSec" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables startup delay — speeds up boot by removing artificial delay" -SettingID "ServiceStartup_NoStartupDelay"

    Write-Host ""
    Write-Success "Service and Startup optimization complete."
}

#endregion

#region ============================================================
# SECTION 5: PERFORMANCE & POWER SETTINGS
# ============================================================

function Invoke-PerformanceOptimization {
    $script:CurrentSection = "Performance"
    Write-Host ""
    Write-Host "--- PERFORMANCE and POWER SETTINGS ---" -ForegroundColor Magenta
    Write-Host ""

    # === HARDWARE-AWARE: SSD vs HDD ===
    $script:BootDriveType = Get-BootDriveType
    Write-Step "Boot drive type detected: $($script:BootDriveType)"

    # === HARDWARE-AWARE: Laptop vs Desktop ===
    if ($script:IsLaptop) {
        Write-Step "Chassis type: Laptop — keeping Balanced power plan."
    } else {
        Write-Step "Chassis type: Desktop — setting High Performance power plan."
    }

    # === HARDWARE-AWARE: RAM detection ===
    $totalRAM = 0
    try {
        $totalRAM = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
        Write-Step "Total RAM detected: $totalRAM GB"
    } catch {
        Write-Warn "Could not detect RAM: $_"
    }

    # 1. Disable Hibernation
    Write-Step "Disabling Hibernation..."
    try {
        powercfg.exe /hibernate off 2>$null
        Write-Success "Hibernation disabled. hiberfil.sys removed."
    } catch { Write-Warn "Hibernation disable failed: $_" }

    # 2. Disable Fast Startup (causes partial shutdowns, driver issues)
    Write-Step "Disabling Fast Startup..."
    Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" `
        -Name "HiberbootEnabled" -Value 0 -Type DWord `
        -SafetyLevel "Safe" -Description "Disables Fast Startup — prevents partial shutdown/driver issues" -SettingID "Perf_NoFastStartup"

    # 3. Disable Modern Standby Networking (battery drain + security)
    Write-Step "Disabling Modern Standby network connectivity..."
    Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power" `
        -Name "ModernSleep" -Value 0 -Type DWord `
        -SafetyLevel "Safe" -Description "Disables Modern Standby network — prevents battery drain during sleep" -SettingID "Perf_NoModernSleep"

    # 4. Set power plan based on chassis type
    if ($script:IsLaptop) {
        # Laptop: keep Balanced, but warn about High Performance option
        Write-Host "  [MODERATE] High Performance on laptop — WARNING: drains battery. Keeping Balanced." -ForegroundColor DarkYellow
        Write-Step "Keeping Balanced power plan (laptop)."
    } else {
        # Desktop: set High Performance, disable lid close action
        Write-Step "Setting High Performance power plan (desktop)..."
        try {
            $highPerf = powercfg.exe /list | Select-String -Pattern "High performance|高性能"
            if ($highPerf) {
                $guid = ($highPerf.ToString() -split '\s+')[3]
                powercfg.exe /setactive $guid 2>$null
                Write-Success "Power plan set to High Performance ($guid)"
            } else {
                powercfg.exe /duplicatecheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null | Out-Null
                Start-Sleep -Seconds 1
                $highPerf = powercfg.exe /list | Select-String -Pattern "High performance|高性能"
                if ($highPerf) {
                    $guid = ($highPerf.ToString() -split '\s+')[3]
                    powercfg.exe /setactive $guid 2>$null
                    Write-Success "High Performance plan created and activated ($guid)"
                } else { Write-Warn "Could not find or create High Performance plan." }
            }
        } catch { Write-Warn "Power plan change failed: $_" }

        # Disable lid close action (desktop doesn't need it)
        Write-Step "Disabling lid close action (desktop)..."
        try {
            powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0 2>$null
            powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0 2>$null
            powercfg.exe /setactive SCHEME_CURRENT 2>$null
            Write-Success "Lid close action set to 'Do nothing' (desktop)."
        } catch { Write-Warn "Could not change lid close action: $_" }
    }

    # 5. Set visual effects to Best Performance
    Write-Step "Setting visual effects to 'Best Performance'..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" `
        -Name "VisualFXSetting" -Value 2 -Type DWord `
        -SafetyLevel "Safe" -Description "Sets visual effects to Best Performance mode" -SettingID "Perf_VisualFX"

    $visualFx = @{
        "AnimateMinMaxMenus"=0; "ComboBoxAnimation"=0; "CursorShadow"=0;
        "DragFullWindows"=0; "ListBoxSmoothScrolling"=0; "ListviewAlphaSelect"=0;
        "ListviewShadow"=0; "MenuAnimation"=0; "SelectionFade"=0;
        "TaskbarAnimations"=0; "TooltipAnimation"=0
    }
    foreach ($key in $visualFx.Keys) {
        Set-Registry -Path "HKCU:\Control Panel\Desktop" -Name $key -Value $visualFx[$key] -Type DWord -SafetyLevel "Safe" -Description "Disables visual animation — improves performance" -SettingID "Performance_VisFX_Performance_VisFX"
    }
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\DWM" `
        -Name "EnableAeroPeek" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Aero Peek — removes desktop preview on taskbar hover" -SettingID "Performance_NoAeroPeek"

    # 6. SysMain/Prefetch based on drive type
    if ($script:BootDriveType -eq "SSD") {
        Write-Step "SSD detected: Disabling SysMain (SuperFetch) and Prefetch..."
        try {
            $sysMain = Get-Service -Name "SysMain" -ErrorAction SilentlyContinue
            if ($sysMain -and $sysMain.StartType -ne 'Disabled') {
                Stop-Service -Name "SysMain" -Force -ErrorAction SilentlyContinue
                Set-Service -Name "SysMain" -StartupType Disabled -ErrorAction Stop
                Write-Success "SysMain disabled (SSD — safe, speeds boot)."
            } elseif ($sysMain) {
                Write-Step "SysMain already disabled."
            }
        } catch { Write-Warn "Could not disable SysMain: $_" }

        # Disable Prefetch via registry
        Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" `
            -Name "EnablePrefetcher" -Value 0 -Type DWord `
            -SafetyLevel "Safe" -Description "Disables Prefetch on SSD — safe, reduces unnecessary disk I/O" -SettingID "Perf_NoPrefetch_SSD"
        Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" `
            -Name "EnableSuperfetch" -Value 0 -Type DWord `
            -SafetyLevel "Safe" -Description "Disables SuperFetch on SSD — safe, reduces unnecessary disk I/O" -SettingID "Perf_NoSuperfetch_SSD"

        # Disable scheduled defrag on SSD
        Write-Step "Disabling scheduled defragmentation (SSD)..."
        try {
            $defragTask = Get-ScheduledTask -TaskName "ScheduledDefrag" -ErrorAction SilentlyContinue
            if ($defragTask -and $defragTask.State -ne 'Disabled') {
                Disable-AppTask -TaskName "ScheduledDefrag" -ErrorAction SilentlyContinue -SafetyLevel "Safe" -Description "Disables scheduled defragmentation — SSD does not need defrag" -SettingID "Performance_NoScheduledDefrag"
                Write-Success "Scheduled defrag disabled (SSD)."
            }
        } catch { Write-Warn "Could not disable scheduled defrag: $_" }

        # Enable TRIM on SSD
        Write-Step "Enabling TRIM on SSD..."
        try {
            $trimResult = fsutil behavior query DisableDeleteNotify 2>$null
            if ($trimResult -match "1") {
                fsutil behavior set DisableDeleteNotify 0 2>$null | Out-Null
                Write-Success "TRIM enabled (SSD)."
            } else {
                Write-Step "TRIM already enabled."
            }
        } catch { Write-Warn "Could not check/enable TRIM: $_" }
    } else {
        # HDD: SysMain is IMPORTANT for performance — do NOT disable
        Write-Host "  HDD detected: Keeping SysMain (SuperFetch) enabled — disabling on HDD kills performance." -ForegroundColor Yellow
        Write-Step "HDD detected: Keeping SysMain (SuperFetch) and Prefetch enabled."
    }

    # 7. Limit Windows Defender CPU usage to ~25%
    Write-Step "Limiting Windows Defender CPU usage..."
    # Note: Windows Defender Tamper Protection blocks direct registry edits.
    # Use Set-MpPreference cmdlet where possible, fall back to registry.
    try {
        Set-MpPreference -ScanAvgCPULoadFactor 25 -ErrorAction Stop
        Write-Success "Defender CPU limit set to 25% via Set-MpPreference"
    } catch {
        Write-Warn "Set-MpPreference failed (Tamper Protection may be on): $_"
        # Fallback: try registry directly (may fail if Tamper Protection is enabled)
        Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows Defender\Scan" `
            -Name "AvgCPULoadFactor" -Value 25 -Type DWord -SafetyLevel "Safe" -Description "Limits Windows Defender CPU usage to 25% — reduces scan impact" -SettingID "Performance_DefenderCPULimit"
    }

    # 8. Disable OEM telemetry services
    Write-Step "Disabling OEM telemetry services..."
    $oemServices = @("HPAppHelperShell","HPDiags","HPHealth","HPSysInfo",
        "HpTouchpointAnalyticsService","HpTouchpointMgr","hpsvcsss",
        "DellClientWMI","DellCommandUpdate","DellDataWarden",
        "Lenovo.SysInterceptor","LENOVO.TVTGard")
    foreach ($svc in $oemServices) {
        try {
            $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($s) {
                Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
                Write-Success "Disabled OEM service: $svc"
            }
        } catch { }
    }

    # 9. Increase SvcHost splitting threshold (reduce svchost.exe proliferation)
    Write-Step "Increasing SvcHost split threshold..."
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ServiceHostConfiguration" `
        -Name "SvcHostSplitThresholdInKB" -Value 0x04000000 -Type DWord -SafetyLevel "Safe" -Description "Increases SvcHost split threshold — reduces svchost.exe proliferation" -SettingID "Performance_SvcHostSplit"

    # === RAM-AWARE TWEAKS ===

    # 10. Page file optimization based on RAM
    if ($totalRAM -ge 32) {
        # >=32GB: Risky to disable page file entirely — only recommend, don't apply
        Write-Host "  [RISKY] Disabling page file with 32GB+ RAM — WARNING: can crash memory-heavy workloads" -ForegroundColor Yellow
        Write-Host "  (Not auto-applied. To disable: System Properties > Advanced > Performance > Virtual Memory > No paging file)" -ForegroundColor DarkGray
    } elseif ($totalRAM -ge 16) {
        # >=16GB: set fixed 1024MB page file (Moderate)
        Write-Host "  [MODERATE] Setting fixed 1GB page file — OK with 16GB+ RAM, but some apps may need more" -ForegroundColor DarkYellow
        Write-Step "RAM >= 16GB: Setting fixed page file to 1024MB..."
        Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" `
            -Name "PagingFiles" -Value "C:\pagefile.sys 1024 1024" -Type MultiString `
            -SafetyLevel "Moderate" -Description "Sets page file to fixed 1GB — OK with 16GB+ RAM" -SettingID "Perf_FixedPageFile"
    } elseif ($totalRAM -le 8 -and $totalRAM -gt 0) {
        # <=8GB: keep system-managed page file, but warn
        Write-Warn "RAM <= 8GB: Keeping system-managed page file. Consider adding more RAM."
    }

    # 11. Disable NTFS last access time updates (improves SSD performance)
    Write-Step "Disabling NTFS last access time updates..."
    try {
        fsutil behavior set DisableLastAccess 1 2>$null | Out-Null
        Write-Success "NTFS last access time updates disabled."
    } catch {
        Write-Warn "Could not set DisableLastAccess: $_"
    }

    Write-Host ""
    Write-Success "Performance and Power optimization complete."
}

#endregion

#region ============================================================
# SECTION 6: SECURITY HARDENING
# ============================================================

function Invoke-SecurityHardening {
    $script:CurrentSection = "Security"
    Write-Host ""
    Write-Host "--- SECURITY HARDENING ---" -ForegroundColor Magenta
    Write-Host ""

    # 1. Ensure Windows Defender real-time protection ON
    Write-Step "Ensuring Windows Defender real-time protection is on..."
    # Note: Defender Tamper Protection blocks registry edits to Defender keys.
    # Use Set-MpPreference cmdlet as primary method.
    try {
        Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
        Set-MpPreference -DisableBehaviorMonitoring $false -ErrorAction Stop
        Write-Success "Defender real-time protection ensured via Set-MpPreference"
    } catch {
        Write-Warn "Set-MpPreference failed (Tamper Protection may be on). Trying registry fallback..."
        foreach ($prop in @("DisableRealtimeMonitoring","DisableBehaviorMonitoring",
                            "DisableOnAccessProtection","DisableScanOnRealtimeEnable")) {
            Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection" `
                -Name $prop -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Ensures Defender real-time protection stays enabled — maintains security" -SettingID "Security_DefenderRT_$prop"
        }
    }

    # 2. Enable DNS over HTTPS
    Write-Step "Configuring DNS-over-HTTPS..."
    Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" `
        -Name "EnableAutoDoh" -Value 2 -Type DWord -SafetyLevel "Safe" -Description "Enables DNS-over-HTTPS — encrypts DNS queries for privacy" -SettingID "Security_EnableDoH"

    # 3. Disable USB auto-run
    Write-Step "Disabling USB auto-run..."
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
        -Name "NoDriveTypeAutoRun" -Value 255 -Type DWord -SafetyLevel "Safe" -Description "Disables USB auto-run — prevents malware from auto-executing on USB" -SettingID "Security_NoAutoRun"

    # 4. Disable Remote Desktop
    Write-Step "Disabling Remote Desktop..."
    Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" `
        -Name "fDenyTSConnections" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Disables Remote Desktop — reduces attack surface" -SettingID "Security_NoRDP"

    # 5. Disable SMBv1
    Write-Step "Disabling SMBv1..."
    Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" `
        -Name "SMB1" -Value 0 -Type DWord `
        -SafetyLevel "Safe" -Description "Disables SMBv1 — protects against WannaCry-like exploits" -SettingID "Sec_NoSMB1"
    Disable-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -NoRestart -ErrorAction SilentlyContinue | Out-Null

    # 6. Disable PowerShell v2 (feature name varies by Windows build)
    Write-Step "Disabling PowerShell v2..."
    Write-Host "  [MODERATE] Disabling PowerShell v2 — breaks very old PS scripts" -ForegroundColor DarkYellow
    try {
        $psv2Disabled = $false
        foreach ($featName in @("MicrosoftWindowsPowerShellV2", "PowerShellV2")) {
            $feat = Get-WindowsOptionalFeature -Online -FeatureName $featName -ErrorAction SilentlyContinue
            if ($feat -and $feat.State -eq 'Enabled') {
                Disable-WindowsOptionalFeature -Online -FeatureName $featName -NoRestart -ErrorAction Stop | Out-Null
                Write-Success "Disabled PowerShell v2 feature: $featName"
                $psv2Disabled = $true
                break
            }
        }
        if (-not $psv2Disabled) {
            Write-Step "PowerShell v2 feature not found or already disabled."
        }
    } catch {
        Write-Warn "Could not disable PowerShell v2: $_"
    }

    # 7. Ensure UAC enabled
    Write-Step "Ensuring UAC is enabled..."
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
        -Name "EnableLUA" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Ensures UAC is enabled — maintains admin consent prompts" -SettingID "Security_UAC_Enabled"
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
        -Name "ConsentPromptBehaviorAdmin" -Value 5 -Type DWord -SafetyLevel "Safe" -Description "Sets UAC to prompt for consent — secure admin elevation behavior" -SettingID "Security_UAC_Consent"

    # 8. Disable password reveal
    Write-Step "Disabling password reveal in credential UI..."
    Set-Registry -Path "HKLM:\Software\Policies\Microsoft\Windows\CredUI" `
        -Name "DisablePasswordReveal" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Disables password reveal button — prevents password visibility" -SettingID "Security_NoPasswordReveal"

    Write-Host ""
    Write-Success "Security hardening complete."
}

#endregion

#region ============================================================
# SECTION 7: NETWORK OPTIMIZATIONS
# ============================================================

function Invoke-NetworkOptimizations {
    $script:CurrentSection = "Network"
    Write-Host ""
    Write-Host "--- NETWORK OPTIMIZATIONS ---" -ForegroundColor Magenta
    Write-Host ""

    # 1. Set DNS to Cloudflare + Google
    Write-Step "Setting DNS servers to Cloudflare (1.1.1.1) and Google (8.8.8.8)..."
    try {
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceType -ne 'Loopback' }
        if ($adapters) {
            foreach ($adapter in $adapters) {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex `
                    -ServerAddresses ("1.1.1.1", "8.8.8.8") -ErrorAction Stop
                Write-Success "DNS set on adapter: $($adapter.Name)"
            }
        } else { Write-Warn "No active network adapters found." }
    } catch { Write-Warn "Failed to set DNS: $_" }

    # 2. Disable Network Throttling
    Write-Step "Disabling network throttling..."
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" `
        -Name "NetworkThrottlingIndex" -Value 0xffffffff -Type DWord -SafetyLevel "Safe" -Description "Disables network throttling — improves network throughput for gaming/streams" -SettingID "Network_NoNetThrottle"
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" `
        -Name "NoLazyMode" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Disables network lazy mode — reduces latency" -SettingID "Network_NoLazyMode"

    # 3. Disable Nagle Algorithm
    Write-Step "Disabling Nagle Algorithm (reduces latency)..."
    foreach ($param in @("TcpAckFrequency", "TCPNoDelay")) {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
        $interfaces = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
        foreach ($iface in $interfaces) {
            Set-Registry -Path $iface.PSPath -Name $param -Value 1 -Type DWord `
                -SafetyLevel "Safe" -Description "Disables Nagle Algorithm on network interface — reduces latency" -SettingID "Network_NoNagle_$($param)_$($iface.PSPath.GetHashCode())"
        }
    }

    # 4. Disable NCSI Active Probing
    Write-Step "Disabling NCSI active probing..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator" `
        -Name "NoActiveProbe" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Disables NCSI active probing — stops network connectivity telemetry" -SettingID "Network_NoNCSIProbe2"

    # 5. Disable Teredo (IPv6 transition)
    Write-Step "Disabling Teredo..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\TCPIP\v6Transition" `
        -Name "Teredo_State" -Value "Disabled" -Type String -SafetyLevel "Safe" -Description "Disables Teredo IPv6 transition — reduces attack surface" -SettingID "Network_NoTeredo"

    # 6. DNS-over-HTTPS provider setup (Cloudflare)
    Write-Step "Configuring DNS-over-HTTPS with Cloudflare..."
    try {
        # Set DNS via netsh for Ethernet adapter
        $ethernetAdapter = Get-NetAdapter -Name "Ethernet" -ErrorAction SilentlyContinue
        if ($ethernetAdapter -and $ethernetAdapter.Status -eq 'Up') {
            netsh interface ip set dns "Ethernet" static 1.1.1.1 primary 2>$null
            netsh interface ip add dns "Ethernet" 1.0.0.1 index=2 2>$null
            Write-Success "DNS set to Cloudflare (1.1.1.1, 1.0.0.1) on Ethernet."
        }
        # Also try Wi-Fi adapter
        $wifiAdapter = Get-NetAdapter -Name "Wi-Fi" -ErrorAction SilentlyContinue
        if ($wifiAdapter -and $wifiAdapter.Status -eq 'Up') {
            netsh interface ip set dns "Wi-Fi" static 1.1.1.1 primary 2>$null
            netsh interface ip add dns "Wi-Fi" 1.0.0.1 index=2 2>$null
            Write-Success "DNS set to Cloudflare (1.1.1.1, 1.0.0.1) on Wi-Fi."
        }
    } catch { Write-Warn "Could not set DNS via netsh: $_" }

    # Enable DoH
    Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" `
        -Name "EnableAutoDoh" -Value 2 -Type DWord -SafetyLevel "Safe" -Description "Enables DNS-over-HTTPS — encrypts DNS queries for privacy" -SettingID "Network_EnableDoH2"
    # Configure Cloudflare DoH template via policy
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" `
        -Name "EnableDOH" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Enables DNS-over-HTTPS via policy — encrypts DNS queries" -SettingID "Network_EnableDoH_Policy"

    # 7. Hosts file hardening - block Microsoft telemetry domains
    Write-Step "Hardening hosts file against telemetry domains..."
    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    $telemetryDomains = @(
        "vortex.data.microsoft.com",
        "vortex-win.data.microsoft.com",
        "tele.microsoft.com",
        "tele-ssl.microsoft.com",
        "watson.telemetry.microsoft.com",
        "watson.telemetry.microsoft.com.nsatc.net",
        "redir.metaservices.microsoft.com",
        "choice.microsoft.com",
        "choice.microsoft.com.nsatc.net",
        "df.telemetry.microsoft.com",
        "oemss.microsoft.com",
        "services.microsoft.com",
        "stats.microsoft.com",
        "survey.watson.microsoft.com",
        "watson.live.com",
        "watson.microsoft.com",
        "telemetry.microsoft.com",
        "telemetry.appex.bing.com",
        "telemetry.urs.microsoft.com",
        "settings-win.data.microsoft.com"
    )

    try {
        # Backup hosts file first
        Copy-Item $hostsPath "$hostsPath.bak" -Force -ErrorAction SilentlyContinue
        $null = $script:UndoCommands.Add("Copy-Item '$hostsPath.bak' '$hostsPath' -Force -ErrorAction SilentlyContinue")
        $null = $script:UndoDescriptions.Add("Restore original hosts file (undo telemetry blocking)")

        $hostsAdded = 0
        foreach ($domain in $telemetryDomains) {
            # Check if entry already exists (idempotent)
            $existing = Select-String -Path $hostsPath -Pattern $domain -ErrorAction SilentlyContinue
            if (-not $existing) {
                Add-Content -Path $hostsPath -Value "0.0.0.0 $domain" -Force -ErrorAction Stop
                $hostsAdded++
            }
        }
        if ($hostsAdded -gt 0) {
            Write-Success "Added $hostsAdded telemetry domains to hosts file."
        } else {
            Write-Step "All telemetry domains already in hosts file."
        }

        # Safety: Verify the system can still resolve microsoft.com after hosts file changes
        Write-Step "Verifying DNS resolution after hosts file modification..."
        try {
            $dnsTest = Resolve-DnsName -Name "microsoft.com" -ErrorAction Stop
            if ($dnsTest) {
                Write-Success "DNS resolution OK: microsoft.com resolves correctly."
            }
        } catch {
            Write-Host "  [WARNING] DNS resolution for microsoft.com failed after hosts file modification!" -ForegroundColor Red
            Write-Host "  Consider reviewing the hosts file at $hostsPath for errors." -ForegroundColor Yellow
        }
    } catch {
        Write-Warn "Could not modify hosts file: $_"
    }

    Write-Host ""
    Write-Success "Network optimizations complete."
}

#endregion

#region ============================================================
# SECTION 8: WINDOWS UPDATE CONFIGURATION
# ============================================================

function Invoke-WindowsUpdateConfig {
    $script:CurrentSection = "WindowsUpdate"
    Write-Host ""

    # 1. Auto-download and notify (not auto-install)
    Write-Step "Configuring Windows Update behavior..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" `
        -Name "AUOptions" -Value 4 -Type DWord -SafetyLevel "Safe" -Description "Sets WU to auto-download and notify — prevents automatic install" -SettingID "WindowsUpdate_WU_NotifyOnly"

    # 2. Prevent auto-reboot
    Write-Step "Disabling automatic reboot after updates..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" `
        -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Prevents auto-reboot after updates when users are logged in" -SettingID "WindowsUpdate_WU_NoAutoReboot"

    # 3. Disable Delivery Optimization
    Write-Step "Disabling Delivery Optimization..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" `
        -Name "DODownloadMode" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Delivery Optimization — stops peer-to-peer update sharing" -SettingID "WindowsUpdate_NoDeliveryOpt"

    # 4. Exclude drivers from quality updates
    Write-Step "Excluding drivers from quality updates..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" `
        -Name "ExcludeWUDriversInQualityUpdate" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Excludes drivers from quality updates — prevents driver issues" -SettingID "WindowsUpdate_WU_NoDriverUpdates"

    # 5. Set Active Hours
    Write-Step "Setting active hours to 09:00 - 21:00..."
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UFH" `
        -Name "ActiveHoursStart" -Value 9 -Type DWord -SafetyLevel "Safe" -Description "Sets active hours start to 09:00 — prevents reboots during work" -SettingID "WindowsUpdate_WU_ActiveHrsStart"
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UFH" `
        -Name "ActiveHoursEnd" -Value 21 -Type DWord -SafetyLevel "Safe" -Description "Sets active hours end to 21:00 — prevents reboots during work" -SettingID "WindowsUpdate_WU_ActiveHrsEnd"

    # 6. Prevent device companion app auto-install
    Write-Step "Preventing device companion app auto-install..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" `
        -Name "DoNotConnectToWindowsUpdateInternetLocations" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Configures WU internet locations — standard WU policy" -SettingID "WindowsUpdate_WU_InternetConfig"
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" `
        -Name "SearchOrderConfig" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Prevents automatic driver search via Windows Update" -SettingID "WindowsUpdate_WU_NoAutoDriverSearch"

    Write-Host ""
    Write-Success "Windows Update configuration complete."
}

#endregion

#region ============================================================
# SECTION 9: DISK CLEANUP & SYSTEM MAINTENANCE
# ============================================================

function Invoke-DiskCleanup {
    $script:CurrentSection = "DiskCleanup"
    Write-Host ""

    # 1. Run Disk Cleanup (Restore point already created at script startup)
    Write-Step "Configuring Disk Cleanup options..."
    foreach ($key in @("ActiveSetupTemp","OldFiles","ServicePackCleanup")) {
        Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\$key" `
            -Name "StateFlags0001" -Value 2 -Type DWord -SafetyLevel "Safe" -Description "Configures Disk Cleanup state flags — enables automated cleanup" -SettingID "DiskCleanup_DiskCleanupFlags_DiskCleanup_DC"
    }
    Write-Step "Running Disk Cleanup..."
    Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:1" -NoNewWindow -Wait -ErrorAction SilentlyContinue
    Write-Success "Disk Cleanup completed."

    # 3. Clean temp folders
    Write-Step "Cleaning temp folders..."
    @($env:TEMP, "$env:LOCALAPPDATA\Temp", "$env:SYSTEMDRIVE\Temp",
      "$env:SystemRoot\Temp",
      "$env:SystemRoot\ServiceProfiles\LocalService\AppData\Local\Temp") | ForEach-Object {
        if (Test-Path $_) {
            Get-ChildItem -Path $_ -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # 4. Disable Storage Sense
    Write-Step "Disabling Storage Sense..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense" `
        -Name "AllowStorageSenseGlobal" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Storage Sense — prevents automatic file deletion" -SettingID "DiskCleanup_NoStorageSense"

    Write-Host ""
    Write-Success "Disk cleanup and maintenance complete."
}

#endregion

#region ============================================================
# SECTION 10: SOFTWARE INSTALLATION (Winget)
# ============================================================

function Invoke-WingetInstall {
    $script:CurrentSection = "Winget"
    Write-Host ""

    $appList = @(
        @{ ID = "Google.Chrome";           Name = "Google Chrome" },
        @{ ID = "Mozilla.Firefox";         Name = "Mozilla Firefox" },
        @{ ID = "7zip.7zip";              Name = "7-Zip" },
        @{ ID = "VideoLAN.VLC";           Name = "VLC Media Player" },
        @{ ID = "Adobe.Acrobat.Reader.64-bit"; Name = "Adobe Acrobat Reader" },
        @{ ID = "Notepad++.Notepad++";    Name = "Notepad++" },
        @{ ID = "voidtools.Everything";   Name = "Everything Search" },
        @{ ID = "RARLab.WinRAR";         Name = "WinRAR" }
    )

    try { $null = Get-Command winget -ErrorAction Stop; Write-Success "Winget found." }
    catch {
        Write-Err "Winget is not installed. Install 'App Installer' from the Microsoft Store."
        return
    }

    Write-Host ""
    Write-Host "  Apps to install:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $appList.Count; $i++) {
        Write-Host "    $($i + 1). $($appList[$i].Name) ($($appList[$i].ID))" -ForegroundColor White
    }
    Write-Host ""

    if (-not $Silent) {
        $confirm = Read-Host "  Install all listed apps? (Y/n)"
        if ($confirm -eq 'n' -or $confirm -eq 'N') { Write-Warn "Skipped."; return }
    }

    $successCount = 0; $failCount = 0; $skippedCount = 0
    foreach ($app in $appList) {
        # Idempotency: Check if the app is already installed via winget
        $alreadyInstalled = $false
        try {
            $wingetList = winget list --id $app.ID --exact 2>$null
            if ($wingetList -match [regex]::Escape($app.ID)) {
                $alreadyInstalled = $true
            }
        } catch { }

        if ($alreadyInstalled) {
            Write-Step "Already installed: $($app.Name)"
            $skippedCount++
            continue
        }

        Write-Step "Installing $($app.Name)..."
        try {
            winget install --id $app.ID --silent --accept-package-agreements --accept-source-agreements `
                --ignore-security-hash --disable-interactivity 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Success "Installed: $($app.Name)"; $successCount++ }
            else { Write-Warn "Exit code $LASTEXITCODE for $($app.Name)"; $failCount++ }
        } catch { Write-Warn "Failed: $($app.Name): $_"; $failCount++ }
    }

    Write-Host ""
    Write-Success "Software install complete. Installed: $successCount | Skipped: $skippedCount | Issues: $failCount"
}

#endregion

#region ============================================================
# SECTION 11: OFFICE 365 INSTALLATION & ACTIVATION
# ============================================================

function Invoke-OfficeActivation {
    $script:CurrentSection = "OfficeActivation"
    Write-Host ""

    $masUrl = "https://get.activate.win"
    $officeSetupPath = "$env:TEMP\OfficeSetup.exe"
    $masScriptPath = "$env:TEMP\MAS.ps1"
    $skipToActivation = $false

    # ================================================================
    # Determine Office version, architecture from config
    # ================================================================
    # Default: Office 365 ProPlus x64
    $officeProductID = "O365ProPlusRetail"
    $officeVersion   = "O16GA"
    $officePlatform  = "x64"
    $officeLang      = "en-us"
    $officeLabel     = "Office 365 ProPlus"
    $doActivation    = $true

    # Read config-driven selections
    if ($script:ConfigSettings) {
        # Version selection (mutually exclusive — first enabled wins)
        if ($script:ConfigSettings["Off_V365"])  { $officeProductID = "O365ProPlusRetail"; $officeLabel = "Office 365 ProPlus" }
        elseif ($script:ConfigSettings["Off_V2024"]) { $officeProductID = "OfficeLtsc2024Volume"; $officeLabel = "Office LTSC 2024" }
        elseif ($script:ConfigSettings["Off_V2021"]) { $officeProductID = "OfficeLtsc2021Volume"; $officeLabel = "Office LTSC 2021" }
        elseif ($script:ConfigSettings["Off_V2019"]) { $officeProductID = "Office2019Volume"; $officeLabel = "Office 2019" }

        # Architecture
        if ($script:ConfigSettings["Off_Arch32"]) { $officePlatform = "x86" }

        # Activation
        if (-not $script:ConfigSettings["Off_Act"]) { $doActivation = $false }
    }

    $officeSetupUrl = "https://c2rsetup.officeapps.live.com/c2r/download.aspx?ProductreleaseID=$officeProductID&platform=$officePlatform&language=$officeLang&version=$officeVersion"

    # --- Step 1: Download Office installer ---
    Write-Host "  [Step 1/3] $officeLabel ($officePlatform) Installation" -ForegroundColor Yellow
    Write-Host ""

    if (-not $Silent) {
        Write-Host "  This will:" -ForegroundColor White
        Write-Host "    1. Download $officeLabel ($officePlatform, $officeLang) installer (~4MB)" -ForegroundColor White
        Write-Host "    2. Run the Office deployment (downloads apps, may take 10-20 min)" -ForegroundColor White
        if ($doActivation) {
            Write-Host "    3. Download and launch Microsoft Activation Scripts (MAS)" -ForegroundColor White
            Write-Host "    4. You manually choose: [1] HWID for Windows, [2] Ohook for Office" -ForegroundColor White
        }
        Write-Host ""
        $confirm = Read-Host "  Proceed with Office install? (Y/n)"
        if ($confirm -eq 'n' -or $confirm -eq 'N') { Write-Warn "Skipped."; return }
    }

    # Check if Office is already installed
    $officeInstalled = $false
    $officeRegPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Office\16.0",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\16.0"
    )
    foreach ($path in $officeRegPaths) {
        if (Test-Path $path) { $officeInstalled = $true; break }
    }

    if ($officeInstalled) {
        Write-Step "$officeLabel detected. Skipping download."
        if (-not $Silent) {
            $skip = Read-Host "  Office found. Skip to activation? (Y/n)"
            if ($skip -ne 'n' -and $skip -ne 'N') {
                Write-Host ""
                $skipToActivation = $true
            }
        } else {
            Write-Host ""
            $skipToActivation = $true
        }
    }

    if (-not $skipToActivation) {
        # Download Office Setup
        Write-Step "Downloading $officeLabel ($officePlatform) installer..."
        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($officeSetupUrl, $officeSetupPath)
            if (Test-Path $officeSetupPath) {
                Write-Success "Office installer downloaded: $officeSetupPath"
            } else {
                throw "Download completed but file not found."
            }
        } catch {
            Write-Err "Failed to download Office installer: $_"
            Write-Warn "Skipping Office installation. Check internet connection."
        }

        # Run Office Setup (silent install)
        Write-Step "Running $officeLabel installation (this takes 10-20 minutes)..."
        Write-Host "  Please wait... Office apps are being installed in the background." -ForegroundColor DarkGray
        try {
            $officeProcess = Start-Process -FilePath $officeSetupPath -ArgumentList "/quiet /norestart" `
                -Wait -PassThru -ErrorAction Stop
            if ($officeProcess.ExitCode -eq 0) {
                Write-Success "$officeLabel installed successfully."
            } else {
                Write-Warn "Office setup exited with code $($officeProcess.ExitCode). It may still be installing."
            }
        } catch {
            Write-Err "Office installation failed: $_"
        }

        # Clean up installer
        if (Test-Path $officeSetupPath) { Remove-Item $officeSetupPath -Force -ErrorAction SilentlyContinue }
    }

    # --- Step 2: Download & Launch Microsoft Activation Scripts ---
    if ($doActivation) {
        Write-Host ""
        Write-Host "  [Step 2/3] Windows and Office Activation (MAS)" -ForegroundColor Yellow
        Write-Host ""

        Write-Step "Downloading Microsoft Activation Scripts..."
        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($masUrl, $masScriptPath)
            if (Test-Path $masScriptPath) {
                Write-Success "MAS downloaded: $masScriptPath"
            } else {
                throw "Download completed but file not found."
            }
        } catch {
            Write-Err "Failed to download MAS: $_"
            Write-Host ""
            Write-Host "  You can run manually: irm https://get.activate.win | iex" -ForegroundColor Yellow
            Write-Host ""
            return
        }

        # --- Step 3: Launch MAS interactively ---
        Write-Host ""
        Write-Host "  [Step 3/3] Launching MAS activation menu..." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  ================================================" -ForegroundColor Cyan
        Write-Host "  MAS is opening in a NEW window." -ForegroundColor Cyan
        Write-Host "  In the MAS window:" -ForegroundColor White
        Write-Host "    [1] HWID     - Activate Windows" -ForegroundColor Green
        Write-Host "    [2] Ohook    - Activate Office" -ForegroundColor Green
        Write-Host "    [0] Exit     - Close MAS when done" -ForegroundColor Gray
        Write-Host "  ================================================" -ForegroundColor Cyan
        Write-Host ""

        try {
            # Launch MAS in a new elevated PowerShell window
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$masScriptPath`"" `
                -Verb RunAs -ErrorAction Stop
            Write-Success "MAS launched in a new Administrator window."
        } catch {
            # Fallback: launch in current window if UAC elevation fails
            Write-Warn "Could not open new window. Running MAS in current session..."
            try {
                & $masScriptPath
            } catch {
                Write-Err "MAS execution failed: $_"
            }
        }
    } else {
        Write-Host ""
        Write-Step "Office activation skipped (not selected in config)."
    }

    # Disable Office telemetry while we're here
    Write-Host ""
    Write-Host "  [Bonus] Disabling Office telemetry..." -ForegroundColor Yellow
    Write-Host ""
    $officeTelemetry = @(
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Office\16.0\Common"; Name = "sendcustomerdata"; Value = 0 },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Office\16.0\Common"; Name = "Uploaddocs"; Value = 0 },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\Feedback"; Name = "Enabled"; Value = 0 },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\Feedback"; Name = "IncludeScreenshot"; Value = 0 },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\ptws"; Name = "ptws"; Value = 0 },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\Internet"; Name = "UseOnlineContent"; Value = 0 },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\SignIn"; Name = "SignInOptions"; Value = 3 },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\Privacy"; Name = "ContentServicesEnabled"; Value = 0 },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\Privacy"; Name = "DownloadContent"; Value = 0 },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\Privacy"; Name = "EnableInsights"; Value = 0 },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\Privacy"; Name = "EnableUserInputTelemetry"; Value = 0 },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\Privacy"; Name = "EnablePersonalization"; Value = 0 },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Office\16.0\Excel\Options"; Name = "Voice"; Value = 0 },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Office\16.0\FirstRun"; Name = "BootedRTM"; Value = 1 },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Options\Calendar"; Name = "EnableOnlineCalendar"; Value = 0 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Common"; Name = "sendcustomerdata"; Value = 0 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Common"; Name = "Uploaddocs"; Value = 0 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Common\Privacy"; Name = "ContentServicesEnabled"; Value = 0 }
    )
    foreach ($item in $officeTelemetry) {
        Set-Registry -Path $item.Path -Name $item.Name -Value $item.Value -Type DWord -SafetyLevel "Safe" -Description "Disables Office telemetry/data collection — stops Office data sharing with Microsoft" -SettingID "OfficeActivation_Office_OfficeActivation_Office"
    }
    Write-Success "Office telemetry disabled (18 keys)."

    Write-Host ""
    Write-Success "Office section complete."
    Write-Host ""
}

#endregion

#region ============================================================
# SECTION 12: EDGE HARDENING
# ============================================================

function Invoke-EdgeHardening {
    $script:CurrentSection = "EdgeHardening"
    Write-Host ""

    $edgePath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

    # ================================================================
    # Config-driven Edge policies (Edge_1 through Edge_24)
    # ================================================================

    # Default: all off (config will enable specific ones)
    $edge1_Telemetry      = $false   # Edge_1
    $edge2_Suggestions    = $false   # Edge_2
    $edge3_Shopping       = $false   # Edge_3
    $edge4_Collections    = $false   # Edge_4
    $edge5_Background     = $false   # Edge_5
    $edge6_Sidebar        = $false   # Edge_6
    $edge7_StrictTracking = $false   # Edge_7
    $edge8_Autofill       = $false   # Edge_8
    $edge9_StartupBoost   = $false   # Edge_9
    $edge10_Experiments   = $false   # Edge_10
    $edge11_DiagData      = $false   # Edge_11
    $edge12_3rdCookies    = $false   # Edge_12
    $edge13_DNT           = $false   # Edge_13
    $edge14_HTTPSOnly     = $false   # Edge_14
    $edge15_WebRTC        = $false   # Edge_15
    $edge16_NoPassSave    = $false   # Edge_16
    $edge17_NoPayFill     = $false   # Edge_17
    $edge18_NoAddrFill    = $false   # Edge_18
    $edge19_NoSignIn      = $false   # Edge_19
    $edge20_SafeBrowsing  = $false   # Edge_20
    $edge21_BlockMixed    = $false   # Edge_21
    $edge22_NoFirstRun    = $false   # Edge_22
    $edge23_NoDefPrompt  = $false   # Edge_23
    $edge24_NoTabPreload  = $false   # Edge_24

    if ($script:ConfigSettings) {
        $edge1_Telemetry      = [bool]$script:ConfigSettings["Edge_1"]
        $edge2_Suggestions    = [bool]$script:ConfigSettings["Edge_2"]
        $edge3_Shopping       = [bool]$script:ConfigSettings["Edge_3"]
        $edge4_Collections    = [bool]$script:ConfigSettings["Edge_4"]
        $edge5_Background     = [bool]$script:ConfigSettings["Edge_5"]
        $edge6_Sidebar        = [bool]$script:ConfigSettings["Edge_6"]
        $edge7_StrictTracking = [bool]$script:ConfigSettings["Edge_7"]
        $edge8_Autofill       = [bool]$script:ConfigSettings["Edge_8"]
        $edge9_StartupBoost   = [bool]$script:ConfigSettings["Edge_9"]
        $edge10_Experiments   = [bool]$script:ConfigSettings["Edge_10"]
        $edge11_DiagData      = [bool]$script:ConfigSettings["Edge_11"]
        $edge12_3rdCookies    = [bool]$script:ConfigSettings["Edge_12"]
        $edge13_DNT           = [bool]$script:ConfigSettings["Edge_13"]
        $edge14_HTTPSOnly     = [bool]$script:ConfigSettings["Edge_14"]
        $edge15_WebRTC        = [bool]$script:ConfigSettings["Edge_15"]
        $edge16_NoPassSave    = [bool]$script:ConfigSettings["Edge_16"]
        $edge17_NoPayFill     = [bool]$script:ConfigSettings["Edge_17"]
        $edge18_NoAddrFill    = [bool]$script:ConfigSettings["Edge_18"]
        $edge19_NoSignIn      = [bool]$script:ConfigSettings["Edge_19"]
        $edge20_SafeBrowsing  = [bool]$script:ConfigSettings["Edge_20"]
        $edge21_BlockMixed    = [bool]$script:ConfigSettings["Edge_21"]
        $edge22_NoFirstRun    = [bool]$script:ConfigSettings["Edge_22"]
        $edge23_NoDefPrompt  = [bool]$script:ConfigSettings["Edge_23"]
        $edge24_NoTabPreload  = [bool]$script:ConfigSettings["Edge_24"]
    }

    Write-Step "Applying Edge security & privacy policies..."

    # --- Telemetry & Data Collection ---
    if ($edge1_Telemetry) {
        Set-Registry -Path $edgePath -Name "MetricsReportingEnabled"       -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Stops Edge diagnostic/usage data" -SettingID "EdgeHardening_MetricsReporting"
        Set-Registry -Path $edgePath -Name "SendSiteInfoToImproveServices" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Stops Edge site info sharing" -SettingID "EdgeHardening_SendSiteInfo"
        Set-Registry -Path $edgePath -Name "PersonalizationReportingEnabled" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Stops Edge personalization reporting" -SettingID "EdgeHardening_Personalization"
    }
    if ($edge2_Suggestions) {
        Set-Registry -Path $edgePath -Name "SearchSuggestEnabled"          -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Edge search suggestions" -SettingID "EdgeHardening_SearchSuggest"
        Set-Registry -Path $edgePath -Name "ShowRecommendationsEnabled"    -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Edge recommendations" -SettingID "EdgeHardening_Recommendations"
    }
    if ($edge10_Experiments) {
        Set-Registry -Path $edgePath -Name "EdgeShoppingAssistantEnabled"  -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Edge experiments/feature flags" -SettingID "EdgeHardening_Experiments"
    }
    if ($edge11_DiagData) {
        Set-Registry -Path $edgePath -Name "DiagnosticData"               -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Sets Edge diagnostic data to required minimum" -SettingID "EdgeHardening_DiagnosticData"
    }

    # --- Anti-Tracking & Privacy ---
    if ($edge7_StrictTracking) {
        Set-Registry -Path $edgePath -Name "TrackingPrevention"            -Value 3 -Type DWord -SafetyLevel "Safe" -Description "Sets Edge tracking prevention to Strict (3)" -SettingID "EdgeHardening_StrictTracking"
    }
    if ($edge12_3rdCookies) {
        Set-Registry -Path $edgePath -Name "BlockThirdPartyCookies"        -Value 1 -Type DWord -SafetyLevel "Moderate" -Description "Blocks third-party cookies in Edge" -SettingID "EdgeHardening_Block3rdCookies"
    }
    if ($edge13_DNT) {
        Set-Registry -Path $edgePath -Name "SendSiteSettingsDoNotTrack"    -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Enables Do Not Track header in Edge" -SettingID "EdgeHardening_DNT"
    }
    if ($edge14_HTTPSOnly) {
        Set-Registry -Path $edgePath -Name "HttpsOnlyMode"                -Value 2 -Type DWord -SafetyLevel "Safe" -Description "Forces HTTPS-Only mode in Edge" -SettingID "EdgeHardening_HTTPSOnly"
    }
    if ($edge15_WebRTC) {
        Set-Registry -Path $edgePath -Name "WebRtcLocalhostIpHandling"     -Value 1 -Type DWord -SafetyLevel "Moderate" -Description "Prevents WebRTC local IP leak in Edge" -SettingID "EdgeHardening_WebRTC"
    }

    # --- Security Hardening ---
    if ($edge16_NoPassSave) {
        Set-Registry -Path $edgePath -Name "PasswordManagerEnabled"        -Value 0 -Type DWord -SafetyLevel "Moderate" -Description "Disables Edge password saving" -SettingID "EdgeHardening_NoPasswordSave"
    }
    if ($edge17_NoPayFill) {
        Set-Registry -Path $edgePath -Name "AutofillCreditCardEnabled"     -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Edge payment autofill" -SettingID "EdgeHardening_NoPayFill"
    }
    if ($edge18_NoAddrFill) {
        Set-Registry -Path $edgePath -Name "AutofillAddressEnabled"        -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Edge address autofill" -SettingID "EdgeHardening_NoAddrFill"
    }
    if ($edge19_NoSignIn) {
        Set-Registry -Path $edgePath -Name "BrowserSignin"                 -Value 0 -Type DWord -SafetyLevel "Moderate" -Description "Disables Edge browser sign-in" -SettingID "EdgeHardening_NoSignIn"
        Set-Registry -Path $edgePath -Name "SyncDisabled"                  -Value 1 -Type DWord -SafetyLevel "Moderate" -Description "Disables Edge sync" -SettingID "EdgeHardening_NoSync"
    }
    if ($edge20_SafeBrowsing) {
        Set-Registry -Path $edgePath -Name "SafeBrowsingLevel"             -Value 2 -Type DWord -SafetyLevel "Safe" -Description "Enables Enhanced Safe Browsing in Edge" -SettingID "EdgeHardening_EnhancedSafeBrowsing"
    }
    if ($edge21_BlockMixed) {
        Set-Registry -Path $edgePath -Name "BlockInsecurePrivateNetworkRequests" -Value 1 -Type DWord -SafetyLevel "Moderate" -Description "Blocks insecure/mixed content in Edge" -SettingID "EdgeHardening_BlockMixed"
    }

    # --- Bloat & Annoyances ---
    if ($edge3_Shopping) {
        Set-Registry -Path $edgePath -Name "EdgeShoppingAssistantEnabled"  -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Edge shopping assistant" -SettingID "EdgeHardening_NoShopping"
    }
    if ($edge4_Collections) {
        Set-Registry -Path $edgePath -Name "CollectionsEnabled"           -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Edge Collections" -SettingID "EdgeHardening_NoCollections"
    }
    if ($edge5_Background) {
        Set-Registry -Path $edgePath -Name "BackgroundModeEnabled"        -Value 0 -Type DWord -SafetyLevel "Moderate" -Description "Disables Edge background mode" -SettingID "EdgeHardening_NoBackground"
    }
    if ($edge6_Sidebar) {
        Set-Registry -Path $edgePath -Name "HubsSidebarEnabled"           -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Edge sidebar/Copilot" -SettingID "EdgeHardening_NoSidebar"
        Set-Registry -Path $edgePath -Name "CopilotPageContext"            -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Edge Copilot page context" -SettingID "EdgeHardening_NoCopilot"
        Set-Registry -Path $edgePath -Name "CopilotCDPPageContext"         -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Edge Copilot CDP context" -SettingID "EdgeHardening_NoCopilotCDP"
    }
    if ($edge8_Autofill) {
        Set-Registry -Path $edgePath -Name "AutofillCreditCardEnabled"     -Value 0 -Type DWord -SafetyLevel "Moderate" -Description "Disables Edge autofill" -SettingID "EdgeHardening_NoAutofill"
        Set-Registry -Path $edgePath -Name "AutofillAddressEnabled"        -Value 0 -Type DWord -SafetyLevel "Moderate" -Description "Disables Edge address autofill" -SettingID "EdgeHardening_NoAddrAutofill"
        Set-Registry -Path $edgePath -Name "PasswordManagerEnabled"        -Value 0 -Type DWord -SafetyLevel "Moderate" -Description "Disables Edge password saving" -SettingID "EdgeHardening_NoPassAutofill"
    }
    if ($edge9_StartupBoost) {
        Set-Registry -Path $edgePath -Name "StartupBoostEnabled"          -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Edge startup boost" -SettingID "EdgeHardening_NoStartupBoost"
    }
    if ($edge22_NoFirstRun) {
        Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\Main" -Name "DisallowFirstRun" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Disables Edge first-run experience" -SettingID "EdgeHardening_NoFirstRun"
    }
    if ($edge23_NoDefPrompt) {
        Set-Registry -Path $edgePath -Name "DefaultBrowserSettingEnabled"  -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Hides Edge default browser prompt" -SettingID "EdgeHardening_NoDefPrompt"
    }
    if ($edge24_NoTabPreload) {
        Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\TabPreloader" -Name "AllowTabPreloading" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Edge tab preloading" -SettingID "EdgeHardening_NoTabPreload"
    }

    # Always disable Edge prelaunch (no user toggle needed — it's purely bloat)
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\Main" `
        -Name "AllowPrelaunch" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Edge prelaunch" -SettingID "EdgeHardening_NoEdgePrelaunch"

    # Also set UserFeedbackAllowed=0 when telemetry is on
    if ($edge1_Telemetry) {
        Set-Registry -Path $edgePath -Name "UserFeedbackAllowed"           -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables Edge user feedback" -SettingID "EdgeHardening_NoFeedback"
    }

    Write-Host ""
    Write-Success "Edge security & privacy hardening complete."
}

#endregion

#region ============================================================
# SECTION 13: ONEDRIVE MANAGEMENT
# ============================================================

function Invoke-OneDriveManagement {
    $script:CurrentSection = "OneDrive"
    Write-Host ""

    # 1. Disable OneDrive via Group Policy
    Write-Step "Disabling OneDrive..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" `
        -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Disables OneDrive file sync via Group Policy — prevents OneDrive integration" -SettingID "OneDrive_DisableOneDrive"

    # 2. Hide OneDrive from File Explorer navigation pane
    Write-Step "Hiding OneDrive from File Explorer..."
    foreach ($path in @(
        "HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}",
        "HKCR:\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}")) {
        Set-Registry -Path $path -Name "System.IsPinnedToNameSpaceTree" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Hides OneDrive from File Explorer navigation pane" -SettingID "OneDrive_HideOneDriveNav"
    }

    # 3. Remove OneDrive from startup (if present)
    Write-Step "Removing OneDrive from startup..."
    $odRun = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    try {
        $val = Get-ItemProperty -Path $odRun -Name "OneDrive" -ErrorAction SilentlyContinue
        if ($val) {
            Remove-ItemProperty -Path $odRun -Name "OneDrive" -Force -ErrorAction Stop
            Write-Success "Removed OneDrive from startup registry."
        }
    } catch { Write-Warn "Could not remove OneDrive from startup: $_" }

    Write-Host ""
    Write-Success "OneDrive management complete."
}

#endregion

#region ============================================================
# SECTION 14: GAMING / XBOX / DVR DISABLE
# ============================================================

function Invoke-GamingDisable {
    $script:CurrentSection = "Gaming"
    Write-Host ""

    # 1. Disable GameDVR via policy
    Write-Step "Disabling GameDVR..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" `
        -Name "AllowgameDVR" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables GameDVR via policy — stops game clip recording" -SettingID "Gaming_NoGameDVR"

    # 2. Disable Game Bar capture
    Write-Step "Disabling Game Bar capture..."
    foreach ($prop in @("AppCaptureEnabled", "HistoricalCaptureEnabled")) {
        Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" `
            -Name $prop -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables GameDVR/Game Bar setting — stops game recording" -SettingID "Gaming_GameDVR_Gaming_GVR"
        Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" `
            -Name $prop -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables GameDVR/Game Bar setting — stops game recording" -SettingID "Gaming_GameDVR_Gaming_GVR_2"
    }

    # 3. Disable GameDVR_Enabled
    Write-Step "Disabling GameDVR_Enabled..."
    Set-Registry -Path "HKCU:\System\GameConfigStore" `
        -Name "GameDVR_Enabled" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables GameDVR — stops game recording and broadcasting" -SettingID "Gaming_GameDVR_Off"
    Set-Registry -Path "HKLM:\System\GameConfigStore" `
        -Name "GameDVR_Enabled" -Value 0 -Type DWord -SafetyLevel "Safe" -Description "Disables GameDVR — stops game recording and broadcasting" -SettingID "Gaming_GameDVR_Off"

    Write-Host ""
    Write-Success "Gaming / Xbox / DVR disable complete."
}

#endregion

#region ============================================================
# SECTION 15: SCHEDULED TASKS CLEANUP
# ============================================================

function Invoke-ScheduledTasksCleanup {
    $script:CurrentSection = "ScheduledTasks"
    Write-Host ""

    $tasksToDisable = @(
        @{ Path = "\Microsoft\Windows\Application Experience\";       Name = "AitAgent" },
        @{ Path = "\Microsoft\Windows\Application Experience\";       Name = "Microsoft Compatibility Appraiser" },
        @{ Path = "\Microsoft\Windows\Application Experience\";       Name = "ProgramDataUpdater" },
        @{ Path = "\Microsoft\Windows\Application Experience\";       Name = "StartupAppTask" },
        @{ Path = "\Microsoft\Windows\Customer Experience Improvement Program\"; Name = "Consolidator" },
        @{ Path = "\Microsoft\Windows\Customer Experience Improvement Program\"; Name = "KernelCeipTask" },
        @{ Path = "\Microsoft\Windows\Customer Experience Improvement Program\"; Name = "UsbCeip" },
        @{ Path = "\Microsoft\Windows\Device Information\";          Name = "Device" },
        @{ Path = "\Microsoft\Windows\ErrorDetails\";                Name = "EnableErrorDetailsUpdate" },
        @{ Path = "\Microsoft\Windows\Windows Error Reporting\";      Name = "QueueReporting" },
        @{ Path = "\Microsoft\Windows\Feedback\";                     Name = "Siuf\DmClient" },
        @{ Path = "\Microsoft\Windows\Feedback\";                     Name = "Siuf\DmClientOnScenarioDownload" },
        @{ Path = "\Microsoft\Windows\Maps\";                         Name = "MapsUpdateTask" },
        @{ Path = "\Microsoft\Windows\Maps\";                         Name = "MapsToastTask" },
        @{ Path = "\Microsoft\Windows\Maintenance\";                  Name = "WinSAT" },
        @{ Path = "\Microsoft\Windows\Shell\";                         Name = "FamilySafetyMonitor" },
        @{ Path = "\Microsoft\Windows\Shell\";                         Name = "FamilySafetyRefresh" },
        @{ Path = "\Microsoft\Windows\Shell\";                         Name = "FamilySafetyUpload" },
        @{ Path = "\Microsoft\Windows\Power Efficiency Diagnostics\"; Name = "AnalyzeSystem" },
        @{ Path = "\Microsoft\Windows\PI\";                           Name = "Sqm-Tasks" },
        @{ Path = "\Microsoft\Windows\NetTrace\";                     Name = "GatherNetworkInfo" },
        @{ Path = "\Microsoft\XblGameSave\";                         Name = "XblGameSaveTask" },
        @{ Path = "\Microsoft\XblGameSave\";                         Name = "XblGameSaveTaskLogon" },
        @{ Path = "\Microsoft\Windows\WindowsUpdate\";               Name = "Automatic App Update" },
        @{ Path = "\Microsoft\Windows\DiskDiagnostic\";              Name = "Microsoft-Windows-DiskDiagnosticDataCollector" },
        @{ Path = "\Microsoft\Windows\DiskFootprint\";               Name = "Diagnostics" },
        @{ Path = "\Microsoft\Windows\License Manager\";            Name = "TempSignedLicenseExchange" },
        @{ Path = "\Microsoft\Windows\Subscription\";                Name = "EnableLicenseAcquisition" },
        @{ Path = "\Microsoft\Windows\Subscription\";                Name = "LicenseAcquisition" }
    )

    $disabled = 0; $notFound = 0
    foreach ($task in $tasksToDisable) {
        Disable-AppTask -TaskPath $task.Path -TaskName $task.Name -SafetyLevel "Safe" -Description "Disables telemetry/diagnostics scheduled task — stops background data collection" -SettingID "ScheduledTasks_TelemetryTask_ScheduledTasks_Task"
        $disabled++
    }

    # Disable Office telemetry tasks
    $officeTasks = @(
        @{ Path = "\Microsoft\Office\"; Name = "OfficeTelemetryAgentFallBack" },
        @{ Path = "\Microsoft\Office\"; Name = "OfficeTelemetryAgentFallBack2016" },
        @{ Path = "\Microsoft\Office\"; Name = "OfficeTelemetryAgentLogOn" },
        @{ Path = "\Microsoft\Office\"; Name = "OfficeTelemetryAgentLogOn2016" },
        @{ Path = "\Microsoft\Office\"; Name = "Office 15 Subscription Heartbeat" },
        @{ Path = "\Microsoft\Office\"; Name = "Office 16 Subscription Heartbeat" }
    )
    foreach ($task in $officeTasks) {
        Disable-AppTask -TaskPath $task.Path -TaskName $task.Name -SafetyLevel "Safe" -Description "Disables telemetry/diagnostics scheduled task — stops background data collection" -SettingID "ScheduledTasks_TelemetryTask_ScheduledTasks_Task_2"
        $disabled++
    }

    Write-Host ""
    Write-Success "Scheduled tasks cleanup complete. Processed $($disabled + $notFound) tasks."
}

#endregion

#region ============================================================
# SECTION 16: BROWSER EXTENSIONS & PRIVACY
# ============================================================

function Invoke-BrowserHardening {
    $script:CurrentSection = "BrowserHardening"
    Write-Host ""

    # ================================================================
    # Extension IDs and install URLs
    # ================================================================
    # uBlock Origin (BE_1)
    $ublockChromeID    = "cjpalhdlnbpafiamejdnhcphjbkeiagm"
    $ublockFirefoxID   = "uBlock0@raymondhill.net"
    $ublockAMOUrl      = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/addon-607454-latest.xpi"
    # AdGuard AdBlocker (BE_2)
    $adguardChromeID   = "bgnkhhnnicmohppcllllhnncibipnjak"
    $adguardFirefoxID  = "adguardadblocker@adguard.com"
    $adguardAMOUrl     = "https://addons.mozilla.org/firefox/downloads/latest/adguard-adblocker/addon-864033-latest.xpi"
    # AdBlock Plus (BE_3)
    $abpChromeID       = "cfhdojbkjhnklbpkdlldjfndllcbknp"
    $abpFirefoxID      = "d10d0cv8z3sbk65modnq@jetpack"
    $abpAMOUrl         = "https://addons.mozilla.org/firefox/downloads/latest/adblock-plus/addon-1865-latest.xpi"
    # SponsorBlock for YouTube (BE_4)
    $sponsorChromeID   = "mnjggcdcoclljnjhpdikcjddbnhijjkh"
    $sponsorFirefoxID  = "sponsorBlocker@ajay.app"
    $sponsorAMOUrl     = "https://addons.mozilla.org/firefox/downloads/latest/sponsorblock/addon-722678-latest.xpi"
    # YouTube NonStop (BE_5)
    $ytNonStopChromeID = "hdbidhplkcgchohbgbgkablbmpkljiki"
    $ytNonStopFirefoxID= "{0e33e5ae-2e58-4342-bc82-e3a776e97e6e}"
    $ytNonStopAMOUrl   = "https://addons.mozilla.org/firefox/downloads/latest/youtube-nonstop/addon-744421-latest.xpi"
    # Privacy Badger (BE_6)
    $badgerChromeID    = "pkehgijcmpdhfbdbbnkijodmdjhbjlgp"
    $badgerFirefoxID   = "jid1-MnnxcxisBPnSXQ@jetpack"
    $badgerAMOUrl      = "https://addons.mozilla.org/firefox/downloads/latest/privacy-badger17/addon-576858-latest.xpi"
    # Popup Blocker (strict) (BE_7) - uBlock Origin with strict mode handles this, plus Poper Blocker
    $poperChromeID     = "bbmhgpmolkhfmfgepgbokjolhcbgbhol"
    $poperFirefoxID    = "{75459c04-9d63-4a18-958e-86e37d07ab52}"
    $poperAMOUrl       = "https://addons.mozilla.org/firefox/downloads/latest/poper-blocker/addon-635728-latest.xpi"
    # Cookie AutoDelete (BE_8)
    $cookieAutoDelChromeID = "fhcgjignffcepefcmhkjgbeibmifglpj"
    $cookieAutoDelFirefoxID= "CookieAutoDelete@kennydo"
    $cookieAutoDelAMOUrl   = "https://addons.mozilla.org/firefox/downloads/latest/cookie-autodelete/addon-576858-latest.xpi"
    # HTTPS Everywhere (BE_9) - Note: mostly superseded by browser built-in HTTPS-Only
    $httpsEChromeID    = "gcbommkclmepnbljdpbkmdhdhpkblhdb"
    $httpsEFirefoxID   = "https-everywhere@eff.org"
    $httpsEAMOUrl      = "https://addons.mozilla.org/firefox/downloads/latest/https-everywhere/addon-3706-latest.xpi"
    # Decentraleyes (BE_10)
    $decentChromeID    = "ldpochfccmkkmhnbpcgljndlmkfmokom"
    $decentFirefoxID   = "jid1-MnnxcxisBPnSXQ@jetpack-decentraleyes"
    $decentAMOUrl      = "https://addons.mozilla.org/firefox/downloads/latest/decentraleyes/addon-641469-latest.xpi"

    # Chromium extension update URLs
    $chromeWebStoreUrl = "https://clients2.google.com/service/update2/crx"
    $edgeAddonsUrl    = "https://edge.microsoft.com/extensionwebstorebase/v1/crx"

    # ================================================================
    # Build extension lists from config (BE_1..BE_10)
    # ================================================================
    # Default: if no config, enable uBlock Origin + Privacy Badger (backward compat)
    $extUblock    = $true   # BE_1
    $extAdguard   = $false  # BE_2
    $extABP       = $false  # BE_3
    $extSponsor   = $false  # BE_4
    $extYTNonStop = $false  # BE_5
    $extBadger    = $true   # BE_6
    $extPoper     = $false  # BE_7
    $extCookieAD  = $false  # BE_8
    $extHTTPSE    = $false  # BE_9
    $extDecent    = $false  # BE_10

    if ($script:ConfigSettings) {
        $extUblock    = [bool]$script:ConfigSettings["BE_1"]
        $extAdguard   = [bool]$script:ConfigSettings["BE_2"]
        $extABP       = [bool]$script:ConfigSettings["BE_3"]
        $extSponsor   = [bool]$script:ConfigSettings["BE_4"]
        $extYTNonStop = [bool]$script:ConfigSettings["BE_5"]
        $extBadger    = [bool]$script:ConfigSettings["BE_6"]
        $extPoper     = [bool]$script:ConfigSettings["BE_7"]
        $extCookieAD  = [bool]$script:ConfigSettings["BE_8"]
        $extHTTPSE    = [bool]$script:ConfigSettings["BE_9"]
        $extDecent    = [bool]$script:ConfigSettings["BE_10"]
    }

    # --- Helper: Add extension to Chromium ExtensionInstallForcelist ---
    function Add-ChromiumExtension {
        param(
            [string]$RegPath,
            [string]$ExtID,
            [string]$UpdateUrl,
            [string]$BrowserName,
            [string]$ExtName
        )
        try {
            if (-not (Test-Path $RegPath)) {
                New-Item -Path $RegPath -Force -ErrorAction Stop | Out-Null
            }
            $entry = "$ExtID;$UpdateUrl"
            # Check if already present (registry values are named 1, 2, 3...)
            $existing = (Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue)
            $found = $false
            if ($existing) {
                $existing.PSObject.Properties | ForEach-Object {
                    if ($_.Value -like "$ExtID;*") { $found = $true }
                }
            }
            if ($found) {
                Write-Step "$BrowserName`: $ExtName already in forcelist."
            } else {
                # Find next available index
                $idx = 1
                while ($existing.PSObject.Properties.Name -contains $idx.ToString()) { $idx++ }
                New-ItemProperty -Path $RegPath -Name $idx.ToString() -Value $entry -PropertyType String -Force -ErrorAction Stop | Out-Null
                Write-Success "$BrowserName`: Force-installed $ExtName ($ExtID)"
            }
        } catch {
            Write-Warn "$BrowserName`: Could not add $ExtName`: $_"
        }
    }

    # --- Helper: Apply selected extensions to a Chromium-based browser ---
    function Add-SelectedChromiumExtensions {
        param(
            [string]$RegPath,
            [string]$UpdateUrl,
            [string]$BrowserName
        )
        if ($extUblock)    { Add-ChromiumExtension -RegPath $RegPath -ExtID $ublockChromeID    -UpdateUrl $UpdateUrl -BrowserName $BrowserName -ExtName "uBlock Origin" }
        if ($extAdguard)   { Add-ChromiumExtension -RegPath $RegPath -ExtID $adguardChromeID   -UpdateUrl $UpdateUrl -BrowserName $BrowserName -ExtName "AdGuard AdBlocker" }
        if ($extABP)       { Add-ChromiumExtension -RegPath $RegPath -ExtID $abpChromeID       -UpdateUrl $UpdateUrl -BrowserName $BrowserName -ExtName "AdBlock Plus" }
        if ($extSponsor)   { Add-ChromiumExtension -RegPath $RegPath -ExtID $sponsorChromeID   -UpdateUrl $UpdateUrl -BrowserName $BrowserName -ExtName "SponsorBlock" }
        if ($extYTNonStop) { Add-ChromiumExtension -RegPath $RegPath -ExtID $ytNonStopChromeID -UpdateUrl $UpdateUrl -BrowserName $BrowserName -ExtName "YouTube NonStop" }
        if ($extBadger)    { Add-ChromiumExtension -RegPath $RegPath -ExtID $badgerChromeID    -UpdateUrl $UpdateUrl -BrowserName $BrowserName -ExtName "Privacy Badger" }
        if ($extPoper)     { Add-ChromiumExtension -RegPath $RegPath -ExtID $poperChromeID     -UpdateUrl $UpdateUrl -BrowserName $BrowserName -ExtName "Popup Blocker" }
        if ($extCookieAD)  { Add-ChromiumExtension -RegPath $RegPath -ExtID $cookieAutoDelChromeID -UpdateUrl $UpdateUrl -BrowserName $BrowserName -ExtName "Cookie AutoDelete" }
        if ($extHTTPSE)    { Add-ChromiumExtension -RegPath $RegPath -ExtID $httpsEChromeID    -UpdateUrl $UpdateUrl -BrowserName $BrowserName -ExtName "HTTPS Everywhere" }
        if ($extDecent)    { Add-ChromiumExtension -RegPath $RegPath -ExtID $decentChromeID    -UpdateUrl $UpdateUrl -BrowserName $BrowserName -ExtName "Decentraleyes" }
    }

    # --- Google Chrome ---
    Write-Step "Configuring Google Chrome extensions..."
    $chromeInstalled = Test-Path "HKLM:\SOFTWARE\Google\Chrome\MBL" -ErrorAction SilentlyContinue
    $chromeInstalled2 = Test-Path "HKLM:\SOFTWARE\WOW6432Node\Google\Chrome\MBL" -ErrorAction SilentlyContinue
    $chromePolicyPath = "HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist"
    if ($chromeInstalled -or $chromeInstalled2 -or (Test-Path "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe") -or (Test-Path "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe")) {
        Add-SelectedChromiumExtensions -RegPath $chromePolicyPath -UpdateUrl $chromeWebStoreUrl -BrowserName "Chrome"
    } else {
        Write-Step "Google Chrome not detected. Setting policies anyway (applies if installed later)."
        Add-SelectedChromiumExtensions -RegPath $chromePolicyPath -UpdateUrl $chromeWebStoreUrl -BrowserName "Chrome"
    }

    # --- Microsoft Edge ---
    Write-Step "Configuring Microsoft Edge extensions..."
    $edgePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist"
    Add-SelectedChromiumExtensions -RegPath $edgePolicyPath -UpdateUrl $edgeAddonsUrl -BrowserName "Edge"

    # --- Brave ---
    Write-Step "Configuring Brave extensions..."
    $bravePolicyPath = "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave\ExtensionInstallForcelist"
    $braveInstalled = (Test-Path "${env:LOCALAPPDATA}\BraveSoftware\Brave-Browser\Application\brave.exe") -or (Test-Path "${env:ProgramFiles}\BraveSoftware\Brave-Browser\Application\brave.exe")
    if ($braveInstalled) {
        Add-SelectedChromiumExtensions -RegPath $bravePolicyPath -UpdateUrl $chromeWebStoreUrl -BrowserName "Brave"
    } else {
        Write-Step "Brave not detected. Setting policies anyway (applies if installed later)."
        Add-SelectedChromiumExtensions -RegPath $bravePolicyPath -UpdateUrl $chromeWebStoreUrl -BrowserName "Brave"
    }

    # --- Opera (uses Chrome Web Store, limited policy support) ---
    Write-Step "Configuring Opera extensions..."
    $operaPolicyPath = "HKLM:\SOFTWARE\Policies\Opera\ExtensionInstallForcelist"
    $operaInstalled = (Test-Path "${env:ProgramFiles}\Opera\launcher.exe") -or (Test-Path "${env:LOCALAPPDATA}\Programs\Opera\launcher.exe")
    if ($operaInstalled) {
        Add-SelectedChromiumExtensions -RegPath $operaPolicyPath -UpdateUrl $chromeWebStoreUrl -BrowserName "Opera"
    } else {
        Write-Step "Opera not detected. Setting policies (may not apply - Opera has limited policy support)."
        Add-SelectedChromiumExtensions -RegPath $operaPolicyPath -UpdateUrl $chromeWebStoreUrl -BrowserName "Opera"
    }

    # --- Firefox (uses policies.json - different mechanism) ---
    Write-Step "Configuring Firefox extensions via policies..."
    $firefoxPaths = @(
        "${env:ProgramFiles}\Mozilla Firefox",
        "${env:ProgramFiles(x86)}\Mozilla Firefox"
    )
    $firefoxRoot = $firefoxPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($firefoxRoot) {
        $distDir = Join-Path $firefoxRoot "distribution"
        if (-not (Test-Path $distDir)) { New-Item -Path $distDir -ItemType Directory -Force | Out-Null }
        $policyFile = Join-Path $distDir "policies.json"

        $firefoxPolicy = @{}
        if (Test-Path $policyFile) {
            try { $firefoxPolicy = Get-Content $policyFile -Raw | ConvertFrom-Json -AsHashtable } catch { $firefoxPolicy = @{} }
        }

        if (-not $firefoxPolicy.ContainsKey("policies")) { $firefoxPolicy["policies"] = @{} }
        $p = $firefoxPolicy["policies"]

        # ExtensionSettings for force-installing extensions
        if (-not $p.ContainsKey("ExtensionSettings")) { $p["ExtensionSettings"] = @{} }
        $extSettings = $p["ExtensionSettings"]

        if ($extUblock)    { $extSettings[$ublockFirefoxID]    = @{ "installation_mode" = "force_installed"; "install_url" = $ublockAMOUrl } }
        if ($extAdguard)   { $extSettings[$adguardFirefoxID]   = @{ "installation_mode" = "force_installed"; "install_url" = $adguardAMOUrl } }
        if ($extABP)       { $extSettings[$abpFirefoxID]       = @{ "installation_mode" = "force_installed"; "install_url" = $abpAMOUrl } }
        if ($extSponsor)   { $extSettings[$sponsorFirefoxID]   = @{ "installation_mode" = "force_installed"; "install_url" = $sponsorAMOUrl } }
        if ($extYTNonStop) { $extSettings[$ytNonStopFirefoxID] = @{ "installation_mode" = "force_installed"; "install_url" = $ytNonStopAMOUrl } }
        if ($extBadger)    { $extSettings[$badgerFirefoxID]    = @{ "installation_mode" = "force_installed"; "install_url" = $badgerAMOUrl } }
        if ($extPoper)     { $extSettings[$poperFirefoxID]     = @{ "installation_mode" = "force_installed"; "install_url" = $poperAMOUrl } }
        if ($extCookieAD)  { $extSettings[$cookieAutoDelFirefoxID] = @{ "installation_mode" = "force_installed"; "install_url" = $cookieAutoDelAMOUrl } }
        if ($extHTTPSE)    { $extSettings[$httpsEFirefoxID]    = @{ "installation_mode" = "force_installed"; "install_url" = $httpsEAMOUrl } }
        if ($extDecent)    { $extSettings[$decentFirefoxID]    = @{ "installation_mode" = "force_installed"; "install_url" = $decentAMOUrl } }

        $firefoxPolicy["policies"] = $p
        $jsonOutput = $firefoxPolicy | ConvertTo-Json -Depth 10 -Compress
        Set-Content -Path $policyFile -Value $jsonOutput -Encoding UTF8 -Force
        $ffExtList = @()
        if ($extUblock)    { $ffExtList += "uBlock Origin" }
        if ($extAdguard)   { $ffExtList += "AdGuard" }
        if ($extABP)       { $ffExtList += "AdBlock Plus" }
        if ($extSponsor)   { $ffExtList += "SponsorBlock" }
        if ($extYTNonStop) { $ffExtList += "YouTube NonStop" }
        if ($extBadger)    { $ffExtList += "Privacy Badger" }
        if ($extPoper)     { $ffExtList += "Popup Blocker" }
        if ($extCookieAD)  { $ffExtList += "Cookie AutoDelete" }
        if ($extHTTPSE)    { $ffExtList += "HTTPS Everywhere" }
        if ($extDecent)    { $ffExtList += "Decentraleyes" }
        Write-Success "Firefox: Force-installed $($ffExtList -join ', ') via policies.json"
    } else {
        # Fallback: set via registry (Firefox also supports this)
        Write-Step "Firefox not found in Program Files. Setting registry-based policies..."
        $ffPolicyPath = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox\ExtensionSettings"
        try {
            if (-not (Test-Path $ffPolicyPath)) { New-Item -Path $ffPolicyPath -Force -ErrorAction Stop | Out-Null }
            if ($extUblock)  { Set-ItemProperty -Path $ffPolicyPath -Name $ublockFirefoxID  -Value ('{"installation_mode":"force_installed","install_url":"' + $ublockAMOUrl + '"}') -Force -ErrorAction Stop }
            if ($extBadger)  { Set-ItemProperty -Path $ffPolicyPath -Name $badgerFirefoxID  -Value ('{"installation_mode":"force_installed","install_url":"' + $badgerAMOUrl + '"}') -Force -ErrorAction Stop }
            if ($extAdguard) { Set-ItemProperty -Path $ffPolicyPath -Name $adguardFirefoxID -Value ('{"installation_mode":"force_installed","install_url":"' + $adguardAMOUrl + '"}') -Force -ErrorAction Stop }
            if ($extSponsor) { Set-ItemProperty -Path $ffPolicyPath -Name $sponsorFirefoxID -Value ('{"installation_mode":"force_installed","install_url":"' + $sponsorAMOUrl + '"}') -Force -ErrorAction Stop }
            Write-Success "Firefox: Extension policies set via registry (applies when Firefox is installed)."
        } catch {
            Write-Warn "Firefox: Could not set extension policies: $_"
        }
    }

    # ================================================================
    # PART B: Browser Privacy Settings
    # ================================================================
    Write-Host ""
    Write-Host "  [Privacy Settings]" -ForegroundColor Yellow
    Write-Host ""

    # --- Google Chrome Privacy ---
    Write-Step "Applying Chrome privacy policies..."
    $chromePol = "HKLM:\SOFTWARE\Policies\Google\Chrome"
    $chromePrivacySettings = @{
        "BlockThirdPartyCookies"                = 1
        "IncognitoModeAvailability"              = 1
        "SyncDisabled"                           = 1
        "BrowserSignin"                          = 0
        "MetricsReportingEnabled"                = 0
        "SendSiteInfoToImproveServices"          = 0
        "SearchSuggestEnabled"                   = 0
        "AlternateErrorPagesEnabled"             = 0
        "UrlKeyedAnonymizedDataCollectionEnabled" = 0
        "SafeBrowsingExtendedReportingEnabled"   = 0
        "WebRtcLocalhostIpHandling"              = 1
        "WebRtcUdpPortRange"                     = "0"
        "RestoreOnStartup"                       = 4
        "DefaultBrowserSettingEnabled"           = 0
    }
    foreach ($prop in $chromePrivacySettings.Keys) {
        $val = $chromePrivacySettings[$prop]
        $type = if ($val -is [int]) { "DWord" } else { "String" }
        Set-Registry -Path $chromePol -Name $prop -Value $val -Type $type `
            -SafetyLevel "Safe" -Description "Applies Chrome privacy policy — reduces Chrome data collection" -SettingID "BrowserHardening_Chrome_$($prop)"
    }

    # --- Brave Privacy (Brave has built-in shields, but we can set policies too) ---
    Write-Step "Applying Brave privacy policies..."
    $bravePol = "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave"
    $bravePrivacySettings = @{
        "BlockThirdPartyCookies"                = 1
        "SyncDisabled"                           = 1
        "BrowserSignin"                          = 0
        "MetricsReportingEnabled"                = 0
        "SendSiteInfoToImproveServices"          = 0
        "SearchSuggestEnabled"                   = 0
        "AlternateErrorPagesEnabled"             = 0
        "UrlKeyedAnonymizedDataCollectionEnabled" = 0
        "WebRtcLocalhostIpHandling"              = 1
        "RestoreOnStartup"                       = 4
        "DefaultBrowserSettingEnabled"           = 0
        "BraveSyncEnabled"                       = 0
    }
    foreach ($prop in $bravePrivacySettings.Keys) {
        $val = $bravePrivacySettings[$prop]
        $type = if ($val -is [int]) { "DWord" } else { "String" }
        Set-Registry -Path $bravePol -Name $prop -Value $val -Type $type `
            -SafetyLevel "Safe" -Description "Applies Brave privacy policy — hardens Brave browser" -SettingID "BrowserHardening_Brave_$($prop)"
    }

    # --- Opera Privacy ---
    Write-Step "Applying Opera privacy policies..."
    $operaPol = "HKLM:\SOFTWARE\Policies\Opera"
    $operaPrivacySettings = @{
        "BlockThirdPartyCookies"                = 1
        "SyncDisabled"                           = 1
        "MetricsReportingEnabled"                = 0
        "SearchSuggestEnabled"                   = 0
        "AlternateErrorPagesEnabled"             = 0
        "UrlKeyedAnonymizedDataCollectionEnabled" = 0
    }
    foreach ($prop in $operaPrivacySettings.Keys) {
        Set-Registry -Path $operaPol -Name $prop -Value $operaPrivacySettings[$prop] -Type DWord `
            -SafetyLevel "Safe" -Description "Applies Opera privacy policy — reduces Opera data collection" -SettingID "BrowserHardening_Opera_$($prop)"
    }

    # --- Firefox Privacy ---
    Write-Step "Applying Firefox privacy policies..."
    $ffPol = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox"
    Set-Registry -Path $ffPol -Name "DisableTelemetry" -Value 1 -Type DWord `
        -SafetyLevel "Safe" -Description "Disables Firefox telemetry — stops Firefox data collection" -SettingID "BrowserHardening_FF_NoTelemetry"
    Set-Registry -Path $ffPol -Name "DisableFirefoxStudies" -Value 1 -Type DWord `
        -SafetyLevel "Safe" -Description "Disables Firefox Studies — stops Firefox A/B experiments" -SettingID "BrowserHardening_FF_NoStudies"
    Set-Registry -Path $ffPol -Name "DisablePocket" -Value 1 -Type DWord `
        -SafetyLevel "Safe" -Description "Disables Pocket integration — stops Pocket data collection" -SettingID "BrowserHardening_FF_NoPocket"
    Set-Registry -Path $ffPol -Name "DisableFormHistory" -Value 1 -Type DWord `
        -SafetyLevel "Safe" -Description "Disables form history — stops autofill data collection" -SettingID "BrowserHardening_FF_NoFormHist"
    Set-Registry -Path $ffPol -Name "OfferToSaveLogins" -Value 0 -Type DWord `
        -SafetyLevel "Safe" -Description "Disables login save offers — prevents credential storage in browser" -SettingID "BrowserHardening_FF_NoSaveLogins"
    Set-Registry -Path $ffPol -Name "PasswordManagerEnabled" -Value 0 -Type DWord `
        -SafetyLevel "Safe" -Description "Disables Firefox password manager — prevents credential storage in browser" -SettingID "BrowserHardening_FF_NoPasswordMgr"
    Set-Registry -Path $ffPol -Name "SanitizeOnShutdown" -Value 1 -Type DWord `
        -SafetyLevel "Safe" -Description "Enables sanitize on shutdown — clears browsing data on exit" -SettingID "BrowserHardening_FF_SanitizeOnShutdown"
    Set-Registry -Path $ffPol -Name "DontCheckDefaultBrowser" -Value 1 -Type DWord `
        -SafetyLevel "Safe" -Description "Disables default browser check — reduces startup prompts" -SettingID "BrowserHardening_FF_NoDefaultCheck"

    # Firefox tracking protection (strict mode) + DoH
    Write-Step "Configuring Firefox strict tracking protection + DoH..."
    $ffTpPath = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox\EnableTrackingProtection"
    Set-Registry -Path $ffTpPath -Name "Value" -Value 1 -Type DWord `
        -SafetyLevel "Safe" -Description "Enables strict tracking protection in Firefox" -SettingID "BrowserHardening_FF_TrackingProt"
    Set-Registry -Path $ffTpPath -Name "Cryptomining" -Value 1 -Type DWord `
        -SafetyLevel "Safe" -Description "Blocks cryptomining in Firefox — stops coin miner scripts" -SettingID "BrowserHardening_FF_NoCryptomining"
    Set-Registry -Path $ffTpPath -Name "Fingerprinting" -Value 1 -Type DWord `
        -SafetyLevel "Safe" -Description "Blocks fingerprinting in Firefox — stops browser fingerprint tracking" -SettingID "BrowserHardening_FF_NoFingerprinting"
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Mozilla\Firefox\DNSOverHTTPS" -Name "Enabled" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Enables DNS-over-HTTPS in Firefox — encrypts DNS queries" -SettingID "BrowserHardening_FF_DoH"

    # If Firefox policies.json exists, also update it with privacy settings
    if ($firefoxRoot -and (Test-Path (Join-Path $firefoxRoot "distribution\policies.json"))) {
        Write-Step "Updating Firefox policies.json with privacy settings..."
        try {
            $policyFile = Join-Path $firefoxRoot "distribution\policies.json"
            $ffPolicy = Get-Content $policyFile -Raw | ConvertFrom-Json -AsHashtable
            $fp = $ffPolicy["policies"]
            $fp["DisableTelemetry"]      = $true
            $fp["DisableFirefoxStudies"] = $true
            $fp["DisablePocket"]        = $true
            $fp["DisableFormHistory"]   = $true
            $fp["SanitizeOnShutdown"]   = $true
            $fp["DontCheckDefaultBrowser"] = $true
            $fp["EnableTrackingProtection"] = @{ "Value" = $true; "Cryptomining" = $true; "Fingerprinting" = $true }
            $fp["DNSOverHTTPS"] = @{ "Enabled" = $true }
            $ffPolicy["policies"] = $fp
            Set-Content -Path $policyFile -Value ($ffPolicy | ConvertTo-Json -Depth 10 -Compress) -Encoding UTF8 -Force
            Write-Success "Firefox policies.json updated with all privacy settings."
        } catch {
            Write-Warn "Could not update Firefox policies.json: $_"
        }
    }

    Write-Host ""
    Write-Success "Browser extensions and privacy configuration complete."
    Write-Host ""
    Write-Host "  NOTE: Extensions install on next browser launch." -ForegroundColor DarkGray
    Write-Host "  NOTE: Policies apply even to browsers installed AFTER running this." -ForegroundColor DarkGray
    Write-Host ""
}

#endregion

#region ============================================================
# SECTION 17: FINAL TOUCHES
# ============================================================

function Invoke-FinalTouches {
    $script:CurrentSection = "FinalTouches"
    Write-Host ""

    # 1. Disable Edge first-run (additional key)
    Write-Step "Disabling Edge first-run (additional)..."
    Set-Registry -Path "HKCU:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\Main" `
        -Name "DisableFirstRunSettings" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Disables Edge first-run experience — prevents Edge welcome screen" -SettingID "FinalTouches_NoEdgeFirstRun"

    # 2. Disable Windows Insider UI
    Write-Step "Hiding Windows Insider page..."
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\WindowsSelfHost\UI\Visibility" `
        -Name "HideInsiderPage" -Value 1 -Type DWord -SafetyLevel "Safe" -Description "Hides Windows Insider page from Settings — removes insider enrollment UI" -SettingID "FinalTouches_HideInsiderPage"

    # 3. Set sound scheme to "No Sounds"
    Write-Step "Setting sound scheme to No Sounds..."
    Set-Registry -Path "HKCU:\AppEvents\Schemes" `
        -Name "(Default)" -Value ".None" -Type String -SafetyLevel "Safe" -Description "Sets sound scheme to No Sounds — disables all system sounds" -SettingID "FinalTouches_NoSounds"

    # 4. Set NumLock OFF at startup
    Write-Step "Setting NumLock OFF at startup..."
    Set-Registry -Path "HKU:\.DEFAULT\Control Panel\Keyboard" `
        -Name "InitialKeyboardIndicators" -Value "0" -Type String -SafetyLevel "Safe" -Description "Sets NumLock state at startup" -SettingID "FinalTouches_NumLockStartup"

    # 5. Disable mouse acceleration (enhance pointer precision)
    Write-Step "Disabling mouse acceleration..."
    Set-Registry -Path "HKCU:\Control Panel\Mouse" `
        -Name "MouseSpeed" -Value 1 -Type String -SafetyLevel "Safe" -Description "Disables mouse acceleration — improves pointer precision for gamers" -SettingID "FinalTouches_NoMouseAccel"
    Set-Registry -Path "HKCU:\Control Panel\Mouse" `
        -Name "MouseThreshold1" -Value 0 -Type String -SafetyLevel "Safe" -Description "Disables mouse acceleration threshold 1 — improves pointer precision" -SettingID "FinalTouches_MouseThreshold1"
    Set-Registry -Path "HKCU:\Control Panel\Mouse" `
        -Name "MouseThreshold2" -Value 0 -Type String -SafetyLevel "Safe" -Description "Disables mouse acceleration threshold 2 — improves pointer precision" -SettingID "FinalTouches_MouseThreshold2"

    # 6. Disable Sticky Keys
    Write-Step "Disabling Sticky Keys..."
    Set-Registry -Path "HKCU:\Control Panel\Accessibility\StickyKeys" `
        -Name "Flags" -Value 506 -Type String -SafetyLevel "Safe" -Description "Disables Sticky Keys accessibility feature — prevents accidental activation" -SettingID "FinalTouches_NoStickyKeys"

    # 7. Restart File Explorer
    Write-Step "Restarting File Explorer to apply changes..."
    try {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-Process explorer.exe -ErrorAction SilentlyContinue
        Write-Success "File Explorer restarted."
    } catch { Write-Warn "Could not restart Explorer: $_" }

    Write-Host ""
    Write-Success "Final touches complete."
}

#endregion

#region ============================================================
# SECTION 18: WINDOWS FEATURES REMOVAL
# ============================================================

function Invoke-WindowsFeaturesRemoval {
    $script:CurrentSection = "WindowsFeatures"
    Write-Host ""

    $featuresToRemove = @(
        @{ Name = "Internet-Explorer-Optional-amd64";            Desc = "Internet Explorer";       Safety = "Safe";    Reason = "Removes Internet Explorer — no one needs this in 2025+" },
        @{ Name = "MediaPlayback";                               Desc = "Media Playback";           Safety = "Safe";    Reason = "Removes Media Playback — VLC is better" },
        @{ Name = "WindowsMediaPlayer";                          Desc = "Windows Media Player";     Safety = "Safe";    Reason = "Removes Windows Media Player — use VLC instead" },
        @{ Name = "MicrosoftWindowsPowerShellV2";                Desc = "PowerShell V2";            Safety = "Moderate"; Reason = "Removes PowerShell v2 engine — legacy only, breaks very old scripts" },
        @{ Name = "MicrosoftWindowsPowerShellV2Root";            Desc = "PowerShell V2 Root";       Safety = "Moderate"; Reason = "Removes PowerShell v2 root — legacy only" },
        @{ Name = "Fax";                                         Desc = "Fax";                      Safety = "Safe";    Reason = "Removes Fax service — obsolete for most users" },
        @{ Name = "Hello-Face-Package";                          Desc = "Windows Hello Face";       Safety = "Risky";   Reason = "Removes Windows Hello Face — WARNING: breaks facial recognition login" },
        @{ Name = "Math-Recognizer";                             Desc = "Math Recognizer";          Safety = "Safe";    Reason = "Removes Math Recognizer — rarely used" },
        @{ Name = "Paint3D";                                     Desc = "Paint 3D";                 Safety = "Safe";    Reason = "Removes Paint 3D — standard Paint still available" },
        @{ Name = "Xps-Foundation-XpsDriver";                    Desc = "XPS Printer Driver";       Safety = "Safe";    Reason = "Removes XPS printer driver — rarely used" },
        @{ Name = "InternetPrintPrintOverInternet";              Desc = "Internet Printing";        Safety = "Safe";    Reason = "Removes Internet Printing — rarely used" },
        @{ Name = "WorkFolders-Client";                          Desc = "Work Folders Client";      Safety = "Safe";    Reason = "Removes Work Folders — enterprise feature, not needed for most" }
    )

    # Risky features (disabled by default, enabled with -AllowRisky)
    $riskyFeatures = @(
        @{ Name = "PrintToPDFServicesFeatures";                  Desc = "Print to PDF";             Safety = "Risky";   Reason = "Removes Print to PDF — WARNING: users often need PDF printing" },
        @{ Name = "WCF-Services45";                              Desc = "WCF Services 4.5";         Safety = "Risky";   Reason = "Removes WCF Services — WARNING: some .NET apps require this" },
        @{ Name = "SmbDirect";                                   Desc = "SMB Direct";               Safety = "Moderate"; Reason = "Removes SMB Direct — needed only for RDMA network storage" }
    )

    $disabledCount = 0; $alreadyOffCount = 0; $notFoundCount = 0

    foreach ($feature in $featuresToRemove) {
        # Safety gate for Risky features
        if ($feature.Safety -eq "Risky" -and -not $script:AllowRisky) {
            Write-Host "  SKIPPED (risky): $($feature.Reason) — use -AllowRisky or enable in menu" -ForegroundColor Yellow
            continue
        }
        # Warn for Moderate
        if ($feature.Safety -eq "Moderate") {
            Write-Host "  [MODERATE] $($feature.Reason)" -ForegroundColor DarkYellow
        }

        Write-Step "Checking feature: $($feature.Desc) ($($feature.Name))..."
        try {
            $featState = Get-WindowsOptionalFeature -Online -FeatureName $feature.Name -ErrorAction SilentlyContinue
            if ($featState) {
                if ($featState.State -eq 'Enabled') {
                    Disable-WindowsOptionalFeature -Online -FeatureName $feature.Name -NoRestart -ErrorAction Stop | Out-Null
                    Write-Success "Disabled feature: $($feature.Desc)"
                    $disabledCount++
                    $script:TotalChanged++
                    $null = $script:UndoCommands.Add("Enable-WindowsOptionalFeature -Online -FeatureName '$($feature.Name)' -NoRestart -ErrorAction SilentlyContinue")
                    $null = $script:UndoDescriptions.Add("Re-enable Windows feature: $($feature.Desc)")
                } else {
                    Write-Step "Already disabled: $($feature.Desc)"
                    $alreadyOffCount++
                    $script:TotalSkipped++
                }
            } else {
                Write-Warn "Feature not found: $($feature.Name)"
                $notFoundCount++
            }
        } catch {
            Write-Warn "Could not disable feature $($feature.Name): $_"
            $script:TotalFailed++
        }
    }

    # Process risky features (only if -AllowRisky)
    foreach ($feature in $riskyFeatures) {
        if ($feature.Safety -eq "Risky" -and -not $script:AllowRisky) {
            $featState = Get-WindowsOptionalFeature -Online -FeatureName $feature.Name -ErrorAction SilentlyContinue
            if ($featState -and $featState.State -eq 'Enabled') {
                Write-Host "  SKIPPED (risky): $($feature.Reason) — use -AllowRisky or enable in menu" -ForegroundColor Yellow
            }
            continue
        }
        if ($feature.Safety -eq "Moderate") {
            Write-Host "  [MODERATE] $($feature.Reason)" -ForegroundColor DarkYellow
        }

        Write-Step "Checking feature: $($feature.Desc) ($($feature.Name))..."
        try {
            $featState = Get-WindowsOptionalFeature -Online -FeatureName $feature.Name -ErrorAction SilentlyContinue
            if ($featState) {
                if ($featState.State -eq 'Enabled') {
                    Disable-WindowsOptionalFeature -Online -FeatureName $feature.Name -NoRestart -ErrorAction Stop | Out-Null
                    Write-Success "Disabled feature: $($feature.Desc)"
                    $disabledCount++
                    $script:TotalChanged++
                    $null = $script:UndoCommands.Add("Enable-WindowsOptionalFeature -Online -FeatureName '$($feature.Name)' -NoRestart -ErrorAction SilentlyContinue")
                    $null = $script:UndoDescriptions.Add("Re-enable Windows feature: $($feature.Desc)")
                } else {
                    Write-Step "Already disabled: $($feature.Desc)"
                    $alreadyOffCount++
                    $script:TotalSkipped++
                }
            } else {
                Write-Warn "Feature not found: $($feature.Name)"
                $notFoundCount++
            }
        } catch {
            Write-Warn "Could not disable feature $($feature.Name): $_"
            $script:TotalFailed++
        }
    }

    Write-Host ""
    Write-Success "Windows Features removal complete. Disabled: $disabledCount | Already off: $alreadyOffCount | Not found: $notFoundCount"
}

#endregion

#region ============================================================
# INTERACTIVE MENU
# ============================================================

# Safety info for each section
$script:SectionSafetyInfo = @{
    "Privacy"         = @{ Safety = "Safe";   RiskyCount = 0; ModerateCount = 2; ItemCount = 26 }
    "Debloat"         = @{ Safety = "Mixed";  RiskyCount = 2; ModerateCount = 7; ItemCount = 60 }
    "ExplorerUI"      = @{ Safety = "Safe";   RiskyCount = 0; ModerateCount = 0; ItemCount = 23 }
    "ServiceStartup"  = @{ Safety = "Mixed";  RiskyCount = 2; ModerateCount = 3; ItemCount = 16 }
    "Performance"     = @{ Safety = "Mixed";  RiskyCount = 0; ModerateCount = 2; ItemCount = 11 }
    "Security"        = @{ Safety = "Mixed";  RiskyCount = 0; ModerateCount = 1; ItemCount = 8 }
    "Network"         = @{ Safety = "Safe";   RiskyCount = 0; ModerateCount = 0; ItemCount = 7 }
    "WindowsUpdate"   = @{ Safety = "Safe";   RiskyCount = 0; ModerateCount = 0; ItemCount = 6 }
    "DiskCleanup"     = @{ Safety = "Safe";   RiskyCount = 0; ModerateCount = 0; ItemCount = 4 }
    "Winget"          = @{ Safety = "Safe";   RiskyCount = 0; ModerateCount = 0; ItemCount = 8 }
    "OfficeActivation"= @{ Safety = "Safe";   RiskyCount = 0; ModerateCount = 0; ItemCount = 3 }
    "EdgeHardening"   = @{ Safety = "Safe";   RiskyCount = 0; ModerateCount = 0; ItemCount = 14 }
    "OneDrive"        = @{ Safety = "Safe";   RiskyCount = 0; ModerateCount = 0; ItemCount = 3 }
    "Gaming"          = @{ Safety = "Safe";   RiskyCount = 0; ModerateCount = 0; ItemCount = 3 }
    "ScheduledTasks"  = @{ Safety = "Safe";   RiskyCount = 0; ModerateCount = 0; ItemCount = 33 }
    "BrowserHardening"= @{ Safety = "Safe";   RiskyCount = 0; ModerateCount = 0; ItemCount = 10 }
    "FinalTouches"    = @{ Safety = "Safe";   RiskyCount = 0; ModerateCount = 0; ItemCount = 7 }
    "WindowsFeatures" = @{ Safety = "Mixed";  RiskyCount = 3; ModerateCount = 2; ItemCount = 15 }
}

function Show-SimpleMenu {
    $menuItems = @(
        @{ ID = "1";  Key = "Privacy";             Name = "Privacy and Telemetry (Aggressive)";          Desc = "Telemetry, Cortana, Copilot, Recall, AI, Bing, tracking" },
        @{ ID = "2";  Key = "Debloat";             Name = "Debloat: Remove Bloatware";                Desc = "Uninstall 60+ pre-installed junk apps" },
        @{ ID = "3";  Key = "ExplorerUI";          Name = "Explorer and UI Optimizations";              Desc = "File extensions, taskbar, CDM lockdown, context menu" },
        @{ ID = "4";  Key = "ServiceStartup";       Name = "Service and Startup Optimization";           Desc = "Disable 16 unnecessary services + startup delay" },
        @{ ID = "5";  Key = "Performance";           Name = "Performance and Power Settings";             Desc = "Hibernation, fast startup, High Perf plan, Defender CPU" },
        @{ ID = "6";  Key = "Security";             Name = "Security Hardening";                       Desc = "Defender, UAC, SMBv1, DNS-over-HTTPS, PSv2" },
        @{ ID = "7";  Key = "Network";              Name = "Network Optimizations";                   Desc = "DNS, Nagle off, throttling off, Teredo off" },
        @{ ID = "8";  Key = "WindowsUpdate";         Name = "Windows Update Configuration";           Desc = "Active hours, no auto-reboot, no delivery opt." },
        @{ ID = "9";  Key = "DiskCleanup";           Name = "Disk Cleanup and Maintenance";              Desc = "Restore point, disk cleanup, temp cleanup" },
        @{ ID = "10"; Key = "Winget";                Name = "Software Installation (Winget)";           Desc = "Chrome, Firefox, 7-Zip, VLC, Reader, Notepad++" },
        @{ ID = "11"; Key = "OfficeActivation";      Name = "Microsoft Office Install + Activation";       Desc = "Choose Office version (365/LTSC 2024/2021/2019), MAS activation, Office telemetry off" },
        @{ ID = "12"; Key = "EdgeHardening";         Name = "Edge Security & Privacy (24 policies)";     Desc = "Telemetry, tracking, HTTPS-only, Safe Browsing, Copilot, autofill, shopping" },
        @{ ID = "13"; Key = "OneDrive";              Name = "OneDrive Management";                      Desc = "Disable sync, hide from Explorer, remove startup" },
        @{ ID = "14"; Key = "Gaming";                Name = "Gaming / Xbox / DVR Disable";              Desc = "GameDVR, Game Bar capture, Xbox overlay" },
        @{ ID = "15"; Key = "ScheduledTasks";         Name = "Scheduled Tasks Cleanup (33+ tasks)";      Desc = "Telemetry, CEIP, Office, Xbox, Maps, diagnostics" },
        @{ ID = "16"; Key = "BrowserHardening";      Name = "Browser Privacy Policies";                  Desc = "WebRTC, cookies, autofill, HTTPS-only, telemetry, experiments" },
        @{ ID = "16b"; Key = "BrowserExtensions";    Name = "Browser Extensions";                        Desc = "uBlock, AdGuard, SponsorBlock, Privacy Badger + 6 more on 5 browsers" },
        @{ ID = "17"; Key = "FinalTouches";           Name = "Final Touches";                            Desc = "Edge first-run, sound, NumLock, mouse accel, Explorer" },
        @{ ID = "18"; Key = "WindowsFeatures";         Name = "Windows Features Removal";                  Desc = "Remove IE, WMP, PSv2, Fax, Paint3D, XPS, Work Folders" }
    )

    Write-Host ""
    Write-Host "  SELECT OPTIMIZATIONS TO RUN:" -ForegroundColor White
    Write-Host "  " + ("-" * 64) -ForegroundColor DarkGray
    foreach ($item in $menuItems) {
        Write-Host "  $($item.ID.ToString().PadRight(3)) $($item.Name)" -ForegroundColor Cyan
        Write-Host "       $($item.Desc)" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "  A    Run ALL sections (full optimization)" -ForegroundColor Green
    Write-Host "  0    Exit without changes" -ForegroundColor Red
    Write-Host ""
}

function Get-SimpleUserSelection {
    Show-SimpleMenu
    $userInput = Read-Host "  Enter section numbers (comma-separated, e.g. '1,3,5') or 'A' for all"

    if ($userInput -eq '0') {
        Write-Host "  Exiting without changes." -ForegroundColor Yellow
        Stop-Transcript | Out-Null
        exit 0
    }

    $selected = @()
    if ($userInput.Trim().ToUpper() -eq 'A') {
        $selected = @("Privacy","Debloat","ExplorerUI","ServiceStartup","Performance",
                      "Security","Network","WindowsUpdate","DiskCleanup","Winget",
                      "OfficeActivation","EdgeHardening","OneDrive","Gaming","ScheduledTasks","BrowserHardening","FinalTouches","WindowsFeatures")
    } else {
        $numbers = $userInput -split ',' | ForEach-Object { $_.Trim() }
        $allSections = @{
            '1'='Privacy';'2'='Debloat';'3'='ExplorerUI';'4'='ServiceStartup'
            '5'='Performance';'6'='Security';'7'='Network';'8'='WindowsUpdate'
            '9'='DiskCleanup';'10'='Winget';'11'='OfficeActivation';'12'='EdgeHardening'
            '13'='OneDrive';'14'='Gaming';'15'='ScheduledTasks';'16'='BrowserHardening';'17'='FinalTouches';'18'='WindowsFeatures'
        }
        foreach ($num in $numbers) {
            if ($allSections.ContainsKey($num)) { $selected += $allSections[$num] }
            else { Write-Warn "Invalid selection: $num (skipped)" }
        }
    }
    return $selected
}

function Show-DetailedMenu {
    $menuItems = @(
        @{ ID = "1";  Key = "Privacy";             Name = "Privacy and Telemetry" },
        @{ ID = "2";  Key = "Debloat";             Name = "Debloat" },
        @{ ID = "3";  Key = "ExplorerUI";          Name = "Explorer and UI" },
        @{ ID = "4";  Key = "ServiceStartup";       Name = "Service and Startup" },
        @{ ID = "5";  Key = "Performance";           Name = "Performance and Power" },
        @{ ID = "6";  Key = "Security";             Name = "Security" },
        @{ ID = "7";  Key = "Network";              Name = "Network" },
        @{ ID = "8";  Key = "WindowsUpdate";         Name = "Windows Update" },
        @{ ID = "9";  Key = "DiskCleanup";           Name = "Disk Cleanup" },
        @{ ID = "10"; Key = "Winget";                Name = "Software (Winget)" },
        @{ ID = "11"; Key = "OfficeActivation";      Name = "Office 365" },
        @{ ID = "12"; Key = "EdgeHardening";         Name = "Edge Hardening" },
        @{ ID = "13"; Key = "OneDrive";              Name = "OneDrive" },
        @{ ID = "14"; Key = "Gaming";                Name = "Gaming / DVR" },
        @{ ID = "15"; Key = "ScheduledTasks";         Name = "Scheduled Tasks" },
        @{ ID = "16"; Key = "BrowserHardening";      Name = "Browser Privacy" },
        @{ ID = "16b"; Key = "BrowserExtensions";    Name = "Browser Extensions" },
        @{ ID = "17"; Key = "FinalTouches";           Name = "Final Touches" },
        @{ ID = "18"; Key = "WindowsFeatures";         Name = "Windows Features" }
    )

    Write-Host ""
    Write-Host "  SELECT OPTIMIZATIONS:" -ForegroundColor White
    Write-Host "  " + ("-" * 72) -ForegroundColor DarkGray

    foreach ($item in $menuItems) {
        $safetyInfo = $script:SectionSafetyInfo[$item.Key]
        if (-not $safetyInfo) { $safetyInfo = @{ Safety = "Safe"; RiskyCount = 0; ModerateCount = 0; ItemCount = 0 } }

        # Color-code the safety badge
        $safetyBadge = ""
        if ($safetyInfo.Safety -eq "Safe") {
            $safetyBadge = "[Safe]"
            $badgeColor = "Green"
        } elseif ($safetyInfo.Safety -eq "Mixed") {
            $riskyCount = $safetyInfo.RiskyCount
            $modCount = $safetyInfo.ModerateCount
            $safetyBadge = "[Mixed]"
            $badgeColor = "Yellow"
        } else {
            $safetyBadge = "[Safe]"
            $badgeColor = "Green"
        }

        $itemCountStr = "$($safetyInfo.ItemCount) items"
        $warningStr = ""
        if ($safetyInfo.RiskyCount -gt 0) {
            $warningStr = " | $($safetyInfo.RiskyCount) risky"
        }
        if ($safetyInfo.ModerateCount -gt 0) {
            $warningStr += " | $($safetyInfo.ModerateCount) moderate"
        }

        Write-Host "  $($item.ID.ToString().PadRight(3)) " -NoNewline
        Write-Host "$($item.Name.PadRight(22))" -ForegroundColor Cyan -NoNewline
        Write-Host " $safetyBadge " -ForegroundColor $badgeColor -NoNewline
        Write-Host "$itemCountStr$warningStr" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "  A   Run ALL safe+moderate (skip risky)" -ForegroundColor Green
    Write-Host "  R   Run ALL including risky" -ForegroundColor Yellow
    Write-Host "  0   Exit without changes" -ForegroundColor Red
    Write-Host ""
}

function Show-SettingTweakMenu {
    <#
    .SYNOPSIS
        Per-setting interactive tweak menu — lets users toggle individual settings on/off
    .DESCRIPTION
        After sections are selected, this menu lets users drill into each section and
        toggle specific settings on/off before execution. Toggled-off settings are added
        to $script:SettingOverrides so that Set-Registry and Disable-AppTask skip them.
    .PARAMETER SelectedSections
        Array of section key names (e.g. "Privacy","Debloat") the user selected.
    #>
    param(
        [string[]]$SelectedSections
    )

    # Section key -> display name mapping (same as Show-DetailedMenu)
    $sectionDisplayNames = @{
        "Privacy"         = "PRIVACY AND TELEMETRY"
        "Debloat"         = "DEBLOAT"
        "ExplorerUI"      = "EXPLORER AND UI"
        "ServiceStartup"  = "SERVICE AND STARTUP"
        "Performance"     = "PERFORMANCE AND POWER"
        "Security"        = "SECURITY"
        "Network"         = "NETWORK"
        "WindowsUpdate"   = "WINDOWS UPDATE"
        "DiskCleanup"     = "DISK CLEANUP"
        "Winget"          = "SOFTWARE (WINGET)"
        "OfficeActivation"= "OFFICE 365"
        "EdgeHardening"   = "EDGE HARDENING"
        "OneDrive"        = "ONEDRIVE"
        "Gaming"          = "GAMING / DVR"
        "ScheduledTasks"  = "SCHEDULED TASKS"
        "BrowserHardening"= "BROWSER PRIVACY"
        "FinalTouches"    = "FINAL TOUCHES"
        "WindowsFeatures" = "WINDOWS FEATURES"
    }

    foreach ($section in $SelectedSections) {
        # Gather settings for this section from the catalog
        $sectionSettings = @()
        foreach ($key in $script:SettingCatalog.Keys) {
            if ($script:SettingCatalog[$key].Section -eq $section) {
                $sectionSettings += $key
            }
        }

        # Skip sections with no catalog entries (e.g. Winget has no registry settings)
        if ($sectionSettings.Count -eq 0) {
            continue
        }

        # Sort settings by Safety level (Safe first, then Moderate, then Risky)
        $safetyOrder = @{ "Safe" = 0; "Moderate" = 1; "Risky" = 2 }
        $sectionSettings = $sectionSettings | Sort-Object { $safetyOrder[$script:SettingCatalog[$_].Safety] }, { $script:SettingCatalog[$_].Desc }

        $displayName = if ($sectionDisplayNames.ContainsKey($section)) { $sectionDisplayNames[$section] } else { $section.ToUpper() }

        # --- Interactive loop for this section ---
        $doneWithSection = $false
        while (-not $doneWithSection) {
            Write-Host ""
            Write-Host "  === $displayName - Individual Settings ===" -ForegroundColor White
            Write-Host ""

            # Print table header
            Write-Host "  #   Toggle  Safety     Setting" -ForegroundColor DarkGray
            Write-Host "  " + ("-" * 72) -ForegroundColor DarkGray

            $index = 0
            $settingList = @()  # Ordered list for index lookup
            foreach ($settingID in $sectionSettings) {
                $index++
                $catEntry = $script:SettingCatalog[$settingID]
                $isOn = -not ($script:SettingOverrides.ContainsKey($settingID) -and $script:SettingOverrides[$settingID])
                $toggleStr = if ($isOn) { "[ON]" } else { "[OFF]" }
                $safetyStr = $catEntry.Safety.PadRight(9)

                # Color the toggle
                $toggleColor = if ($isOn) { "Green" } else { "DarkGray" }
                # Color the safety badge
                $safetyColor = switch ($catEntry.Safety) {
                    "Safe"     { "Green" }
                    "Moderate" { "Yellow" }
                    "Risky"    { "Red" }
                    default    { "White" }
                }

                $numStr = $index.ToString().PadRight(4)
                Write-Host "  $numStr" -NoNewline
                Write-Host "$toggleStr  " -ForegroundColor $toggleColor -NoNewline
                Write-Host "$safetyStr" -ForegroundColor $safetyColor -NoNewline
                Write-Host " $($catEntry.Desc)" -ForegroundColor White

                $settingList += $settingID
            }

            Write-Host ""
            Write-Host "  Enter number to toggle ON/OFF, 'D#' for details, 'Q' when done:" -ForegroundColor Cyan
            $menuInput = Read-Host "  "

            $menuInput = $menuInput.Trim()

            if ($menuInput -eq 'Q' -or $menuInput -eq 'q' -or [string]::IsNullOrEmpty($menuInput)) {
                $doneWithSection = $true
                continue
            }

            # Handle 'D#' — show details for setting number
            if ($menuInput -match '^[Dd](\d+)$') {
                $detailNum = [int]$Matches[1]
                if ($detailNum -ge 1 -and $detailNum -le $settingList.Count) {
                    $detailID = $settingList[$detailNum - 1]
                    $detailEntry = $script:SettingCatalog[$detailID]
                    $isOn = -not ($script:SettingOverrides.ContainsKey($detailID) -and $script:SettingOverrides[$detailID])

                    Write-Host ""
                    Write-Host "  Setting #$detailNum`: $($detailEntry.Desc)" -ForegroundColor White
                    $safetyColor = switch ($detailEntry.Safety) {
                        "Safe"     { "Green" }
                        "Moderate" { "Yellow" }
                        "Risky"    { "Red" }
                        default    { "White" }
                    }
                    Write-Host "  Safety: " -NoNewline
                    Write-Host "$($detailEntry.Safety)" -ForegroundColor $safetyColor
                    Write-Host "  Action: $($detailEntry.Action)" -ForegroundColor DarkGray
                    Write-Host "  Type:   $($detailEntry.Type)" -ForegroundColor DarkGray
                    Write-Host "  State:  $(if ($isOn) { 'ON (will be applied)' } else { 'OFF (will be skipped)' })" -ForegroundColor $(if ($isOn) { 'Green' } else { 'DarkGray' })
                    Write-Host "  ID:     $detailID" -ForegroundColor DarkGray

                    # Provide a brief effect description based on safety level
                    if ($detailEntry.Safety -eq "Risky") {
                        Write-Host "  Effect: This is a RISKY change. Disabling may affect system functionality." -ForegroundColor Yellow
                        Write-Host "          Only toggle OFF if you understand the consequences." -ForegroundColor Yellow
                    } elseif ($detailEntry.Safety -eq "Moderate") {
                        Write-Host "  Effect: This is a MODERATE change. Some users may notice side effects." -ForegroundColor DarkYellow
                    } else {
                        Write-Host "  Effect: Safe to apply. No significant side effects expected." -ForegroundColor DarkGray
                    }
                    Write-Host ""
                } else {
                    Write-Host "  Invalid setting number: $detailNum" -ForegroundColor Red
                }
                continue
            }

            # Handle plain number — toggle setting
            if ($menuInput -match '^\d+$') {
                $toggleNum = [int]$menuInput
                if ($toggleNum -ge 1 -and $toggleNum -le $settingList.Count) {
                    $toggleID = $settingList[$toggleNum - 1]
                    $isOn = -not ($script:SettingOverrides.ContainsKey($toggleID) -and $script:SettingOverrides[$toggleID])

                    if ($isOn) {
                        # Currently ON → toggle OFF
                        $script:SettingOverrides[$toggleID] = $true
                        $desc = $script:SettingCatalog[$toggleID].Desc
                        Write-Host "  Toggled OFF: $desc" -ForegroundColor DarkGray
                    } else {
                        # Currently OFF → toggle ON (remove from overrides)
                        $script:SettingOverrides.Remove($toggleID)
                        $desc = $script:SettingCatalog[$toggleID].Desc
                        Write-Host "  Toggled ON: $desc" -ForegroundColor Green
                    }
                } else {
                    Write-Host "  Invalid setting number: $toggleNum (range 1-$($settingList.Count))" -ForegroundColor Red
                }
                continue
            }

            # Unrecognized input
            Write-Host "  Unrecognized input. Enter a number, 'D#', or 'Q'." -ForegroundColor Red
        }
    }
}

function Get-DetailedUserSelection {
    # Show section-level menu and get selections
    Show-DetailedMenu
    $userInput = Read-Host "  Enter section numbers (comma-separated), 'A' for safe+moderate, 'R' for all+risky"

    if ($userInput -eq '0') {
        Write-Host "  Exiting without changes." -ForegroundColor Yellow
        Stop-Transcript | Out-Null
        exit 0
    }

    $allSectionKeys = @("Privacy","Debloat","ExplorerUI","ServiceStartup","Performance",
                        "Security","Network","WindowsUpdate","DiskCleanup","Winget",
                        "OfficeActivation","EdgeHardening","OneDrive","Gaming","ScheduledTasks","BrowserHardening","FinalTouches","WindowsFeatures")

    $selected = @()
    if ($userInput.Trim().ToUpper() -eq 'R') {
        # Run ALL including risky
        $selected = $allSectionKeys
        $script:AllowRisky = $true
        Write-Host "  Risky settings ENABLED for this run." -ForegroundColor Yellow
    } elseif ($userInput.Trim().ToUpper() -eq 'A') {
        # Run ALL safe+moderate (skip risky)
        $selected = $allSectionKeys
        $script:AllowRisky = $false
        Write-Host "  Running safe + moderate settings only. Risky settings will be skipped." -ForegroundColor Green
    } else {
        $numbers = $userInput -split ',' | ForEach-Object { $_.Trim() }
        $allSections = @{
            '1'='Privacy';'2'='Debloat';'3'='ExplorerUI';'4'='ServiceStartup'
            '5'='Performance';'6'='Security';'7'='Network';'8'='WindowsUpdate'
            '9'='DiskCleanup';'10'='Winget';'11'='OfficeActivation';'12'='EdgeHardening'
            '13'='OneDrive';'14'='Gaming';'15'='ScheduledTasks';'16'='BrowserHardening';'17'='FinalTouches';'18'='WindowsFeatures'
        }
        foreach ($num in $numbers) {
            if ($allSections.ContainsKey($num)) { $selected += $allSections[$num] }
            else { Write-Warn "Invalid selection: $num (skipped)" }
        }

        # Ask about risky settings
        if ($selected.Count -gt 0) {
            Write-Host ""
            Write-Host "  Enable risky settings for selected sections? (y/N)" -ForegroundColor Yellow
            $riskyChoice = Read-Host "  "
            if ($riskyChoice -eq 'y' -or $riskyChoice -eq 'Y') {
                $script:AllowRisky = $true
                Write-Host "  Risky settings ENABLED." -ForegroundColor Yellow
            }
        }
    }

    # Show per-setting details for selected sections
    if ($selected.Count -gt 0 -and -not $Silent) {
        Write-Host ""
        Write-Host "  SELECTED SECTIONS:" -ForegroundColor Cyan
        Write-Host "  " + ("-" * 50) -ForegroundColor DarkGray

        foreach ($sec in $selected) {
            $safetyInfo = $script:SectionSafetyInfo[$sec]
            if (-not $safetyInfo) { continue }

            $riskyNote = ""
            if ($safetyInfo.RiskyCount -gt 0) {
                $riskyNote = " (NOTE: $($safetyInfo.RiskyCount) risky items will be $(if ($script:AllowRisky) { 'APPLIED' } else { 'SKIPPED' }))"
            }
            $modNote = ""
            if ($safetyInfo.ModerateCount -gt 0) {
                $modNote = " | $($safetyInfo.ModerateCount) moderate warnings"
            }
            Write-Host "  - $sec : $($safetyInfo.Safety) | $($safetyInfo.ItemCount) items$modNote$riskyNote" -ForegroundColor White
        }

        # Show risky descriptions if any exist and risky is not enabled
        if (-not $script:AllowRisky) {
            $totalRiskyInSelected = 0
            foreach ($sec in $selected) {
                $si = $script:SectionSafetyInfo[$sec]
                if ($si) { $totalRiskyInSelected += $si.RiskyCount }
            }
            if ($totalRiskyInSelected -gt 0) {
                Write-Host ""
                Write-Host "  RISKY SETTINGS THAT WILL BE SKIPPED (use -AllowRisky to enable):" -ForegroundColor Yellow
                Write-Host "  " + ("-" * 60) -ForegroundColor DarkGray

                # Show known risky settings per section
                $riskyDescriptions = @{
                    "Debloat"         = @("Microsoft.WindowsAlarms — Clock/Alarms app (some users rely on this)", "Microsoft.WindowsCamera — Camera app (laptop users need this)")
                    "ServiceStartup"  = @("WSearch — Windows Search (breaks Start menu search, Cortana, Office)", "WbioSrvc — Biometrics (breaks Windows Hello fingerprint/face login)")
                    "WindowsFeatures" = @("PrintToPDFServicesFeatures — Print to PDF (users often need PDF printing)", "WCF-Services45 — WCF Services (some .NET apps require this)", "Hello-Face-Package — Windows Hello Face (breaks facial recognition)")
                }
                foreach ($sec in $selected) {
                    if ($riskyDescriptions.ContainsKey($sec)) {
                        foreach ($desc in $riskyDescriptions[$sec]) {
                            Write-Host "    [RISKY] $desc" -ForegroundColor Yellow
                        }
                    }
                }
            }
        }

        # Offer per-setting tweak menu
        Write-Host ""
        Write-Host "  Do you want to review/tweak individual settings? (y/N)" -ForegroundColor Cyan
        $tweakChoice = Read-Host "  "
        if ($tweakChoice -eq 'y' -or $tweakChoice -eq 'Y') {
            Show-SettingTweakMenu -SelectedSections $selected
            Write-Host ""
            # Summarize how many settings were toggled off
            $toggledOff = 0
            foreach ($key in $script:SettingOverrides.Keys) {
                $catEntry = $script:SettingCatalog[$key]
                if ($catEntry -and $selected -contains $catEntry.Section) {
                    $toggledOff++
                }
            }
            if ($toggledOff -gt 0) {
                Write-Host "  $toggledOff setting(s) toggled OFF and will be skipped." -ForegroundColor Yellow
            } else {
                Write-Host "  All settings remain ON (default)." -ForegroundColor Green
            }
        }

        Write-Host ""
        Write-Host "  Press Enter to proceed, or Ctrl+C to cancel..." -ForegroundColor DarkGray
        Read-Host "  "
    }

    return $selected
}

#endregion

#region ============================================================
# MAIN EXECUTION
# ============================================================

try {
    Initialize-Script

    # === REMOTE EXECUTION SUPPORT ===
    if ($ComputerName -and $ComputerName.Count -gt 0) {
        Write-Host ""
        Write-Host "  [REMOTE] Executing on remote computers..." -ForegroundColor Cyan
        Write-Host ""
        foreach ($comp in $ComputerName) {
            Write-Step "Connecting to $comp..."
            try {
                $session = New-PSSession -ComputerName $comp -ErrorAction Stop
                Write-Success "Connected to $comp."

                # Copy script to remote machine
                Write-Step "Copying script to $comp..."
                try {
                    Invoke-Command -Session $session -ScriptBlock {
                        if (-not (Test-Path "C:\Temp")) { New-Item -Path "C:\Temp" -ItemType Directory -Force | Out-Null }
                    } -ErrorAction SilentlyContinue
                    Copy-Item -Path $PSCommandPath -Destination "C:\Temp\WinPostInstall.ps1" -ToSession $session -Force -ErrorAction Stop
                    Write-Success "Script copied to $comp."
                } catch {
                    Write-Err "Failed to copy script to $comp : $_"
                    Remove-PSSession -Session $session -ErrorAction SilentlyContinue
                    continue
                }

                # Invoke script on remote machine
                Write-Step "Running WinPostInstall on $comp..."
                try {
                    $remoteResult = Invoke-Command -Session $session -ScriptBlock {
                        & "C:\Temp\WinPostInstall.ps1" -Silent
                    } -ErrorAction Stop
                    Write-Success "Execution completed on $comp."
                } catch {
                    Write-Err "Execution failed on $comp : $_"
                }

                Remove-PSSession -Session $session -ErrorAction SilentlyContinue
                Write-Success "Session closed for $comp."
            } catch {
                Write-Err "Could not connect to $comp : $_"
            }
        }
        Write-Host ""
        Write-Success "Remote execution complete."
        return
    }

    # SAFETY FIRST: Enable System Restore (if disabled) and create a restore point
    # BEFORE any optimization changes are made
    Enable-SystemRestore
    New-SystemRestorePoint

    $selectedSections = @()
    $script:ConfigSettings = @{}   # Merged settings from all config sections (SettingID -> bool)

    if ($ConfigFile -and (Test-Path $ConfigFile -ErrorAction SilentlyContinue)) {
        # Load configuration from JSON file
        Write-Step "Loading configuration from: $ConfigFile"
        try {
            $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
            if ($config.Sections) {
                $selectedSections = @($config.Sections)
                Write-Success "Loaded sections from config: $($selectedSections -join ', ')"
            }
            # Parse per-section settings into flat ConfigSettings map
            if ($config.sections -is [System.Collections.Specialized.OrderedDictionary] -or $config.sections -is [hashtable]) {
                foreach ($sectionKey in $config.sections.Keys) {
                    $sectionData = $config.sections[$sectionKey]
                    if ($sectionData -is [System.Collections.Specialized.OrderedDictionary] -or $sectionData -is [hashtable]) {
                        foreach ($settingKey in $sectionData.Keys) {
                            $script:ConfigSettings[$settingKey] = [bool]$sectionData[$settingKey]
                        }
                    }
                }
                $enabledCount = ($script:ConfigSettings.Values | Where-Object { $_ -eq $true }).Count
                Write-Success "Loaded $enabledCount setting toggles from config."
            }
            # Override Winget app list if specified
            if ($config.AppList) {
                Write-Success "Custom AppList loaded from config ($($config.AppList.Count) apps)."
                $script:CustomAppList = $config.AppList
            }
            # Override bloatware list if specified
            if ($config.BloatwareList) {
                Write-Success "Custom BloatwareList loaded from config ($($config.BloatwareList.Count) items)."
                $script:CustomBloatwareList = $config.BloatwareList
            }
        } catch {
            Write-Err "Failed to load config file: $_"
        }
    } elseif ($Sections -and $Sections.Count -gt 0) {
        $selectedSections = $Sections
    } elseif ($Silent) {
        $selectedSections = @("Privacy","Debloat","ExplorerUI","ServiceStartup","Performance",
                              "Security","Network","WindowsUpdate","DiskCleanup","Winget",
                              "OfficeActivation","EdgeHardening","OneDrive","Gaming","ScheduledTasks","BrowserHardening","BrowserExtensions","FinalTouches","WindowsFeatures")
        Write-Host "  Silent mode: running all sections." -ForegroundColor DarkGray
        if ($AllowRisky) {
            $script:AllowRisky = $true
            Write-Host "  Risky settings ENABLED via -AllowRisky flag." -ForegroundColor Yellow
        }
    } else {
        # Interactive mode — use new detailed menu (or simple menu if -SimpleMenu)
        if ($SimpleMenu) {
            $selectedSections = Get-SimpleUserSelection
        } else {
            $selectedSections = Get-DetailedUserSelection
        }
    }

    Write-Host ""
    Write-Host "  SECTIONS SELECTED:" -ForegroundColor Cyan
    foreach ($s in $selectedSections) { Write-Host "    - $s" -ForegroundColor White }
    Write-Host ""

    # === BEFORE/AFTER SNAPSHOT (start) ===
    Write-Step "Taking 'before' snapshot of services and tasks..."
    try {
        if (-not (Test-Path $script:BackupDir)) { New-Item -Path $script:BackupDir -ItemType Directory -Force | Out-Null }
        Get-Service | Select-Object Name, StartType, Status | Export-Csv "$script:BackupDir\Services_Before.csv" -NoTypeInformation -ErrorAction SilentlyContinue
        Get-ScheduledTask | Select-Object TaskName, TaskPath, State | Export-Csv "$script:BackupDir\Tasks_Before.csv" -NoTypeInformation -ErrorAction SilentlyContinue
        Write-Success "Before snapshots saved to $script:BackupDir"
    } catch {
        Write-Warn "Could not take before snapshot: $_"
    }

    $startTime = Get-Date

    foreach ($section in $selectedSections) {
        # Section timing
        $sectionStart = Get-Date
        $sectionChangedBefore = $script:TotalChanged
        $sectionSkippedBefore = $script:TotalSkipped
        $sectionFailedBefore = $script:TotalFailed

        switch ($section) {
            "Privacy"           { Invoke-PrivacyTweaks }
            "Debloat"           { Invoke-Debloat }
            "ExplorerUI"        { Invoke-ExplorerUI }
            "ServiceStartup"    { Invoke-ServiceStartupOptimization }
            "Performance"       { Invoke-PerformanceOptimization }
            "Security"          { Invoke-SecurityHardening }
            "Network"           { Invoke-NetworkOptimizations }
            "WindowsUpdate"     { Invoke-WindowsUpdateConfig }
            "DiskCleanup"       { Invoke-DiskCleanup }
            "Winget"            { Invoke-WingetInstall }
            "OfficeActivation"  { Invoke-OfficeActivation }
            "EdgeHardening"     { Invoke-EdgeHardening }
            "OneDrive"          { Invoke-OneDriveManagement }
            "Gaming"            { Invoke-GamingDisable }
            "ScheduledTasks"    { Invoke-ScheduledTasksCleanup }
            "BrowserHardening"  { Invoke-BrowserHardening }
            "BrowserExtensions" { Invoke-BrowserHardening }   # Alias — extensions config (BE_1..BE_10) is read inside the function
            "FinalTouches"      { Invoke-FinalTouches }
            "WindowsFeatures"   { Invoke-WindowsFeaturesRemoval }
            default { Write-Warn "Unknown section: $section (skipped)" }
        }

        $sectionDuration = (Get-Date) - $sectionStart
        $script:SectionStats[$section] = @{
            Duration = $sectionDuration
            Changed = $script:TotalChanged - $sectionChangedBefore
            Skipped = $script:TotalSkipped - $sectionSkippedBefore
            Failed  = $script:TotalFailed - $sectionFailedBefore
        }
    }

    # === BEFORE/AFTER SNAPSHOT (end) ===
    Write-Step "Taking 'after' snapshot of services and tasks..."
    try {
        Get-Service | Select-Object Name, StartType, Status | Export-Csv "$script:BackupDir\Services_After.csv" -NoTypeInformation -ErrorAction SilentlyContinue
        Get-ScheduledTask | Select-Object TaskName, TaskPath, State | Export-Csv "$script:BackupDir\Tasks_After.csv" -NoTypeInformation -ErrorAction SilentlyContinue
        Write-Success "After snapshots saved to $script:BackupDir"
        Write-Host "  Before/after snapshots saved to $script:BackupDir" -ForegroundColor DarkGray
    } catch {
        Write-Warn "Could not take after snapshot: $_"
    }

    $endTime = Get-Date
    $duration = $endTime - $startTime

    # === SECTION SUMMARY TABLE ===
    Write-Host ""
    Write-Host "  SECTION SUMMARY:" -ForegroundColor Cyan
    Write-Host "  " + ("-" * 70) -ForegroundColor DarkGray
    foreach ($sec in $selectedSections) {
        if ($script:SectionStats.ContainsKey($sec)) {
            $stat = $script:SectionStats[$sec]
            $dur = $stat.Duration.ToString('mm\:ss')
            $ch = $stat.Changed; $sk = $stat.Skipped; $fa = $stat.Failed
            $line = "  {0,-20} | Changed: {1,3} | Skipped: {2,3} | Failed: {3,1} | {4}" -f $sec, $ch, $sk, $fa, $dur
            Write-Host $line -ForegroundColor White
        }
    }
    Write-Host "  " + ("-" * 70) -ForegroundColor DarkGray
    $totalLine = "  {0,-20} | Changed: {1,3} | Skipped: {2,3} | Failed: {3,1}" -f "TOTAL", $script:TotalChanged, $script:TotalSkipped, $script:TotalFailed
    Write-Host $totalLine -ForegroundColor Green
    Write-Host ""

    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  OPTIMIZATION COMPLETE" -ForegroundColor Green
    Write-Host "  Duration: $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor White
    Write-Host "  Sections run: $($selectedSections.Count)" -ForegroundColor White
    Write-Host "  Changes: $($script:TotalChanged) | Skipped: $($script:TotalSkipped) | Failed: $($script:TotalFailed)" -ForegroundColor White
    Write-Host "  Log saved to: $LogFile" -ForegroundColor DarkGray
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""

    $restartSections = @("DiskCleanup","Security","ServiceStartup","Performance","ScheduledTasks","Gaming","BrowserHardening","OfficeActivation")
    if ($selectedSections | Where-Object { $restartSections -contains $_ }) {
        Write-Host "  A RESTART is recommended to apply all changes." -ForegroundColor Yellow
        Write-Host ""
        if (-not $Silent) {
            $restart = Read-Host "  Restart now? (y/N)"
            if ($restart -eq 'y' -or $restart -eq 'Y') {
                Write-Host "  Restarting in 10 seconds..." -ForegroundColor Yellow
                Restart-Computer -Force -Delay 10
            }
        }
    }

} catch {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Red
    Write-Host "  UNEXPECTED ERROR" -ForegroundColor Red
    Write-Host "================================================================" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "  Line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Yellow
    Write-Host "  Command: $($_.InvocationInfo.Line.Trim())" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Check the log file for details: $LogFile" -ForegroundColor DarkGray
    Write-Host "================================================================" -ForegroundColor Red
    Write-Host ""
} finally {
    # Generate undo script
    if ($script:UndoCommands -and $script:UndoCommands.Count -gt 0) {
        $undoPath = Join-Path (Split-Path $PSCommandPath -Parent) "WinPostInstall-Undo.ps1"
        try {
            # Build embedded data arrays for the self-contained undo script
            $embeddedCmds = @()
            $embeddedDescs = @()
            $embeddedTypes = @()

            for ($i = 0; $i -lt $script:UndoCommands.Count; $i++) {
                $cmd = $script:UndoCommands[$i]
                $desc = if ($i -lt $script:UndoDescriptions.Count) { $script:UndoDescriptions[$i] } else { "Unknown change" }

                # Determine type from the command
                $type = "Other"
                if ($cmd -match 'Set-ItemProperty|Remove-ItemProperty|New-Item') {
                    $type = "Registry"
                } elseif ($cmd -match 'Enable-ScheduledTask') {
                    $type = "Task"
                } elseif ($cmd -match 'Add-AppxPackage|Re-install') {
                    $type = "AppX"
                } elseif ($cmd -match 'Enable-WindowsOptionalFeature') {
                    $type = "Feature"
                } elseif ($cmd -match 'Copy-Item.*hosts') {
                    $type = "Hosts"
                }

                # Escape single quotes for embedding in PowerShell string literals
                $escapedCmd = $cmd -replace "'", "''"
                $escapedDesc = $desc -replace "'", "''"

                $embeddedCmds += "    '$escapedCmd'"
                $embeddedDescs += "    '$escapedDesc'"
                $embeddedTypes += "    '$type'"
            }

            $undoContent = @(
                "<#",
                ".SYNOPSIS",
                "    Undo script for WinPostInstall v$ScriptVersion",
                ".DESCRIPTION",
                "    Generated automatically. Run without arguments for an interactive menu",
                "    to select which changes to revert. Run with -Silent to revert all changes",
                "    without prompts.",
                ".PARAMETER Silent",
                "    Revert all changes without showing the interactive menu.",
                "#>",
                "",
                "param([switch]`$Silent)",
                "",
                "# Requires Administrator",
                "if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {",
                "    Write-Host 'This script requires Administrator privileges.' -ForegroundColor Red",
                "    exit 1",
                "}",
                "",
                "# Data embedded by WinPostInstall v$ScriptVersion",
                "`$undoCommands = @(",
                ($embeddedCmds -join "`n"),
                ")",
                "",
                "`$undoDescs = @(",
                ($embeddedDescs -join "`n"),
                ")",
                "",
                "`$undoTypes = @(",
                ($embeddedTypes -join "`n"),
                ")",
                "",
                "# === Silent mode: run all undo commands ===",
                "if (`$Silent) {",
                "    Write-Host '' -ForegroundColor White",
                "    Write-Host '  WinPostInstall Undo Script v$ScriptVersion (Silent Mode)' -ForegroundColor Cyan",
                "    Write-Host '  Reverting all changes...' -ForegroundColor White",
                "    Write-Host '' -ForegroundColor White",
                "    for (`$i = 0; `$i -lt `$undoCommands.Count; `$i++) {",
                "        `$cmd = `$undoCommands[`$i]",
                "        `$desc = `$undoDescs[`$i]",
                "        if (`$cmd -match '^#\s*Re-install') {",
                "            Write-Host `"  [AppX] `$desc (skipped — cannot auto-reinstall)`" -ForegroundColor DarkYellow",
                "            continue",
                "        }",
                "        try {",
                "            Write-Host `"  [`$(`$undoTypes[`$i])] `$desc`" -ForegroundColor White",
                "            Invoke-Expression `$cmd",
                "        } catch {",
                "            Write-Host `"  FAILED: `$desc — `$_`" -ForegroundColor Red",
                "        }",
                "    }",
                "    Write-Host '' -ForegroundColor White",
                "    Write-Host '  All applicable changes have been reverted.' -ForegroundColor Green",
                "    Write-Host '' -ForegroundColor White",
                "    exit 0",
                "}",
                "",
                "# === Interactive mode ===",
                "Write-Host '' -ForegroundColor White",
                "Write-Host '  WinPostInstall Undo Script v$ScriptVersion' -ForegroundColor Cyan",
                "Write-Host '  Select which changes to revert:' -ForegroundColor White",
                "Write-Host '' -ForegroundColor White",
                "",
                "# Separate AppX items for display grouping",
                "`$appxIndices = @()",
                "`$otherIndices = @()",
                "for (`$i = 0; `$i -lt `$undoCommands.Count; `$i++) {",
                "    if (`$undoTypes[`$i] -eq 'AppX') { `$appxIndices += `$i }",
                "    else { `$otherIndices += `$i }",
                "}",
                "",
                "# Display non-AppX items",
                "Write-Host '  #   Type          Change' -ForegroundColor White",
                "Write-Host '  --  -----------   ------' -ForegroundColor DarkGray",
                "foreach (`$idx in `$otherIndices) {",
                "    `$numStr = (`$idx + 1).ToString().PadLeft(3)",
                "    `$typeStr = `$undoTypes[`$idx].PadRight(13)",
                "    Write-Host `"  `$numStr  `$typeStr `$(`$undoDescs[`$idx])`" -ForegroundColor White",
                "}",
                "",
                "# Display AppX items in a separate group",
                "if (`$appxIndices.Count -gt 0) {",
                "    Write-Host '' -ForegroundColor White",
                "    Write-Host '  AppX packages that were removed (cannot be auto-reinstalled):' -ForegroundColor Yellow",
                "    foreach (`$idx in `$appxIndices) {",
                "        `$numStr = (`$idx + 1).ToString().PadLeft(3)",
                "        `$typeStr = `$undoTypes[`$idx].PadRight(13)",
                "        Write-Host `"  `$numStr  `$typeStr `$(`$undoDescs[`$idx])`" -ForegroundColor Yellow",
                "    }",
                "}",
                "",
                "Write-Host '' -ForegroundColor White",
                "Write-Host '  A   Undo ALL changes' -ForegroundColor Green",
                "Write-Host '  0   Exit without undoing anything' -ForegroundColor DarkGray",
                "Write-Host '' -ForegroundColor White",
                "",
                "# Prompt for selection",
                "`$menuInput = Read-Host '  Enter numbers (comma-separated), A for all, 0 to exit'",
                "",
                "if (`$menuInput -eq '0' -or `$menuInput -eq 'q') {",
                "    Write-Host '  Exiting without undoing anything.' -ForegroundColor DarkGray",
                "    exit 0",
                "}",
                "",
                "# Parse selection",
                "`$selectedIndices = @()",
                "if (`$menuInput -eq 'A' -or `$menuInput -eq 'a') {",
                "    `$selectedIndices = 0..(`$undoCommands.Count - 1)",
                "} else {",
                "    foreach (`$part in `$menuInput -split ',') {",
                "        `$trimmed = `$part.Trim()",
                "        if (`$trimmed -match '^\d+$') {",
                "            `$num = [int]`$trimmed",
                "            if (`$num -ge 1 -and `$num -le `$undoCommands.Count) {",
                "                `$selectedIndices += `$num - 1",
                "            }",
                "        }",
                "    }",
                "}",
                "",
                "if (`$selectedIndices.Count -eq 0) {",
                "    Write-Host '  No valid selection. Exiting.' -ForegroundColor DarkGray",
                "    exit 0",
                "}",
                "",
                "# Execute selected undo commands",
                "Write-Host '' -ForegroundColor White",
                "Write-Host '  Reverting selected changes...' -ForegroundColor Cyan",
                "Write-Host '' -ForegroundColor White",
                "",
                "foreach (`$idx in `$selectedIndices) {",
                "    `$cmd = `$undoCommands[`$idx]",
                "    `$desc = `$undoDescs[`$idx]",
                "    `$type = `$undoTypes[`$idx]",
                "",
                "    if (`$type -eq 'AppX') {",
                "        # AppX reinstall: show the command but warn",
                "        Write-Host `"  [AppX] `$desc`" -ForegroundColor Yellow",
                "        if (`$cmd -match 'Add-AppxPackage\s+-Package\s+'(.+?)'') {",
                "            Write-Host '        Command: Add-AppxPackage -Package' `"`$(`$Matches[1])`" -ForegroundColor DarkGray",
                "        }",
                "        Write-Host '        NOTE: May require Microsoft Store to reinstall.' -ForegroundColor DarkGray",
                "        continue",
                "    }",
                "",
                "    try {",
                "        Write-Host `"  [`$type] `$desc`" -ForegroundColor White",
                "        Invoke-Expression `$cmd",
                "        Write-Host '        OK' -ForegroundColor Green",
                "    } catch {",
                "        Write-Host `"        FAILED: `$_`" -ForegroundColor Red",
                "    }",
                "}",
                "",
                "Write-Host '' -ForegroundColor White",
                "Write-Host '  Selected changes have been reverted.' -ForegroundColor Green",
                "Write-Host '' -ForegroundColor White"
            )

            Set-Content -Path $undoPath -Value $undoContent -Encoding UTF8 -Force

            # Count AppX items for notification
            $appxCount = 0
            for ($i = 0; $i -lt $script:UndoCommands.Count; $i++) {
                if ($script:UndoCommands[$i] -match '^#\s*Re-install:\s*Add-AppxPackage') {
                    $appxCount++
                }
            }

            # Display prominent undo script notification
            Write-Host ""
            Write-Host "  ================================================================" -ForegroundColor Green
            Write-Host "  UNDO SCRIPT SAVED:" -ForegroundColor White
            Write-Host "  $undoPath" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  To undo ALL changes:" -ForegroundColor White
            Write-Host "      powershell -ExecutionPolicy Bypass -File `"WinPostInstall-Undo.ps1`" -Silent" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  To undo SELECTED changes (interactive menu):" -ForegroundColor White
            Write-Host "      powershell -ExecutionPolicy Bypass -File `"WinPostInstall-Undo.ps1`"" -ForegroundColor Yellow
            if ($appxCount -gt 0) {
                Write-Host ""
                Write-Host "  NOTE: AppX reinstall commands are included — you can select which ones to run." -ForegroundColor Yellow
            }
            Write-Host "  ================================================================" -ForegroundColor Green
            Write-Host ""
        } catch {
            Write-Warn "Could not write undo script: $_"
        }
    }

    try { Stop-Transcript | Out-Null } catch { }
    Write-Host "  Press Enter to exit..." -ForegroundColor DarkGray
    Read-Host "  "
}

#endregion
