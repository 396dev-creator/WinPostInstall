<#
.SYNOPSIS
    Windows Post-Installation Optimization Script v3.0
.DESCRIPTION
    Comprehensive post-install optimization for Windows 10/11.
    Supports interactive menu, fully unattended (silent), and targeted section modes.
    Designed for computer repair technicians to standardize OS setup.
.VERSION
    3.0.0
.NOTES
    Requires Administrator privileges.
    Usage:
        Interactive:  .\WinPostInstall.ps1
        Silent:       .\WinPostInstall.ps1 -Silent
        Specific:     .\WinPostInstall.ps1 -Sections Privacy,EdgeHardening,Gamedvr
#>

#region ============================================================
# PARAMETERS & CONFIGURATION
# ============================================================

[CmdletBinding()]
param(
    [switch]$Silent,
    [string[]]$Sections
)

$ScriptVersion = "3.0.0"
$LogFile = "$env:SYSTEMDRIVE\Temp\PostInstall_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

#endregion

#region ============================================================
# BOOTSTRAP: Admin check, logging, OS detection
# ============================================================

function Initialize-Script {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "[ERROR] This script must be run as Administrator." -ForegroundColor Red
        Write-Host "Right-click PowerShell and select 'Run as Administrator', then re-run this script." -ForegroundColor Yellow
        if (-not $Silent) { Read-Host "Press Enter to exit" }
        exit 1
    }

    $logDir = "$env:SYSTEMDRIVE\Temp"
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }

    Start-Transcript -Path $LogFile -Force | Out-Null

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

