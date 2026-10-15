#!/usr/bin/env python3
"""
Annotate all Set-Registry and Disable-ScheduledTask calls in WinPostInstall.ps1
that are missing -SafetyLevel, -Description, -SettingID parameters.
"""

import re
import sys

INPUT_FILE = "/home/z/my-project/scripts/WinPostInstall.ps1"
OUTPUT_FILE = "/home/z/my-project/scripts/WinPostInstall_annotated.ps1"

# Read the file
with open(INPUT_FILE, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# We'll process the file line by line, joining continuation lines (backtick at end)
# and then splitting them back after annotation.

# First, let's join continuation lines into logical lines
# Each logical line may span multiple physical lines connected by backtick

class LogicalLine:
    def __init__(self, start_line, end_line, content):
        self.start_line = start_line  # 0-based
        self.end_line = end_line      # 0-based, inclusive
        self.content = content        # joined content (backticks removed)
        self.physical_lines = []      # original physical lines

# Join continuation lines
logical_lines = []
i = 0
while i < len(lines):
    line = lines[i].rstrip('\n')
    start = i
    content_parts = []
    physical = [lines[i]]
    
    while True:
        stripped = line.rstrip()
        if stripped.endswith('`'):
            # Continuation line - remove backtick and join
            content_parts.append(stripped[:-1])
            i += 1
            if i >= len(lines):
                break
            line = lines[i].rstrip('\n')
            physical.append(lines[i])
        else:
            content_parts.append(stripped)
            break
    
    content = ' '.join(content_parts)
    ll = LogicalLine(start, i, content)
    ll.physical_lines = physical
    logical_lines.append(ll)
    i += 1

# Now we need to identify Set-Registry and Disable-ScheduledTask calls
# and annotate the ones missing -SafetyLevel

# Track which section we're in
current_section = ""

# For each logical line containing Set-Registry or Disable-ScheduledTask without -SafetyLevel,
# we need to generate the annotation and modify the line

annotated_count = 0
skip_count = 0

# We'll rebuild the output as physical lines
output_lines = list(lines)  # start with a copy

# Process in reverse order so line numbers don't shift
# First, collect all the edits we need to make
edits = []  # list of (start_line, end_line, new_content)

for ll in logical_lines:
    content = ll.content
    
    # Track section
    section_match = re.search(r'\$script:CurrentSection\s*=\s*"(\w+)"', content)
    if section_match:
        current_section = section_match.group(1)
    
    # Check for Set-Registry without -SafetyLevel
    if 'Set-Registry' in content and '-SafetyLevel' not in content:
        # Extract parameters
        path_match = re.search(r'-Path\s+"([^"]+)"', content)
        name_match = re.search(r'-Name\s+"([^"]+)"', content)
        value_match = re.search(r'-Value\s+(\S+)', content)
        
        if not path_match or not name_match:
            continue
        
        path = path_match.group(1)
        name = name_match.group(1)
        value = value_match.group(1) if value_match else ""
        
        # Determine safety level, description, setting ID
        safety, desc, setting_id = classify_set_registry(current_section, path, name, value)
        
        if safety is None:
            skip_count += 1
            continue
        
        # Build annotation string
        annotation = f' -SafetyLevel "{safety}" -Description "{desc}" -SettingID "{setting_id}"'
        
        # Find where to insert the annotation - after the last parameter of the Set-Registry call
        # We need to insert it on the last physical line of the logical line
        # The annotation should go after the last -Type parameter or last parameter
        
        edits.append((ll.start_line, ll.end_line, ll.physical_lines, annotation, 'Set-Registry'))
        annotated_count += 1
    
    # Check for Disable-ScheduledTask without -SafetyLevel
    elif 'Disable-ScheduledTask' in content and '-SafetyLevel' not in content:
        # Skip if this is the built-in Disable-ScheduledTask function definition
        if 'function Disable-ScheduledTask' in content:
            continue
        # Skip if it's the internal call inside the Disable-ScheduledTask function itself
        if ll.start_line >= 813 and ll.start_line <= 886:
            continue
        
        taskpath_match = re.search(r'-TaskPath\s+"([^"]+)"', content)
        taskname_match = re.search(r'-TaskName\s+"([^"]+)"', content)
        
        taskpath = taskpath_match.group(1) if taskpath_match else ""
        taskname = taskname_match.group(1) if taskname_match else ""
        
        safety, desc, setting_id = classify_disable_task(current_section, taskpath, taskname)
        
        if safety is None:
            skip_count += 1
            continue
        
        annotation = f' -SafetyLevel "{safety}" -Description "{desc}" -SettingID "{setting_id}"'
        edits.append((ll.start_line, ll.end_line, ll.physical_lines, annotation, 'Disable-ScheduledTask'))
        annotated_count += 1

print(f"Found {annotated_count} calls to annotate, {skip_count} skipped")
print(f"Total edits: {len(edits)}")


def classify_set_registry(section, path, name, value):
    """Classify a Set-Registry call and return (SafetyLevel, Description, SettingID)"""
    
    # Build a short section prefix for SettingID
    sec = section if section else "Unknown"
    
    # Normalize path for matching
    pl = path.lower()
    nl = name.lower()
    
    # =========================================================
    # PRIVACY SECTION
    # =========================================================
    if 'appcompat' in pl:
        if 'aitenable' in nl:
            return ("Safe", "Disables Application Impact Telemetry — stops app compat data collection", f"{sec}_AITEnable")
        if 'disableinventory' in nl:
            return ("Safe", "Disables app compatibility inventory — stops hardware/software inventory", f"{sec}_DisableInventory")
        if 'disableuar' in nl:
            return ("Safe", "Disables User App Compatibility Reporter — stops compat data uploads", f"{sec}_DisableUAR")
        if 'disablepca' in nl:
            return ("Safe", "Disables Program Compatibility Assistant — stops compatibility telemetry", f"{sec}_DisablePCA")
    
    if 'ceipenable' in nl:
        return ("Safe", "Disables Customer Experience Improvement Program — stops CEIP data collection", f"{sec}_CEIPEnable")
    
    if 'disabletailoredexperiences' in nl:
        return ("Safe", "Disables tailored experiences with diagnostic data — stops personalized ads/tips", f"{sec}_NoTailoredExp")
    
    if 'compatelrunner' in pl or 'image file execution options' in pl:
        return ("Safe", "Kills CompatTelRunner.exe via IFEO — blocks telemetry compatibility runner", f"{sec}_KillCompatTelRunner")
    
    if 'enableactivityfeed' in nl or 'publishuseractivities' in nl or 'uploaduseractivities' in nl:
        desc_map = {
            'enableactivityfeed': "Disables Activity Feed — stops Windows from tracking activity history",
            'publishuseractivities': "Prevents publishing user activities to Microsoft cloud",
            'uploaduseractivities': "Prevents uploading activity history to Microsoft cloud",
        }
        d = desc_map.get(nl, "Disables activity history tracking")
        return ("Safe", d, f"{sec}_{name}")
    
    if 'consentstore\\location' in pl or 'lfsvc' in pl:
        return ("Moderate", "Disables geolocation service — breaks Find My Device and Maps location", f"{sec}_NoGeolocation")
    
    if 'advertisinginfo' in pl:
        if 'disabledbygrouppolicy' in nl:
            return ("Safe", "Removes advertising ID via group policy — stops targeted advertising", f"{sec}_AdvIDPolicy")
        if 'enabled' in nl:
            return ("Safe", "Disables advertising ID in current user scope", f"{sec}_AdvIDUser")
    
    if 'windows search' in pl and 'policies' in pl:
        if 'allowcortana' in nl:
            return ("Safe", "Disables Cortana digital assistant and web search in Start", f"{sec}_NoCortana")
        if 'allowsearchtouselocation' in nl:
            return ("Safe", "Prevents search from using location data", f"{sec}_NoSearchLocation")
        if 'allowcloudsearch' in nl:
            return ("Safe", "Disables cloud search integration", f"{sec}_NoCloudSearch")
        if 'disablewebsearch' in nl:
            return ("Safe", "Stops Start menu from using Bing web search", f"{sec}_DisableWebSearch")
        if 'connectedsearchuseweb' in nl:
            return ("Safe", "Blocks Cortana from using web for search results", f"{sec}_NoConnectedSearch")
    
    if 'windowsstore' in pl and 'disablewindowsstorerealtimeconfig' in nl:
        return ("Safe", "Disables Windows Store real-time configuration — reduces Store telemetry", f"{sec}_NoStoreRealTime")
    
    if 'bingsearchenabled' in nl:
        return ("Safe", "Disables Bing search in Start Menu — stops web search results", f"{sec}_NoBingSearch")
    if 'cortanaconsent' in nl:
        return ("Safe", "Revokes Cortana consent — stops Cortana data collection", f"{sec}_NoCortanaConsent")
    
    if 'windowscopilot' in pl:
        return ("Safe", "Disables Windows Copilot AI assistant", f"{sec}_NoCopilot")
    if 'showcopilotbutton' in nl:
        return ("Safe", "Hides Copilot button from taskbar", f"{sec}_HideCopilotBtn")
    
    if 'windowsai' in pl:
        if 'allowrecallenablement' in nl:
            return ("Safe", "Disables Windows Recall AI memory/timeline feature", f"{sec}_NoRecall")
        if 'disableaidataanalysis' in nl:
            return ("Safe", "Disables AI data analysis — stops AI telemetry collection", f"{sec}_NoAIDataAnalysis")
        if 'disableclicktodo' in nl:
            return ("Safe", "Disables Click-to-Do AI feature — stops AI suggestions", f"{sec}_NoClickToDo")
        if 'disableimagecreator' in nl:
            return ("Safe", "Disables AI Image Creator — stops AI image generation telemetry", f"{sec}_NoImageCreator")
        if 'disablecocreator' in nl:
            return ("Safe", "Disables AI Cocreator — stops AI co-creation telemetry", f"{sec}_NoCocreator")
        if 'disablegenerativefill' in nl:
            return ("Safe", "Disables AI Generative Fill — stops AI fill telemetry", f"{sec}_NoGenerativeFill")
    
    if 'paintstudio' in pl:
        return ("Safe", "Disables AI feature in Paint — stops AI telemetry", f"{sec}_NoPaintAI")
    
    if 'allowclipboardhistory' in nl:
        return ("Safe", "Disables clipboard history (Win+V)", f"{sec}_NoClipHistory")
    if 'allowcrossdeviceclipboard' in nl:
        return ("Safe", "Disables cloud clipboard sync across devices", f"{sec}_NoClipSync")
    
    if 'restrictimplicittextcollection' in nl:
        return ("Safe", "Restricts implicit text collection — stops typing telemetry", f"{sec}_NoImplicitText")
    if 'restrictimplicitinkcollection' in nl:
        return ("Safe", "Restricts implicit ink collection — stops inking telemetry", f"{sec}_NoImplicitInk")
    if 'harvestcontacts' in nl:
        return ("Safe", "Disables contact harvesting for typing suggestions — stops contact data collection", f"{sec}_NoHarvestContacts")
    
    if 'numberofsiufinperiod' in nl:
        return ("Safe", "Disables feedback notifications — stops Feedback Hub prompts", f"{sec}_NoFeedbackNotif")
    
    if 'start_trackprogs' in nl:
        return ("Safe", "Disables tracking of most-used programs in Start — stops usage telemetry", f"{sec}_NoTrackProgs")
    if 'start_trackdocs' in nl:
        return ("Safe", "Disables tracking of recently opened documents in Start — stops usage telemetry", f"{sec}_NoTrackDocs")
    if 'disablesoftlanding' in nl:
        return ("Safe", "Disables Windows soft landing tips — stops suggestion telemetry", f"{sec}_NoSoftLanding")
    if 'disablewindowsconsumerfeatures' in nl:
        return ("Safe", "Disables Windows consumer features — stops Store suggestions/ads", f"{sec}_NoConsumerFeatures")
    
    if 'wifi' in pl or 'wifinetworkmanager' in pl or 'wcmvc' in pl:
        return ("Safe", "Disables Wi-Fi Sense — stops sharing Wi-Fi passwords with contacts", f"{sec}_NoWiFiSense")
    
    if 'windows error reporting' in pl and 'policies' in pl:
        if 'disabled' in nl:
            return ("Moderate", "Stops Windows Error Reporting — makes troubleshooting harder", f"{sec}_NoWER")
    
    if 'previewbuilds' in pl:
        return ("Moderate", "Disables Windows Insider experiments — stops A/B testing and flighting", f"{sec}_NoInsiderExperiments")
    
    if 'settingsync' in pl:
        return ("Moderate", "Disables Setting Sync / Windows Backup — stops cloud settings sync", f"{sec}_NoSettingSync")
    
    if 'fulltelemetryoninstall' in nl:
        return ("Safe", "Disables full telemetry on install — stops initial data collection burst", f"{sec}_NoFullTelemetryInstall")
    if 'allowupdatecompliancetelemetry' in nl:
        return ("Safe", "Disables Update Compliance telemetry — stops WU data reporting", f"{sec}_NoUpdateComplianceTelemetry")
    if 'enablediagnosticdataviewer' in nl:
        return ("Safe", "Disables Diagnostic Data Viewer — removes data viewer feature", f"{sec}_NoDiagDataViewer")
    if 'disabledevicecensus' in nl:
        return ("Safe", "Disables Device Census — stops hardware inventory reporting to Microsoft", f"{sec}_NoDeviceCensus")
    
    if 'apphost' in pl and 'enablewebcontentevaluation' in nl:
        return ("Safe", "Disables web content evaluation — stops app telemetry", f"{sec}_NoWebContentEval")
    
    if 'globaluserdisabled' in nl:
        return ("Safe", "Disables background app access globally — stops apps running in background", f"{sec}_NoBackgroundApps")
    if 'letappsgetdiagnosticinfo' in nl:
        return ("Safe", "Denies apps access to diagnostic info — stops app diagnostics data sharing", f"{sec}_NoAppDiagInfo")
    if 'letappsaccessactivityhistory' in nl:
        return ("Safe", "Denies apps access to activity history — stops app activity tracking", f"{sec}_NoAppActivityHist")
    
    if 'disablecloudoptimizedcontent' in nl:
        return ("Safe", "Disables cloud-optimized content — stops personalized suggestions", f"{sec}_NoCloudContent")
    if 'disablethirdpartysuggestions' in nl:
        return ("Safe", "Disables third-party suggestions in Windows — stops third-party ads", f"{sec}_No3rdPartySuggestions")
    
    if 'contentdeliverymanager' in pl:
        if 'subscribedcontent-338389' in nl:
            return ("Safe", "Disables Windows Spotlight suggestions — stops lock screen tips/ads", f"{sec}_NoSpotlight338389")
        if 'subscribedcontent-310093' in nl:
            return ("Safe", "Disables 'Get even more out of Windows' tips — stops suggestion prompts", f"{sec}_NoTips310093")
        if 'contentdeliveryenabled' in nl:
            return ("Safe", "Disables content delivery — stops silent app installs and suggestions", f"{sec}_NoContentDelivery")
        if 'subscribedcontent-338387' in nl:
            return ("Safe", "Disables suggested content in Settings — stops Settings suggestions", f"{sec}_NoSuggestedContent338387")
        if 'subscribedcontent-338388' in nl:
            return ("Safe", "Disables suggested content (tips) — stops tips/suggestions", f"{sec}_NoSuggestedContent338388")
        if 'rotatinglockscreenenabled' in nl:
            return ("Safe", "Disables rotating lock screen images — stops Windows Spotlight ads", f"{sec}_NoRotatingLockScreen")
        if 'rotatinglockscre-overlayenabled' in nl:
            return ("Safe", "Disables lock screen overlay — stops Windows Spotlight tips/ads", f"{sec}_NoLockScreenOverlay")
        # Generic CDM key
        return ("Safe", "Disables content delivery manager setting — stops suggestions/silent installs", f"{sec}_CDM_{name}")
    
    if 'autologger-diagtrack' in pl:
        return ("Safe", "Disables AutoLogger DiagTrack listener — stops kernel telemetry logging", f"{sec}_NoDiagtrackListener")
    
    if 'networkconnectivitystatusindicator' in pl and 'noactiveprobe' in nl:
        return ("Safe", "Disables NCSI active probing — stops network connectivity telemetry", f"{sec}_NoNCSIProbe")
    
    if 'userprofile' in pl and 'disableuserprofiletelemetry' in nl:
        return ("Safe", "Disables User Profile service telemetry — stops profile data collection", f"{sec}_NoUserProfileTelemetry")
    
    if 'notifications\\settings' in pl:
        return ("Safe", "Disables lock screen toast notifications — stops lock screen notification display", f"{sec}_NoLockScreenNotif")
    
    # =========================================================
    # EXPLORER UI SECTION
    # =========================================================
    if 'hidefileext' in nl:
        return ("Safe", "Shows file extensions — prevents accidental execution of disguised files", f"{sec}_ShowFileExt")
    if nl == 'hidden' or nl == '"hidden"':
        return ("Safe", "Shows hidden files — improves visibility of system files", f"{sec}_ShowHiddenFiles")
    if '(default)' in nl or '"(default)"' in nl:
        if 'inprocserver32' in pl:
            return ("Safe", "Enables classic right-click context menu — removes Win11 simplified menu", f"{sec}_ClassicContextMenu")
    if 'showsyncprovidernotifications' in nl:
        return ("Safe", "Disables File Explorer ads — removes OneDrive ads in Explorer", f"{sec}_NoExplorerAds")
    if 'nolockscreen' in nl:
        return ("Safe", "Disables Lock Screen — goes directly to login screen", f"{sec}_NoLockScreen")
    if 'taskbarmn' in nl:
        return ("Safe", "Removes Chat icon from Taskbar — hides Microsoft Chat/Teams", f"{sec}_NoChatIcon")
    if 'taskbarda' in nl:
        return ("Safe", "Removes Widgets from Taskbar — hides news/weather widget", f"{sec}_NoWidgets")
    if 'taskbarsearchbox' in nl:
        return ("Safe", "Removes Search box from Taskbar — simplifies taskbar", f"{sec}_NoSearchBox")
    if 'enablesnapassistflyout' in nl:
        return ("Safe", "Disables Snap Layouts flyout — removes snap layout suggestions", f"{sec}_NoSnapAssist")
    if 'taskbarendtask' in nl:
        return ("Safe", "Enables 'End Task' in Taskbar right-click — adds quick task kill option", f"{sec}_TaskbarEndTask")
    if 'launchto' in nl:
        return ("Safe", "Sets File Explorer to open This PC instead of Quick Access", f"{sec}_OpenThisPC")
    if 'dragbetweenwindows' in nl:
        return ("Safe", "Disables Drag Tray — removes Win11 share/move files tray", f"{sec}_NoDragTray")
    if 'showtaskviewbutton' in nl:
        return ("Safe", "Removes Task View button from Taskbar — hides virtual desktops UI", f"{sec}_NoTaskView")
    if 'searchboxtaskbarmode' in nl:
        return ("Safe", "Sets Search bar to icon-only mode — simplifies taskbar", f"{sec}_SearchIconOnly")
    if 'showcopilotbutton' in nl:
        return ("Safe", "Hides Copilot button from Taskbar", f"{sec}_HideCopilotBtn")
    
    # =========================================================
    # SERVICE STARTUP SECTION
    # =========================================================
    if 'startupdelayinmsec' in nl:
        return ("Safe", "Disables startup delay — speeds up boot by removing artificial delay", f"{sec}_NoStartupDelay")
    
    # =========================================================
    # PERFORMANCE SECTION
    # =========================================================
    if 'hiberbootenabled' in nl:
        return ("Safe", "Disables Fast Startup — prevents partial shutdown/driver issues", f"{sec}_NoFastStartup")
    if 'modernsleep' in nl:
        return ("Safe", "Disables Modern Standby network — prevents battery drain during sleep", f"{sec}_NoModernSleep")
    if 'visualfxsetting' in nl:
        return ("Safe", "Sets visual effects to Best Performance mode", f"{sec}_VisualFX")
    if 'animateMinMaxMenus'.lower() in nl or 'comboboxanimation' in nl or 'cursorshadow' in nl:
        return ("Safe", "Disables visual animation — improves performance", f"{sec}_DisableAnim_{name}")
    if 'enableaeropeek' in nl:
        return ("Safe", "Disables Aero Peek — removes desktop preview on taskbar hover", f"{sec}_NoAeroPeek")
    if 'enableprefetcher' in nl:
        return ("Safe", "Disables Prefetch on SSD — safe, reduces unnecessary disk I/O", f"{sec}_NoPrefetch_SSD")
    if 'enablesuperfetch' in nl:
        return ("Safe", "Disables SuperFetch on SSD — safe, reduces unnecessary disk I/O", f"{sec}_NoSuperfetch_SSD")
    if 'excludedprocesses' in nl:
        return ("Safe", "Clears Defender excluded processes — maintains scan coverage", f"{sec}_DefenderNoExclusions")
    if 'avgcpuloadfactor' in nl:
        return ("Safe", "Limits Windows Defender CPU usage to 25% — reduces scan impact", f"{sec}_DefenderCPULimit")
    if 'svchostsplitthresholdinkb' in nl:
        return ("Safe", "Increases SvcHost split threshold — reduces svchost.exe proliferation", f"{sec}_SvcHostSplit")
    if 'pagingfiles' in nl:
        return ("Moderate", "Sets page file to fixed 1GB — OK with 16GB+ RAM", f"{sec}_FixedPageFile")
    
    # =========================================================
    # SECURITY SECTION
    # =========================================================
    if 'disablerealtime' in nl or 'disablebehavior' in nl or 'disableonaccess' in nl or 'disablescanonrealtime' in nl:
        return ("Safe", "Ensures Defender real-time protection stays enabled — maintains security", f"{sec}_DefenderRT_{name}")
    if 'enableautodoh' in nl:
        return ("Safe", "Enables DNS-over-HTTPS — encrypts DNS queries for privacy", f"{sec}_EnableDoH")
    if 'nodrivetypeautorun' in nl:
        return ("Safe", "Disables USB auto-run — prevents malware from auto-executing on USB", f"{sec}_NoAutoRun")
    if 'fdenytsconnections' in nl:
        return ("Safe", "Disables Remote Desktop — reduces attack surface", f"{sec}_NoRDP")
    if 'smb1' in nl:
        return ("Safe", "Disables SMBv1 — protects against WannaCry-like exploits", f"{sec}_NoSMB1")
    if 'enablelua' in nl:
        return ("Safe", "Ensures UAC is enabled — maintains admin consent prompts", f"{sec}_UAC_Enabled")
    if 'consentpromptbehavioradmin' in nl:
        return ("Safe", "Sets UAC to prompt for consent — secure admin elevation behavior", f"{sec}_UAC_Consent")
    if 'disablepasswordreveal' in nl:
        return ("Safe", "Disables password reveal button — prevents password visibility", f"{sec}_NoPasswordReveal")
    
    # =========================================================
    # NETWORK SECTION
    # =========================================================
    if 'networkthrottlingindex' in nl:
        return ("Safe", "Disables network throttling — improves network throughput for gaming/streams", f"{sec}_NoNetThrottle")
    if 'nolazymode' in nl:
        return ("Safe", "Disables network lazy mode — reduces latency", f"{sec}_NoLazyMode")
    if 'tcpackfrequency' in nl:
        return ("Safe", "Disables Nagle Algorithm — reduces TCP latency for gaming", f"{sec}_NoNagle")
    if 'tcpnodelay' in nl:
        return ("Safe", "Disables Nagle Algorithm — reduces TCP latency for gaming", f"{sec}_TcpNoDelay")
    if 'teredo_state' in nl:
        return ("Safe", "Disables Teredo IPv6 transition — reduces attack surface", f"{sec}_NoTeredo")
    if 'enabledoh' in nl:
        return ("Safe", "Enables DNS-over-HTTPS via policy — encrypts DNS queries", f"{sec}_EnableDoH_Policy")
    
    # =========================================================
    # WINDOWS UPDATE SECTION
    # =========================================================
    if 'auoptions' in nl:
        return ("Safe", "Sets WU to auto-download and notify — prevents automatic install", f"{sec}_WU_NotifyOnly")
    if 'noautorebootwithloggedonusers' in nl:
        return ("Safe", "Prevents auto-reboot after updates when users are logged in", f"{sec}_WU_NoAutoReboot")
    if 'dodownloadmode' in nl:
        return ("Safe", "Disables Delivery Optimization — stops peer-to-peer update sharing", f"{sec}_NoDeliveryOpt")
    if 'excludewudriversinqualityupdate' in nl:
        return ("Safe", "Excludes drivers from quality updates — prevents driver issues", f"{sec}_WU_NoDriverUpdates")
    if 'activehoursstart' in nl:
        return ("Safe", "Sets active hours start to 09:00 — prevents reboots during work", f"{sec}_WU_ActiveHrsStart")
    if 'activehoursend' in nl:
        return ("Safe", "Sets active hours end to 21:00 — prevents reboots during work", f"{sec}_WU_ActiveHrsEnd")
    if 'donotconnecttowindowsupdateinternetlocations' in nl:
        return ("Safe", "Configures WU internet locations — standard WU policy", f"{sec}_WU_InternetConfig")
    if 'searchorderconfig' in nl:
        return ("Safe", "Prevents automatic driver search via Windows Update", f"{sec}_WU_NoAutoDriverSearch")
    
    # =========================================================
    # DISK CLEANUP SECTION
    # =========================================================
    if 'stateflags0001' in nl:
        return ("Safe", "Configures Disk Cleanup state flags — enables automated cleanup", f"{sec}_DiskCleanupFlags")
    if 'allowstoragesenseglobal' in nl:
        return ("Safe", "Disables Storage Sense — prevents automatic file deletion", f"{sec}_NoStorageSense")
    
    # =========================================================
    # OFFICE ACTIVATION SECTION (Office telemetry)
    # =========================================================
    if 'office' in pl.lower() or 'office' in sec.lower():
        return ("Safe", "Disables Office telemetry/data collection — stops Office data sharing with Microsoft", f"{sec}_Office_{name}")
    
    # =========================================================
    # EDGE HARDENING SECTION
    # =========================================================
    if 'edge' in pl.lower() or 'microsoftedge' in pl.lower():
        return ("Safe", "Hardens Edge browser privacy/security — reduces Edge data collection", f"{sec}_Edge_{name}")
    
    # =========================================================
    # ONEDRIVE SECTION
    # =========================================================
    if 'disablefilesyncngsc' in nl:
        return ("Safe", "Disables OneDrive file sync via Group Policy — prevents OneDrive integration", f"{sec}_DisableOneDrive")
    if 'system.ispinnedtonamespacetree' in nl:
        return ("Safe", "Hides OneDrive from File Explorer navigation pane", f"{sec}_HideOneDriveNav")
    
    # =========================================================
    # GAMING SECTION
    # =========================================================
    if 'allowgamedvr' in nl:
        return ("Safe", "Disables GameDVR via policy — stops game clip recording", f"{sec}_NoGameDVR")
    if 'appcaptureenabled' in nl:
        return ("Safe", "Disables Game Bar capture — stops background game recording", f"{sec}_NoGameBarCapture")
    if 'historicalcaptureenabled' in nl:
        return ("Safe", "Disables Game Bar historical capture — stops background recording", f"{sec}_NoHistoricalCapture")
    if 'gamedvr_enabled' in nl:
        return ("Safe", "Disables GameDVR — stops game recording and broadcasting", f"{sec}_GameDVR_Off")
    
    # =========================================================
    # BROWSER HARDENING SECTION
    # =========================================================
    if 'google\\chrome' in pl.lower():
        return ("Safe", "Applies Chrome privacy policy — reduces Chrome data collection", f"{sec}_Chrome_{name}")
    if 'brave' in pl.lower():
        return ("Safe", "Applies Brave privacy policy — hardens Brave browser", f"{sec}_Brave_{name}")
    if 'opera' in pl.lower():
        return ("Safe", "Applies Opera privacy policy — reduces Opera data collection", f"{sec}_Opera_{name}")
    if 'mozilla\\firefox' in pl.lower():
        return ("Safe", "Applies Firefox privacy policy — reduces Firefox data collection", f"{sec}_Firefox_{name}")
    
    # =========================================================
    # FINAL TOUCHES SECTION
    # =========================================================
    if 'disablefirstrunsettings' in nl:
        return ("Safe", "Disables Edge first-run experience — prevents Edge welcome screen", f"{sec}_NoEdgeFirstRun")
    if 'hideinsiderpage' in nl:
        return ("Safe", "Hides Windows Insider page from Settings — removes insider enrollment UI", f"{sec}_HideInsiderPage")
    if '(default)' in nl and 'appevents' in pl:
        return ("Safe", "Sets sound scheme to No Sounds — disables all system sounds", f"{sec}_NoSounds")
    if 'initialkeyboardindicators' in nl:
        return ("Safe", "Sets NumLock state at startup", f"{sec}_NumLockStartup")
    if 'mousespeed' in nl:
        return ("Safe", "Disables mouse acceleration — improves pointer precision for gamers", f"{sec}_NoMouseAccel")
    if 'mousethreshold1' in nl:
        return ("Safe", "Disables mouse acceleration threshold 1 — improves pointer precision", f"{sec}_MouseThreshold1")
    if 'mousethreshold2' in nl:
        return ("Safe", "Disables mouse acceleration threshold 2 — improves pointer precision", f"{sec}_MouseThreshold2")
    if 'flags' in nl and 'accessibility\\stickykeys' in pl:
        return ("Safe", "Disables Sticky Keys accessibility feature — prevents accidental activation", f"{sec}_NoStickyKeys")
    
    # =========================================================
    # Generic fallback based on section
    # =========================================================
    # Visual FX in Control Panel\Desktop
    if 'control panel\\desktop' in pl:
        return ("Safe", "Disables visual animation — improves performance", f"{sec}_VisFX_{name}")
    
    # Generic CDM path
    if 'contentdeliverymanager' in pl:
        return ("Safe", "Disables content delivery setting — stops suggestions/ads", f"{sec}_CDM_{name}")
    
    # Fallback: we can't classify, return None to skip
    return None


def classify_disable_task(section, taskpath, taskname):
    """Classify a Disable-ScheduledTask call and return (SafetyLevel, Description, SettingID)"""
    
    sec = section if section else "ScheduledTasks"
    tp = taskpath.lower()
    tn = taskname.lower()
    
    # Telemetry/CEIP/diagnostics tasks = Safe
    if 'application experience' in tp:
        return ("Safe", f"Disables scheduled task {taskname} — stops app compatibility telemetry", f"{sec}_AppExp_{taskname.replace(' ','')}")
    if 'customer experience' in tp:
        return ("Safe", f"Disables scheduled task {taskname} — stops CEIP data collection", f"{sec}_CEIP_{taskname.replace(' ','')}")
    if 'device information' in tp:
        return ("Safe", f"Disables scheduled task {taskname} — stops device info telemetry", f"{sec}_DevInfo_{taskname.replace(' ','')}")
    if 'errordetails' in tp:
        return ("Safe", f"Disables scheduled task {taskname} — stops error detail reporting", f"{sec}_ErrDetails_{taskname.replace(' ','')}")
    if 'windows error reporting' in tp:
        return ("Safe", f"Disables scheduled task {taskname} — stops Windows Error Reporting", f"{sec}_WER_{taskname.replace(' ','')}")
    if 'feedback' in tp:
        return ("Safe", f"Disables scheduled task {taskname} — stops feedback/diagnostic data collection", f"{sec}_Feedback_{taskname.replace(' ','')}")
    if 'maps' in tp:
        return ("Safe", f"Disables scheduled task {taskname} — stops Maps auto-update", f"{sec}_Maps_{taskname.replace(' ','')}")
    if 'maintenance' in tp:
        return ("Safe", f"Disables scheduled task {taskname} — stops automatic WinSAT performance assessment", f"{sec}_WinSAT_{taskname.replace(' ','')}")
    if 'shell' in tp and 'familysafety' in tn:
        return ("Safe", f"Disables scheduled task {taskname} — stops parental controls monitoring", f"{sec}_FamilySafety_{taskname.replace(' ','')}")
    if 'power efficiency' in tp:
        return ("Safe", f"Disables scheduled task {taskname} — stops power efficiency diagnostics", f"{sec}_PowerDiag_{taskname.replace(' ','')}")
    if 'pi' in tp:
        return ("Safe", f"Disables scheduled task {taskname} — stops SQM/PI telemetry", f"{sec}_PI_{taskname.replace(' ','')}")
    if 'nettrace' in tp:
        return ("Safe", f"Disables scheduled task {taskname} — stops network trace data collection", f"{sec}_NetTrace_{taskname.replace(' ','')}")
    if 'xblgamesave' in tp:
        return ("Safe", f"Disables scheduled task {taskname} — stops Xbox Game Save sync", f"{sec}_XblGameSave_{taskname.replace(' ','')}")
    if 'windowsupdate' in tp:
        return ("Safe", f"Disables scheduled task {taskname} — stops automatic app updates via Store", f"{sec}_WU_{taskname.replace(' ','')}")
    if 'diskdiagnostic' in tp:
        return ("Safe", f"Disables scheduled task {taskname} — stops disk diagnostic data collection", f"{sec}_DiskDiag_{taskname.replace(' ','')}")
    if 'diskfootprint' in tp:
        return ("Safe", f"Disables scheduled task {taskname} — stops disk footprint diagnostics", f"{sec}_DiskFootprint_{taskname.replace(' ','')}")
    if 'license manager' in tp:
        return ("Safe", f"Disables scheduled task {taskname} — stops license exchange telemetry", f"{sec}_LicenseMgr_{taskname.replace(' ','')}")
    if 'subscription' in tp:
        return ("Safe", f"Disables scheduled task {taskname} — stops subscription license acquisition", f"{sec}_Subscription_{taskname.replace(' ','')}")
    if 'office' in tp:
        return ("Safe", f"Disables scheduled task {taskname} — stops Office telemetry data collection", f"{sec}_Office_{taskname.replace(' ','')}")
    if 'scheduleddefrag' in tn:
        return ("Safe", f"Disables scheduled defragmentation — SSD does not need defrag", f"{sec}_NoScheduledDefrag")
    
    # Fallback
    return ("Safe", f"Disables scheduled task {taskname} — stops background telemetry/data collection", f"{sec}_{taskname.replace(' ','')}")


# Now apply edits
# We need to be careful about where to insert the annotation text.
# For multi-line calls, we append to the last physical line.
# For single-line calls, we append to the line.

# Sort edits by start_line in reverse order to avoid line number shifting
edits.sort(key=lambda x: x[0], reverse=True)

total_annotated = 0

for start_line, end_line, physical_lines, annotation, call_type in edits:
    # Modify the last physical line to append the annotation
    last_line = physical_lines[-1]
    
    # The last line may end with a newline
    if last_line.endswith('\n'):
        last_line_stripped = last_line.rstrip('\n')
        # Append annotation before the newline
        # If the line has a backtick continuation, insert after the backtick content
        # Actually, for single-line calls, just append
        # For multi-line calls (backtick-continued), the last line doesn't have a backtick
        
        # Just append the annotation at the end of the last physical line
        new_last_line = last_line_stripped + annotation + '\n'
    else:
        new_last_line = last_line + annotation
    
    physical_lines[-1] = new_last_line
    
    # Replace the physical lines in output_lines
    output_lines[start_line:end_line+1] = physical_lines
    
    total_annotated += 1

print(f"Total annotations applied: {total_annotated}")

# Write output
with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
    f.writelines(output_lines)

print(f"Written to {OUTPUT_FILE}")
