export type SafetyLevel = "Safe" | "Moderate" | "Risky";

export interface SettingDependency {
  /** Setting IDs that this setting requires to be enabled */
  requires?: string[];
  /** Setting IDs that conflict with this setting (cannot both be enabled) */
  conflicts?: string[];
  /** Human-readable conflict message */
  conflictMessage?: string;
}

export interface Setting {
  id: string;
  name: string;
  safety: SafetyLevel;
  desc: string;
  /** Dependencies and conflicts with other settings */
  deps?: SettingDependency;
}

export interface Section {
  id: string;
  name: string;
  icon: string;
  description: string;
  settings: Setting[];
}

export interface SoftwareApp {
  id: string;
  name: string;
  category: string;
  wingetId: string;
  desc: string;
}

/** Client scenario — a guided use-case that maps to a profile */
export interface ClientScenario {
  id: string;
  name: string;
  subtitle: string;
  description: string;
  /** Lucide icon name */
  icon: string;
  /** Color accent for the scenario card */
  color: string;
  /** What this scenario does (bullet points) */
  highlights: string[];
  /** What this scenario does NOT do (bullet points) */
  excludes: string[];
  /** The builtin profile ID to load when selected */
  profileId: string;
  /** Whether this scenario is recommended for first-time users */
  recommended?: boolean;
}

export const clientScenarios: ClientScenario[] = [
  {
    id: "privacy-security",
    name: "Privacy & Security Hardening",
    subtitle: "Harden the system, keep stock apps",
    description:
      "For clients who want to tighten privacy and security of Windows but are fine with all or most of the out-of-box apps. This scenario disables telemetry, hardens network and browser settings, and locks down security — without removing any pre-installed applications.",
    icon: "ShieldCheck",
    color: "#22c55e",
    highlights: [
      "Disable all Windows telemetry and tracking",
      "Harden security: DNS-over-HTTPS, disable SMBv1, enable firewall, disable LLMNR/WPAD",
      "Configure Edge and browser privacy (tracking prevention, disable suggestions)",
      "Lock down OneDrive privacy without removing it",
      "Disable Office telemetry and connected experiences",
      "Harden scheduled tasks (disable CEIP, compatibility assistant, app launch telemetry)",
      "Safe system improvements: file extensions, 24h clock, long paths, restore point",
    ],
    excludes: [
      "No bloatware removal — keeps all pre-installed apps",
      "No aggressive service disabling",
      "No OneDrive uninstall",
      "No risky settings (Error Reporting stays on for diagnostics)",
      "No performance overclocking or risky tweaks",
    ],
    profileId: "privacysecurity",
    recommended: true,
  },
  {
    id: "app-setup",
    name: "App Setup & Defender Config",
    subtitle: "Keep stock system, install apps",
    description:
      "For clients who are fine with the out-of-box Windows experience and just need installation of alternative browsers, zip software, essential utilities, plus Windows Defender configuration and browser plugin setup. Minimal system changes — just software.",
    icon: "Package",
    color: "#3b82f6",
    highlights: [
      "Install alternative browsers: Chrome, Firefox, Brave",
      "Install essential utilities: 7-Zip, Everything Search, PowerToys",
      "Install security tools: Bitwarden, VeraCrypt",
      "Install media and communication apps: VLC, Discord",
      "Configure Windows Defender and firewall (ensure active)",
      "Set Edge strict tracking prevention",
      "Show file extensions (essential for tech-savvy users)",
    ],
    excludes: [
      "No privacy hardening beyond basic Edge tracking prevention",
      "No bloatware removal",
      "No telemetry disabling",
      "No service disabling",
      "No browser hardening beyond tracking prevention",
      "No OneDrive changes (except ad notification suppression)",
    ],
    profileId: "appsetup",
  },
];

