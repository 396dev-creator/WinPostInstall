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
    4.0.0
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
    [string[]]$ComputerName
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

$ScriptVersion = "4.0.0"
$LogFile = "$env:SYSTEMDRIVE\Temp\PostInstall_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Undo command tracker (for rollback script generation)
$script:UndoCommands = [System.Collections.ArrayList]::new()

# Statistics counters (for change summary report)
$script:TotalChanged = 0
$script:TotalSkipped = 0
$script:TotalFailed = 0
$script:SectionStats = @{}
$script:BackupDir = "$env:SYSTEMDRIVE\Temp\PostInstall_RegBackup"

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

# Self-elevate: If not running as Administrator, re-launch in an elevated window
# This allows the user to simply double-click the script
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "  Not running as Administrator. Requesting elevation..." -ForegroundColor Yellow
    $scriptArgs = @()
    if ($Silent) { $scriptArgs += "-Silent" }
    if ($Sections) { $scriptArgs += "-Sections"; $scriptArgs += $Sections }
    if ($ConfigFile) { $scriptArgs += "-ConfigFile"; $scriptArgs += $ConfigFile }
    if ($ComputerName) { $scriptArgs += "-ComputerName"; $scriptArgs += $ComputerName }
    try {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $scriptArgs" -Verb RunAs -ErrorAction Stop
        Write-Host "  Elevated window opened. This window can be closed." -ForegroundColor Green
    } catch {
        Write-Host "  Could not self-elevate. Please right-click -> Run as Administrator." -ForegroundColor Red
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
    $script:ComputerName = $env:COMPUTERNAME

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
    Write-Host "  Computer: $script:ComputerName" -ForegroundColor Cyan
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
        [string]$Type = "DWord"
    )
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
        } else {
            $null = $script:UndoCommands.Add("Remove-ItemProperty -Path '$Path' -Name '$Name' -Force -ErrorAction SilentlyContinue")
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

function Disable-ScheduledTask {
    [CmdletBinding()]
    param(
        [string]$TaskPath,
        [string]$TaskName
    )
    try {
        $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($task) {
            if ($task.State -eq 'Disabled') {
                Write-Step "Already disabled: $TaskPath$TaskName"
                $script:TotalSkipped++
            } else {
                Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null
                Write-Success "Task disabled: $TaskPath$TaskName"
                $script:TotalChanged++
                $null = $script:UndoCommands.Add("Enable-ScheduledTask -TaskPath '$TaskPath' -TaskName '$TaskName' -ErrorAction SilentlyContinue")
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
    Write-Host ""
    Write-Host "--- PRIVACY & TELEMETRY (Aggressive) ---" -ForegroundColor Magenta
    Write-Host ""

    # 1. Disable Telemetry via Registry (multiple paths)
    Write-Step "Disabling Windows telemetry..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "AllowTelemetry" -Value 0 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" `
        -Name "AllowTelemetry" -Value 0 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "DoNotShowFeedbackNotifications" -Value 1 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "LimitDiagnosticLogCollection" -Value 1 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "LimitDumpCollection" -Value 1 -Type DWord

    # Disable Application Impact Telemetry + Inventory + UAR
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat" `
        -Name "AITEnable" -Value 0 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat" `
        -Name "DisableInventory" -Value 1 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat" `
        -Name "DisableUAR" -Value 1 -Type DWord

    # Disable CEIP
    foreach ($p in @("HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows",
                      "HKCU:\SOFTWARE\Microsoft\SQMClient\Windows")) {
        Set-Registry -Path $p -Name "CEIPEnable" -Value 0 -Type DWord
    }

    # Disable Tailored Experiences
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
        -Name "DisableTailoredExperiencesWithDiagnosticData" -Value 1 -Type DWord

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
        -Name "Debugger" -Value "%windir%\System32\taskkill.exe" -Type String

    # 4. Disable Activity History
    Write-Step "Disabling activity history..."
    foreach ($name in @("EnableActivityFeed", "PublishUserActivities", "UploadUserActivities")) {
        Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
            -Name $name -Value 0 -Type DWord
    }

    # 5. Disable Location Tracking
    Write-Step "Disabling location tracking..."
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" `
        -Name "Value" -Value "Deny" -Type String
    Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration" `
        -Name "Status" -Value 0 -Type DWord

    # 6. Disable Advertising ID
    Write-Step "Disabling advertising ID..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" `
        -Name "DisabledByGroupPolicy" -Value 1 -Type DWord
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" `
        -Name "Enabled" -Value 0 -Type DWord

    # 7. Disable Cortana (multi-layer)
    Write-Step "Disabling Cortana (multi-layer)..."
    foreach ($prop in @("AllowCortana", "AllowSearchToUseLocation", "AllowCloudSearch")) {
        Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" `
            -Name $prop -Value 0 -Type DWord
    }
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" `
        -Name "DisableWebSearch" -Value 1 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" `
        -Name "ConnectedSearchUseWeb" -Value 0 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsStore" `
        -Name "DisableWindowsStoreRealTimeConfig" -Value 1 -Type DWord

    # 8. Disable Bing Search in Start Menu
    Write-Step "Disabling Bing search in Start Menu..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" `
        -Name "BingSearchEnabled" -Value 0 -Type DWord
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" `
        -Name "CortanaConsent" -Value 0 -Type DWord

    # 9. Disable Copilot (policy + button)
    Write-Step "Disabling Copilot (multi-layer)..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" `
        -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord
    Set-Registry -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" `
        -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "ShowCopilotButton" -Value 0 -Type DWord

    # 10. Disable Windows Recall (Win11 24H2+)
    Write-Step "Disabling Windows Recall..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" `
        -Name "AllowRecallEnablement" -Value 0 -Type DWord
    Set-Registry -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" `
        -Name "AllowRecallEnablement" -Value 0 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" `
        -Name "DisableAIDataAnalysis" -Value 1 -Type DWord

    # 11. Disable AI: Click-to-Do, Image Creator, Cocreator, Generative Fill
    Write-Step "Disabling AI features..."
    foreach ($prop in @("DisableClickToDo", "DisableImageCreator", "DisableCocreator", "DisableGenerativeFill")) {
        Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" `
            -Name $prop -Value 1 -Type DWord
    }

    # 12. Disable AI in Paint
    Write-Step "Disabling AI features in Paint..."
    foreach ($prop in @("DisableImageCreator", "DisableCocreator", "DisableGenerativeFill")) {
        Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\PaintStudio" `
            -Name $prop -Value 1 -Type DWord
    }

    # 13. Disable Clipboard
    Write-Step "Disabling Clipboard cloud sync & history..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
        -Name "AllowClipboardHistory" -Value 0 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
        -Name "AllowCrossDeviceClipboard" -Value 0 -Type DWord

    # 14. Disable Input Telemetry
    Write-Step "Disabling input/typing telemetry..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization" `
        -Name "RestrictImplicitTextCollection" -Value 1 -Type DWord
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization" `
        -Name "RestrictImplicitInkCollection" -Value 1 -Type DWord
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore" `
        -Name "HarvestContacts" -Value 0 -Type DWord

    # 15. Disable Feedback
    Write-Step "Disabling Feedback notifications..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Siuf\Rules" `
        -Name "NumberOfSIUFInPeriod" -Value 0 -Type DWord

    # 16. Disable targeted tips
    Write-Step "Disabling targeted tips & suggestions..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "Start_TrackProgs" -Value 0 -Type DWord
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "Start_TrackDocs" -Value 0 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
        -Name "DisableSoftLanding" -Value 1 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
        -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord

    # 17. Disable Wi-Fi Sense
    Write-Step "Disabling Wi-Fi Sense..."
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting" `
        -Name "Value" -Value 0 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots" `
        -Name "Value" -Value 0 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config" `
        -Name "AutoConnectAllowedOEM" -Value 0 -Type DWord

    # 18. Disable Error Reporting
    Write-Step "Disabling Windows Error Reporting..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" `
        -Name "Disabled" -Value 1 -Type DWord

    # 19. Disable Insider experiments
    Write-Step "Disabling Windows Insider experiments..."
    foreach ($prop in @("EnableExperimentation", "EnableConfigFlighting", "AllowBuildPreview")) {
        Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PreviewBuilds" `
            -Name $prop -Value 0 -Type DWord
    }

    # 20. Disable Setting Sync (Windows Backup)
    Write-Step "Disabling Setting Sync / Windows Backup..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync" `
        -Name "DisableSettingSync" -Value 2 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync" `
        -Name "DisableSettingSyncUserOverride" -Value 1 -Type DWord

    # 21. Full diagnostics/analytics lockdown (Settings > Privacy > Diagnostics & Feedback)
    Write-Step "Locking down all diagnostics & analytics for developers..."
    # Diagnostic Data: Send required only (=1) or off (=0)
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "AllowTelemetry" -Value 0 -Type DWord
    # Tailored Experiences
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
        -Name "DisableTailoredExperiencesWithDiagnosticData" -Value 1 -Type DWord
    # Feedback frequency: Never
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "DoNotShowFeedbackNotifications" -Value 1 -Type DWord
    # Diagnostic Data Viewer: disable
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "EnableDiagnosticDataViewer" -Value 0 -Type DWord
    # Limit diagnostic log collection
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "LimitDiagnosticLogCollection" -Value 1 -Type DWord
    # Limit dump collection
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "LimitDumpCollection" -Value 1 -Type DWord
    # Microsoft Compatibility Telemetry (AIT/Inventory/UAR) - already above but reinforced
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat" `
        -Name "AITEnable" -Value 0 -Type DWord
    # Device Census (sends hardware inventory)
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeviceCensus" `
        -Name "DisableDeviceCensus" -Value 1 -Type DWord
    # Watson (error reporting telemetry)
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" `
        -Name "Disabled" -Value 1 -Type DWord
    # SQM (Customer Experience Improvement) - reinforced
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\SQMClient\Windows" `
        -Name "CEIPEnable" -Value 0 -Type DWord
    # Disable Windows Error Reporting completely
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" `
        -Name "Disabled" -Value 1 -Type DWord
    # Disable Program Compatibility Assistant
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat" `
        -Name "DisablePCA" -Value 1 -Type DWord
    # Disable Application Impact Telemetry
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost" `
        -Name "EnableWebContentEvaluation" -Value 0 -Type DWord
    # Disable活动记录 (Activity History) - additional key
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
        -Name "PublishUserActivities" -Value 0 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
        -Name "UploadUserActivities" -Value 0 -Type DWord
    # Disable Full Language Telemetry
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "FullTelemetryOnInstall" -Value 0 -Type DWord
    # Disable the diagnostic data viewer feature
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "AllowUpdateComplianceTelemetry" -Value 0 -Type DWord

    # 22. Disable all Background Activity / App Diagnostics permissions
    Write-Step "Disabling background app diagnostics..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" `
        -Name "GlobalUserDisabled" -Value 1 -Type DWord
    # Disable App Diagnostics (Settings > Privacy > App Diagnostics)
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" `
        -Name "LetAppsGetDiagnosticInfo" -Value 2 -Type DWord
    # Disable App Activity History
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" `
        -Name "LetAppsAccessActivityHistory" -Value 2 -Type DWord

    # 23. Disable all Advertising and personalization data sharing
    Write-Step "Disabling advertising & personalization data sharing..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" `
        -Name "DisabledByGroupPolicy" -Value 1 -Type DWord
    # Disable Browse Web / Search suggestions personalization
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
        -Name "DisableCloudOptimizedContent" -Value 1 -Type DWord
    # Disable third-party suggestions in Windows
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
        -Name "DisableThirdPartySuggestions" -Value 1 -Type DWord
    # Disable Windows Spotlight (lock screen tips, suggestions)
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" `
        -Name "SubscribedContent-338389Enabled" -Value 0 -Type DWord
    # Disable Get even more out of Windows / Tips
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" `
        -Name "SubscribedContent-310093Enabled" -Value 0 -Type DWord

    # 24. Disable all optional diagnostic data (Kernel, network, app crashes)
    Write-Step "Disabling optional diagnostic data providers..."
    # Disable Windows Kernel telemetry
    Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\AutoLogger-Diagtrack-Listener" `
        -Name "Start" -Value 0 -Type DWord
    # Disable NCSI passive polling (network connectivity telemetry)
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator" `
        -Name "NoActiveProbe" -Value 1 -Type DWord
    # Disable User Profile service telemetry
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\UserProfile" `
        -Name "DisableUserProfileTelemetry" -Value 1 -Type DWord

    # === LOCK SCREEN / SPOTLIGHT ADS ===

    # 25. Disable Windows Spotlight and lock screen ads
    Write-Step "Disabling Windows Spotlight and lock screen ads..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" `
        -Name "ContentDeliveryEnabled" -Value 0 -Type DWord
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" `
        -Name "SubscribedContent-338387Enabled" -Value 0 -Type DWord
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" `
        -Name "SubscribedContent-338388Enabled" -Value 0 -Type DWord
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" `
        -Name "RotatingLockScreenEnabled" -Value 0 -Type DWord
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" `
        -Name "RotatingLockScreenOverlayEnabled" -Value 0 -Type DWord

    # 26. Disable lock screen app notifications
    Write-Step "Disabling lock screen app notifications..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings" `
        -Name "NOC_GLOBAL_SETTING_TOASTS_ENABLED" -Value 0 -Type DWord

    Write-Host ""
    Write-Success "Privacy & Telemetry section complete (26 items)."
}

#endregion

#region ============================================================
# SECTION 2: DEBLOAT (Remove bloatware apps)
# ============================================================

function Invoke-Debloat {
    Write-Host ""
    Write-Host "--- DEBLOAT: Removing Bloatware ---" -ForegroundColor Magenta
    Write-Host ""

    $bloatwareList = @(
        # Microsoft bloat
        "*Microsoft.3DBuilder*","*Microsoft.BingFinance*","*Microsoft.BingFoodAndDrink*",
        "*Microsoft.BingHealth*","*Microsoft.BingMaps*","*Microsoft.BingNews*",
        "*Microsoft.BingSports*","*Microsoft.BingTranslator*","*Microsoft.BingTravel*",
        "*Microsoft.BingWeather*","*Microsoft.CommsPhone*","*Microsoft.Getstarted*",
        "*Microsoft.GamingApp*","*Microsoft.GamingServices*","*Microsoft.Messaging*",
        "*Microsoft.Microsoft3DViewer*","*Microsoft.MicrosoftOfficeHub*",
        "*Microsoft.MicrosoftSolitaireCollection*","*Microsoft.MixedReality.Portal*",
        "*Microsoft.MinecraftUWP*","*Microsoft.NetworkSpeedTest*",
        "*Microsoft.Office.OneNote*","*Microsoft.Office.Sway*","*Microsoft.Office.Lens*",
        "*Microsoft.People*","*Microsoft.PowerAutomateDesktop*",
        "*Microsoft.Print3D*","*Microsoft.SkypeApp*","*Microsoft.Wallet*",
        "*Microsoft.Whiteboard*","*Microsoft.WindowsAlarms*","*Microsoft.WindowsCamera*",
        "*microsoft.windowscommunicationsapps*","*Microsoft.WindowsFeedbackHub*",
        "*Microsoft.WindowsMaps*","*Microsoft.WindowsSoundRecorder*",
        "*Microsoft.XboxApp*","*Microsoft.Xbox.TCUI*","*Microsoft.XboxGameOverlay*",
        "*Microsoft.XboxGamingOverlay*","*Microsoft.XboxIdentityProvider*",
        "*Microsoft.XboxSpeechToTextOverlay*","*Microsoft.ZuneMusic*","*Microsoft.ZuneVideo*",
        "*MicrosoftTeamsFree*","*Microsoft.Copilot*","*Microsoft.Todos*",
        "*Microsoft.OutlookForWindows*","*Microsoft.Windows.DevHome*",
        "*MicrosoftCorporationII.QuickAssist*","*Clipchamp.Clipchamp*",
        "*Microsoft.Advertising.Xaml*",
        # Third-party bloat
        "*ActiproSoftware*","*Disney*","*Duolingo*","*EclipseManager*",
        "*Facebook*","*Fitbit*","*Flipboard*","*king.com.CandyCrush*",
        "*king.com.CandyCrushSodaSaga*","*king.com.FarmHeroesSaga*",
        "*king.com.BubbleWitch3Saga*","*Hulu*","*Netflix*","*Pandora*",
        "*Plex*","*Shazam*","*SlingTV*","*SpotifyAB*","*TikTok*",
        "*Twitter*","*WildTangent*","*Wunderlist*","*LinkedInforWindows*",
        "*AutodeskSketchBook*","*DisneyMagicKingdoms*","*MarchofEmpires*",
        "*CookingFever*","*iHeartRadio*","*PicsArt*","*Polarr*",
        "*TuneIn*","*NYTCrossword*"
    )

    $removed = 0; $notFound = 0

    foreach ($app in $bloatwareList) {
        $packages = Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue
        if ($packages) {
            foreach ($pkg in $packages) {
                try {
                    Write-Step "Removing: $($pkg.Name)"
                    Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                    $removed++
                    $script:TotalChanged++
                    $null = $script:UndoCommands.Add("# Re-install: Add-AppxPackage -Package '$($pkg.PackageFullName)'")
                    Write-Success "Removed: $($pkg.Name)"
                } catch { Write-Warn "Could not remove $($pkg.Name): $_" }
            }
        } else { $notFound++ }
    }

    # Remove provisioned packages (prevents reinstall for new users)
    Write-Step "Cleaning provisioned (stub) packages..."
    $provRemoved = 0; $provNotFound = 0
    foreach ($app in $bloatwareList) {
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
    Write-Success "Debloat complete. Removed: $removed | Already removed: $notFound | Provisioned removed: $provRemoved | Provisioned clean: $provNotFound"
}

#endregion

#region ============================================================
# SECTION 3: EXPLORER & UI OPTIMIZATIONS
# ============================================================

function Invoke-ExplorerUI {
    Write-Host ""
    Write-Host "--- EXPLORER & UI OPTIMIZATIONS ---" -ForegroundColor Magenta
    Write-Host ""

    # 1. Show file extensions
    Write-Step "Showing file extensions..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "HideFileExt" -Value 0 -Type DWord

    # 2. Show hidden files
    Write-Step "Showing hidden files..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "Hidden" -Value 1 -Type DWord

    # 3. Classic right-click context menu (Win11)
    Write-Step "Enabling classic right-click context menu..."
    if ($script:IsWin11) {
        Set-Registry -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" `
            -Name "(Default)" -Value "" -Type String
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
        Set-Registry -Path $cdmPath -Name $key -Value 0 -Type DWord
    }

    # 5. Disable File Explorer ads
    Write-Step "Disabling File Explorer ads..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "ShowSyncProviderNotifications" -Value 0 -Type DWord

    # 6. Disable Lock Screen
    Write-Step "Disabling Lock Screen..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" `
        -Name "NoLockScreen" -Value 1 -Type DWord
    Set-Registry -Path $cdmPath -Name "RotatingLockScreenEnabled" -Value 0 -Type DWord
    Set-Registry -Path $cdmPath -Name "RotatingLockScreenOverlayEnabled" -Value 0 -Type DWord

    # 7. Disable consumer suggestions
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
        -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord

    # 8. Remove Chat icon from Taskbar (Win11)
    Write-Step "Removing Chat icon from Taskbar..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "TaskbarMn" -Value 0 -Type DWord

    # 9. Remove Widgets from Taskbar (Win11)
    Write-Step "Removing Widgets from Taskbar..."
    if ($script:IsWin11) {
        Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
            -Name "TaskbarDa" -Value 0 -Type DWord
    }

    # 10. Remove Search from Taskbar
    Write-Step "Removing Search from Taskbar..."
    if ($script:IsWin11) {
        Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
            -Name "TaskbarSearchBox" -Value 0 -Type DWord
    }

    # 11. Disable Snap Layouts flyout (Win11)
    Write-Step "Disabling Snap Layouts flyout..."
    if ($script:IsWin11) {
        Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
            -Name "EnableSnapAssistFlyout" -Value 0 -Type DWord
    }

    # 12. Enable "End Task" in Taskbar right-click (Win11 22H2+)
    Write-Step "Enabling 'End Task' in Taskbar right-click menu..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarEndTask" `
        -Name "TaskbarEndTask" -Value 1 -Type DWord

    # 13. Open This PC instead of Quick Access
    Write-Step "Setting File Explorer to open 'This PC'..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "LaunchTo" -Value 1 -Type DWord

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
            -Name "DragBetweenWindows" -Value 0 -Type DWord
    }

    # === TASKBAR DEEP CUSTOMIZATION ===

    # 16. Remove Task View button from Taskbar
    Write-Step "Removing Task View button from Taskbar..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "ShowTaskViewButton" -Value 0 -Type DWord

    # 17. Set Search bar to icon-only (not full bar)
    Write-Step "Setting Search bar to icon-only mode..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" `
        -Name "SearchboxTaskbarMode" -Value 1 -Type DWord

    # 18. Hide Copilot button from Taskbar
    Write-Step "Hiding Copilot button from Taskbar..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "ShowCopilotButton" -Value 0 -Type DWord

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
            Remove-Item -Path $libraryKey -Recurse -Force -ErrorAction SilentlyContinue
            Write-Success "Removed: Include in library"
        }
    } catch { Write-Warn "Could not remove library key: $_" }

    Write-Host ""
    Write-Success "Explorer & UI optimizations complete."
}

#endregion

#region ============================================================
# SECTION 4: SERVICE & STARTUP OPTIMIZATION
# ============================================================

function Invoke-ServiceStartupOptimization {
    Write-Host ""
    Write-Host "--- SERVICE & STARTUP OPTIMIZATION ---" -ForegroundColor Magenta
    Write-Host ""

    $disableServices = @(
        @{ Name = "WSearch";               Desc = "Windows Search" },
        @{ Name = "WMPNetworkSvc";         Desc = "Windows Media Player Network Sharing" },
        @{ Name = "WpcSvc";                Desc = "Parental Controls" },
        @{ Name = "TabletInputService";    Desc = "Tablet PC Input" },
        @{ Name = "RetailDemo";            Desc = "Retail Demo Service" },
        @{ Name = "PimIndexMaintenance";   Desc = "People Indexing" },
        @{ Name = "MessagingService";      Desc = "Messaging Service" },
        @{ Name = "MapsBroker";            Desc = "Downloaded Maps Manager" },
        @{ Name = "lfsvc";                 Desc = "Geolocation Service" },
        @{ Name = "HvHost";                Desc = "Hyper-V Host Compute Service" },
        @{ Name = "wisvc";                 Desc = "Windows Insider Service" },
        @{ Name = "WbioSrvc";              Desc = "Windows Biometric Service" },
        @{ Name = "wisvc";                 Desc = "Windows Insider Service" },
        @{ Name = "OneSyncSvc";            Desc = "OneSync Sync Host" },
        @{ Name = "UnistoreSvc";           Desc = "User Data Storage Service" },
        @{ Name = "PushToInstall";         Desc = "Push to Install Service" }
    )

    foreach ($svc in $disableServices) {
        try {
            $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
            if ($service -and $service.StartType -ne 'Disabled') {
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
        -Name "StartupDelayInMSec" -Value 0 -Type DWord

    Write-Host ""
    Write-Success "Service & Startup optimization complete."
}

#endregion

#region ============================================================
# SECTION 5: PERFORMANCE & POWER SETTINGS
# ============================================================

function Invoke-PerformanceOptimization {
    Write-Host ""
    Write-Host "--- PERFORMANCE & POWER SETTINGS ---" -ForegroundColor Magenta
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
        -Name "HiberbootEnabled" -Value 0 -Type DWord

    # 3. Disable Modern Standby Networking (battery drain + security)
    Write-Step "Disabling Modern Standby network connectivity..."
    Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power" `
        -Name "ModernSleep" -Value 0 -Type DWord

    # 4. Set power plan based on chassis type
    if ($script:IsLaptop) {
        # Laptop: keep Balanced, just tweak
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
        -Name "VisualFXSetting" -Value 2 -Type DWord

    $visualFx = @{
        "AnimateMinMaxMenus"=0; "ComboBoxAnimation"=0; "CursorShadow"=0;
        "DragFullWindows"=0; "ListBoxSmoothScrolling"=0; "ListviewAlphaSelect"=0;
        "ListviewShadow"=0; "MenuAnimation"=0; "SelectionFade"=0;
        "TaskbarAnimations"=0; "TooltipAnimation"=0
    }
    foreach ($key in $visualFx.Keys) {
        Set-Registry -Path "HKCU:\Control Panel\Desktop" -Name $key -Value $visualFx[$key] -Type DWord
    }
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\DWM" `
        -Name "EnableAeroPeek" -Value 0 -Type DWord

    # 6. SysMain/Prefetch based on drive type
    if ($script:BootDriveType -eq "SSD") {
        Write-Step "SSD detected: Disabling SysMain (SuperFetch) and Prefetch..."
        try {
            $sysMain = Get-Service -Name "SysMain" -ErrorAction SilentlyContinue
            if ($sysMain -and $sysMain.StartType -ne 'Disabled') {
                Stop-Service -Name "SysMain" -Force -ErrorAction SilentlyContinue
                Set-Service -Name "SysMain" -StartupType Disabled -ErrorAction Stop
                Write-Success "SysMain disabled (SSD)."
            } elseif ($sysMain) {
                Write-Step "SysMain already disabled."
            }
        } catch { Write-Warn "Could not disable SysMain: $_" }

        # Disable Prefetch via registry
        Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" `
            -Name "EnablePrefetcher" -Value 0 -Type DWord
        Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" `
            -Name "EnableSuperfetch" -Value 0 -Type DWord

        # Disable scheduled defrag on SSD
        Write-Step "Disabling scheduled defragmentation (SSD)..."
        try {
            $defragTask = Get-ScheduledTask -TaskName "ScheduledDefrag" -ErrorAction SilentlyContinue
            if ($defragTask -and $defragTask.State -ne 'Disabled') {
                Disable-ScheduledTask -TaskName "ScheduledDefrag" -ErrorAction SilentlyContinue
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
        Write-Step "HDD detected: Keeping SysMain (SuperFetch) and Prefetch enabled."
        # Do not disable SysMain on HDD - it helps with performance
    }

    # 7. Limit Windows Defender CPU usage to ~25%
    Write-Step "Limiting Windows Defender CPU usage..."
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows Defender\Advanced" `
        -Name "ExcludedProcesses" -Value "" -Type String
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows Defender\Scan" `
        -Name "AvgCPULoadFactor" -Value 25 -Type DWord

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
        -Name "SvcHostSplitThresholdInKB" -Value 0x04000000 -Type DWord

    # === RAM-AWARE TWEAKS ===

    # 10. Page file optimization based on RAM
    if ($totalRAM -ge 32) {
        # >=32GB: suggest disabling page file entirely (comment, don't auto-apply)
        Write-Step "RAM >= 32GB: Consider disabling the page file entirely for maximum performance."
        Write-Host "    (Not auto-applied. To disable: System Properties > Advanced > Performance > Virtual Memory > No paging file)" -ForegroundColor DarkGray
    } elseif ($totalRAM -ge 16) {
        # >=16GB: set fixed 1024MB page file
        Write-Step "RAM >= 16GB: Setting fixed page file to 1024MB..."
        Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" `
            -Name "PagingFiles" -Value "C:\pagefile.sys 1024 1024" -Type MultiString
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
    Write-Success "Performance & Power optimization complete."
}

#endregion

#region ============================================================
# SECTION 6: SECURITY HARDENING
# ============================================================

function Invoke-SecurityHardening {
    Write-Host ""
    Write-Host "--- SECURITY HARDENING ---" -ForegroundColor Magenta
    Write-Host ""

    # 1. Ensure Windows Defender real-time protection ON
    Write-Step "Ensuring Windows Defender real-time protection is on..."
    foreach ($prop in @("DisableRealtimeMonitoring","DisableBehaviorMonitoring",
                        "DisableOnAccessProtection","DisableScanOnRealtimeEnable")) {
        Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection" `
            -Name $prop -Value 0 -Type DWord
    }

    # 2. Enable DNS over HTTPS
    Write-Step "Configuring DNS-over-HTTPS..."
    Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" `
        -Name "EnableAutoDoh" -Value 2 -Type DWord

    # 3. Disable USB auto-run
    Write-Step "Disabling USB auto-run..."
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
        -Name "NoDriveTypeAutoRun" -Value 255 -Type DWord

    # 4. Disable Remote Desktop
    Write-Step "Disabling Remote Desktop..."
    Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" `
        -Name "fDenyTSConnections" -Value 1 -Type DWord

    # 5. Disable SMBv1
    Write-Step "Disabling SMBv1..."
    Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" `
        -Name "SMB1" -Value 0 -Type DWord
    Disable-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -NoRestart -ErrorAction SilentlyContinue | Out-Null

    # 6. Disable PowerShell v2
    Write-Step "Disabling PowerShell v2..."
    Disable-WindowsOptionalFeature -Online -FeatureName "MicrosoftWindowsPowerShellV2" `
        -NoRestart -ErrorAction SilentlyContinue | Out-Null

    # 7. Ensure UAC enabled
    Write-Step "Ensuring UAC is enabled..."
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
        -Name "EnableLUA" -Value 1 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
        -Name "ConsentPromptBehaviorAdmin" -Value 5 -Type DWord

    # 8. Disable password reveal
    Write-Step "Disabling password reveal in credential UI..."
    Set-Registry -Path "HKLM:\Software\Policies\Microsoft\Windows\CredUI" `
        -Name "DisablePasswordReveal" -Value 1 -Type DWord

    Write-Host ""
    Write-Success "Security hardening complete."
}

#endregion

#region ============================================================
# SECTION 7: NETWORK OPTIMIZATIONS
# ============================================================

function Invoke-NetworkOptimizations {
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
        -Name "NetworkThrottlingIndex" -Value 0xffffffff -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" `
        -Name "NoLazyMode" -Value 1 -Type DWord

    # 3. Disable Nagle Algorithm
    Write-Step "Disabling Nagle Algorithm (reduces latency)..."
    foreach ($param in @("TcpAckFrequency", "TCPNoDelay")) {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
        $interfaces = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
        foreach ($iface in $interfaces) {
            Set-Registry -Path $iface.PSPath -Name $param -Value 1 -Type DWord
        }
    }

    # 4. Disable NCSI Active Probing
    Write-Step "Disabling NCSI active probing..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator" `
        -Name "NoActiveProbe" -Value 1 -Type DWord

    # 5. Disable Teredo (IPv6 transition)
    Write-Step "Disabling Teredo..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\TCPIP\v6Transition" `
        -Name "Teredo_State" -Value "Disabled" -Type String

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
        -Name "EnableAutoDoh" -Value 2 -Type DWord
    # Configure Cloudflare DoH template via policy
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" `
        -Name "EnableDOH" -Value 1 -Type DWord

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
    Write-Host ""
    Write-Host "--- WINDOWS UPDATE CONFIGURATION ---" -ForegroundColor Magenta
    Write-Host ""

    # 1. Auto-download and notify (not auto-install)
    Write-Step "Configuring Windows Update behavior..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" `
        -Name "AUOptions" -Value 4 -Type DWord

    # 2. Prevent auto-reboot
    Write-Step "Disabling automatic reboot after updates..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" `
        -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord

    # 3. Disable Delivery Optimization
    Write-Step "Disabling Delivery Optimization..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" `
        -Name "DODownloadMode" -Value 0 -Type DWord

    # 4. Exclude drivers from quality updates
    Write-Step "Excluding drivers from quality updates..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" `
        -Name "ExcludeWUDriversInQualityUpdate" -Value 1 -Type DWord

    # 5. Set Active Hours
    Write-Step "Setting active hours to 09:00 - 21:00..."
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UFH" `
        -Name "ActiveHoursStart" -Value 9 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UFH" `
        -Name "ActiveHoursEnd" -Value 21 -Type DWord

    # 6. Prevent device companion app auto-install
    Write-Step "Preventing device companion app auto-install..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" `
        -Name "DoNotConnectToWindowsUpdateInternetLocations" -Value 0 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" `
        -Name "SearchOrderConfig" -Value 0 -Type DWord

    Write-Host ""
    Write-Success "Windows Update configuration complete."
}

#endregion

#region ============================================================
# SECTION 9: DISK CLEANUP & SYSTEM MAINTENANCE
# ============================================================

function Invoke-DiskCleanup {
    Write-Host ""
    Write-Host "--- DISK CLEANUP & SYSTEM MAINTENANCE ---" -ForegroundColor Magenta
    Write-Host ""

    # 1. Run Disk Cleanup (Restore point already created at script startup)
    Write-Step "Configuring Disk Cleanup options..."
    foreach ($key in @("ActiveSetupTemp","OldFiles","ServicePackCleanup")) {
        Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\$key" `
            -Name "StateFlags0001" -Value 2 -Type DWord
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
        -Name "AllowStorageSenseGlobal" -Value 0 -Type DWord

    Write-Host ""
    Write-Success "Disk cleanup & maintenance complete."
}

#endregion

#region ============================================================
# SECTION 10: SOFTWARE INSTALLATION (Winget)
# ============================================================

function Invoke-WingetInstall {
    Write-Host ""
    Write-Host "--- SOFTWARE INSTALLATION (Winget) ---" -ForegroundColor Magenta
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
    Write-Host ""
    Write-Host "--- OFFICE 365 INSTALLATION & ACTIVATION ---" -ForegroundColor Magenta
    Write-Host ""

    $officeSetupUrl = "https://c2rsetup.officeapps.live.com/c2r/download.aspx?ProductreleaseID=O365ProPlusRetail&platform=x64&language=en-us&version=O16GA"
    $masUrl = "https://get.activate.win"
    $officeSetupPath = "$env:TEMP\OfficeSetup.exe"
    $masScriptPath = "$env:TEMP\MAS.ps1"
    $skipToActivation = $false

    # --- Step 1: Download Office 365 ProPlus installer ---
    Write-Host "  [Step 1/3] Office 365 Installation" -ForegroundColor Yellow
    Write-Host ""

    if (-not $Silent) {
        Write-Host "  This will:" -ForegroundColor White
        Write-Host "    1. Download Office 365 ProPlus (x64, English) installer (~4MB)" -ForegroundColor White
        Write-Host "    2. Run the Office deployment (downloads apps, may take 10-20 min)" -ForegroundColor White
        Write-Host "    3. Download and launch Microsoft Activation Scripts (MAS)" -ForegroundColor White
        Write-Host "    4. You manually choose: [1] HWID for Windows, [2] Ohook for Office" -ForegroundColor White
        Write-Host ""
        $confirm = Read-Host "  Proceed with Office install + activation? (Y/n)"
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
        Write-Step "Office 365/2019+ detected. Skipping download."
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
        Write-Step "Downloading Office 365 ProPlus installer..."
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
        Write-Step "Running Office 365 installation (this takes 10-20 minutes)..."
        Write-Host "  Please wait... Office apps are being installed in the background." -ForegroundColor DarkGray
        try {
            $officeProcess = Start-Process -FilePath $officeSetupPath -ArgumentList "/quiet /norestart" `
                -Wait -PassThru -ErrorAction Stop
            if ($officeProcess.ExitCode -eq 0) {
                Write-Success "Office 365 ProPlus installed successfully."
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
    Write-Host ""
    Write-Host "  [Step 2/3] Windows & Office Activation (MAS)" -ForegroundColor Yellow
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
        Set-Registry -Path $item.Path -Name $item.Name -Value $item.Value -Type DWord
    }
    Write-Success "Office telemetry disabled (18 keys)."

    Write-Host ""
    Write-Success "Office section complete. Complete activation in the MAS window."
    Write-Host ""
}

#endregion

#region ============================================================
# SECTION 12: EDGE HARDENING
# ============================================================

function Invoke-EdgeHardening {
    Write-Host ""
    Write-Host "--- EDGE HARDENING ---" -ForegroundColor Magenta
    Write-Host ""

    $edgePath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    $edgePolicies = @{
        "MetricsReportingEnabled"       = 0
        "SendSiteInfoToImproveServices" = 0
        "PersonalizationReportingEnabled" = 0
        "DiagnosticData"                = 0
        "UserFeedbackAllowed"           = 0
        "EdgeShoppingAssistantEnabled"  = 0
        "ShowRecommendationsEnabled"    = 0
        "SearchSuggestEnabled"          = 0
        "HubsSidebarEnabled"            = 0
        "CopilotPageContext"            = 0
        "CopilotCDPPageContext"         = 0
        "BlockThirdPartyCookies"        = 1
        "BackgroundModeEnabled"         = 0
        "SyncDisabled"                  = 1
        "AutofillCreditCardEnabled"     = 0
        "HideRestoreDialogForSycProfiles" = 1
    }

    Write-Step "Applying Edge hardening policies..."
    foreach ($prop in $edgePolicies.Keys) {
        Set-Registry -Path $edgePath -Name $prop -Value $edgePolicies[$prop] -Type DWord
    }

    # Disable Edge prelaunch and tab preloading
    Write-Step "Disabling Edge prelaunch and tab preloading..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\Main" `
        -Name "AllowPrelaunch" -Value 0 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\TabPreloader" `
        -Name "AllowTabPreloading" -Value 0 -Type DWord

    # Disable first-run experience
    Write-Step "Disabling Edge first-run..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\Main" `
        -Name "DisallowFirstRun" -Value 1 -Type DWord

    Write-Host ""
    Write-Success "Edge hardening complete."
}

#endregion

#region ============================================================
# SECTION 13: ONEDRIVE MANAGEMENT
# ============================================================

function Invoke-OneDriveManagement {
    Write-Host ""
    Write-Host "--- ONEDRIVE MANAGEMENT ---" -ForegroundColor Magenta
    Write-Host ""

    # 1. Disable OneDrive via Group Policy
    Write-Step "Disabling OneDrive..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" `
        -Name "DisableFileSyncNGSC" -Value 1 -Type DWord

    # 2. Hide OneDrive from File Explorer navigation pane
    Write-Step "Hiding OneDrive from File Explorer..."
    foreach ($path in @(
        "HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}",
        "HKCR:\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}")) {
        Set-Registry -Path $path -Name "System.IsPinnedToNameSpaceTree" -Value 0 -Type DWord
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
    Write-Host ""
    Write-Host "--- GAMING / XBOX / DVR DISABLE ---" -ForegroundColor Magenta
    Write-Host ""

    # 1. Disable GameDVR via policy
    Write-Step "Disabling GameDVR..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" `
        -Name "AllowgameDVR" -Value 0 -Type DWord

    # 2. Disable Game Bar capture
    Write-Step "Disabling Game Bar capture..."
    foreach ($prop in @("AppCaptureEnabled", "HistoricalCaptureEnabled")) {
        Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" `
            -Name $prop -Value 0 -Type DWord
        Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" `
            -Name $prop -Value 0 -Type DWord
    }

    # 3. Disable GameDVR_Enabled
    Write-Step "Disabling GameDVR_Enabled..."
    Set-Registry -Path "HKCU:\System\GameConfigStore" `
        -Name "GameDVR_Enabled" -Value 0 -Type DWord
    Set-Registry -Path "HKLM:\System\GameConfigStore" `
        -Name "GameDVR_Enabled" -Value 0 -Type DWord

    Write-Host ""
    Write-Success "Gaming / Xbox / DVR disable complete."
}

#endregion

#region ============================================================
# SECTION 15: SCHEDULED TASKS CLEANUP
# ============================================================

function Invoke-ScheduledTasksCleanup {
    Write-Host ""
    Write-Host "--- SCHEDULED TASKS CLEANUP ---" -ForegroundColor Magenta
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
        Disable-ScheduledTask -TaskPath $task.Path -TaskName $task.Name
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
        Disable-ScheduledTask -TaskPath $task.Path -TaskName $task.Name
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
    Write-Host ""
    Write-Host "--- BROWSER EXTENSIONS & PRIVACY ---" -ForegroundColor Magenta
    Write-Host ""

    # ================================================================
    # Extension IDs and install URLs
    # ================================================================
    # uBlock Origin
    $ublockChromeID    = "cjpalhdlnbpafiamejdnhcphjbkeiagm"
    $ublockFirefoxID   = "uBlock0@raymondhill.net"
    $ublockAMOUrl      = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/addon-607454-latest.xpi"
    # Privacy Badger
    $badgerChromeID    = "pkehgijcmpdhfbdbbnkijodmdjhbjlgp"
    $badgerFirefoxID   = "jid1-MnnxcxisBPnSXQ@jetpack"
    $badgerAMOUrl      = "https://addons.mozilla.org/firefox/downloads/latest/privacy-badger17/addon-576858-latest.xpi"

    # Chromium extension update URLs
    $chromeWebStoreUrl = "https://clients2.google.com/service/update2/crx"
    $edgeAddonsUrl    = "https://edge.microsoft.com/extensionwebstorebase/v1/crx"

    # ================================================================
    # PART A: Force-install extensions via Group Policy
    # ================================================================
    Write-Host "  [Extensions]" -ForegroundColor Yellow
    Write-Host ""

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

    # --- Google Chrome ---
    Write-Step "Configuring Google Chrome extensions..."
    $chromeInstalled = Test-Path "HKLM:\SOFTWARE\Google\Chrome\MBL" -ErrorAction SilentlyContinue
    $chromeInstalled2 = Test-Path "HKLM:\SOFTWARE\WOW6432Node\Google\Chrome\MBL" -ErrorAction SilentlyContinue
    $chromePolicyPath = "HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist"
    if ($chromeInstalled -or $chromeInstalled2 -or (Test-Path "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe") -or (Test-Path "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe")) {
        Add-ChromiumExtension -RegPath $chromePolicyPath -ExtID $ublockChromeID -UpdateUrl $chromeWebStoreUrl -BrowserName "Chrome" -ExtName "uBlock Origin"
        Add-ChromiumExtension -RegPath $chromePolicyPath -ExtID $badgerChromeID -UpdateUrl $chromeWebStoreUrl -BrowserName "Chrome" -ExtName "Privacy Badger"
    } else {
        Write-Step "Google Chrome not detected. Setting policies anyway (applies if installed later)."
        Add-ChromiumExtension -RegPath $chromePolicyPath -ExtID $ublockChromeID -UpdateUrl $chromeWebStoreUrl -BrowserName "Chrome" -ExtName "uBlock Origin"
        Add-ChromiumExtension -RegPath $chromePolicyPath -ExtID $badgerChromeID -UpdateUrl $chromeWebStoreUrl -BrowserName "Chrome" -ExtName "Privacy Badger"
    }

    # --- Microsoft Edge ---
    Write-Step "Configuring Microsoft Edge extensions..."
    $edgePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist"
    Add-ChromiumExtension -RegPath $edgePolicyPath -ExtID $ublockChromeID -UpdateUrl $edgeAddonsUrl -BrowserName "Edge" -ExtName "uBlock Origin"
    Add-ChromiumExtension -RegPath $edgePolicyPath -ExtID $badgerChromeID -UpdateUrl $edgeAddonsUrl -BrowserName "Edge" -ExtName "Privacy Badger"

    # --- Brave ---
    Write-Step "Configuring Brave extensions..."
    $bravePolicyPath = "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave\ExtensionInstallForcelist"
    $braveInstalled = (Test-Path "${env:LOCALAPPDATA}\BraveSoftware\Brave-Browser\Application\brave.exe") -or (Test-Path "${env:ProgramFiles}\BraveSoftware\Brave-Browser\Application\brave.exe")
    if ($braveInstalled) {
        Add-ChromiumExtension -RegPath $bravePolicyPath -ExtID $ublockChromeID -UpdateUrl $chromeWebStoreUrl -BrowserName "Brave" -ExtName "uBlock Origin"
        Add-ChromiumExtension -RegPath $bravePolicyPath -ExtID $badgerChromeID -UpdateUrl $chromeWebStoreUrl -BrowserName "Brave" -ExtName "Privacy Badger"
    } else {
        Write-Step "Brave not detected. Setting policies anyway (applies if installed later)."
        Add-ChromiumExtension -RegPath $bravePolicyPath -ExtID $ublockChromeID -UpdateUrl $chromeWebStoreUrl -BrowserName "Brave" -ExtName "uBlock Origin"
        Add-ChromiumExtension -RegPath $bravePolicyPath -ExtID $badgerChromeID -UpdateUrl $chromeWebStoreUrl -BrowserName "Brave" -ExtName "Privacy Badger"
    }

    # --- Opera (uses Chrome Web Store, limited policy support) ---
    Write-Step "Configuring Opera extensions..."
    $operaPolicyPath = "HKLM:\SOFTWARE\Policies\Opera\ExtensionInstallForcelist"
    $operaInstalled = (Test-Path "${env:ProgramFiles}\Opera\launcher.exe") -or (Test-Path "${env:LOCALAPPDATA}\Programs\Opera\launcher.exe")
    if ($operaInstalled) {
        Add-ChromiumExtension -RegPath $operaPolicyPath -ExtID $ublockChromeID -UpdateUrl $chromeWebStoreUrl -BrowserName "Opera" -ExtName "uBlock Origin"
        Add-ChromiumExtension -RegPath $operaPolicyPath -ExtID $badgerChromeID -UpdateUrl $chromeWebStoreUrl -BrowserName "Opera" -ExtName "Privacy Badger"
    } else {
        Write-Step "Opera not detected. Setting policies (may not apply - Opera has limited policy support)."
        Add-ChromiumExtension -RegPath $operaPolicyPath -ExtID $ublockChromeID -UpdateUrl $chromeWebStoreUrl -BrowserName "Opera" -ExtName "uBlock Origin"
        Add-ChromiumExtension -RegPath $operaPolicyPath -ExtID $badgerChromeID -UpdateUrl $chromeWebStoreUrl -BrowserName "Opera" -ExtName "Privacy Badger"
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

        $extSettings[$ublockFirefoxID] = @{
            "installation_mode" = "force_installed"
            "install_url"       = $ublockAMOUrl
        }
        $extSettings[$badgerFirefoxID] = @{
            "installation_mode" = "force_installed"
            "install_url"       = $badgerAMOUrl
        }

        $firefoxPolicy["policies"] = $p
        $jsonOutput = $firefoxPolicy | ConvertTo-Json -Depth 10 -Compress
        Set-Content -Path $policyFile -Value $jsonOutput -Encoding UTF8 -Force
        Write-Success "Firefox: Force-installed uBlock Origin + Privacy Badger via policies.json"
    } else {
        # Fallback: set via registry (Firefox also supports this)
        Write-Step "Firefox not found in Program Files. Setting registry-based policies..."
        $ffPolicyPath = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox\ExtensionSettings"
        try {
            if (-not (Test-Path $ffPolicyPath)) { New-Item -Path $ffPolicyPath -Force -ErrorAction Stop | Out-Null }
            $ublockJson = '{"installation_mode":"force_installed","install_url":"' + $ublockAMOUrl + '"}'
            $badgerJson = '{"installation_mode":"force_installed","install_url":"' + $badgerAMOUrl + '"}'
            Set-ItemProperty -Path $ffPolicyPath -Name $ublockFirefoxID -Value $ublockJson -Force -ErrorAction Stop
            Set-ItemProperty -Path $ffPolicyPath -Name $badgerFirefoxID -Value $badgerJson -Force -ErrorAction Stop
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
        Set-Registry -Path $chromePol -Name $prop -Value $val -Type $type
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
        Set-Registry -Path $bravePol -Name $prop -Value $val -Type $type
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
        Set-Registry -Path $operaPol -Name $prop -Value $operaPrivacySettings[$prop] -Type DWord
    }

    # --- Firefox Privacy ---
    Write-Step "Applying Firefox privacy policies..."
    $ffPol = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox"
    Set-Registry -Path $ffPol -Name "DisableTelemetry" -Value 1 -Type DWord
    Set-Registry -Path $ffPol -Name "DisableFirefoxStudies" -Value 1 -Type DWord
    Set-Registry -Path $ffPol -Name "DisablePocket" -Value 1 -Type DWord
    Set-Registry -Path $ffPol -Name "DisableFormHistory" -Value 1 -Type DWord
    Set-Registry -Path $ffPol -Name "OfferToSaveLogins" -Value 0 -Type DWord
    Set-Registry -Path $ffPol -Name "PasswordManagerEnabled" -Value 0 -Type DWord
    Set-Registry -Path $ffPol -Name "SanitizeOnShutdown" -Value 1 -Type DWord
    Set-Registry -Path $ffPol -Name "DontCheckDefaultBrowser" -Value 1 -Type DWord

    # Firefox tracking protection (strict mode) + DoH
    Write-Step "Configuring Firefox strict tracking protection + DoH..."
    $ffTpPath = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox\EnableTrackingProtection"
    Set-Registry -Path $ffTpPath -Name "Value" -Value 1 -Type DWord
    Set-Registry -Path $ffTpPath -Name "Cryptomining" -Value 1 -Type DWord
    Set-Registry -Path $ffTpPath -Name "Fingerprinting" -Value 1 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Mozilla\Firefox\DNSOverHTTPS" -Name "Enabled" -Value 1 -Type DWord

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
    Write-Success "Browser extensions & privacy configuration complete."
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
    Write-Host ""
    Write-Host "--- FINAL TOUCHES ---" -ForegroundColor Magenta
    Write-Host ""

    # 1. Disable Edge first-run (additional key)
    Write-Step "Disabling Edge first-run (additional)..."
    Set-Registry -Path "HKCU:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\Main" `
        -Name "DisableFirstRunSettings" -Value 1 -Type DWord

    # 2. Disable Windows Insider UI
    Write-Step "Hiding Windows Insider page..."
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\WindowsSelfHost\UI\Visibility" `
        -Name "HideInsiderPage" -Value 1 -Type DWord

    # 3. Set sound scheme to "No Sounds"
    Write-Step "Setting sound scheme to No Sounds..."
    Set-Registry -Path "HKCU:\AppEvents\Schemes" `
        -Name "(Default)" -Value ".None" -Type String

    # 4. Set NumLock OFF at startup
    Write-Step "Setting NumLock OFF at startup..."
    Set-Registry -Path "HKU:\.DEFAULT\Control Panel\Keyboard" `
        -Name "InitialKeyboardIndicators" -Value "0" -Type String

    # 5. Disable mouse acceleration (enhance pointer precision)
    Write-Step "Disabling mouse acceleration..."
    Set-Registry -Path "HKCU:\Control Panel\Mouse" `
        -Name "MouseSpeed" -Value 1 -Type String
    Set-Registry -Path "HKCU:\Control Panel\Mouse" `
        -Name "MouseThreshold1" -Value 0 -Type String
    Set-Registry -Path "HKCU:\Control Panel\Mouse" `
        -Name "MouseThreshold2" -Value 0 -Type String

    # 6. Disable Sticky Keys
    Write-Step "Disabling Sticky Keys..."
    Set-Registry -Path "HKCU:\Control Panel\Accessibility\StickyKeys" `
        -Name "Flags" -Value 506 -Type String

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
    Write-Host ""
    Write-Host "--- WINDOWS FEATURES REMOVAL ---" -ForegroundColor Magenta
    Write-Host ""

    $featuresToRemove = @(
        @{ Name = "Internet-Explorer-Optional-amd64";            Desc = "Internet Explorer" },
        @{ Name = "MediaPlayback";                               Desc = "Media Playback" },
        @{ Name = "WindowsMediaPlayer";                          Desc = "Windows Media Player" },
        @{ Name = "MicrosoftWindowsPowerShellV2";                Desc = "PowerShell V2" },
        @{ Name = "MicrosoftWindowsPowerShellV2Root";            Desc = "PowerShell V2 Root" },
        @{ Name = "Fax";                                         Desc = "Fax" },
        @{ Name = "Hello-Face-Package";                          Desc = "Windows Hello Face" },
        @{ Name = "Math-Recognizer";                             Desc = "Math Recognizer" },
        @{ Name = "Paint3D";                                     Desc = "Paint 3D" },
        # PrintToPDFServicesFeatures - keep if user needs PDF printing
        # @{ Name = "PrintToPDFServicesFeatures";                Desc = "Print to PDF (keep if needed)" },
        @{ Name = "Xps-Foundation-XpsDriver";                    Desc = "XPS Printer Driver" },
        # WCF-Services45 - some apps need it
        # @{ Name = "WCF-Services45";                            Desc = "WCF Services (keep if needed)" },
        @{ Name = "InternetPrintPrintOverInternet";              Desc = "Internet Printing" },
        @{ Name = "WorkFolders-Client";                          Desc = "Work Folders Client" }
        # SmbDirect - may be needed on some systems
        # @{ Name = "SmbDirect";                                 Desc = "SMB Direct (keep if needed)" }
    )

    $disabledCount = 0; $alreadyOffCount = 0; $notFoundCount = 0

    foreach ($feature in $featuresToRemove) {
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

function Show-Menu {
    $menuItems = @(
        @{ ID = "1";  Key = "Privacy";             Name = "Privacy & Telemetry (Aggressive)";          Desc = "Telemetry, Cortana, Copilot, Recall, AI, Bing, tracking" },
        @{ ID = "2";  Key = "Debloat";             Name = "Debloat: Remove Bloatware";                Desc = "Uninstall 60+ pre-installed junk apps" },
        @{ ID = "3";  Key = "ExplorerUI";          Name = "Explorer & UI Optimizations";              Desc = "File extensions, taskbar, CDM lockdown, context menu" },
        @{ ID = "4";  Key = "ServiceStartup";       Name = "Service & Startup Optimization";           Desc = "Disable 16 unnecessary services + startup delay" },
        @{ ID = "5";  Key = "Performance";           Name = "Performance & Power Settings";             Desc = "Hibernation, fast startup, High Perf plan, Defender CPU" },
        @{ ID = "6";  Key = "Security";             Name = "Security Hardening";                       Desc = "Defender, UAC, SMBv1, DNS-over-HTTPS, PSv2" },
        @{ ID = "7";  Key = "Network";              Name = "Network Optimizations";                   Desc = "DNS, Nagle off, throttling off, Teredo off" },
        @{ ID = "8";  Key = "WindowsUpdate";         Name = "Windows Update Configuration";           Desc = "Active hours, no auto-reboot, no delivery opt." },
        @{ ID = "9";  Key = "DiskCleanup";           Name = "Disk Cleanup & Maintenance";              Desc = "Restore point, disk cleanup, temp cleanup" },
        @{ ID = "10"; Key = "Winget";                Name = "Software Installation (Winget)";           Desc = "Chrome, Firefox, 7-Zip, VLC, Reader, Notepad++" },
        @{ ID = "11"; Key = "OfficeActivation";      Name = "Office 365 Install + Activation";            Desc = "Download Office, MAS activation, Office telemetry off" },
        @{ ID = "12"; Key = "EdgeHardening";         Name = "Edge Hardening (14 policies)";             Desc = "Shopping, Copilot, telemetry, preload, sync" },
        @{ ID = "13"; Key = "OneDrive";              Name = "OneDrive Management";                      Desc = "Disable sync, hide from Explorer, remove startup" },
        @{ ID = "14"; Key = "Gaming";                Name = "Gaming / Xbox / DVR Disable";              Desc = "GameDVR, Game Bar capture, Xbox overlay" },
        @{ ID = "15"; Key = "ScheduledTasks";         Name = "Scheduled Tasks Cleanup (33+ tasks)";      Desc = "Telemetry, CEIP, Office, Xbox, Maps, diagnostics" },
        @{ ID = "16"; Key = "BrowserHardening";      Name = "Browser Extensions & Privacy";              Desc = "uBlock Origin + Privacy Badger on 5 browsers + privacy policies" },
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

function Get-UserSelection {
    Show-Menu
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
    if ($ConfigFile -and (Test-Path $ConfigFile -ErrorAction SilentlyContinue)) {
        # Load configuration from JSON file
        Write-Step "Loading configuration from: $ConfigFile"
        try {
            $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
            if ($config.Sections) {
                $selectedSections = @($config.Sections)
                Write-Success "Loaded sections from config: $($selectedSections -join ', ')"
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
                              "OfficeActivation","EdgeHardening","OneDrive","Gaming","ScheduledTasks","BrowserHardening","FinalTouches","WindowsFeatures")
        Write-Host "  Silent mode: running all sections." -ForegroundColor DarkGray
    } else {
        $selectedSections = Get-UserSelection
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

    if ($selectedSections -intersect @("DiskCleanup","Security","ServiceStartup","Performance","ScheduledTasks","Gaming","BrowserHardening","OfficeActivation")) {
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
            $undoHeader = @(
                "<#",
                ".SYNOPSIS",
                "    Undo script for WinPostInstall v$ScriptVersion",
                ".DESCRIPTION",
                "    Generated automatically. Run this to revert registry and scheduled task changes.",
                "    NOTE: AppX package removals cannot be undone automatically.",
                "#>"
                "",
                "# Requires Administrator",
                "if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {",
                "    Write-Host 'This script requires Administrator privileges.' -ForegroundColor Red",
                "    exit 1",
                "}"
                ""
            )
            $undoContent = $undoHeader + $script:UndoCommands
            Set-Content -Path $undoPath -Value $undoContent -Encoding UTF8 -Force
            Write-Host "  Undo script saved to: $undoPath" -ForegroundColor Green
        } catch {
            Write-Warn "Could not write undo script: $_"
        }
    }

    try { Stop-Transcript | Out-Null } catch { }
    Write-Host "  Press Enter to exit..." -ForegroundColor DarkGray
    Read-Host "  "
}

#endregion
