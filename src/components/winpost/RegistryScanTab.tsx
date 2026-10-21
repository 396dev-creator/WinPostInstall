"use client";

import React, { useState } from "react";
import { motion } from "framer-motion";
import {
  Scan, Download, CheckCircle2, AlertCircle, Monitor,
  FileText, Terminal, RefreshCw,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";
import { sections } from "@/data/settings";
import { useAppStore } from "@/store/useAppStore";

interface ScanResult {
  settingId: string;
  settingName: string;
  sectionName: string;
  currentState: "changed" | "default" | "unknown";
  safety: "Safe" | "Moderate" | "Risky";
}

export function RegistryScanTab() {
  const { settings, toggleSetting } = useAppStore();
  const [scanComplete, setScanComplete] = useState(false);
  const [scanning, setScanning] = useState(false);
  const [scanResults, setScanResults] = useState<ScanResult[]>([]);

  // Simulated scan for web mode — in Tauri this would call PowerShell
  const handleScan = () => {
    setScanning(true);
    // Simulate scan delay
    setTimeout(() => {
      const results: ScanResult[] = [];
      // In a real Tauri app, this would execute PowerShell commands
      // to check registry values and compare against defaults.
      // For now, we simulate with random results.
      sections.forEach((section) => {
        section.settings.forEach((s) => {
          // Randomly mark some as "changed" to simulate detection
          const rand = Math.random();
          results.push({
            settingId: s.id,
            settingName: s.name,
            sectionName: section.name,
            currentState: rand < 0.2 ? "changed" : rand < 0.1 ? "unknown" : "default",
            safety: s.safety,
          });
        });
      });
      setScanResults(results);
      setScanComplete(true);
      setScanning(false);
    }, 2000);
  };

  const changedCount = scanResults.filter((r) => r.currentState === "changed").length;
  const unknownCount = scanResults.filter((r) => r.currentState === "unknown").length;

  // Apply detected changes to the GUI
  const handleApplyDetected = () => {
    scanResults.forEach((r) => {
      if (r.currentState === "changed") {
        toggleSetting(r.settingId);
      }
    });
  };

  // Generate PowerShell scan script for download
  const handleDownloadScanScript = () => {
    const script = `# WinPostInstall Registry Scanner
# This script scans current system state and outputs a JSON report
# of settings that differ from Windows defaults.

$scanResults = @()

# --- Privacy Settings ---
# Telemetry
$telemetry = Get-ItemProperty -Path "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\DataCollection" -Name "AllowTelemetry" -ErrorAction SilentlyContinue
if ($telemetry -and $telemetry.AllowTelemetry -ne 3) {
    $scanResults += @{ SettingId = "Priv_1"; State = "changed"; Value = $telemetry.AllowTelemetry }
}

# Advertising ID
$adId = Get-ItemProperty -Path "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\AdvertisingInfo" -Name "Enabled" -ErrorAction SilentlyContinue
if ($adId -and $adId.Enabled -ne 1) {
    $scanResults += @{ SettingId = "Priv_5"; State = "changed"; Value = $adId.Enabled }
}

# Cortana
$cortana = Get-ItemProperty -Path "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Search" -Name "BingSearchEnabled" -ErrorAction SilentlyContinue
if ($cortana -and $cortana.BingSearchEnabled -ne 1) {
    $scanResults += @{ SettingId = "Priv_2"; State = "changed"; Value = $cortana.BingSearchEnabled }
}

# --- Output Results ---
$scanResults | ConvertTo-Json -Depth 3 | Out-File -FilePath "WinPostInstall-ScanResults.json" -Encoding UTF8
Write-Host "Scan complete. Results saved to WinPostInstall-ScanResults.json"
Write-Host "Found $($scanResults.Count) non-default settings."
`;

    const blob = new Blob([script], { type: "text/plain" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "Scan-Registry.ps1";
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h2 className="text-base font-semibold text-[var(--wpi-text)]">System Scanner</h2>
          <p className="text-xs text-[var(--wpi-muted)]">
            Scan current system state to detect non-default settings
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={handleDownloadScanScript}
            className="h-8 gap-1.5 bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:bg-[var(--wpi-card)] hover:text-[var(--wpi-text)] text-xs"
          >
            <Download className="h-3.5 w-3.5" />
            Download Scanner Script
          </Button>
          <Button
            size="sm"
            onClick={handleScan}
            disabled={scanning}
            className="h-8 gap-1.5 bg-[var(--wpi-accent)] hover:bg-[var(--wpi-accent)]/90 text-[var(--wpi-bg)] font-semibold text-xs"
          >
            <RefreshCw className={`h-3.5 w-3.5 ${scanning ? "animate-spin" : ""}`} />
            {scanning ? "Scanning..." : "Scan System"}
          </Button>
        </div>
      </div>

      {/* Info banner */}
      <motion.div
        initial={{ opacity: 0, y: -5 }}
        animate={{ opacity: 1, y: 0 }}
        className="rounded-xl border border-[var(--wpi-accent)]/20 bg-[var(--wpi-accent)]/5 p-4"
      >
        <div className="flex items-start gap-3">
          <Monitor className="h-5 w-5 text-[var(--wpi-accent)] shrink-0 mt-0.5" />
          <div>
            <h3 className="text-sm font-semibold text-[var(--wpi-accent)] mb-1">Registry Scanner</h3>
            <p className="text-xs text-[var(--wpi-accent)]/70">
              Scans your Windows registry and system settings to detect which settings have already been modified from their defaults.
              In the desktop app (Tauri), this runs PowerShell directly. In the web version, download the scanner script and run it on your machine.
            </p>
          </div>
        </div>
      </motion.div>

      {!scanComplete ? (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          className="flex flex-col items-center justify-center py-16 text-center"
        >
          <div className="h-16 w-16 rounded-2xl bg-[var(--wpi-deep)] border border-[var(--wpi-border)] flex items-center justify-center mb-4">
            <Scan className="h-8 w-8 text-[var(--wpi-muted)]/50" />
          </div>
          <p className="text-sm text-[var(--wpi-muted)] mb-1">No scan results yet</p>
          <p className="text-xs text-[var(--wpi-muted)]/50">Click Scan System or download the script</p>
        </motion.div>
      ) : (
        <>
          {/* Scan Summary */}
          <div className="grid grid-cols-3 gap-3">
            <div className="rounded-xl border border-[var(--wpi-safe-20)] bg-[var(--wpi-safe-5)] p-3 text-center">
              <p className="text-lg font-bold text-[var(--wpi-safe)]">{scanResults.length - changedCount - unknownCount}</p>
              <p className="text-[10px] text-[var(--wpi-safe)]/70">Default</p>
            </div>
            <div className="rounded-xl border border-[var(--wpi-moderate-20)] bg-[var(--wpi-moderate-5)] p-3 text-center">
              <p className="text-lg font-bold text-[var(--wpi-moderate)]">{changedCount}</p>
              <p className="text-[10px] text-[var(--wpi-moderate)]/70">Modified</p>
            </div>
            <div className="rounded-xl border border-[var(--wpi-muted)]/20 bg-[var(--wpi-muted)]/5 p-3 text-center">
              <p className="text-lg font-bold text-[var(--wpi-muted)]">{unknownCount}</p>
              <p className="text-[10px] text-[var(--wpi-muted)]/70">Unknown</p>
            </div>
          </div>

          {changedCount > 0 && (
            <div className="flex items-center gap-2">
              <Button
                size="sm"
                onClick={handleApplyDetected}
                className="h-8 gap-1.5 bg-[var(--wpi-accent)] hover:bg-[var(--wpi-accent)]/90 text-[var(--wpi-accent-foreground)] font-semibold text-xs"
              >
                <CheckCircle2 className="h-3.5 w-3.5" />
                Apply {changedCount} Detected Changes
              </Button>
              <span className="text-[10px] text-[var(--wpi-muted)]">Toggle all detected non-default settings in the GUI</span>
            </div>
          )}

          {/* Results */}
          <ScrollArea className="max-h-[calc(100vh-480px)]">
            <div className="space-y-2 p-1">
              {scanResults.filter((r) => r.currentState === "changed").map((result, index) => (
                <motion.div
                  key={result.settingId}
                  initial={{ opacity: 0, x: -10 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ delay: index * 0.02 }}
                  className="flex items-center gap-3 p-3 rounded-lg bg-[var(--wpi-moderate-5)] border border-[var(--wpi-moderate-20)]"
                >
                  <AlertCircle className="h-4 w-4 text-[var(--wpi-moderate)] shrink-0" />
                  <div className="flex-1 min-w-0">
                    <span className="text-sm text-[var(--wpi-text)]">{result.settingName}</span>
                    <span className="text-[10px] text-[var(--wpi-muted)] ml-2">({result.sectionName})</span>
                  </div>
                  <Badge variant="outline" className={`h-4 px-1 text-[9px] shrink-0 ${
                    result.safety === "Safe" ? "bg-[var(--wpi-safe-5)] border-[var(--wpi-safe-20)] text-[var(--wpi-safe)]"
                      : result.safety === "Moderate" ? "bg-[var(--wpi-moderate-5)] border-[var(--wpi-moderate-20)] text-[var(--wpi-moderate)]"
                      : "bg-[var(--wpi-risky-5)] border-[var(--wpi-risky-20)] text-[var(--wpi-risky)]"
                  }`}>
                    {result.safety}
                  </Badge>
                </motion.div>
              ))}
            </div>
          </ScrollArea>
        </>
      )}
    </div>
  );
}