export const sections: Section[] = [
  {
    id: "Privacy",
    name: "Privacy and Telemetry",
    icon: "Shield",
    description: "Control Windows telemetry, tracking, and data collection settings",
    settings: [
      { id: "Priv_1", name: "Disable Windows telemetry", safety: "Safe", desc: "Stops Windows from sending diagnostic and usage data to Microsoft. No functional impact." },
      { id: "Priv_2", name: "Disable Cortana & Bing search", safety: "Safe", desc: "Removes Cortana and Bing web search from Start menu. Local search still works." },
      { id: "Priv_3", name: "Disable activity history", safety: "Safe", desc: "Stops Windows from tracking your activity history across devices." },
      { id: "Priv_4", name: "Disable location tracking", safety: "Moderate", desc: "Disables Windows location services. Some apps (maps, weather) may not work properly." },
      { id: "Priv_5", name: "Disable advertising ID", safety: "Safe", desc: "Removes unique advertising identifier. Reduces targeted ads across apps." },
      { id: "Priv_6", name: "Disable Clipboard cloud sync", safety: "Safe", desc: "Prevents clipboard contents from syncing to the cloud and other devices." },
      { id: "Priv_7", name: "Disable Error Reporting", safety: "Risky", desc: "Stops crash reports to Microsoft. You won't get automated solutions for crashes." },
      { id: "Priv_8", name: "Disable feedback notifications", safety: "Safe", desc: "Removes Windows Feedback Hub notifications and prompts." },
      { id: "Priv_9", name: "Disable timeline history", safety: "Safe", desc: "Prevents Windows from saving timeline activity history." },
      { id: "Priv_10", name: "Disable diagnostic data viewer", safety: "Safe", desc: "Removes the diagnostic data viewer tool and stops data collection for it." },
      { id: "Priv_11", name: "Disable telemetry in Scheduled Tasks", safety: "Safe", desc: "Disables Microsoft telemetry scheduled tasks that run in the background." },
    ],
  },
  {
    id: "Debloat",
    name: "Remove Bloatware",
    icon: "Trash2",
    description: "Remove pre-installed bloatware and unnecessary apps",
    settings: [
      { id: "Deb_1", name: "Remove sponsored apps", safety: "Safe", desc: "Uninstalls pre-installed third-party sponsored apps (Candy Crush, etc.)." },
      { id: "Deb_2", name: "Remove Windows Store apps", safety: "Moderate", desc: "Uninstalls UWP apps from the Microsoft Store. May affect Store functionality." },
      { id: "Deb_3", name: "Remove Xbox Game Bar", safety: "Moderate", desc: "Removes Xbox Game Bar and related components. Game recording won't work." },
      { id: "Deb_4", name: "Remove OneNote UWP", safety: "Safe", desc: "Uninstalls the UWP OneNote app. Desktop OneNote still works." },
      { id: "Deb_5", name: "Remove Mail & Calendar", safety: "Safe", desc: "Uninstalls the built-in Mail and Calendar UWP apps." },
      { id: "Deb_6", name: "Remove Maps app", safety: "Safe", desc: "Uninstalls the Windows Maps application." },
      { id: "Deb_7", name: "Remove People app", safety: "Safe", desc: "Uninstalls the Microsoft People contacts app." },
      { id: "Deb_8", name: "Remove Groove Music", safety: "Safe", desc: "Uninstalls the Groove Music UWP app." },
      { id: "Deb_9", name: "Remove Movies & TV", safety: "Safe", desc: "Uninstalls the Movies & TV UWP player app." },
      { id: "Deb_10", name: "Remove Paint 3D", safety: "Safe", desc: "Uninstalls the Paint 3D UWP app. Classic Paint still works." },
      { id: "Deb_11", name: "Remove 3D Viewer", safety: "Safe", desc: "Uninstalls the 3D Viewer application." },
      { id: "Deb_12", name: "Remove Skype", safety: "Safe", desc: "Uninstalls the pre-installed Skype app." },
      { id: "Deb_13", name: "Remove Microsoft Teams (personal)", safety: "Safe", desc: "Uninstalls the consumer version of Microsoft Teams." },
    ],
  },
  {
    id: "ExplorerUI",
    name: "Explorer and UI",
    icon: "FolderOpen",
    description: "Customize Windows Explorer and UI behavior",
    settings: [
      { id: "Exp_1", name: "Show file extensions", safety: "Safe", desc: "Displays file extensions for all file types in Explorer." },
      { id: "Exp_2", name: "Show hidden files", safety: "Safe", desc: "Makes hidden files and folders visible in Explorer." },
      { id: "Exp_3", name: "Disable Web Search in Start", safety: "Safe", desc: "Removes web search results from the Start menu search." },
      { id: "Exp_4", name: "Set Explorer to This PC", safety: "Safe", desc: "Opens Explorer to This PC instead of Quick Access." },
      { id: "Exp_5", name: "Disable recent files in Quick Access", safety: "Safe", desc: "Stops showing recently used files in Quick Access." },
      { id: "Exp_6", name: "Disable frequent folders in Quick Access", safety: "Safe", desc: "Stops showing frequently used folders in Quick Access." },
      { id: "Exp_7", name: "Classic context menu (Win11)", safety: "Moderate", desc: "Restores the full classic right-click context menu in Windows 11." },
      { id: "Exp_8", name: "Disable Taskbar Widgets", safety: "Safe", desc: "Removes the Widgets button from the Windows taskbar." },
      { id: "Exp_9", name: "Disable Taskbar Chat icon", safety: "Safe", desc: "Removes the Microsoft Teams Chat icon from the taskbar." },
      { id: "Exp_10", name: "Left-align Taskbar (Win11)", safety: "Safe", desc: "Moves the taskbar icons to the left like Windows 10." },
      { id: "Exp_11", name: "Disable Snap Layouts (Win11)", safety: "Safe", desc: "Removes the snap layout popup when hovering the maximize button." },
    ],
  },
  {
    id: "ServiceStartup",
    name: "Service and Startup",
    icon: "Settings",
    description: "Manage Windows services and startup programs",
    settings: [
      { id: "Svc_1", name: "Disable SysMain (Superfetch)", safety: "Moderate", desc: "Disables SysMain service. May reduce performance on HDD systems, improves SSD life." },
      { id: "Svc_2", name: "Disable Windows Search indexer", safety: "Moderate", desc: "Stops search indexing. Search will be slower but reduces disk I/O." },
      { id: "Svc_3", name: "Disable Print Spooler", safety: "Moderate", desc: "Disables print service. Only disable if you don't use a printer." },
      { id: "Svc_4", name: "Disable Fax service", safety: "Safe", desc: "Disables the legacy Fax service. Rarely needed." },
      { id: "Svc_5", name: "Disable Remote Registry", safety: "Safe", desc: "Stops remote registry access. Improves security." },
      { id: "Svc_6", name: "Disable Connected Standby", safety: "Risky", desc: "Disables connected standby power state. May affect sleep behavior." },
      { id: "Svc_7", name: "Disable biometric service", safety: "Moderate", desc: "Disables Windows Biometric Service. Windows Hello won't work." },
      { id: "Svc_8", name: "Disable diagnostic service", safety: "Safe", desc: "Stops the Diagnostic Policy Service from running." },
      { id: "Svc_9", name: "Disable DMWAPPUSERVICE", safety: "Safe", desc: "Disables the Windows Content Delivery Manager service." },
      { id: "Svc_10", name: "Disable startup delay", safety: "Safe", desc: "Removes the artificial startup delay for faster boot times." },
    ],
  },
  {
    id: "Performance",
    name: "Performance and Power",
    icon: "Zap",
    description: "Optimize system performance and power settings",
    settings: [
      { id: "Perf_1", name: "Disable visual effects", safety: "Moderate", desc: "Turns off animations, shadows, and transparency for snappier UI." },
      { id: "Perf_2", name: "Set High Performance power plan", safety: "Safe", desc: "Switches to the High Performance power plan for maximum speed." },
      { id: "Perf_3", name: "Disable power throttling", safety: "Moderate", desc: "Prevents Windows from throttling background apps. Increases power usage." },
      { id: "Perf_4", name: "Disable HPET timer", safety: "Risky", desc: "Disables High Precision Event Timer. May improve gaming latency but can cause instability." },
      { id: "Perf_5", name: "Optimize SSD", safety: "Safe", desc: "Ensures TRIM is enabled and defrag is disabled for SSDs." },
      { id: "Perf_6", name: "Disable Memory Compression", safety: "Moderate", desc: "Turns off memory compression. Can reduce latency but increases RAM usage." },
      { id: "Perf_7", name: "Disable Prefetch and Superfetch", safety: "Moderate", desc: "Disables Prefetch/Superfetch. Reduces disk I/O but may slow app launches on HDD." },
      { id: "Perf_8", name: "Reduce startup wait time", safety: "Safe", desc: "Reduces the time Windows waits for services during boot." },
      { id: "Perf_9", name: "Disable Core Isolation", safety: "Risky", desc: "Disables Memory Integrity (VBS). Improves performance but reduces security." },
      { id: "Perf_10", name: "Enable Game Mode", safety: "Safe", desc: "Turns on Windows Game Mode for optimized gaming performance." },
    ],
  },
  {
    id: "Security",
    name: "Security Hardening",
    icon: "Lock",
    description: "Strengthen Windows security and protection",
    settings: [
      { id: "Sec_1", name: "Enable BitLocker", safety: "Risky", desc: "Enables BitLocker drive encryption. Ensure you have recovery key backed up." },
      { id: "Sec_2", name: "Disable AutoRun/AutoPlay", safety: "Safe", desc: "Prevents automatic execution of programs from inserted media." },
      { id: "Sec_3", name: "Enable DNS over HTTPS", safety: "Safe", desc: "Encrypts DNS queries for better privacy and security." },
      { id: "Sec_4", name: "Disable SMBv1", safety: "Safe", desc: "Disables the insecure SMBv1 protocol. Prevents WannaCry-type exploits." },
      { id: "Sec_5", name: "Disable Remote Desktop", safety: "Moderate", desc: "Disables RDP access. You won't be able to remote into this PC." },
      { id: "Sec_6", name: "Enable Windows Firewall", safety: "Safe", desc: "Ensures Windows Firewall is active and properly configured." },
      { id: "Sec_7", name: "Disable LLMNR", safety: "Safe", desc: "Disables Link-Local Multicast Name Resolution. Reduces spoofing attacks." },
      { id: "Sec_8", name: "Disable WPAD", safety: "Safe", desc: "Disables Web Proxy Auto-Discovery. Prevents proxy hijacking." },
      { id: "Sec_9", name: "Disable NetBIOS over TCP/IP", safety: "Moderate", desc: "Disables NetBIOS over TCP/IP. May affect file sharing on local networks." },
      { id: "Sec_10", name: "Enable Credential Guard", safety: "Risky", desc: "Enables Credential Guard via virtualization. Requires compatible hardware." },
    ],
  },
  {
    id: "Network",
    name: "Network Optimization",
    icon: "Wifi",
    description: "Optimize network settings and connections",
    settings: [
      { id: "Net_1", name: "Disable Nagle's Algorithm", safety: "Moderate", desc: "Disables TCP Nagle algorithm. Reduces latency for gaming but may decrease throughput." },
      { id: "Net_2", name: "Optimize DNS settings", safety: "Safe", desc: "Configures faster DNS resolvers and enables DNS caching optimizations." },
      { id: "Net_3", name: "Disable Network Throttling", safety: "Moderate", desc: "Removes network throttling for multimedia. Improves network performance." },
      { id: "Net_4", name: "Disable Wi-Fi Sense", safety: "Safe", desc: "Stops sharing Wi-Fi passwords with contacts." },
      { id: "Net_5", name: "Disable Network Discovery", safety: "Moderate", desc: "Makes your PC invisible on the network. File sharing won't work." },
      { id: "Net_6", name: "Optimize TCP window size", safety: "Safe", desc: "Sets optimal TCP window size for better throughput." },
      { id: "Net_7", name: "Disable peer-to-peer updates", safety: "Safe", desc: "Stops Windows from using your bandwidth to share updates with other PCs." },
      { id: "Net_8", name: "Set DNS to Cloudflare", safety: "Safe", desc: "Configures DNS to use Cloudflare (1.1.1.1) for faster, private DNS." },
      { id: "Net_9", name: "Disable LLMNR protocol", safety: "Safe", desc: "Disables LLMNR name resolution protocol for security." },
      { id: "Net_10", name: "Tweak network adapter settings", safety: "Moderate", desc: "Optimizes network adapter power management and offload settings." },
    ],
  },
  {
    id: "WindowsUpdate",
    name: "Windows Update",
    icon: "RefreshCw",
    description: "Configure Windows Update behavior",
    settings: [
      { id: "WU_1", name: "Disable auto-restart for updates", safety: "Safe", desc: "Prevents Windows from automatically restarting to install updates." },
      { id: "WU_2", name: "Set active hours (8am-11pm)", safety: "Safe", desc: "Configures active hours so updates don't restart during the day." },
      { id: "WU_3", name: "Disable delivery optimization", safety: "Safe", desc: "Stops using your PC to distribute updates to other network PCs." },
      { id: "WU_4", name: "Pause updates for 5 days", safety: "Safe", desc: "Temporarily pauses Windows Update for 5 days." },
      { id: "WU_5", name: "Disable driver updates via WU", safety: "Moderate", desc: "Prevents Windows Update from automatically updating drivers." },
      { id: "WU_6", name: "Set update notification mode", safety: "Safe", desc: "Changes to notify-only mode so you choose when to install updates." },
      { id: "WU_7", name: "Disable Store auto-updates", safety: "Moderate", desc: "Stops the Microsoft Store from auto-updating installed apps." },
      { id: "WU_8", name: "Disable update restart notifications", safety: "Safe", desc: "Removes restart notifications after updates are installed." },
      { id: "WU_9", name: "Block Windows Store", safety: "Risky", desc: "Blocks access to Microsoft Store entirely. Store apps can't be installed." },
    ],
  },
  {
    id: "DiskCleanup",
    name: "Disk Cleanup",
    icon: "HardDrive",
    description: "Clean up disk space and remove temp files",
    settings: [
      { id: "Disk_1", name: "Clean temp files", safety: "Safe", desc: "Deletes temporary files from Windows and user temp folders." },
      { id: "Disk_2", name: "Clean Windows Update cache", safety: "Safe", desc: "Removes downloaded Windows Update files that are no longer needed." },
      { id: "Disk_3", name: "Clean thumbnail cache", safety: "Safe", desc: "Deletes the thumbnail cache to free up space." },
      { id: "Disk_4", name: "Clean delivery optimization", safety: "Safe", desc: "Removes delivery optimization files used for peer update distribution." },
      { id: "Disk_5", name: "Clean old Windows installation", safety: "Moderate", desc: "Removes Windows.old folder. You won't be able to rollback to previous version." },
      { id: "Disk_6", name: "Disable hibernation file", safety: "Moderate", desc: "Deletes hibernation file (hiberfil.sys). Fast startup and hibernate won't work." },
      { id: "Disk_7", name: "Clean Software Distribution", safety: "Moderate", desc: "Clears the Software Distribution folder. Pending updates will re-download." },
      { id: "Disk_8", name: "Compact OS files", safety: "Moderate", desc: "Uses compact OS to reduce Windows installation size. Slightly slower boot." },
      { id: "Disk_9", name: "Clean error reports", safety: "Safe", desc: "Deletes Windows Error Reporting files and queued reports." },
      { id: "Disk_10", name: "Clean Font cache", safety: "Safe", desc: "Clears the font cache to rebuild it. Fixes font rendering issues." },
    ],
  },
  {
    id: "Winget",
    name: "Software Install",
    icon: "Package",
    description: "Install essential software via Winget package manager",
    settings: [
      { id: "Wg_1", name: "Install 7-Zip", safety: "Safe", desc: "Installs 7-Zip file archiver for handling archive formats." },
      { id: "Wg_2", name: "Install VLC", safety: "Safe", desc: "Installs VLC media player for universal media playback." },
      { id: "Wg_3", name: "Install Notepad++", safety: "Safe", desc: "Installs Notepad++ advanced text editor." },
      { id: "Wg_4", name: "Install PowerShell 7", safety: "Safe", desc: "Installs the latest PowerShell 7 for improved scripting." },
      { id: "Wg_5", name: "Install Windows Terminal", safety: "Safe", desc: "Installs Windows Terminal for modern multi-tab terminal experience." },
      { id: "Wg_6", name: "Install Firefox", safety: "Safe", desc: "Installs Mozilla Firefox web browser." },
      { id: "Wg_7", name: "Install Chrome", safety: "Safe", desc: "Installs Google Chrome web browser." },
      { id: "Wg_8", name: "Install VSCode", safety: "Safe", desc: "Installs Visual Studio Code editor." },
      { id: "Wg_9", name: "Install Git", safety: "Safe", desc: "Installs Git version control system." },
      { id: "Wg_10", name: "Install Everything Search", safety: "Safe", desc: "Installs Voidtools Everything for instant file search." },
    ],
  },
  {
    id: "OfficeActivation",
    name: "Office 365",
    icon: "FileSpreadsheet",
    description: "Configure Microsoft Office 365 settings",
    settings: [
      { id: "Off_1", name: "Disable Office telemetry", safety: "Safe", desc: "Stops Office from sending usage and diagnostic data to Microsoft." },
      { id: "Off_2", name: "Disable Office feedback", safety: "Safe", desc: "Removes feedback prompts and telemetry in Office apps." },
      { id: "Off_3", name: "Disable Office auto-updates", safety: "Moderate", desc: "Prevents Office from automatically downloading and installing updates." },
      { id: "Off_4", name: "Disable Connected Experiences", safety: "Moderate", desc: "Disables cloud-connected features in Office. Some features won't work." },
      { id: "Off_5", name: "Disable Office analytics", safety: "Safe", desc: "Stops Office from collecting analytics on your usage patterns." },
      { id: "Off_6", name: "Set Office update channel", safety: "Moderate", desc: "Configures Office update channel to Current Channel for stable updates." },
      { id: "Off_7", name: "Disable macro security warnings", safety: "Risky", desc: "Disables macro security warnings. Increases risk of malicious macro execution." },
      { id: "Off_8", name: "Disable Office Spotlight", safety: "Safe", desc: "Removes the Spotlight feature from Office apps." },
    ],
  },
  {
    id: "EdgeHardening",
    name: "Edge Hardening",
    icon: "Globe",
    description: "Harden Microsoft Edge browser settings",
    settings: [
      { id: "Edge_1", name: "Disable Edge telemetry", safety: "Safe", desc: "Stops Edge from sending diagnostic and usage data." },
      { id: "Edge_2", name: "Disable Edge suggestions", safety: "Safe", desc: "Removes suggestions and recommendations in Edge." },
      { id: "Edge_3", name: "Block Edge shopping assistant", safety: "Safe", desc: "Disables the shopping/coupons feature in Edge." },
      { id: "Edge_4", name: "Disable Edge Collections", safety: "Safe", desc: "Removes the Collections feature from Edge." },
      { id: "Edge_5", name: "Disable Edge EdgeDefender", safety: "Moderate", desc: "Prevents Edge from running at startup and in background." },
      { id: "Edge_6", name: "Disable Edge sidebar", safety: "Safe", desc: "Removes the Edge sidebar (Copilot, etc.) from the browser." },
      { id: "Edge_7", name: "Enable strict tracking prevention", safety: "Safe", desc: "Sets Edge tracking prevention to Strict level." },
      { id: "Edge_8", name: "Disable Edge auto-fill", safety: "Moderate", desc: "Disables auto-fill for passwords and payment info. Less convenient but more private." },
      { id: "Edge_9", name: "Disable Edge startup boost", safety: "Safe", desc: "Disables Edge startup boost to reduce background resource usage." },
    ],
  },
  {
    id: "OneDrive",
    name: "OneDrive",
    icon: "Cloud",
    description: "Configure or remove Microsoft OneDrive",
    settings: [
      { id: "OD_1", name: "Uninstall OneDrive", safety: "Risky", desc: "Completely removes OneDrive. Cloud sync will stop; local files remain." },
      { id: "OD_2", name: "Disable OneDrive at startup", safety: "Safe", desc: "Prevents OneDrive from launching at Windows startup." },
      { id: "OD_3", name: "Remove OneDrive from Explorer", safety: "Moderate", desc: "Removes the OneDrive folder from File Explorer navigation pane." },
      { id: "OD_4", name: "Disable OneDrive file sync", safety: "Moderate", desc: "Pauses OneDrive file synchronization. Files stay local only." },
      { id: "OD_5", name: "Disable OneDrive ad notifications", safety: "Safe", desc: "Removes OneDrive promotional notifications." },
      { id: "OD_6", name: "Prevent OneDrive installation", safety: "Risky", desc: "Sets policy to prevent future OneDrive installations. Hard to reverse." },
      { id: "OD_7", name: "Disable OneDrive Files On-Demand", safety: "Safe", desc: "Disables Files On-Demand. All synced files will be stored locally." },
    ],
  },
  {
    id: "Gaming",
    name: "Gaming and DVR",
    icon: "Gamepad2",
    description: "Optimize gaming experience and disable DVR",
    settings: [
      { id: "Gam_1", name: "Disable Game DVR", safety: "Safe", desc: "Disables Windows Game DVR background recording. Saves CPU and disk." },
      { id: "Gam_2", name: "Disable Game Bar", safety: "Safe", desc: "Removes the Game Bar overlay. Use third-party alternatives instead." },
      { id: "Gam_3", name: "Disable Game Mode tips", safety: "Safe", desc: "Removes Game Mode tips and suggestions." },
      { id: "Gam_4", name: "Enable Game Mode", safety: "Safe", desc: "Enables Windows Game Mode to prioritize gaming processes." },
      { id: "Gam_5", name: "Disable OpenXR runtime", safety: "Moderate", desc: "Disables the Windows Mixed Reality OpenXR runtime." },
      { id: "Gam_6", name: "Optimize GPU scheduling", safety: "Moderate", desc: "Enables hardware-accelerated GPU scheduling. Requires compatible GPU." },
      { id: "Gam_7", name: "Disable Game Input", safety: "Moderate", desc: "Disables Game Input Monitoring Service. May affect some game controllers." },
      { id: "Gam_8", name: "Set power plan for gaming", safety: "Safe", desc: "Configures power settings optimized for gaming performance." },
      { id: "Gam_9", name: "Disable fullscreen optimizations", safety: "Moderate", desc: "Disables fullscreen optimizations for exclusive fullscreen mode in games." },
    ],
  },
  {
    id: "ScheduledTasks",
    name: "Scheduled Tasks",
    icon: "CalendarClock",
    description: "Manage Windows scheduled tasks",
    settings: [
      { id: "ST_1", name: "Disable CEIP tasks", safety: "Safe", desc: "Disables Customer Experience Improvement Program scheduled tasks." },
      { id: "ST_2", name: "Disable compatibility assistant", safety: "Safe", desc: "Disables the Program Compatibility Assistant scheduled task." },
      { id: "ST_3", name: "Disable consolidated messenger", safety: "Safe", desc: "Disables the Microsoft Consolidated Messenger task." },
      { id: "ST_4", name: "Disable disk diagnostics", safety: "Moderate", desc: "Disables disk diagnostic tasks. You won't get disk failure warnings." },
      { id: "ST_5", name: "Disable auto-logout", safety: "Safe", desc: "Prevents automatic logout of inactive RDP sessions." },
      { id: "ST_6", name: "Disablescheduled defrag", safety: "Moderate", desc: "Disables automatic scheduled defragmentation tasks." },
      { id: "ST_7", name: "Disable app launch telemetry", safety: "Safe", desc: "Disables Microsoft application launch telemetry tasks." },
      { id: "ST_8", name: "Disable SysReset task", safety: "Moderate", desc: "Disables the System Reset scheduled task." },
      { id: "ST_9", name: "Disable license monitoring", safety: "Safe", desc: "Disables the license monitoring scheduled task." },
    ],
  },
  {
    id: "BrowserHardening",
    name: "Browser Privacy",
    icon: "ShieldCheck",
    description: "Harden browser settings for privacy",
    settings: [
      { id: "BH_1", name: "Disable WebRTC", safety: "Moderate", desc: "Disables WebRTC in browsers. Prevents IP leaks but breaks video calls." },
      { id: "BH_2", name: "Block third-party cookies", safety: "Moderate", desc: "Blocks third-party cookies. May break some website functionality." },
      { id: "BH_3", name: "Disable browser autofill", safety: "Moderate", desc: "Disables autofill for personal data in browsers." },
      { id: "BH_4", name: "Enable HTTPS-Only mode", safety: "Safe", desc: "Forces HTTPS connections in supported browsers." },
      { id: "BH_5", name: "Disable browser telemetry", safety: "Safe", desc: "Stops all browsers from sending usage data and crash reports." },
      { id: "BH_6", name: "Disable browser experiments", safety: "Safe", desc: "Disables A/B testing and experimental features in browsers." },
      { id: "BH_7", name: "Disable browser suggestions", safety: "Safe", desc: "Removes search suggestions and URL autocomplete from browsers." },
      { id: "BH_8", name: "Clear browser data on exit", safety: "Moderate", desc: "Configures browsers to clear browsing data on exit. History won't persist." },
      { id: "BH_9", name: "Disable password saving", safety: "Moderate", desc: "Prevents browsers from saving passwords. Use a dedicated password manager." },
    ],
  },
  {
    id: "FinalTouches",
    name: "Final Touches",
    icon: "Sparkles",
    description: "Final polish and quality-of-life improvements",
    settings: [
      { id: "FT_1", name: "Set dark mode as default", safety: "Safe", desc: "Enables Windows dark mode for system and apps." },
      { id: "FT_2", name: "Set time format to 24h", safety: "Safe", desc: "Changes the system clock to 24-hour format." },
      { id: "FT_3", name: "Show seconds in taskbar clock", safety: "Safe", desc: "Displays seconds in the system tray clock." },
      { id: "FT_4", name: "Disable notification sounds", safety: "Safe", desc: "Mutes system notification sounds." },
      { id: "FT_5", name: "Set default apps", safety: "Moderate", desc: "Configures preferred default applications for common file types." },
      { id: "FT_6", name: "Create restore point", safety: "Safe", desc: "Creates a System Restore point before making changes." },
      { id: "FT_7", name: "Enable long paths", safety: "Safe", desc: "Enables NTFS long path support (over 260 characters)." },
      { id: "FT_8", name: "Disable sticky keys", safety: "Safe", desc: "Disables the Sticky Keys accessibility shortcut." },
      { id: "FT_9", name: "Set UTF-8 as default", safety: "Moderate", desc: "Sets system locale to use UTF-8 encoding. May affect legacy apps." },
      { id: "FT_10", name: "Enable GodMode folder", safety: "Safe", desc: "Creates the GodMode control panel folder on the desktop." },
    ],
  },
  {
    id: "WindowsFeatures",
    name: "Windows Features",
    icon: "Puzzle",
    description: "Enable or disable optional Windows features",
    settings: [
      { id: "WF_1", name: "Disable Hyper-V", safety: "Moderate", desc: "Disables Hyper-V virtualization. Required for some VMs but uses resources." },
      { id: "WF_2", name: "Disable WSL", safety: "Moderate", desc: "Disables Windows Subsystem for Linux. WSL distros won't run." },
      { id: "WF_3", name: "Disable SMB1 protocol", safety: "Safe", desc: "Removes the insecure SMB1/CIFS protocol from Windows." },
      { id: "WF_4", name: "Disable Internet Explorer", safety: "Safe", desc: "Removes Internet Explorer 11 from Windows." },
      { id: "WF_5", name: "Disable Windows Sandbox", safety: "Moderate", desc: "Disables Windows Sandbox. You can't run apps in isolation." },
      { id: "WF_6", name: "Enable .NET Framework 3.5", safety: "Safe", desc: "Installs .NET Framework 3.5 for legacy application compatibility." },
      { id: "WF_7", name: "Disable Print and Document Services", safety: "Moderate", desc: "Removes print and document services. Only if you don't use printers." },
      { id: "WF_8", name: "Disable Remote Differential Compression", safety: "Safe", desc: "Removes RDC feature. Saves resources if you don't use DFS replication." },
      { id: "WF_9", name: "Disable Work Folders Client", safety: "Safe", desc: "Removes Work Folders client. Not needed for personal PCs." },
      { id: "WF_10", name: "Enable Telnet Client", safety: "Moderate", desc: "Enables the Telnet client for network troubleshooting." },
      { id: "WF_11", name: "Disable Media Features", safety: "Risky", desc: "Removes Windows Media Player and media features. Breaks media playback." },
    ],
  },
];

