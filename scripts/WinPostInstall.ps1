<#
.SYNOPSIS
    Windows Post-Installation Optimization Script
.DESCRIPTION
    Automates common post-installation optimizations for Windows 10/11.
    Supports both interactive menu mode and fully unattended (silent) mode.
    Designed for computer repair technicians to standardize OS setup.
.AUTHOR
    Auto-generated optimization script
.VERSION
    2.0.0
.NOTES
    Requires Administrator privileges.
    Usage:
        Interactive:  .\WinPostInstall.ps1
        Silent:       .\WinPostInstall.ps1 -Silent
        Specific:     .\WinPostInstall.ps1 -Sections Privacy,Debloat,Performance
#>

#region ============================================================
# PARAMETERS & CONFIGURATION
# ============================================================

[CmdletBinding()]
param(
    [switch]$Silent,
    [string[]]$Sections
)

$ScriptVersion = "2.0.0"
$LogFile = "$env:SYSTEMDRIVE\Temp\PostInstall_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

#endregion

#region ============================================================
# BOOTSTRAP: Admin check, logging, OS detection
# ============================================================

function Initialize-Script {
    # Require Administrator
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "[ERROR] This script must be run as Administrator." -ForegroundColor Red
        Write-Host "Right-click PowerShell and select 'Run as Administrator', then re-run this script." -ForegroundColor Yellow
        if (-not $Silent) { Read-Host "Press Enter to exit" }
        exit 1
    }

    # Create log directory
    $logDir = "$env:SYSTEMDRIVE\Temp"
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }

    # Start transcript logging
    Start-Transcript -Path $LogFile -Force | Out-Null

    # Detect OS
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    $script:OSVersion = [version]$osInfo.Version
    $script:OSBuild = $osInfo.BuildNumber
    $script:IsWin11 = $script:OSBuild -ge 22000
    $script:OSCaption = if ($script:IsWin11) { "Windows 11" } else { "Windows 10" }
    $script:ComputerName = $env:COMPUTERNAME

    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  Windows Post-Installation Optimizer v$ScriptVersion" -ForegroundColor Cyan
    Write-Host "  Target: $script:OSCaption (Build $script:OSBuild)" -ForegroundColor Cyan
    Write-Host "  Computer: $script:ComputerName" -ForegroundColor Cyan
    Write-Host "  Log file: $LogFile" -ForegroundColor DarkGray
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
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

