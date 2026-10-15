#!/usr/bin/env python3
"""
Annotate all Set-Registry and Disable-ScheduledTask calls in WinPostInstall.ps1
that are missing -SafetyLevel, -Description, -SettingID parameters.
"""
import re
import sys

INPUT_FILE = "/home/z/my-project/scripts/WinPostInstall.ps1"

with open(INPUT_FILE, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Track current section
current_section = ""

# Join continuation lines to identify logical lines
i = 0
logical = []
while i < len(lines):
    line = lines[i].rstrip('\n')
    start = i
    parts = []
    phys = [i]
    while True:
        stripped = line.rstrip()
        if stripped.endswith('`'):
            parts.append(stripped[:-1])
            i += 1
            if i >= len(lines):
                break
            line = lines[i].rstrip('\n')
            phys.append(i)
        else:
            parts.append(stripped)
            break
    content = ' '.join(parts)
    logical.append((start, phys, content))
    i += 1

# Build annotation map: line_number -> annotation_text_to_append
annotations = {}

# Counter for unique IDs when in loops
id_counter = {}

def make_id(section, base):
    key = f"{section}_{base}"
    if key in id_counter:
        id_counter[key] += 1
        return f"{key}_{id_counter[key]}"
    else:
        id_counter[key] = 1
        return key

def classify_sr(section, path, name, value, line_num):
    """Return (SafetyLevel, Description, SettingID) for a Set-Registry call."""
    pl = (path or "").lower()
    nl = (name or "").lower()
    sec = section or "Unknown"
    
    # =========================================================
    # PRIVACY SECTION  
    # =========================================================
    if 'appcompat' in pl:
        if 'aitenable' in nl: return ("Safe", "Disables Application Impact Telemetry — stops app compat data collection", f"{sec}_AITEnable")
        if 'disableinventory' in nl: return ("Safe", "Disables app compatibility inventory — stops hardware/software inventory", f"{sec}_DisableInventory")
        if 'disableuar' in nl: return ("Safe", "Disables User App Compatibility Reporter — stops compat data uploads", f"{sec}_DisableUAR")
        if 'disablepca' in nl: return ("Safe", "Disables Program Compatibility Assistant — stops compatibility telemetry", f"{sec}_DisablePCA")
    
    if 'ceipenable' in nl: return ("Safe", "Disables Customer Experience Improvement Program — stops CEIP data collection", f"{sec}_CEIPEnable")
    
    if 'tailoredexperiences' in nl.lower() or 'disabletailoredexperiences' in nl: 
        return ("Safe", "Disables tailored experiences with diagnostic data — stops personalized ads/tips", f"{sec}_NoTailoredExp")
    
    if 'compatelrunner' in pl or 'image file execution options' in pl:
        return ("Safe", "Kills CompatTelRunner.exe via IFEO — blocks telemetry compatibility runner", f"{sec}_KillCompatTelRunner")
    
    # Activity History (EnableActivityFeed, PublishUserActivities, UploadUserActivities)
    if 'enableactivityfeed' in nl: return ("Safe", "Disables Activity Feed — stops Windows from tracking activity history", f"{sec}_NoActivityFeed")
    if 'publishuseractivities' in nl: return ("Safe", "Prevents publishing user activities to timeline/cloud", f"{sec}_NoPublishActivities2")
    if 'uploaduseractivities' in nl: return ("Safe", "Prevents uploading activity history to Microsoft cloud", f"{sec}_NoUploadActivities2")
    
    # Location
    if 'consentstore\\location' in pl or 'lfsvc' in pl:
        return ("Moderate", "Disables geolocation service — breaks Find My Device and Maps location", f"{sec}_NoGeolocation")
    
    # Advertising ID
    if 'advertisinginfo' in pl:
        if 'disabledbygrouppolicy' in nl: return ("Safe", "Removes advertising ID via group policy — stops targeted advertising", f"{sec}_AdvIDPolicy2")
        if 'enabled' in nl: return ("Safe", "Disables advertising ID in current user scope", f"{sec}_AdvIDUser2")
    
    # Windows Search / Cortana policies
    if 'windows search' in pl and 'policies' in pl:
        if 'allowcortana' in nl: return ("Safe", "Disables Cortana digital assistant and web search in Start", f"{sec}_NoCortana2")
        if 'allowsearchtouselocation' in nl: return ("Safe", "Prevents search from using location data", f"{sec}_NoSearchLocation")
        if 'allowcloudsearch' in nl: return ("Safe", "Disables cloud search integration", f"{sec}_NoCloudSearch")
        if 'disablewebsearch' in nl: return ("Safe", "Stops Start menu from using Bing web search", f"{sec}_DisableWebSearch2")
        if 'connectedsearchuseweb' in nl: return ("Safe", "Blocks Cortana from using web for search results", f"{sec}_NoConnectedSearch2")
    
    if 'windowsstore' in pl and 'disablewindowsstorerealtimeconfig' in nl:
        return ("Safe", "Disables Windows Store real-time configuration — reduces Store telemetry", f"{sec}_NoStoreRealTime")
    
    if 'bingsearchenabled' in nl: return ("Safe", "Disables Bing search in Start Menu — stops web search results", f"{sec}_NoBingSearch")
    if 'cortanaconsent' in nl: return ("Safe", "Revokes Cortana consent — stops Cortana data collection", f"{sec}_NoCortanaConsent")
    
    # Copilot
    if 'windowscopilot' in pl: return ("Safe", "Disables Windows Copilot AI assistant", f"{sec}_NoCopilot2")
    if 'showcopilotbutton' in nl: return ("Safe", "Hides Copilot button from taskbar", f"{sec}_HideCopilotBtn2")
    
    # Windows AI / Recall
    if 'windowsai' in pl:
        if 'allowrecallenablement' in nl: return ("Safe", "Disables Windows Recall AI memory/timeline feature", f"{sec}_NoRecall2")
        if 'disableaidataanalysis' in nl: return ("Safe", "Disables AI data analysis — stops AI telemetry collection", f"{sec}_NoAIDataAnalysis")
        if 'disableclicktodo' in nl: return ("Safe", "Disables Click-to-Do AI feature — stops AI suggestions", f"{sec}_NoClickToDo")
        if 'disableimagecreator' in nl: return ("Safe", "Disables AI Image Creator — stops AI image generation telemetry", f"{sec}_NoImageCreator")
        if 'disablecocreator' in nl: return ("Safe", "Disables AI Cocreator — stops AI co-creation telemetry", f"{sec}_NoCocreator")
        if 'disablegenerativefill' in nl: return ("Safe", "Disables AI Generative Fill — stops AI fill telemetry", f"{sec}_NoGenerativeFill")
        # Variable name in loop
        return ("Safe", "Disables Windows AI feature — stops AI data collection", f"{sec}_AI_{make_id(sec,'AIFeature')}")
    
    # Paint Studio AI
    if 'paintstudio' in pl: return ("Safe", "Disables AI feature in Paint — stops AI telemetry", f"{sec}_NoPaintAI_{make_id(sec,'PaintAI')}")
    
    # Clipboard
    if 'allowclipboardhistory' in nl: return ("Safe", "Disables clipboard history (Win+V)", f"{sec}_NoClipHistory2")
    if 'allowcrossdeviceclipboard' in nl: return ("Safe", "Disables cloud clipboard sync across devices", f"{sec}_NoClipSync2")
    
    # Input telemetry
    if 'restrictimplicittextcollection' in nl: return ("Safe", "Restricts implicit text collection — stops typing telemetry", f"{sec}_NoImplicitText")
    if 'restrictimplicitinkcollection' in nl: return ("Safe", "Restricts implicit ink collection — stops inking telemetry", f"{sec}_NoImplicitInk")
    if 'harvestcontacts' in nl: return ("Safe", "Disables contact harvesting for typing suggestions — stops contact data collection", f"{sec}_NoHarvestContacts")
    
    # Feedback
    if 'numberofsiufinperiod' in nl: return ("Safe", "Disables feedback notifications — stops Feedback Hub prompts", f"{sec}_NoFeedbackNotif")
    
    # Targeted tips
    if 'start_trackprogs' in nl: return ("Safe", "Disables tracking of most-used programs in Start — stops usage telemetry", f"{sec}_NoTrackProgs")
    if 'start_trackdocs' in nl: return ("Safe", "Disables tracking of recently opened documents in Start — stops usage telemetry", f"{sec}_NoTrackDocs")
    if 'disablesoftlanding' in nl: return ("Safe", "Disables Windows soft landing tips — stops suggestion telemetry", f"{sec}_NoSoftLanding")
    if 'disablewindowsconsumerfeatures' in nl: return ("Safe", "Disables Windows consumer features — stops Store suggestions/ads", f"{sec}_NoConsumerFeatures2")
    
    # Wi-Fi Sense
    if 'wifi' in pl or 'wifinetworkmanager' in pl or 'wcmvc' in pl:
        return ("Safe", "Disables Wi-Fi Sense — stops sharing Wi-Fi passwords with contacts", f"{sec}_NoWiFiSense_{make_id(sec,'WiFi')}")
    
    # Error Reporting  
    if 'windows error reporting' in pl and 'policies' in pl:
        if 'disabled' in nl: return ("Moderate", "Stops Windows Error Reporting — makes troubleshooting harder", f"{sec}_NoWER2")
    
    # Insider experiments
    if 'previewbuilds' in pl: return ("Moderate", "Disables Windows Insider experiments — stops A/B testing and flighting", f"{sec}_NoInsiderExperiments_{make_id(sec,'Insider')}")
    
    # Setting Sync
    if 'settingsync' in pl:
        if 'disablesettingsync' in nl: return ("Moderate", "Disables Setting Sync — stops cloud settings sync", f"{sec}_NoSettingSync")
        if 'disablesettingsyncuseroverride' in nl: return ("Moderate", "Prevents user override of Setting Sync disable — enforces policy", f"{sec}_NoSettingSyncOverride")
    
    # DataCollection (telemetry)
    if 'datacollection' in pl:
        if 'allowtelemetry' in nl: return ("Safe", "Stops Windows from sending telemetry and diagnostic data to Microsoft", f"{sec}_AllowTelemetry3")
        if 'donotshowfeedbacknotifications' in nl: return ("Safe", "Removes Feedback Hub notifications and prompts", f"{sec}_NoFeedback2")
        if 'enablediagnosticdataviewer' in nl: return ("Safe", "Disables Diagnostic Data Viewer — removes data viewer feature", f"{sec}_NoDiagDataViewer")
        if 'limitdiagnosticlogcollection' in nl: return ("Safe", "Limits diagnostic log collection to critical events only", f"{sec}_LimitDiagLog2")
        if 'limitdumpcollection' in nl: return ("Safe", "Limits crash dump collection to reduce data sent to Microsoft", f"{sec}_LimitDump2")
        if 'fulltelemetryoninstall' in nl: return ("Safe", "Disables full telemetry on install — stops initial data collection burst", f"{sec}_NoFullTelemetryInstall")
        if 'allowupdatecompliancetelemetry' in nl: return ("Safe", "Disables Update Compliance telemetry — stops WU data reporting", f"{sec}_NoUpdateComplianceTelemetry")
    
    # CloudContent
    if 'cloudcontent' in pl:
        if 'disabletailoredexperiences' in nl: return ("Safe", "Disables tailored experiences — stops personalized suggestions", f"{sec}_NoTailoredExp2")
        if 'disablecloudoptimizedcontent' in nl: return ("Safe", "Disables cloud-optimized content — stops personalized suggestions", f"{sec}_NoCloudContent")
        if 'disablethirdpartysuggestions' in nl: return ("Safe", "Disables third-party suggestions in Windows — stops third-party ads", f"{sec}_No3rdPartySuggestions")
        if 'disablewindowsconsumerfeatures' in nl: return ("Safe", "Disables Windows consumer features — stops Store suggestions/ads", f"{sec}_NoConsumerFeatures3")
        if 'disablesoftlanding' in nl: return ("Safe", "Disables soft landing tips — stops suggestion telemetry", f"{sec}_NoSoftLanding2")
    
    # Device Census
    if 'disabledevicecensus' in nl: return ("Safe", "Disables Device Census — stops hardware inventory reporting to Microsoft", f"{sec}_NoDeviceCensus")
    
    # SQMClient / CEIP
    if 'sqmclient' in pl: return ("Safe", "Disables SQM/CEIP telemetry — stops Customer Experience data collection", f"{sec}_NoSQM_{make_id(sec,'SQM')}")
    
    # AppHost
    if 'apphost' in pl and 'enablewebcontentevaluation' in nl: return ("Safe", "Disables web content evaluation — stops app telemetry", f"{sec}_NoWebContentEval")
    
    # Background apps
    if 'globaluserdisabled' in nl: return ("Safe", "Disables background app access globally — stops apps running in background", f"{sec}_NoBackgroundApps")
    if 'letappsgetdiagnosticinfo' in nl: return ("Safe", "Denies apps access to diagnostic info — stops app diagnostics data sharing", f"{sec}_NoAppDiagInfo")
    if 'letappsaccessactivityhistory' in nl: return ("Safe", "Denies apps access to activity history — stops app activity tracking", f"{sec}_NoAppActivityHist")
    
    # ContentDeliveryManager
    if 'contentdeliverymanager' in pl:
        if 'subscribedcontent-338389' in nl: return ("Safe", "Disables Windows Spotlight suggestions — stops lock screen tips/ads", f"{sec}_NoSpotlight338389")
        if 'subscribedcontent-310093' in nl: return ("Safe", "Disables 'Get even more out of Windows' tips — stops suggestion prompts", f"{sec}_NoTips310093")
        if 'contentdeliveryenabled' in nl: return ("Safe", "Disables content delivery — stops silent app installs and suggestions", f"{sec}_NoContentDelivery")
        if 'subscribedcontent-338387' in nl: return ("Safe", "Disables suggested content in Settings — stops Settings suggestions", f"{sec}_NoSuggestedContent338387")
        if 'subscribedcontent-338388' in nl: return ("Safe", "Disables suggested content (tips) — stops tips/suggestions", f"{sec}_NoSuggestedContent338388")
        if 'rotatinglockscreenenabled' in nl: return ("Safe", "Disables rotating lock screen images — stops Windows Spotlight ads", f"{sec}_NoRotatingLockScreen2")
        if 'rotatinglockscreenoverlayenabled' in nl: return ("Safe", "Disables lock screen overlay — stops Windows Spotlight tips/ads", f"{sec}_NoLockScreenOverlay2")
        # Generic CDM
        return ("Safe", "Disables content delivery manager setting — stops suggestions/silent installs", f"{sec}_CDM_{make_id(sec,'CDM')}")
    
    # AutoLogger
    if 'autologger-diagtrack' in pl: return ("Safe", "Disables AutoLogger DiagTrack listener — stops kernel telemetry logging", f"{sec}_NoDiagtrackListener")
    
    # NCSI
    if 'networkconnectivitystatusindicator' in pl and 'noactiveprobe' in nl:
        return ("Safe", "Disables NCSI active probing — stops network connectivity telemetry", f"{sec}_NoNCSIProbe2")
    
    # UserProfile
    if 'disableuserprofiletelemetry' in nl: return ("Safe", "Disables User Profile service telemetry — stops profile data collection", f"{sec}_NoUserProfileTelemetry")
    
    # Notifications
    if 'notifications\\settings' in pl: return ("Safe", "Disables lock screen toast notifications — stops lock screen notification display", f"{sec}_NoLockScreenNotif")
    
    # =========================================================
    # EXPLORER UI SECTION
    # =========================================================
    if 'hidefileext' in nl: return ("Safe", "Shows file extensions — prevents accidental execution of disguised files", f"{sec}_ShowFileExt")
    if nl == 'hidden': return ("Safe", "Shows hidden files — improves visibility of system files", f"{sec}_ShowHiddenFiles")
    if '(default)' in nl or '"(default)"' in nl:
        if 'inprocserver32' in pl: return ("Safe", "Enables classic right-click context menu — removes Win11 simplified menu", f"{sec}_ClassicContextMenu")
        if 'appevents' in pl: return ("Safe", "Sets sound scheme to No Sounds — disables all system sounds", f"{sec}_NoSounds")
    if 'showsyncprovidernotifications' in nl: return ("Safe", "Disables File Explorer ads — removes OneDrive ads in Explorer", f"{sec}_NoExplorerAds")
    if 'nolockscreen' in nl: return ("Safe", "Disables Lock Screen — goes directly to login screen", f"{sec}_NoLockScreen")
    if 'rotatinglockscreenenabled' in nl and sec == "ExplorerUI": return ("Safe", "Disables rotating lock screen images — stops Windows Spotlight ads", f"{sec}_NoRotatingLockScreen")
    if 'rotatinglockscreenoverlayenabled' in nl and sec == "ExplorerUI": return ("Safe", "Disables lock screen overlay — stops Windows Spotlight tips/ads", f"{sec}_NoLockScreenOverlay")
    if 'disablewindowsconsumerfeatures' in nl and sec == "ExplorerUI": return ("Safe", "Disables Windows consumer features — stops Store suggestions/ads", f"{sec}_NoConsumerFeatures")
    if 'taskbarmn' in nl: return ("Safe", "Removes Chat icon from Taskbar — hides Microsoft Chat/Teams", f"{sec}_NoChatIcon")
    if 'taskbarda' in nl: return ("Safe", "Removes Widgets from Taskbar — hides news/weather widget", f"{sec}_NoWidgets")
    if 'taskbarsearchbox' in nl: return ("Safe", "Removes Search box from Taskbar — simplifies taskbar", f"{sec}_NoSearchBox")
    if 'enablesnapassistflyout' in nl: return ("Safe", "Disables Snap Layouts flyout — removes snap layout suggestions", f"{sec}_NoSnapAssist")
    if 'taskbarendtask' in nl: return ("Safe", "Enables 'End Task' in Taskbar right-click — adds quick task kill option", f"{sec}_TaskbarEndTask")
    if 'launchto' in nl: return ("Safe", "Sets File Explorer to open This PC instead of Quick Access", f"{sec}_OpenThisPC")
    if 'dragbetweenwindows' in nl: return ("Safe", "Disables Drag Tray — removes Win11 share/move files tray", f"{sec}_NoDragTray")
    if 'showtaskviewbutton' in nl: return ("Safe", "Removes Task View button from Taskbar — hides virtual desktops UI", f"{sec}_NoTaskView")
    if 'searchboxtaskbarmode' in nl: return ("Safe", "Sets Search bar to icon-only mode — simplifies taskbar", f"{sec}_SearchIconOnly")
    if 'showcopilotbutton' in nl and sec == "ExplorerUI": return ("Safe", "Hides Copilot button from Taskbar", f"{sec}_HideCopilotBtn")
    
    # =========================================================
    # SERVICE STARTUP SECTION
    # =========================================================
    if 'startupdelayinmsec' in nl: return ("Safe", "Disables startup delay — speeds up boot by removing artificial delay", f"{sec}_NoStartupDelay")
    
    # =========================================================
    # PERFORMANCE SECTION
    # =========================================================
    if 'hiberbootenabled' in nl: return ("Safe", "Disables Fast Startup — prevents partial shutdown/driver issues", f"{sec}_NoFastStartup2")
    if 'modernsleep' in nl: return ("Safe", "Disables Modern Standby network — prevents battery drain during sleep", f"{sec}_NoModernSleep2")
    if 'visualfxsetting' in nl: return ("Safe", "Sets visual effects to Best Performance mode", f"{sec}_VisualFX2")
    if 'enableaeropeek' in nl: return ("Safe", "Disables Aero Peek — removes desktop preview on taskbar hover", f"{sec}_NoAeroPeek")
    if 'enableprefetcher' in nl: return ("Safe", "Disables Prefetch on SSD — safe, reduces unnecessary disk I/O", f"{sec}_NoPrefetch_SSD2")
    if 'enablesuperfetch' in nl: return ("Safe", "Disables SuperFetch on SSD — safe, reduces unnecessary disk I/O", f"{sec}_NoSuperfetch_SSD2")
    if 'excludedprocesses' in nl: return ("Safe", "Clears Defender excluded processes — maintains scan coverage", f"{sec}_DefenderNoExclusions")
    if 'avgcpuloadfactor' in nl: return ("Safe", "Limits Windows Defender CPU usage to 25% — reduces scan impact", f"{sec}_DefenderCPULimit")
    if 'svchostsplitthresholdinkb' in nl: return ("Safe", "Increases SvcHost split threshold — reduces svchost.exe proliferation", f"{sec}_SvcHostSplit")
    if 'pagingfiles' in nl: return ("Moderate", "Sets page file to fixed 1GB — OK with 16GB+ RAM", f"{sec}_FixedPageFile2")
    
    # Visual FX in Control Panel\Desktop (loop with variables)
    if 'control panel\\desktop' in pl:
        return ("Safe", "Disables visual animation — improves performance", f"{sec}_VisFX_{make_id(sec,'VisFX')}")
    
    # =========================================================
    # SECURITY SECTION
    # =========================================================
    if 'windows defender' in pl and 'real-time protection' in pl:
        return ("Safe", "Ensures Defender real-time protection stays enabled — maintains security", f"{sec}_DefenderRT_{make_id(sec,'DefRT')}")
    if 'enableautodoh' in nl and sec == "Security": return ("Safe", "Enables DNS-over-HTTPS — encrypts DNS queries for privacy", f"{sec}_EnableDoH")
    if 'nodrivetypeautorun' in nl: return ("Safe", "Disables USB auto-run — prevents malware from auto-executing on USB", f"{sec}_NoAutoRun")
    if 'fdenytsconnections' in nl: return ("Safe", "Disables Remote Desktop — reduces attack surface", f"{sec}_NoRDP")
    if 'enablelua' in nl: return ("Safe", "Ensures UAC is enabled — maintains admin consent prompts", f"{sec}_UAC_Enabled")
    if 'consentpromptbehavioradmin' in nl: return ("Safe", "Sets UAC to prompt for consent — secure admin elevation behavior", f"{sec}_UAC_Consent")
    if 'disablepasswordreveal' in nl: return ("Safe", "Disables password reveal button — prevents password visibility", f"{sec}_NoPasswordReveal")
    
    # =========================================================
    # NETWORK SECTION
    # =========================================================
    if 'networkthrottlingindex' in nl: return ("Safe", "Disables network throttling — improves network throughput for gaming/streams", f"{sec}_NoNetThrottle")
    if 'nolazymode' in nl: return ("Safe", "Disables network lazy mode — reduces latency", f"{sec}_NoLazyMode")
    if 'tcpackfrequency' in nl: return ("Safe", "Disables Nagle Algorithm — reduces TCP latency for gaming", f"{sec}_NoNagle")
    if 'tcpnodelay' in nl: return ("Safe", "Disables Nagle Algorithm via TcpNoDelay — reduces TCP latency", f"{sec}_TcpNoDelay")
    if 'teredo_state' in nl: return ("Safe", "Disables Teredo IPv6 transition — reduces attack surface", f"{sec}_NoTeredo")
    if 'enabledoh' in nl: return ("Safe", "Enables DNS-over-HTTPS via policy — encrypts DNS queries", f"{sec}_EnableDoH_Policy")
    if 'noactiveprobe' in nl and sec == "Network": return ("Safe", "Disables NCSI active probing — stops network connectivity telemetry", f"{sec}_NoNCSIProbe")
    if 'dnscache' in pl and 'parameters' in pl and 'enableautodoh' in nl:
        return ("Safe", "Enables DNS-over-HTTPS — encrypts DNS queries for privacy", f"{sec}_EnableDoH2")
    # Nagle loop (variables)
    if 'tcpip\\parameters\\interfaces' in pl:
        return ("Safe", "Disables Nagle Algorithm on network interface — reduces latency", f"{sec}_NoNagle_{make_id(sec,'Nagle')}")
    
    # =========================================================
    # WINDOWS UPDATE SECTION
    # =========================================================
    if 'auoptions' in nl: return ("Safe", "Sets WU to auto-download and notify — prevents automatic install", f"{sec}_WU_NotifyOnly")
    if 'noautorebootwithloggedonusers' in nl: return ("Safe", "Prevents auto-reboot after updates when users are logged in", f"{sec}_WU_NoAutoReboot")
    if 'dodownloadmode' in nl: return ("Safe", "Disables Delivery Optimization — stops peer-to-peer update sharing", f"{sec}_NoDeliveryOpt")
    if 'excludewudriversinqualityupdate' in nl: return ("Safe", "Excludes drivers from quality updates — prevents driver issues", f"{sec}_WU_NoDriverUpdates")
    if 'activehoursstart' in nl: return ("Safe", "Sets active hours start to 09:00 — prevents reboots during work", f"{sec}_WU_ActiveHrsStart")
    if 'activehoursend' in nl: return ("Safe", "Sets active hours end to 21:00 — prevents reboots during work", f"{sec}_WU_ActiveHrsEnd")
    if 'donotconnecttowindowsupdateinternetlocations' in nl: return ("Safe", "Configures WU internet locations — standard WU policy", f"{sec}_WU_InternetConfig")
    if 'searchorderconfig' in nl: return ("Safe", "Prevents automatic driver search via Windows Update", f"{sec}_WU_NoAutoDriverSearch")
    
    # =========================================================
    # DISK CLEANUP SECTION
    # =========================================================
    if 'stateflags0001' in nl: return ("Safe", "Configures Disk Cleanup state flags — enables automated cleanup", f"{sec}_DiskCleanupFlags_{make_id(sec,'DC')}")
    if 'allowstoragesenseglobal' in nl: return ("Safe", "Disables Storage Sense — prevents automatic file deletion", f"{sec}_NoStorageSense")
    
    # =========================================================
    # OFFICE ACTIVATION SECTION (Office telemetry)
    # =========================================================
    if sec == "OfficeActivation":
        return ("Safe", "Disables Office telemetry/data collection — stops Office data sharing with Microsoft", f"{sec}_Office_{make_id(sec,'Office')}")
    
    # =========================================================
    # EDGE HARDENING SECTION
    # =========================================================
    if sec == "EdgeHardening":
        if 'edge' in pl or 'microsoftedge' in pl:
            if 'allowprelaunch' in nl: return ("Safe", "Disables Edge prelaunch — prevents Edge running in background at startup", f"{sec}_NoEdgePrelaunch")
            if 'allowtabpreloading' in nl: return ("Safe", "Disables Edge tab preloading — reduces background resource usage", f"{sec}_NoEdgeTabPreload")
            if 'disallowfirstrun' in nl: return ("Safe", "Disables Edge first-run experience — prevents Edge welcome screen", f"{sec}_NoEdgeFirstRun2")
            # Loop with variables
            return ("Safe", "Hardens Edge browser privacy/security — reduces Edge data collection", f"{sec}_Edge_{make_id(sec,'Edge')}")
    
    # =========================================================
    # ONEDRIVE SECTION
    # =========================================================
    if 'disablefilesyncngsc' in nl: return ("Safe", "Disables OneDrive file sync via Group Policy — prevents OneDrive integration", f"{sec}_DisableOneDrive")
    if 'system.ispinnedtonamespacetree' in nl: return ("Safe", "Hides OneDrive from File Explorer navigation pane", f"{sec}_HideOneDriveNav")
    
    # =========================================================
    # GAMING SECTION
    # =========================================================
    if 'allowgamedvr' in nl: return ("Safe", "Disables GameDVR via policy — stops game clip recording", f"{sec}_NoGameDVR")
    if 'appcaptureenabled' in nl: return ("Safe", "Disables Game Bar capture — stops background game recording", f"{sec}_NoGameBarCapture")
    if 'historicalcaptureenabled' in nl: return ("Safe", "Disables Game Bar historical capture — stops background recording", f"{sec}_NoHistoricalCapture")
    if 'gamedvr_enabled' in nl: return ("Safe", "Disables GameDVR — stops game recording and broadcasting", f"{sec}_GameDVR_Off")
    if 'gamedvr' in pl.lower() and sec == "Gaming":
        return ("Safe", "Disables GameDVR/Game Bar setting — stops game recording", f"{sec}_GameDVR_{make_id(sec,'GVR')}")
    
    # =========================================================
    # BROWSER HARDENING SECTION
    # =========================================================
    if sec == "BrowserHardening":
        if 'chrome' in pl.lower():
            return ("Safe", "Applies Chrome privacy policy — reduces Chrome data collection", f"{sec}_Chrome_{make_id(sec,'Chrome')}")
        if 'brave' in pl.lower():
            return ("Safe", "Applies Brave privacy policy — hardens Brave browser", f"{sec}_Brave_{make_id(sec,'Brave')}")
        if 'opera' in pl.lower():
            return ("Safe", "Applies Opera privacy policy — reduces Opera data collection", f"{sec}_Opera_{make_id(sec,'Opera')}")
        if 'firefox' in pl.lower() or 'mozilla' in pl.lower():
            # Specific Firefox policies
            if 'disabletelemetry' in nl: return ("Safe", "Disables Firefox telemetry — stops Firefox data collection", f"{sec}_FF_NoTelemetry")
            if 'disablefirefoxstudies' in nl: return ("Safe", "Disables Firefox Studies — stops Firefox A/B experiments", f"{sec}_FF_NoStudies")
            if 'disablepocket' in nl: return ("Safe", "Disables Pocket integration — stops Pocket data collection", f"{sec}_FF_NoPocket")
            if 'disableformhistory' in nl: return ("Safe", "Disables form history — stops autofill data collection", f"{sec}_FF_NoFormHist")
            if 'offertosavelogins' in nl: return ("Safe", "Disables login save offers — prevents credential storage in browser", f"{sec}_FF_NoSaveLogins")
            if 'passwordmanagerenabled' in nl: return ("Safe", "Disables Firefox password manager — prevents credential storage in browser", f"{sec}_FF_NoPasswordMgr")
            if 'sanitizeonshutdown' in nl: return ("Safe", "Enables sanitize on shutdown — clears browsing data on exit", f"{sec}_FF_SanitizeOnShutdown")
            if 'dontcheckdefaultbrowser' in nl: return ("Safe", "Disables default browser check — reduces startup prompts", f"{sec}_FF_NoDefaultCheck")
            if 'value' in nl and 'trackingprotection' in pl.lower(): return ("Safe", "Enables strict tracking protection in Firefox", f"{sec}_FF_TrackingProt")
            if 'cryptomining' in nl: return ("Safe", "Blocks cryptomining in Firefox — stops coin miner scripts", f"{sec}_FF_NoCryptomining")
            if 'fingerprinting' in nl: return ("Safe", "Blocks fingerprinting in Firefox — stops browser fingerprint tracking", f"{sec}_FF_NoFingerprinting")
            if 'enabled' in nl and 'dnsoverhttps' in pl.lower(): return ("Safe", "Enables DNS-over-HTTPS in Firefox — encrypts DNS queries", f"{sec}_FF_DoH")
            return ("Safe", "Applies Firefox privacy policy — reduces Firefox data collection", f"{sec}_Firefox_{make_id(sec,'FF')}")
    
    # =========================================================
    # FINAL TOUCHES SECTION
    # =========================================================
    if 'disablefirstrunsettings' in nl: return ("Safe", "Disables Edge first-run experience — prevents Edge welcome screen", f"{sec}_NoEdgeFirstRun")
    if 'hideinsiderpage' in nl: return ("Safe", "Hides Windows Insider page from Settings — removes insider enrollment UI", f"{sec}_HideInsiderPage")
    if 'initialkeyboardindicators' in nl: return ("Safe", "Sets NumLock state at startup", f"{sec}_NumLockStartup")
    if 'mousespeed' in nl: return ("Safe", "Disables mouse acceleration — improves pointer precision for gamers", f"{sec}_NoMouseAccel")
    if 'mousethreshold1' in nl: return ("Safe", "Disables mouse acceleration threshold 1 — improves pointer precision", f"{sec}_MouseThreshold1")
    if 'mousethreshold2' in nl: return ("Safe", "Disables mouse acceleration threshold 2 — improves pointer precision", f"{sec}_MouseThreshold2")
    if 'flags' in nl and 'stickykeys' in pl: return ("Safe", "Disables Sticky Keys accessibility feature — prevents accidental activation", f"{sec}_NoStickyKeys")
    
    # =========================================================
    # FALLBACK
    # =========================================================
    # None matched - return None to signal we can't classify
    return None


def classify_dst(section, taskpath, taskname):
    """Classify a Disable-ScheduledTask call."""
    sec = section or "ScheduledTasks"
    tp = (taskpath or "").lower()
    tn = (taskname or "").lower()
    
    if 'application experience' in tp:
        return ("Safe", f"Disables {taskname} — stops app compatibility telemetry", f"{sec}_AppExp_{taskname.replace(' ','').replace('\\','')}")
    if 'customer experience' in tp:
        return ("Safe", f"Disables {taskname} — stops CEIP data collection", f"{sec}_CEIP_{taskname.replace(' ','').replace('\\','')}")
    if 'device information' in tp:
        return ("Safe", f"Disables {taskname} — stops device info telemetry", f"{sec}_DevInfo_{taskname.replace(' ','').replace('\\','')}")
    if 'errordetails' in tp:
        return ("Safe", f"Disables {taskname} — stops error detail reporting", f"{sec}_ErrDetails_{taskname.replace(' ','').replace('\\','')}")
    if 'windows error reporting' in tp:
        return ("Safe", f"Disables {taskname} — stops Windows Error Reporting", f"{sec}_WER_{taskname.replace(' ','').replace('\\','')}")
    if 'feedback' in tp:
        return ("Safe", f"Disables {taskname} — stops feedback/diagnostic data collection", f"{sec}_Feedback_{taskname.replace(' ','').replace('\\','')}")
    if 'maps' in tp:
        return ("Safe", f"Disables {taskname} — stops Maps auto-update", f"{sec}_Maps_{taskname.replace(' ','').replace('\\','')}")
    if 'maintenance' in tp:
        return ("Safe", f"Disables {taskname} — stops automatic WinSAT performance assessment", f"{sec}_WinSAT_{taskname.replace(' ','').replace('\\','')}")
    if 'shell' in tp and 'familysafety' in tn:
        return ("Safe", f"Disables {taskname} — stops parental controls monitoring", f"{sec}_FamilySafety_{taskname.replace(' ','').replace('\\','')}")
    if 'power efficiency' in tp:
        return ("Safe", f"Disables {taskname} — stops power efficiency diagnostics", f"{sec}_PowerDiag_{taskname.replace(' ','').replace('\\','')}")
    if 'pi' in tp and 'sqm' in tn:
        return ("Safe", f"Disables {taskname} — stops SQM/PI telemetry", f"{sec}_PI_{taskname.replace(' ','').replace('\\','')}")
    if 'nettrace' in tp:
        return ("Safe", f"Disables {taskname} — stops network trace data collection", f"{sec}_NetTrace_{taskname.replace(' ','').replace('\\','')}")
    if 'xblgamesave' in tp:
        return ("Safe", f"Disables {taskname} — stops Xbox Game Save sync", f"{sec}_XblGameSave_{taskname.replace(' ','').replace('\\','')}")
    if 'windowsupdate' in tp:
        return ("Safe", f"Disables {taskname} — stops automatic app updates via Store", f"{sec}_WU_{taskname.replace(' ','').replace('\\','')}")
    if 'diskdiagnostic' in tp:
        return ("Safe", f"Disables {taskname} — stops disk diagnostic data collection", f"{sec}_DiskDiag_{taskname.replace(' ','').replace('\\','')}")
    if 'diskfootprint' in tp:
        return ("Safe", f"Disables {taskname} — stops disk footprint diagnostics", f"{sec}_DiskFootprint_{taskname.replace(' ','').replace('\\','')}")
    if 'license manager' in tp:
        return ("Safe", f"Disables {taskname} — stops license exchange telemetry", f"{sec}_LicenseMgr_{taskname.replace(' ','').replace('\\','')}")
    if 'subscription' in tp:
        return ("Safe", f"Disables {taskname} — stops subscription license acquisition", f"{sec}_Subscription_{taskname.replace(' ','').replace('\\','')}")
    if 'office' in tp:
        return ("Safe", f"Disables {taskname} — stops Office telemetry data collection", f"{sec}_Office_{taskname.replace(' ','').replace('\\','')}")
    if 'scheduleddefrag' in tn:
        return ("Safe", "Disables scheduled defragmentation — SSD does not need defrag", f"{sec}_NoScheduledDefrag")
    
    # For variable-based calls in loops (ScheduledTasks section)
    if sec == "ScheduledTasks":
        return ("Safe", "Disables telemetry/diagnostics scheduled task — stops background data collection", f"{sec}_TelemetryTask_{make_id(sec,'Task')}")
    
    return ("Safe", f"Disables scheduled task — stops background telemetry/data collection", f"{sec}_{make_id(sec,'Task')}")


# Now process all logical lines
total_sr = 0
total_dst = 0
unclassified = []

for start, phys, content in logical:
    # Track section
    m = re.search(r'\$script:CurrentSection\s*=\s*"(\w+)"', content)
    if m:
        current_section = m.group(1)
    
    # Set-Registry without -SafetyLevel
    if 'Set-Registry' in content and '-SafetyLevel' not in content:
        if 'function Set-Registry' in content:
            continue
        
        path_m = re.search(r'-Path\s+"([^"]+)"', content)
        name_m = re.search(r'-Name\s+"([^"]+)"', content)
        value_m = re.search(r'-Value\s+(\S+)', content)
        
        path = path_m.group(1) if path_m else ""
        name = name_m.group(1) if name_m else ""
        value = value_m.group(1) if value_m else ""
        
        result = classify_sr(current_section, path, name, value, start)
        if result is None:
            unclassified.append((start+1, "Set-Registry", path, name))
            continue
        
        safety, desc, setting_id = result
        annotation = f' -SafetyLevel "{safety}" -Description "{desc}" -SettingID "{setting_id}"'
        
        # Add annotation to the last physical line
        last_phys_idx = phys[-1]
        annotations[last_phys_idx] = annotation
        total_sr += 1
    
    # Disable-ScheduledTask without -SafetyLevel
    elif 'Disable-ScheduledTask' in content and '-SafetyLevel' not in content:
        if 'function Disable-ScheduledTask' in content:
            continue
        # Skip the internal call inside the function definition
        if start >= 812 and start <= 886:
            continue
        
        tp_m = re.search(r'-TaskPath\s+"([^"]+)"', content)
        tn_m = re.search(r'-TaskName\s+"([^"]+)"', content)
        taskpath = tp_m.group(1) if tp_m else ""
        taskname = tn_m.group(1) if tn_m else ""
        
        result = classify_dst(current_section, taskpath, taskname)
        if result is None:
            unclassified.append((start+1, "Disable-ScheduledTask", taskpath, taskname))
            continue
        
        safety, desc, setting_id = result
        annotation = f' -SafetyLevel "{safety}" -Description "{desc}" -SettingID "{setting_id}"'
        
        last_phys_idx = phys[-1]
        annotations[last_phys_idx] = annotation
        total_dst += 1

print(f"Annotated {total_sr} Set-Registry calls")
print(f"Annotated {total_dst} Disable-ScheduledTask calls")
print(f"Unclassified: {len(unclassified)}")
for line, typ, p, n in unclassified:
    print(f"  Line {line}: {typ} path={p} name={n}")

# Apply annotations to the file
for line_idx, annotation in annotations.items():
    line = lines[line_idx]
    if line.endswith('\n'):
        lines[line_idx] = line.rstrip('\n') + annotation + '\n'
    else:
        lines[line_idx] = line + annotation

# Write the modified file
with open(INPUT_FILE, 'w', encoding='utf-8') as f:
    f.writelines(lines)

print(f"\nFile written to {INPUT_FILE}")
print(f"Total annotations: {total_sr + total_dst}")
