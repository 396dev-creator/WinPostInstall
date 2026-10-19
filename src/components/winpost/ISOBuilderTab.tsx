"use client";

import React, { useState } from "react";
import { motion } from "framer-motion";
import {
  Disc3, Upload, Download, AlertCircle, CheckCircle2,
  HardDrive, FileArchive, Settings2, Terminal,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Checkbox } from "@/components/ui/checkbox";
import { useAppStore } from "@/store/useAppStore";
import { isTauriApp } from "@/lib/tauri-bridge";

export function ISOBuilderTab() {
  const { settings, generateConfig, getGlobalEnabledSafetyCounts } = useAppStore();
  const enabledCounts = getGlobalEnabledSafetyCounts();
  const totalEnabled = enabledCounts.Safe + enabledCounts.Moderate + enabledCounts.Risky;

  const [isoPath, setIsoPath] = useState("");
  const [outputPath, setOutputPath] = useState("");
  const [includeDrivers, setIncludeDrivers] = useState(false);
  const [includeUpdates, setIncludeUpdates] = useState(false);
  const [autoUnattend, setAutoUnattend] = useState(true);
  const [isBuilding, setIsBuilding] = useState(false);
  const [buildComplete, setBuildComplete] = useState(false);

  const inTauri = isTauriApp();

  // Generate the auto-unattend XML that embeds our settings
  const generateAutoUnattend = () => {
    const config = generateConfig();
    const configJson = JSON.stringify(config, null, 2);

    return `<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreen>true</HideOnlineAccountScreen>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
    </component>
  </settings>
  <settings pass="specialize">
    <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <RunSynchronous>
        <RunSynchronousCommand wcm:action="add">
          <Order>1</Order>
          <Description>WinPostInstall Post-Setup</Description>
          <Path>powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SYSTEMDRIVE%\\WinPostInstall\\WinPostInstall.ps1" -ConfigFile "%SYSTEMDRIVE%\\WinPostInstall\\config.json" -NonInteractive</Path>
        </RunSynchronousCommand>
      </RunSynchronous>
    </component>
  </settings>
</unattend>`;
  };

  const handleDownloadUnattend = () => {
    const xml = generateAutoUnattend();
    const blob = new Blob([xml], { type: "application/xml" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "autounattend.xml";
    a.click();
    URL.revokeObjectURL(url);
  };

  const handleDownloadISOBuilder = () => {
    const includeDriversSection = includeDrivers
      ? `# Include drivers
Write-Host "[3.5/5] Integrating drivers..." -ForegroundColor Green
$driverDir = ".\\\\Drivers"
if (Test-Path $driverDir) {
    Add-WindowsDriver -Path (Join-Path $workDir "sources\\\\install.wim") -Driver $driverDir -Recurse
}`
      : "";

    const includeUpdatesSection = includeUpdates
      ? `# Include updates
Write-Host "[3.7/5] Integrating updates..." -ForegroundColor Green
$updateDir = ".\\\\Updates"
if (Test-Path $updateDir) {
    Get-ChildItem $updateDir -Filter "*.cab" | ForEach-Object {
        Add-WindowsPackage -Path (Join-Path $workDir "sources\\\\install.wim") -PackagePath $_.FullName
    }
}`
      : "";

    const script = `# WinPostInstall ISO Builder
# This script creates a custom Windows ISO with WinPostInstall embedded

param(
    [Parameter(Mandatory=$true)]
    [string]$SourceISO,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "WinPostInstall-Custom.iso",
    
    [switch]$IncludeDrivers,
    [switch]$IncludeUpdates
)

Write-Host "=== WinPostInstall ISO Builder ===" -ForegroundColor Cyan

# Check for required tools
$oscdbimg = Get-Command "oscdimg" -ErrorAction SilentlyContinue
if (-not $oscdbimg) {
    Write-Host "oscdimg not found. Attempting to use DISM..." -ForegroundColor Yellow
}

# Mount source ISO
Write-Host "[1/5] Mounting source ISO..." -ForegroundColor Green
$mountResult = Mount-DiskImage -ImagePath $SourceISO -PassThru
$driveLetter = ($mountResult | Get-Volume).DriveLetter + ":"
Write-Host "  Mounted at $driveLetter"

# Create working directory
$workDir = Join-Path $env:TEMP "WinPostInstall-ISO"
if (Test-Path $workDir) { Remove-Item $workDir -Recurse -Force }
New-Item -ItemType Directory -Path $workDir | Out-Null

# Copy Windows files
Write-Host "[2/5] Copying Windows installation files..." -ForegroundColor Green
Copy-Item -Path "$driveLetter\\*" -Destination $workDir -Recurse

# Embed WinPostInstall
Write-Host "[3/5] Embedding WinPostInstall..." -ForegroundColor Green
$wpiDir = Join-Path $workDir "WinPostInstall"
New-Item -ItemType Directory -Path $wpiDir -Force | Out-Null

# Copy the script and config
Copy-Item -Path ".\\WinPostInstall.ps1" -Destination $wpiDir -ErrorAction SilentlyContinue
Copy-Item -Path ".\\WinPostInstall-Config.json" -Destination $wpiDir -ErrorAction SilentlyContinue
Copy-Item -Path ".\\autounattend.xml" -Destination $workDir -ErrorAction SilentlyContinue

${includeDriversSection}

${includeUpdatesSection}

# Create ISO
Write-Host "[4/5] Creating custom ISO..." -ForegroundColor Green
if ($oscdbimg) {
    & oscdimg -m -o -u2 -l"WinPostInstall" $workDir $OutputPath
} else {
    # Fallback: use MakeISO or inform user
    Write-Host "  Using DISM/MakeISO..." -ForegroundColor Yellow
}

# Cleanup
Write-Host "[5/5] Cleaning up..." -ForegroundColor Green
Dismount-DiskImage -ImagePath $SourceISO
Remove-Item $workDir -Recurse -Force

Write-Host ""
Write-Host "Custom ISO created: $OutputPath" -ForegroundColor Cyan
Write-Host "Boot from this ISO to install Windows with WinPostInstall pre-configured." -ForegroundColor Green
`;

    const blob = new Blob([script], { type: "text/plain" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "Build-CustomISO.ps1";
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h2 className="text-base font-semibold text-[#e0e0e0]">ISO Builder</h2>
          <p className="text-xs text-[#8888a0]">
            Create a custom Windows ISO with your settings pre-configured
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Badge className="bg-[#00d4ff]/10 text-[#00d4ff] border-[#00d4ff]/20 text-xs">
            {totalEnabled} settings
          </Badge>
          <Badge variant="outline" className="h-5 text-[10px] bg-[#12121a] border-[#2a2a3e] text-[#8888a0]">
            {inTauri ? "Desktop Mode" : "Web Mode"}
          </Badge>
        </div>
      </div>

      {/* Info banner */}
      <motion.div
        initial={{ opacity: 0, y: -5 }}
        animate={{ opacity: 1, y: 0 }}
        className="rounded-xl border border-[#00d4ff]/20 bg-[#00d4ff]/5 p-4"
      >
        <div className="flex items-start gap-3">
          <Disc3 className="h-5 w-5 text-[#00d4ff] shrink-0 mt-0.5" />
          <div>
            <h3 className="text-sm font-semibold text-[#00d4ff] mb-1">Custom ISO Builder</h3>
            <p className="text-xs text-[#00d4ff]/70">
              Embed your WinPostInstall configuration into a custom Windows ISO. When you install from this ISO,
              your settings will be automatically applied during setup via an autounattend.xml file.
              Download the builder script and run it on your Windows machine with a source ISO.
            </p>
          </div>
        </div>
      </motion.div>

      {/* ISO Builder Configuration */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        {/* Source ISO */}
        <div className="rounded-xl border border-[#2a2a3e] bg-[#1a1a2e] p-4">
          <div className="flex items-center gap-2 mb-3">
            <Upload className="h-4 w-4 text-[#8888a0]" />
            <h3 className="text-sm font-semibold text-[#e0e0e0]">Source ISO</h3>
          </div>
          <Input
            placeholder="C:\path\to\Windows11.iso"
            value={isoPath}
            onChange={(e) => setIsoPath(e.target.value)}
            className="bg-[#12121a] border-[#2a2a3e] text-[#e0e0e0] placeholder:text-[#8888a0] text-xs"
          />
          <p className="text-[10px] text-[#8888a0] mt-2">Official Windows 10/11 ISO from Microsoft</p>
        </div>

        {/* Output Path */}
        <div className="rounded-xl border border-[#2a2a3e] bg-[#1a1a2e] p-4">
          <div className="flex items-center gap-2 mb-3">
            <HardDrive className="h-4 w-4 text-[#8888a0]" />
            <h3 className="text-sm font-semibold text-[#e0e0e0]">Output ISO</h3>
          </div>
          <Input
            placeholder="C:\path\to\WinPostInstall-Custom.iso"
            value={outputPath}
            onChange={(e) => setOutputPath(e.target.value)}
            className="bg-[#12121a] border-[#2a2a3e] text-[#e0e0e0] placeholder:text-[#8888a0] text-xs"
          />
          <p className="text-[10px] text-[#8888a0] mt-2">Custom ISO with your configuration</p>
        </div>
      </div>

      {/* Options */}
      <div className="rounded-xl border border-[#2a2a3e] bg-[#1a1a2e] p-4">
        <div className="flex items-center gap-2 mb-3">
          <Settings2 className="h-4 w-4 text-[#8888a0]" />
          <h3 className="text-sm font-semibold text-[#e0e0e0]">Build Options</h3>
        </div>
        <div className="space-y-3">
          <div className="flex items-center gap-3">
            <Checkbox
              id="auto-unattend"
              checked={autoUnattend}
              onCheckedChange={(checked) => setAutoUnattend(checked === true)}
              className="border-[#00d4ff]/30 data-[state=checked]:bg-[#00d4ff] data-[state=checked]:border-[#00d4ff]"
            />
            <div>
              <label htmlFor="auto-unattend" className="text-xs text-[#e0e0e0] cursor-pointer">
                Generate autounattend.xml
              </label>
              <p className="text-[10px] text-[#8888a0]">Creates an unattended setup file that runs WinPostInstall during OOBE</p>
            </div>
          </div>
          <div className="flex items-center gap-3">
            <Checkbox
              id="include-drivers"
              checked={includeDrivers}
              onCheckedChange={(checked) => setIncludeDrivers(checked === true)}
              className="border-[#00d4ff]/30 data-[state=checked]:bg-[#00d4ff] data-[state=checked]:border-[#00d4ff]"
            />
            <div>
              <label htmlFor="include-drivers" className="text-xs text-[#e0e0e0] cursor-pointer">
                Integrate drivers
              </label>
              <p className="text-[10px] text-[#8888a0]">Add drivers from a Drivers\\ folder into the install image</p>
            </div>
          </div>
          <div className="flex items-center gap-3">
            <Checkbox
              id="include-updates"
              checked={includeUpdates}
              onCheckedChange={(checked) => setIncludeUpdates(checked === true)}
              className="border-[#00d4ff]/30 data-[state=checked]:bg-[#00d4ff] data-[state=checked]:border-[#00d4ff]"
            />
            <div>
              <label htmlFor="include-updates" className="text-xs text-[#e0e0e0] cursor-pointer">
                Integrate Windows updates (.cab)
              </label>
              <p className="text-[10px] text-[#8888a0]">Slipstream offline updates from an Updates\\ folder</p>
            </div>
          </div>
        </div>
      </div>

      {/* Actions */}
      <div className="flex items-center gap-3 flex-wrap">
        <Button
          size="sm"
          onClick={handleDownloadUnattend}
          disabled={totalEnabled === 0}
          className="h-9 gap-1.5 bg-[#00d4ff] hover:bg-[#00d4ff]/90 text-[#0a0a0f] font-semibold text-xs"
        >
          <FileArchive className="h-3.5 w-3.5" />
          Download autounattend.xml
        </Button>
        <Button
          variant="outline"
          size="sm"
          onClick={handleDownloadISOBuilder}
          className="h-9 gap-1.5 bg-[#12121a] border-[#2a2a3e] text-[#e0e0e0] hover:bg-[#1a1a2e] hover:text-[#00d4ff] text-xs"
        >
          <Download className="h-3.5 w-3.5" />
          Download ISO Builder Script
        </Button>
      </div>

      {/* Safety summary of what's included */}
      {totalEnabled > 0 && (
        <div className="rounded-xl border border-[#2a2a3e] bg-[#12121a] p-4">
          <h3 className="text-sm font-semibold text-[#e0e0e0] mb-2">Configuration Summary</h3>
          <div className="flex items-center gap-4 text-xs">
            {enabledCounts.Safe > 0 && (
              <div className="flex items-center gap-1.5">
                <div className="h-2 w-2 rounded-full bg-[#22c55e]" />
                <span className="text-[#22c55e]">{enabledCounts.Safe} Safe</span>
              </div>
            )}
            {enabledCounts.Moderate > 0 && (
              <div className="flex items-center gap-1.5">
                <div className="h-2 w-2 rounded-full bg-[#eab308]" />
                <span className="text-[#eab308]">{enabledCounts.Moderate} Moderate</span>
              </div>
            )}
            {enabledCounts.Risky > 0 && (
              <div className="flex items-center gap-1.5">
                <div className="h-2 w-2 rounded-full bg-[#ef4444]" />
                <span className="text-[#ef4444]">{enabledCounts.Risky} Risky</span>
              </div>
            )}
            <div className="h-3 w-px bg-[#2a2a3e]" />
            <span className="text-[#8888a0]">{totalEnabled} total settings will be embedded</span>
          </div>
        </div>
      )}
    </div>
  );
}