export const softwareApps: SoftwareApp[] = [
  // Browsers
  { id: "sw_1", name: "Google Chrome", category: "Browsers", wingetId: "Google.Chrome", desc: "Fast, secure web browser by Google" },
  { id: "sw_2", name: "Mozilla Firefox", category: "Browsers", wingetId: "Mozilla.Firefox", desc: "Privacy-focused open-source browser" },
  { id: "sw_3", name: "Brave Browser", category: "Browsers", wingetId: "Brave.Brave", desc: "Privacy browser with built-in ad blocking" },
  { id: "sw_4", name: "Vivaldi", category: "Browsers", wingetId: "Vivaldi.Vivaldi", desc: "Highly customizable browser for power users" },
  // Utilities
  { id: "sw_5", name: "7-Zip", category: "Utilities", wingetId: "7zip.7zip", desc: "Free and open-source file archiver" },
  { id: "sw_6", name: "Everything Search", category: "Utilities", wingetId: "voidtools.Everything", desc: "Instant file name search utility" },
  { id: "sw_7", name: "PowerToys", category: "Utilities", wingetId: "Microsoft.PowerToys", desc: "Windows system utilities for power users" },
  { id: "sw_8", name: "ShareX", category: "Utilities", wingetId: "ShareX.ShareX", desc: "Advanced screenshot and screen capture tool" },
  { id: "sw_9", name: "FluentTerminal", category: "Utilities", wingetId: "AdrianSerioux.FluentTerminal", desc: "UWP-based terminal emulator" },
  // Dev Tools
  { id: "sw_10", name: "Visual Studio Code", category: "Dev Tools", wingetId: "Microsoft.VisualStudioCode", desc: "Lightweight but powerful code editor" },
  { id: "sw_11", name: "Git", category: "Dev Tools", wingetId: "Git.Git", desc: "Distributed version control system" },
  { id: "sw_12", name: "Windows Terminal", category: "Dev Tools", wingetId: "Microsoft.WindowsTerminal", desc: "Modern terminal application for Windows" },
  { id: "sw_13", name: "PowerShell 7", category: "Dev Tools", wingetId: "Microsoft.PowerShell", desc: "Cross-platform PowerShell for automation" },
  { id: "sw_14", name: "Node.js LTS", category: "Dev Tools", wingetId: "OpenJS.NodeJS.LTS", desc: "JavaScript runtime for server-side development" },
  { id: "sw_15", name: "Python 3", category: "Dev Tools", wingetId: "Python.Python.3.12", desc: "Python programming language interpreter" },
  { id: "sw_16", name: "Docker Desktop", category: "Dev Tools", wingetId: "Docker.DockerDesktop", desc: "Container platform for application development" },
  // Media
  { id: "sw_17", name: "VLC Media Player", category: "Media", wingetId: "VideoLAN.VLC", desc: "Universal media player for all formats" },
  { id: "sw_18", name: "Spotify", category: "Media", wingetId: "Spotify.Spotify", desc: "Digital music streaming service" },
  { id: "sw_19", name: "OBS Studio", category: "Media", wingetId: "OBSProject.OBSStudio", desc: "Open-source software for video recording and streaming" },
  { id: "sw_20", name: "Audacity", category: "Media", wingetId: "Audacity.Audacity", desc: "Free open-source audio editor and recorder" },
  // Productivity
  { id: "sw_21", name: "Notion", category: "Productivity", wingetId: "Notion.Notion", desc: "All-in-one workspace for notes and collaboration" },
  { id: "sw_22", name: "Obsidian", category: "Productivity", wingetId: "Obsidian.Obsidian", desc: "Knowledge base and note-taking app" },
  { id: "sw_23", name: "Notepad++", category: "Productivity", wingetId: "Notepad++.Notepad++", desc: "Feature-rich text and source code editor" },
  { id: "sw_24", name: "SumatraPDF", category: "Productivity", wingetId: "SumatraPDF.SumatraPDF", desc: "Lightweight PDF, EPUB, and comic reader" },
  // Communication
  { id: "sw_25", name: "Discord", category: "Communication", wingetId: "Discord.Discord", desc: "Voice, video, and text communication platform" },
  { id: "sw_26", name: "Telegram", category: "Communication", wingetId: "Telegram.TelegramDesktop", desc: "Fast, secure messaging application" },
  { id: "sw_27", name: "Signal", category: "Communication", wingetId: "OpenWhisperSystems.Signal", desc: "Private messaging with end-to-end encryption" },
  // Security
  { id: "sw_28", name: "VeraCrypt", category: "Security", wingetId: "VeraCrypt.VeraCrypt", desc: "Free disk encryption software" },
  { id: "sw_29", name: "Bitwarden", category: "Security", wingetId: "Bitwarden.Bitwarden", desc: "Open-source password manager" },
  { id: "sw_30", name: "WinSCP", category: "Security", wingetId: "WinSCP.WinSCP", desc: "SFTP and SCP client for Windows" },
];