function Disable-ScheduledTask {
    [CmdletBinding()]
    param(
        [string]$TaskPath,
        [string]$TaskName
    )
    try {
        $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($task) {
            Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null
            Write-Success "Task disabled: $TaskPath$TaskName"
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
                    Write-Success "Removed: $($pkg.Name)"
                } catch { Write-Warn "Could not remove $($pkg.Name): $_" }
            }
        } else { $notFound++ }
    }

    # Remove provisioned packages (prevents reinstall for new users)
    Write-Step "Cleaning provisioned (stub) packages..."
    foreach ($app in $bloatwareList) {
        $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object DisplayName -like $app
        if ($prov) {
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop
                Write-Success "Removed provisioned: $($prov.DisplayName)"
            } catch { Write-Warn "Could not remove provisioned $($prov.DisplayName): $_" }
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

    # 4. Set High Performance power plan
    Write-Step "Setting High Performance power plan..."
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

    # 6. Disable SysMain
    Write-Step "Disabling SysMain (SuperFetch)..."
    try {
        $sysMain = Get-Service -Name "SysMain" -ErrorAction SilentlyContinue
        if ($sysMain) {
            Stop-Service -Name "SysMain" -Force -ErrorAction SilentlyContinue
            Set-Service -Name "SysMain" -StartupType Disabled -ErrorAction Stop
            Write-Success "SysMain disabled."
        }
    } catch { Write-Warn "Could not disable SysMain: $_" }

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

    # 1. Create System Restore point
    Write-Step "Creating System Restore point..."
    try {
        Enable-ComputerRestore -Drive "$env:SYSTEMDRIVE\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "Post-Install Optimizer v3 - Pre-optimization snapshot" `
            -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Success "System Restore point created."
    } catch { Write-Warn "Could not create Restore Point: $_" }

    # 2. Run Disk Cleanup
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

    $successCount = 0; $failCount = 0
    foreach ($app in $appList) {
        Write-Step "Installing $($app.Name)..."
        try {
            winget install --id $app.ID --silent --accept-package-agreements --accept-source-agreements `
                --ignore-security-hash --disable-interactivity 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Success "Installed: $($app.Name)"; $successCount++ }
            else { Write-Warn "Exit code $LASTEXITCODE for $($app.Name)"; $failCount++ }
        } catch { Write-Warn "Failed: $($app.Name): $_"; $failCount++ }
    }

    Write-Host ""
    Write-Success "Software install complete. Success: $successCount | Issues: $failCount"
}

#endregion

#region ============================================================
# SECTION 11: EDGE HARDENING
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
# SECTION 12: ONEDRIVE MANAGEMENT
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
# SECTION 13: GAMING / XBOX / DVR DISABLE
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
# SECTION 14: SCHEDULED TASKS CLEANUP
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
# SECTION 15: FINAL TOUCHES
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
        @{ ID = "11"; Key = "EdgeHardening";         Name = "Edge Hardening (14 policies)";             Desc = "Shopping, Copilot, telemetry, preload, sync" },
        @{ ID = "12"; Key = "OneDrive";              Name = "OneDrive Management";                      Desc = "Disable sync, hide from Explorer, remove startup" },
        @{ ID = "13"; Key = "Gaming";                Name = "Gaming / Xbox / DVR Disable";              Desc = "GameDVR, Game Bar capture, Xbox overlay" },
        @{ ID = "14"; Key = "ScheduledTasks";         Name = "Scheduled Tasks Cleanup (33+ tasks)";      Desc = "Telemetry, CEIP, Office, Xbox, Maps, diagnostics" },
        @{ ID = "15"; Key = "FinalTouches";           Name = "Final Touches";                            Desc = "Edge first-run, sound, NumLock, mouse accel, Explorer" }
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
    $input = Read-Host "  Enter section numbers (comma-separated, e.g. '1,3,5') or 'A' for all"

    if ($input -eq '0') {
        Write-Host "  Exiting without changes." -ForegroundColor Yellow
        Stop-Transcript | Out-Null
        exit 0
    }

    $selected = @()
    if ($input.Trim().ToUpper() -eq 'A') {
        $selected = @("Privacy","Debloat","ExplorerUI","ServiceStartup","Performance",
                      "Security","Network","WindowsUpdate","DiskCleanup","Winget",
                      "EdgeHardening","OneDrive","Gaming","ScheduledTasks","FinalTouches")
    } else {
        $numbers = $input -split ',' | ForEach-Object { $_.Trim() }
        $allSections = @{
            '1'='Privacy';'2'='Debloat';'3'='ExplorerUI';'4'='ServiceStartup'
            '5'='Performance';'6'='Security';'7'='Network';'8'='WindowsUpdate'
            '9'='DiskCleanup';'10'='Winget';'11'='EdgeHardening';'12'='OneDrive'
            '13'='Gaming';'14'='ScheduledTasks';'15'='FinalTouches'
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

Initialize-Script

$selectedSections = @()
if ($Sections -and $Sections.Count -gt 0) {
    $selectedSections = $Sections
} elseif ($Silent) {
    $selectedSections = @("Privacy","Debloat","ExplorerUI","ServiceStartup","Performance",
                          "Security","Network","WindowsUpdate","DiskCleanup","Winget",
                          "EdgeHardening","OneDrive","Gaming","ScheduledTasks","FinalTouches")
    Write-Host "  Silent mode: running all sections." -ForegroundColor DarkGray
} else {
    $selectedSections = Get-UserSelection
}

Write-Host ""
Write-Host "  SECTIONS SELECTED:" -ForegroundColor Cyan
foreach ($s in $selectedSections) { Write-Host "    - $s" -ForegroundColor White }
Write-Host ""

$startTime = Get-Date

foreach ($section in $selectedSections) {
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
        "EdgeHardening"     { Invoke-EdgeHardening }
        "OneDrive"          { Invoke-OneDriveManagement }
        "Gaming"            { Invoke-GamingDisable }
        "ScheduledTasks"    { Invoke-ScheduledTasksCleanup }
        "FinalTouches"      { Invoke-FinalTouches }
        default { Write-Warn "Unknown section: $section (skipped)" }
    }
}

$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  OPTIMIZATION COMPLETE" -ForegroundColor Green
Write-Host "  Duration: $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor White
Write-Host "  Sections run: $($selectedSections.Count)" -ForegroundColor White
Write-Host "  Log saved to: $LogFile" -ForegroundColor DarkGray
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

if ($selectedSections -intersect @("DiskCleanup","Security","ServiceStartup","Performance","ScheduledTasks","Gaming")) {
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
if (-not $Silent) { Read-Host "Press Enter to exit" }

#endregion