function Set-Registry {
    <#
    .SYNOPSIS
        Safely set a registry value, creating the path if needed.
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = "DWord"
    )
    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
        Write-Success "Registry: $Path\$Name = $Value"
    }
    catch {
        Write-Err "Failed to set $Path\$Name : $_"
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
            Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction Stop 2>$null
            Write-Success "Registry removed: $Path\$Name"
        }
    }
    catch {
        Write-Warn "Could not remove $Path\$Name : $_"
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

    # 1. Disable Telemetry via Registry
    Write-Step "Disabling Windows telemetry..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "AllowTelemetry" -Value 0 -Type DWord

    # Disable Diagnostic Data Viewer
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack" `
        -Name "ShowedToastAtLevel" -Value 0 -Type DWord

    # Disable Customer Experience Improvement Program (CEIP)
    $ceipPaths = @(
        "HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows",
        "HKCU:\SOFTWARE\Microsoft\SQMClient\Windows"
    )
    foreach ($p in $ceipPaths) {
        Set-Registry -Path $p -Name "CEIPEnable" -Value 0 -Type DWord
    }

    # 2. Disable Diagnostics Tracking Service
    Write-Step "Stopping and disabling diagnostic tracking services..."
    $diagServices = @(
        "DiagTrack",           # Connected User Experiences and Telemetry
        "dmwappushservice",    # WAP Push Message Routing Service
        "WerSvc"               # Windows Error Reporting Service
    )
    foreach ($svc in $diagServices) {
        try {
            $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($service) {
                Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
                Write-Success "Service disabled: $svc"
            } else {
                Write-Warn "Service not found: $svc"
            }
        } catch {
            Write-Warn "Could not disable service $svc : $_"
        }
    }

    # 3. Disable Activity History
    Write-Step "Disabling activity history..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
        -Name "EnableActivityFeed" -Value 0 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
        -Name "PublishUserActivities" -Value 0 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
        -Name "UploadUserActivities" -Value 0 -Type DWord

    # 4. Disable Location Tracking
    Write-Step "Disabling location tracking..."
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" `
        -Name "Value" -Value "Deny" -Type String

    # 5. Disable Advertising ID
    Write-Step "Disabling advertising ID..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" `
        -Name "DisabledByGroupPolicy" -Value 1 -Type DWord
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" `
        -Name "Enabled" -Value 0 -Type DWord

    # 6. Disable Cortana
    Write-Step "Disabling Cortana..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore" `
        -Name "DisableWindowsStoreRealTimeConfig" -Value 1 -Type DWord

    if ($script:IsWin11) {
        # Win11 specific Cortana disable
        $cortanaPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
        Set-Registry -Path $cortanaPath -Name "AllowCortana" -Value 0 -Type DWord
        Set-Registry -Path $cortanaPath -Name "DisableWebSearch" -Value 1 -Type DWord
        Set-Registry -Path $cortanaPath -Name "AllowSearchToUseLocation" -Value 0 -Type DWord

        # Disable Copilot (Win11)
        Write-Step "Disabling Windows Copilot..."
        Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" `
            -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord
    } else {
        # Win10 specific Cortana disable
        Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" `
            -Name "AllowCortana" -Value 0 -Type DWord
        Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" `
            -Name "DisableWebSearch" -Value 1 -Type DWord
    }

    # 7. Disable Timeline / Clipboard History (Win10)
    if (-not $script:IsWin11) {
        Write-Step "Disabling Timeline..."
        Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
            -Name "EnableActivityFeed" -Value 0 -Type DWord
    }

    # 8. Disable Clipboard cloud sync
    Write-Step "Disabling Clipboard cloud sync..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
        -Name "AllowClipboardHistory" -Value 0 -Type DWord

    # 9. Disable Feedback notifications
    Write-Step "Disabling Feedback notifications..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Siuf\Rules" `
        -Name "NumberOfSIUFInPeriod" -Value 0 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "DoNotShowFeedbackNotifications" -Value 1 -Type DWord

    # 10. Disable Tailored Experiences (content-based suggestions)
    Write-Step "Disabling Tailored Experiences..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" `
        -Name "SubscribedContent-338389Enabled" -Value 0 -Type DWord

    # 11. Disable targeted tips
    Write-Step "Disabling targeted tips & suggestions..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "Start_TrackProgs" -Value 0 -Type DWord
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "Start_TrackDocs" -Value 0 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
        -Name "DisableSoftLanding" -Value 1 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
        -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord

    # 12. Disable Text Input Telemetry
    Write-Step "Disabling text input telemetry..."
    $tipPath = "HKCU:\SOFTWARE\Microsoft\Input\Settings"
    if (Test-Path $tipPath) {
        Set-Registry -Path $tipPath -Name "InsightsDisabled" -Value 1 -Type DWord
    }

    # 13. Disable Wi-Fi Sense (auto-connect to open networks, share networks)
    Write-Step "Disabling Wi-Fi Sense..."
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting" `
        -Name "Value" -Value 0 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots" `
        -Name "Value" -Value 0 -Type DWord

    Write-Host ""
    Write-Success "Privacy & Telemetry section complete."
}

#endregion

#region ============================================================
# SECTION 2: DEBLOAT (Remove bloatware apps)
# ============================================================