export const softwareCategories = [
  "Browsers",
  "Utilities",
  "Dev Tools",
  "Media",
  "Productivity",
  "Communication",
  "Security",
];

export interface Profile {
  id: string;
  name: string;
  description: string;
  isBuiltin: boolean;
  settings: Record<string, boolean>;
  software: string[];
}

/**
 * Setting dependency and conflict definitions
 * Maps setting ID to its dependencies/conflicts
 */
export const settingDependencies: Record<string, SettingDependency> = {
  // Privacy
  Priv_7: { conflicts: ["Sec_8"], conflictMessage: "Disabling Error Reporting conflicts with Security Audit Logging. Both monitor system issues." },
  Priv_4: { conflicts: ["Gaming_3"], conflictMessage: "Disabling Location Tracking may break Game DVR location features." },

  // Debloat
  Deb_6: { conflicts: ["OD_1"], conflictMessage: "Removing OneDrive app conflicts with OneDrive settings. Disable OneDrive instead of removing it." },
  Deb_7: { conflicts: ["Office_1"], conflictMessage: "Removing Microsoft Office apps will conflict with Office 365 activation." },

  // Explorer/UI
  Exp_5: { requires: ["Exp_1"], conflictMessage: "Classic context menu requires Show file extensions to be enabled." },
  Exp_6: { requires: ["Exp_1"], conflictMessage: "Classic File Explorer requires Show file extensions to be enabled." },

  // Services
  Svc_1: { conflicts: ["Svc_2"], conflictMessage: "Disabling Windows Search conflicts with disabling Superfetch. Both affect search performance." },
  Svc_3: { conflicts: ["Perf_5"], conflictMessage: "Disabling Print Spooler conflicts with Performance power plan if you need printing." },

  // Performance
  Perf_1: { conflicts: ["Gaming_1"], conflictMessage: "Ultimate Performance plan may conflict with Game Mode power settings." },
  Perf_5: { conflicts: ["Svc_3"], conflictMessage: "High Performance power plan conflicts with disabling Print Spooler." },

  // Network
  Net_4: { conflicts: ["Net_7"], conflictMessage: "Disabling IPv6 may conflict with DNS-over-HTTPS which can use IPv6 resolvers." },
  Net_5: { conflicts: ["Net_8"], conflictMessage: "Disabling Network Throttling conflicts with QoS bandwidth reserve. Both manage network bandwidth." },

  // Gaming
  Gaming_1: { conflicts: ["Perf_1"], conflictMessage: "Game Mode conflicts with Ultimate Performance plan." },
  Gaming_3: { conflicts: ["Priv_4"], conflictMessage: "Game DVR features conflict with disabling Location Tracking." },

  // OneDrive
  OD_1: { conflicts: ["Deb_6"], conflictMessage: "Disabling OneDrive conflicts with removing OneDrive app. Choose one approach." },
  OD_2: { conflicts: ["Deb_6"], conflictMessage: "Preventing OneDrive auto-start conflicts with removing OneDrive. Choose one approach." },

  // Office
  Office_1: { conflicts: ["Deb_7"], conflictMessage: "Office 365 activation conflicts with removing Microsoft Office apps." },

  // Edge
  Edge_5: { conflicts: ["Edge_1"], conflictMessage: "Enabling Edge Superfetch conflicts with disabling Edge background processes." },

  // Browser
  BH_3: { requires: ["BH_1"], conflictMessage: "Strict tracking protection requires telemetry blocking to be effective." },
};

/**
 * Check for conflicts and unsatisfied dependencies given current settings state
 */
export function checkSettingConflicts(
  settingId: string,
  settingsState: Record<string, boolean>
): { type: "conflict" | "unmet_require"; settingId: string; settingName: string; message: string }[] {
  const warnings: { type: "conflict" | "unmet_require"; settingId: string; settingName: string; message: string }[] = [];
  const deps = settingDependencies[settingId];
  if (!deps) return warnings;

  // Check conflicts
  if (deps.conflicts) {
    for (const conflictId of deps.conflicts) {
      if (settingsState[conflictId]) {
        // Find the name of the conflicting setting
        let conflictName = conflictId;
        for (const section of sections) {
          const found = section.settings.find((s) => s.id === conflictId);
          if (found) { conflictName = found.name; break; }
        }
        warnings.push({
          type: "conflict",
          settingId: conflictId,
          settingName: conflictName,
          message: deps.conflictMessage || `${settingId} conflicts with ${conflictName}`,
        });
      }
    }
  }

  // Check unmet requirements (only warn when this setting is being enabled)
  if (deps.requires && settingsState[settingId]) {
    for (const reqId of deps.requires) {
      if (!settingsState[reqId]) {
        let reqName = reqId;
        for (const section of sections) {
          const found = section.settings.find((s) => s.id === reqId);
          if (found) { reqName = found.name; break; }
        }
        warnings.push({
          type: "unmet_require",
          settingId: reqId,
          settingName: reqName,
          message: deps.conflictMessage || `${settingId} requires ${reqName} to be enabled`,
        });
      }
    }
  }

  return warnings;
}