function Invoke-Debloat {
    Write-Host ""
    Write-Host "--- DEBLOAT: Removing Bloatware ---" -ForegroundColor Magenta
    Write-Host ""

    # List of bloatware AppX packages to remove
    $bloatwareList = @(
        # Common manufacturer bloat
        "*ActiproSoftware*",
        "*AdobeSystems*",
        "*Disney*",
        "*Duolingo*",
        "*EclipseManager*",
        "*Facebook*",
        "*Fitbit*",
        "*Flipboard*",
        "*HiddenCity*",
        "*Hulu*",
        "*King*",
        "*Minecraft*",
        "*Netflix*",
        "*Pandora*",
        "*Plex*",
        "*Shazam*",
        "*SlingTV*",
        "*Spotify*",
        "*TikTok*",
        "*Twitter*",
        "*WildTangent*",
        "*Wunderlist*",

        # Microsoft bloat
        "*Microsoft.3DBuilder*",
        "*Microsoft.BingFinance*",
        "*Microsoft.BingFoodAndDrink*",
        "*Microsoft.BingHealth*",
        "*Microsoft.BingMaps*",
        "*Microsoft.BingNews*",
        "*Microsoft.BingSports*",
        "*Microsoft.BingTranslator*",
        "*Microsoft.BingTravel*",
        "*Microsoft.BingWeather*",
        "*Microsoft.CommsPhone*",
        "*Microsoft.Getstarted*",
        "*Microsoft.GamingApp*",
        "*Microsoft.Messaging*",
        "*Microsoft.Microsoft3DViewer*",
        "*Microsoft.MicrosoftOfficeHub*",
        "*Microsoft.MicrosoftSolitaireCollection*",
        "*Microsoft.MixedReality.Portal*",
        "*Microsoft.Moju*",
        "*Microsoft.NetworkSpeedTest*",
        "*Microsoft.Office.OneNote*",
        "*Microsoft.People*",
        "*Microsoft.Print3D*",
        "*Microsoft.SkypeApp*",
        "*Microsoft.Wallet*",
        "*Microsoft.Whiteboard*",
        "*Microsoft.WindowsAlarms*",
        "*Microsoft.WindowsCamera*",
        "*microsoft.windowscommunicationsapps*",
        "*Microsoft.WindowsFeedbackHub*",
        "*Microsoft.WindowsMaps*",
        "*Microsoft.WindowsSoundRecorder*",
        "*Microsoft.XboxApp*",
        "*Microsoft.ZuneMusic*",
        "*Microsoft.ZuneVideo*",
        "*MicrosoftTeamsFree*",
        "*Microsoft.Copilot*",
        "*Microsoft.Todos*",
        "*Microsoft.PowerAutomateDesktop*"
    )

    $removed = 0
    $notFound = 0

    foreach ($app in $bloatwareList) {
        $packages = Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue
        if ($packages) {
            foreach ($pkg in $packages) {
                try {
                    Write-Step "Removing: $($pkg.Name)"
                    Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                    $removed++
                    Write-Success "Removed: $($pkg.Name)"
                } catch {
                    Write-Warn "Could not remove $($pkg.Name): $_"
                }
            }
        } else {
            $notFound++
        }
    }

    # Also provisioned packages (pre-installed for new users)
    Write-Step "Cleaning provisioned (stub) packages for future users..."
    foreach ($app in $bloatwareList) {
        $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object DisplayName -like $app
        if ($prov) {
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop
                Write-Success "Removed provisioned: $($prov.DisplayName)"
            } catch {
                Write-Warn "Could not remove provisioned $($prov.DisplayName): $_"
            }
        }
    }

    Write-Host ""
    Write-Success "Debloat complete. Removed $removed packages ($notFound not found)."
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

    # 3. Show full right-click context menu (Win11 restores classic menu)
    Write-Step "Enabling full context menu..."
    if ($script:IsWin11) {
        Set-Registry -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" `
            -Name "(Default)" -Value "" -Type String
    }

    # 4. Disable File Explorer ads (OneDrive, tips)
    Write-Step "Disabling File Explorer ads..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "ShowSyncProviderNotifications" -Value 0 -Type DWord
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes\{e88865ea-0e1c-400e-9427-f8b7af49b52d}" `
        -Name "TopView" -Value 0 -Type DWord

    # 5. Disable Lock Screen
    Write-Step "Disabling Lock Screen..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" `
        -Name "NoLockScreen" -Value 1 -Type DWord

    # 6. Disable Lock Screen tips
    Write-Step "Disabling Lock Screen tips..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" `
        -Name "RotatingLockScreenOverlayEnabled" -Value 0 -Type DWord
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" `
        -Name "SubscribedContent-310093Enabled" -Value 0 -Type DWord

    # 7. Disable consumer suggestions
    Write-Step "Disabling 'Get more out of Windows' suggestions..."
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

    # 10. Remove Search icon from Taskbar
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

    # 12. Open This PC instead of Quick Access
    Write-Step "Setting File Explorer to open 'This PC'..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "LaunchTo" -Value 1 -Type DWord

    # 13. Remove 3D Objects from This PC
    Write-Step "Removing 3D Objects from This PC..."
    $shellKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}"
    if (Test-Path $shellKey) {
        Remove-Item -Path $shellKey -Force -ErrorAction SilentlyContinue
        Write-Success "Removed 3D Objects namespace key."
    }

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

    # Services to disable for performance
    $disableServices = @(
        @{ Name = "WSearch";               Desc = "Windows Search" },
        @{ Name = "WMPNetworkSvc";         Desc = "Windows Media Player Network Sharing" },
        @{ Name = "WpcSvc";                Desc = "Parental Controls" },
        @{ Name = "WerSvc";                Desc = "Windows Error Reporting" },
        @{ Name = "TabletInputService";    Desc = "Tablet PC Input" },
        @{ Name = "RetailDemo";            Desc = "Retail Demo Service" },
        @{ Name = "PimIndexMaintenance";   Desc = "People Indexing" },
        @{ Name = "MessagingService";      Desc = "Messaging Service" },
        @{ Name = "MapsBroker";            Desc = "Downloaded Maps Manager" },
        @{ Name = "lfsvc";                 Desc = "Geolocation Service" },
        @{ Name = "HvHost";                Desc = "Hyper-V Host Compute Service" },
        @{ Name = "wisvc";                 Desc = "Windows Insider Service" },
        @{ Name = "WbioSrvc";              Desc = "Windows Biometric Service" }
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
        }
        catch {
            Write-Warn "Could not disable $($svc.Name): $_"
        }
    }

    # Disable Startup delay (10-second artificial delay)
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

    # 1. Disable Hibernation (frees up hiberfil.sys which can be GBs)
    Write-Step "Disabling Hibernation..."
    try {
        powercfg.exe /hibernate off 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Hibernation disabled. hiberfil.sys removed."
        } else {
            Write-Warn "Could not disable hibernation (may already be off)."
        }
    } catch {
        Write-Warn "Hibernation disable failed: $_"
    }

    # 2. Set High Performance power plan
    Write-Step "Setting High Performance power plan..."
    try {
        $highPerf = powercfg.exe /list | Select-String -Pattern "High performance|高性能"
        if ($highPerf) {
            $guid = ($highPerf.ToString() -split '\s+')[3]
            powercfg.exe /setactive $guid 2>$null
            Write-Success "Power plan set to High Performance ($guid)"
        } else {
            # Create it from the Ultimate Performance / High Perf GUID
            powercfg.exe /duplicatecheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null | Out-Null
            Start-Sleep -Seconds 1
            $highPerf = powercfg.exe /list | Select-String -Pattern "High performance|高性能"
            if ($highPerf) {
                $guid = ($highPerf.ToString() -split '\s+')[3]
                powercfg.exe /setactive $guid 2>$null
                Write-Success "High Performance plan created and activated ($guid)"
            } else {
                Write-Warn "Could not find or create High Performance plan."
            }
        }
    } catch {
        Write-Warn "Power plan change failed: $_"
    }

    # 3. Set visual effects to Best Performance
    Write-Step "Setting visual effects to 'Best Performance'..."
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" `
        -Name "VisualFXSetting" -Value 2 -Type DWord

    # Disable individual animations for snappier UI
    $visualFx = @{
        "AnimateMinMaxMenus" = 0
        "ComboBoxAnimation" = 0
        "CursorShadow" = 0
        "DragFullWindows" = 0
        "ListBoxSmoothScrolling" = 0
        "ListviewAlphaSelect" = 0
        "ListviewShadow" = 0
        "MenuAnimation" = 0
        "SelectionFade" = 0
        "TaskbarAnimations" = 0
        "TooltipAnimation" = 0
    }
    foreach ($key in $visualFx.Keys) {
        Set-Registry -Path "HKCU:\Control Panel\Desktop" `
            -Name $key -Value $visualFx[$key] -Type DWord
    }

    # Disable transparent glass / Aero Peek
    Set-Registry -Path "HKCU:\SOFTWARE\Microsoft\Windows\DWM" `
        -Name "EnableAeroPeek" -Value 0 -Type DWord

    # 4. Disable SysMain (formerly SuperFetch / Prefetch)
    Write-Step "Disabling SysMain (SuperFetch)..."
    try {
        $sysMain = Get-Service -Name "SysMain" -ErrorAction SilentlyContinue
        if ($sysMain) {
            Stop-Service -Name "SysMain" -Force -ErrorAction SilentlyContinue
            Set-Service -Name "SysMain" -StartupType Disabled -ErrorAction Stop
            Write-Success "SysMain disabled."
        }
    } catch {
        Write-Warn "Could not disable SysMain: $_"
    }

    # 5. Disable common OEM telemetry services
    Write-Step "Disabling OEM telemetry services..."
    $oemServices = @(
        "HPAppHelperShell",
        "HPDiags",
        "HPHealth",
        "HPSysInfo",
        "HpTouchpointAnalyticsService",
        "HpTouchpointMgr",
        "hpsvcsss",
        "DellClientWMI",
        "DellCommandUpdate",
        "DellDataWarden",
        "Lenovo.SysInterceptor",
        "LENOVO.TVTGard"
    )
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

    # 1. Ensure Windows Defender real-time protection is ON
    Write-Step "Ensuring Windows Defender real-time protection is on..."
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection" `
        -Name "DisableRealtimeMonitoring" -Value 0 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection" `
        -Name "DisableBehaviorMonitoring" -Value 0 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection" `
        -Name "DisableOnAccessProtection" -Value 0 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection" `
        -Name "DisableScanOnRealtimeEnable" -Value 0 -Type DWord

    # 2. Enable DNS over HTTPS system-wide
    Write-Step "Configuring DNS-over-HTTPS settings..."
    Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" `
        -Name "EnableAutoDoh" -Value 2 -Type DWord

    # 3. Disable USB auto-run / auto-play
    Write-Step "Disabling USB auto-run..."
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
        -Name "NoDriveTypeAutoRun" -Value 255 -Type DWord

    # 4. Disable Remote Desktop (re-enable manually if client needs it)
    Write-Step "Disabling Remote Desktop..."
    Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" `
        -Name "fDenyTSConnections" -Value 1 -Type DWord

    # 5. Disable SMBv1 (known security vulnerability)
    Write-Step "Disabling SMBv1..."
    Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" `
        -Name "SMB1" -Value 0 -Type DWord

    # 6. Disable PowerShell v2 (deprecated, security risk)
    Write-Step "Disabling PowerShell v2..."
    Disable-WindowsOptionalFeature -Online -FeatureName "MicrosoftWindowsPowerShellV2" `
        -NoRestart -ErrorAction SilentlyContinue | Out-Null

    # 7. Ensure UAC (User Account Control) is enabled
    Write-Step "Ensuring UAC is enabled..."
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
        -Name "EnableLUA" -Value 1 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
        -Name "ConsentPromptBehaviorAdmin" -Value 5 -Type DWord

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

    # 1. Set DNS to Cloudflare + Google (fast, private, reliable)
    Write-Step "Setting DNS servers to Cloudflare (1.1.1.1) and Google (8.8.8.8)..."
    try {
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceType -ne 'Loopback' }
        if ($adapters) {
            foreach ($adapter in $adapters) {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex `
                    -ServerAddresses ("1.1.1.1", "8.8.8.8") -ErrorAction Stop
                Write-Success "DNS set on adapter: $($adapter.Name)"
            }
        } else {
            Write-Warn "No active network adapters found."
        }
    } catch {
        Write-Warn "Failed to set DNS: $_"
    }

    # 2. Disable Network Throttling
    Write-Step "Disabling network throttling..."
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" `
        -Name "NetworkThrottlingIndex" -Value 0xffffffff -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" `
        -Name "NoLazyMode" -Value 1 -Type DWord

    # 3. Disable Nagle Algorithm (reduces network latency)
    Write-Step "Disabling Nagle Algorithm (reduces latency)..."
    $netParams = @("TcpAckFrequency", "TCPNoDelay")
    foreach ($param in $netParams) {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
        $interfaces = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
        foreach ($iface in $interfaces) {
            Set-Registry -Path $iface.PSPath -Name $param -Value 1 -Type DWord
        }
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

    # 1. Set Windows Update to auto-download and notify before install
    Write-Step "Configuring Windows Update behavior..."
    # AUOptions: 4 = Auto download & notify, with no auto-reboot
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" `
        -Name "AUOptions" -Value 4 -Type DWord

    # 2. Prevent auto-reboot when users are logged on
    Write-Step "Disabling automatic reboot after updates..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" `
        -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord

    # 3. Disable Windows Update Delivery Optimization (P2P sharing)
    Write-Step "Disabling Windows Update delivery optimization..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" `
        -Name "DODownloadMode" -Value 0 -Type DWord

    # 4. Set Active Hours to 9 AM - 9 PM
    Write-Step "Setting active hours to 09:00 - 21:00..."
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UFH" `
        -Name "ActiveHoursStart" -Value 9 -Type DWord
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UFH" `
        -Name "ActiveHoursEnd" -Value 21 -Type DWord

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

    # 1. Create a System Restore point before making changes
    Write-Step "Creating System Restore point..."
    try {
        Enable-ComputerRestore -Drive "$env:SYSTEMDRIVE\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "Post-Install Optimizer - Pre-optimization snapshot" `
            -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Success "System Restore point created."
    } catch {
        Write-Warn "Could not create Restore Point: $_"
    }

    # 2. Run Disk Cleanup silently with preset flags
    Write-Step "Configuring Disk Cleanup options..."
    $stateFlags = @{
        "ActiveSetupTemp" = 2
        "OldFiles" = 2
        "ServicePackCleanup" = 2
    }

    $sagePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
    foreach ($key in $stateFlags.Keys) {
        Set-Registry -Path "$sagePath\$key" -Name "StateFlags0001" -Value $stateFlags[$key] -Type DWord
    }

    Write-Step "Running Disk Cleanup..."
    Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:1" -NoNewWindow -Wait -ErrorAction SilentlyContinue
    Write-Success "Disk Cleanup completed."

    # 3. Disable Storage Sense (prevents accidental file deletion)
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

    # Curated list of commonly-needed apps for fresh installs
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

    # Check if Winget is available
    try {
        $null = Get-Command winget -ErrorAction Stop
        Write-Success "Winget found."
    } catch {
        Write-Err "Winget is not installed or not in PATH."
        Write-Host "  Install 'App Installer' from the Microsoft Store, then re-run this section." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "  The following apps will be installed:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $appList.Count; $i++) {
        Write-Host "    $($i + 1). $($appList[$i].Name) ($($appList[$i].ID))" -ForegroundColor White
    }
    Write-Host ""

    if (-not $Silent) {
        $confirm = Read-Host "  Install all listed apps? (Y/n)"
        if ($confirm -eq 'n' -or $confirm -eq 'N') {
            Write-Warn "Software installation skipped by user."
            return
        }
    }

    $successCount = 0
    $failCount = 0

    foreach ($app in $appList) {
        Write-Step "Installing $($app.Name)..."
        try {
            winget install --id $app.ID --silent --accept-package-agreements --accept-source-agreements `
                --ignore-security-hash --disable-interactivity 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Installed: $($app.Name)"
                $successCount++
            } else {
                Write-Warn "Winget exit code $LASTEXITCODE for $($app.Name) (may already be installed)"
                $failCount++
            }
        } catch {
            Write-Warn "Failed to install $($app.Name): $_"
            $failCount++
        }
    }

    Write-Host ""
    Write-Success "Software installation complete. Success: $successCount | Issues: $failCount"
}

#endregion

#region ============================================================
# SECTION 11: FINAL TOUCHES
# ============================================================

function Invoke-FinalTouches {
    Write-Host ""
    Write-Host "--- FINAL TOUCHES ---" -ForegroundColor Magenta
    Write-Host ""

    # 1. Disable Edge first-run splash / welcome page
    Write-Step "Disabling Edge first-run experience..."
    Set-Registry -Path "HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\Main" `
        -Name "DisallowFirstRun" -Value 1 -Type DWord
    Set-Registry -Path "HKCU:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\Main" `
        -Name "DisableFirstRunSettings" -Value 1 -Type DWord

    # 2. Remove Edge from startup
    Write-Step "Removing Edge from startup folder..."
    $edgeStartup = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    $edgeShortcut = Get-ChildItem -Path $edgeStartup -Filter "*edge*" -ErrorAction SilentlyContinue
    if ($edgeShortcut) {
        Remove-Item $edgeShortcut.FullName -Force -ErrorAction SilentlyContinue
        Write-Success "Removed Edge from startup folder."
    }

    # 3. Disable Windows Insider Program
    Write-Step "Disabling Windows Insider Program..."
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\WindowsUpdate" `
        -Name "ManagePreviewBuilds" -Value 0 -Type DWord

    # 4. Set sound scheme to "No Sounds" (clean, no annoying dings)
    Write-Step "Setting sound scheme to No Sounds..."
    Set-Registry -Path "HKCU:\AppEvents\Schemes" `
        -Name "(Default)" -Value ".None" -Type String

    # 5. Set NumLock OFF at startup
    Write-Step "Setting NumLock OFF at startup..."
    Set-Registry -Path "HKU:\.DEFAULT\Control Panel\Keyboard" `
        -Name "InitialKeyboardIndicators" -Value "0" -Type String

    # 6. Restart File Explorer to apply all UI changes immediately
    Write-Step "Restarting File Explorer to apply changes..."
    try {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-Process explorer.exe -ErrorAction SilentlyContinue
        Write-Success "File Explorer restarted."
    } catch {
        Write-Warn "Could not restart Explorer: $_"
    }

    Write-Host ""
    Write-Success "Final touches complete."
}

#endregion

#region ============================================================
# INTERACTIVE MENU
# ============================================================

function Show-Menu {
    $menuItems = @(
        @{ ID = "1";  Key = "Privacy";          Name = "Privacy & Telemetry (Aggressive)";                  Desc = "Disable all telemetry, Cortana, tracking, ads" },
        @{ ID = "2";  Key = "Debloat";          Name = "Debloat: Remove Bloatware";                        Desc = "Uninstall pre-installed junk apps" },
        @{ ID = "3";  Key = "ExplorerUI";       Name = "Explorer & UI Optimizations";                      Desc = "File extensions, taskbar, lock screen, context menu" },
        @{ ID = "4";  Key = "ServiceStartup";   Name = "Service & Startup Optimization";                   Desc = "Disable unnecessary services, startup delay" },
        @{ ID = "5";  Key = "Performance";       Name = "Performance & Power Settings";                     Desc = "Hibernation off, high perf plan, visual effects" },
        @{ ID = "6";  Key = "Security";          Name = "Security Hardening";                               Desc = "Defender, UAC, SMBv1 off, DNS-over-HTTPS" },
        @{ ID = "7";  Key = "Network";           Name = "Network Optimizations";                             Desc = "DNS servers, Nagle off, throttling off" },
        @{ ID = "8";  Key = "WindowsUpdate";     Name = "Windows Update Configuration";                     Desc = "Auto-update settings, active hours, no auto-reboot" },
        @{ ID = "9";  Key = "DiskCleanup";       Name = "Disk Cleanup & System Maintenance";               Desc = "Restore point, disk cleanup, Storage Sense off" },
        @{ ID = "10"; Key = "Winget";            Name = "Software Installation (Winget)";                  Desc = "Chrome, VLC, 7-Zip, Reader, Notepad++, etc." },
        @{ ID = "11"; Key = "FinalTouches";      Name = "Final Touches & Edge Tweaks";                      Desc = "Edge first-run, sounds, NumLock, restart Explorer" }
    )

    Write-Host ""
    Write-Host "  SELECT OPTIMIZATIONS TO RUN:" -ForegroundColor White
    Write-Host "  " + ("-" * 60) -ForegroundColor DarkGray
    foreach ($item in $menuItems) {
        Write-Host "  $($item.ID.PadRight(3)) $($item.Name)" -ForegroundColor Cyan
        Write-Host "       $($item.Desc)" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "  A    Run ALL sections (full optimization)" -ForegroundColor Green
    Write-Host "  0    Exit without changes" -ForegroundColor Red
    Write-Host ""
}

function Get-UserSelection {
    Show-Menu
    $input = Read-Host "  Enter section numbers (comma-separated, e.g. '1,3,5') or 'A' for all"

    if ($input -eq '0') {
        Write-Host "  Exiting without changes." -ForegroundColor Yellow
        Stop-Transcript | Out-Null
        exit 0
    }

    $selected = @()

    if ($input.Trim().ToUpper() -eq 'A') {
        $selected = @("Privacy", "Debloat", "ExplorerUI", "ServiceStartup",
                       "Performance", "Security", "Network", "WindowsUpdate",
                       "DiskCleanup", "Winget", "FinalTouches")
    } else {
        $numbers = $input -split ',' | ForEach-Object { $_.Trim() }
        $allSections = @{
            '1' = 'Privacy';        '2' = 'Debloat';        '3' = 'ExplorerUI'
            '4' = 'ServiceStartup'; '5' = 'Performance';  '6' = 'Security'
            '7' = 'Network';        '8' = 'WindowsUpdate';  '9' = 'DiskCleanup'
            '10' = 'Winget';        '11' = 'FinalTouches'
        }
        foreach ($num in $numbers) {
            if ($allSections.ContainsKey($num)) {
                $selected += $allSections[$num]
            } else {
                Write-Warn "Invalid selection: $num (skipped)"
            }
        }
    }

    return $selected
}

#endregion

#region ============================================================
# MAIN EXECUTION
# ============================================================

# Initialize
Initialize-Script

# Determine which sections to run
$selectedSections = @()

if ($Sections -and $Sections.Count -gt 0) {
    $selectedSections = $Sections
} elseif ($Silent) {
    # Silent mode: run everything
    $selectedSections = @("Privacy", "Debloat", "ExplorerUI", "ServiceStartup",
                          "Performance", "Security", "Network", "WindowsUpdate",
                          "DiskCleanup", "Winget", "FinalTouches")
    Write-Host "  Silent mode: running all sections." -ForegroundColor DarkGray
} else {
    $selectedSections = Get-UserSelection
}

Write-Host ""
Write-Host "  SECTIONS SELECTED:" -ForegroundColor Cyan
foreach ($s in $selectedSections) {
    Write-Host "    - $s" -ForegroundColor White
}
Write-Host ""

$startTime = Get-Date

# Execute selected sections
foreach ($section in $selectedSections) {
    switch ($section) {
        "Privacy"        { Invoke-PrivacyTweaks }
        "Debloat"        { Invoke-Debloat }
        "ExplorerUI"     { Invoke-ExplorerUI }
        "ServiceStartup" { Invoke-ServiceStartupOptimization }
        "Performance"    { Invoke-PerformanceOptimization }
        "Security"       { Invoke-SecurityHardening }
        "Network"        { Invoke-NetworkOptimizations }
        "WindowsUpdate"  { Invoke-WindowsUpdateConfig }
        "DiskCleanup"    { Invoke-DiskCleanup }
        "Winget"         { Invoke-WingetInstall }
        "FinalTouches"   { Invoke-FinalTouches }
        default {
            Write-Warn "Unknown section: $section (skipped)"
        }
    }
}

$endTime = Get-Date
$duration = $endTime - $startTime

# Summary
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  OPTIMIZATION COMPLETE" -ForegroundColor Green
Write-Host "  Duration: $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor White
Write-Host "  Sections run: $($selectedSections.Count)" -ForegroundColor White
Write-Host "  Log saved to: $LogFile" -ForegroundColor DarkGray
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# Recommend restart if we changed services, security, or performance settings
if ($selectedSections -contains "DiskCleanup" -or $selectedSections -contains "Security" `
    -or $selectedSections -contains "ServiceStartup" -or $selectedSections -contains "Performance") {
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

Stop-Transcript | Out-Null

if (-not $Silent) {
    Read-Host "Press Enter to exit"
}