/**
 * Get all conflicts for all currently enabled settings
 */
export function getAllConflicts(
  settingsState: Record<string, boolean>
): { settingId: string; settingName: string; type: "conflict" | "unmet_require"; targetId: string; targetName: string; message: string }[] {
  const allWarnings: { settingId: string; settingName: string; type: "conflict" | "unmet_require"; targetId: string; targetName: string; message: string }[] = [];
  const seen = new Set<string>();

  for (const section of sections) {
    for (const setting of section.settings) {
      if (!settingsState[setting.id]) continue;
      const deps = settingDependencies[setting.id];
      if (!deps) continue;

      if (deps.conflicts) {
        for (const conflictId of deps.conflicts) {
          if (settingsState[conflictId]) {
            const key = [setting.id, conflictId].sort().join("|");
            if (seen.has(key)) continue;
            seen.add(key);
            let conflictName = conflictId;
            for (const s2 of sections) {
              const found = s2.settings.find((s) => s.id === conflictId);
              if (found) { conflictName = found.name; break; }
            }
            allWarnings.push({
              settingId: setting.id,
              settingName: setting.name,
              type: "conflict",
              targetId: conflictId,
              targetName: conflictName,
              message: deps.conflictMessage || `${setting.name} conflicts with ${conflictName}`,
            });
          }
        }
      }

      if (deps.requires) {
        for (const reqId of deps.requires) {
          if (!settingsState[reqId]) {
            const key = `${setting.id}|req|${reqId}`;
            if (seen.has(key)) continue;
            seen.add(key);
            let reqName = reqId;
            for (const s2 of sections) {
              const found = s2.settings.find((s) => s.id === reqId);
              if (found) { reqName = found.name; break; }
            }
            allWarnings.push({
              settingId: setting.id,
              settingName: setting.name,
              type: "unmet_require",
              targetId: reqId,
              targetName: reqName,
              message: deps.conflictMessage || `${setting.name} requires ${reqName}`,
            });
          }
        }
      }
    }
  }

  return allWarnings;
}

export const builtinProfiles: Profile[] = [
  {
    id: "gaming",
    name: "Gaming PC",
    description: "Optimized for maximum gaming performance. Disables DVR, enables Game Mode, disables unnecessary services.",
    isBuiltin: true,
    settings: {
      Priv_1: true, Priv_2: true, Priv_5: true, Priv_6: true, Priv_8: true, Priv_11: true,
      Deb_1: true, Deb_2: true, Deb_12: true, Deb_13: true,
      Exp_1: true, Exp_3: true, Exp_4: true,
      Svc_1: true, Svc_4: true, Svc_5: true, Svc_10: true,
      Perf_2: true, Perf_10: true, Perf_8: true,
      Sec_2: true, Sec_4: true, Sec_6: true,
      Net_1: true, Net_7: true, Net_3: true,
      WU_1: true, WU_2: true,
      Disk_1: true, Disk_2: true, Disk_3: true,
      Gam_1: true, Gam_2: true, Gam_4: true, Gam_6: true, Gam_8: true,
      FT_1: true, FT_6: true, FT_7: true,
    },
    software: ["sw_1", "sw_5", "sw_6", "sw_7", "sw_17", "sw_19", "sw_25", "sw_10"],
  },
  {
    id: "office",
    name: "Office Laptop",
    description: "Balanced settings for office work. Privacy improvements, stable performance, essential software.",
    isBuiltin: true,
    settings: {
      Priv_1: true, Priv_2: true, Priv_3: true, Priv_5: true, Priv_6: true, Priv_8: true, Priv_11: true,
      Deb_1: true, Deb_12: true, Deb_13: true,
      Exp_1: true, Exp_3: true, Exp_4: true,
      Svc_5: true,
      Sec_2: true, Sec_4: true, Sec_6: true, Sec_7: true, Sec_8: true,
      Net_7: true, Net_8: true,
      WU_1: true, WU_2: true,
      Disk_1: true, Disk_2: true,
      Edge_1: true, Edge_2: true, Edge_7: true,
      BH_4: true, BH_5: true,
      FT_1: true, FT_6: true,
    },
    software: ["sw_2", "sw_5", "sw_7", "sw_23", "sw_24", "sw_21", "sw_26"],
  },
  {
    id: "minimal",
    name: "Minimal",
    description: "Minimal changes. Only the safest optimizations with no risk of breaking anything.",
    isBuiltin: true,
    settings: {
      Priv_5: true, Priv_6: true, Priv_8: true,
      Deb_1: true,
      Exp_1: true,
      Sec_2: true, Sec_4: true,
      WU_1: true,
      Disk_1: true,
      FT_6: true,
    },
    software: [],
  },
  {
    id: "maxprivacy",
    name: "Maximum Privacy",
    description: "Aggressive privacy settings. May break some functionality. Maximum data protection.",
    isBuiltin: true,
    settings: {
      Priv_1: true, Priv_2: true, Priv_3: true, Priv_4: true, Priv_5: true, Priv_6: true, Priv_7: true,
      Priv_8: true, Priv_9: true, Priv_10: true, Priv_11: true,
      Deb_1: true, Deb_2: true, Deb_3: true, Deb_4: true, Deb_5: true, Deb_6: true, Deb_7: true,
      Deb_8: true, Deb_9: true, Deb_10: true, Deb_11: true, Deb_12: true, Deb_13: true,
      Exp_1: true, Exp_3: true, Exp_4: true, Exp_5: true, Exp_6: true, Exp_8: true, Exp_9: true,
      Svc_5: true, Svc_8: true, Svc_9: true,
      Sec_2: true, Sec_4: true, Sec_6: true, Sec_7: true, Sec_8: true, Sec_9: true,
      Net_4: true, Net_5: true, Net_7: true, Net_8: true, Net_9: true,
      WU_1: true, WU_3: true,
      Edge_1: true, Edge_2: true, Edge_3: true, Edge_4: true, Edge_6: true, Edge_7: true, Edge_8: true, Edge_9: true,
      BH_1: true, BH_2: true, BH_4: true, BH_5: true, BH_6: true, BH_7: true, BH_8: true, BH_9: true,
      OD_2: true, OD_3: true, OD_5: true,
      FT_1: true, FT_6: true,
    },
    software: ["sw_2", "sw_3", "sw_29", "sw_27"],
  },
  {
    id: "developer",
    name: "Developer",
    description: "Optimized for software development. Installs dev tools, enables WSL, disables telemetry.",
    isBuiltin: true,
    settings: {
      Priv_1: true, Priv_2: true, Priv_5: true, Priv_6: true, Priv_8: true,
      Deb_1: true, Deb_12: true, Deb_13: true,
      Exp_1: true, Exp_3: true, Exp_4: true, Exp_7: true,
      Svc_5: true, Svc_10: true,
      Perf_8: true,
      Sec_2: true, Sec_4: true, Sec_6: true,
      Net_7: true, Net_8: true,
      WU_1: true, WU_2: true,
      Disk_1: true,
      FT_1: true, FT_6: true, FT_7: true, FT_9: true,
    },
    software: ["sw_10", "sw_11", "sw_12", "sw_13", "sw_14", "sw_15", "sw_16", "sw_5", "sw_6", "sw_7", "sw_2", "sw_25"],
  },
  {
    id: "privacysecurity",
    name: "Privacy & Security Only",
    description: "Tighten privacy and security while keeping all default Windows apps intact. No debloat or app removal — ideal for clients who want a hardened system without changing the out-of-box experience.",
    isBuiltin: true,
    settings: {
      // Privacy — all Safe + Moderate (skip Risky Error Reporting to keep crash diagnostics)
      Priv_1: true, Priv_2: true, Priv_3: true, Priv_4: true, Priv_5: true, Priv_6: true,
      Priv_8: true, Priv_9: true, Priv_10: true, Priv_11: true,
      // NO debloat — keep all pre-installed apps
      // Explorer — minimal safe changes
      Exp_1: true, Exp_3: true,
      // Services — only security-relevant
      Svc_5: true, Svc_8: true, Svc_9: true,
      // Performance — only safe
      Perf_5: true, Perf_8: true,
      // Security — all Safe + DNS over HTTPS
      Sec_2: true, Sec_3: true, Sec_4: true, Sec_6: true, Sec_7: true, Sec_8: true,
      // Network — privacy-focused
      Net_2: true, Net_4: true, Net_7: true, Net_8: true, Net_9: true,
      // Windows Update — sane defaults
      WU_1: true, WU_2: true, WU_3: true,
      // Edge — privacy only (don't remove or disable Edge)
      Edge_1: true, Edge_2: true, Edge_3: true, Edge_6: true, Edge_7: true, Edge_9: true,
      // Browser hardening — Safe items
      BH_4: true, BH_5: true, BH_6: true, BH_7: true,
      // OneDrive — privacy only (don't uninstall)
      OD_2: true, OD_5: true,
      // Office — privacy only
      Off_1: true, Off_2: true, Off_5: true, Off_8: true,
      // Scheduled tasks — Safe privacy-relevant
      ST_1: true, ST_2: true, ST_3: true, ST_7: true, ST_9: true,
      // Final touches — safe system improvements
      FT_1: true, FT_6: true, FT_7: true,
    },
    software: ["sw_29"], // Bitwarden for password security
  },
  {
    id: "appsetup",
    name: "App Setup",
    description: "Keep the out-of-box Windows experience almost unchanged. Just install alternative browsers, essential utilities (zip, search), configure Windows Defender, and set up browser plugins. Perfect for clients who only need software and Defender configuration.",
    isBuiltin: true,
    settings: {
      // Minimal system changes — only the safest, non-disruptive ones
      Exp_1: true, // Show file extensions (essential for tech users)
      // Security — Defender-focused
      Sec_2: true, // Disable AutoRun/AutoPlay
      Sec_6: true, // Ensure Firewall is on
      // Windows Update — just active hours
      WU_2: true, // Set active hours
      // OneDrive — just stop startup nag (keep OneDrive functional)
      OD_5: true, // Disable OneDrive ad notifications
      // Edge — minimal privacy (keep Edge fully functional)
      Edge_7: true, // Strict tracking prevention
      // Final touches
      FT_6: true, // Create restore point
    },
    software: [
      // Alternative browsers
      "sw_1", // Google Chrome
      "sw_2", // Mozilla Firefox
      "sw_3", // Brave Browser
      // Essential utilities
      "sw_5", // 7-Zip
      "sw_6", // Everything Search
      "sw_7", // PowerToys
      // Security tools
      "sw_29", // Bitwarden password manager
      "sw_28", // VeraCrypt disk encryption
      // Media
      "sw_17", // VLC Media Player
      // Communication
      "sw_25", // Discord
    ],
  },
];
