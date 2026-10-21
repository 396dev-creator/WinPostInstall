"use client";

import React from "react";
import { motion } from "framer-motion";
import { Download, AlertTriangle, CheckCircle2, Shield, ShieldAlert, ShieldX, AlertCircle, RotateCcw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Checkbox } from "@/components/ui/checkbox";
import { sections, getAllConflicts } from "@/data/settings";
import { useAppStore } from "@/store/useAppStore";
import { SafetyBadge } from "./SafetyBadge";

export function PreviewTab() {
  const { settings, selectedSoftware, applyChanges, generateConfig } = useAppStore();
  const [createRestorePoint, setCreateRestorePoint] = React.useState(true);

  // Build change summary
  const changeSummary = sections.map((section) => {
    const enabledSettings = section.settings.filter((s) => settings[s.id]);
    const safetyBreakdown = {
      Safe: enabledSettings.filter((s) => s.safety === "Safe").length,
      Moderate: enabledSettings.filter((s) => s.safety === "Moderate").length,
      Risky: enabledSettings.filter((s) => s.safety === "Risky").length,
    };
    return {
      section,
      enabledSettings,
      safetyBreakdown,
      hasChanges: enabledSettings.length > 0,
    };
  }).filter((s) => s.hasChanges);

  const totalEnabled = changeSummary.reduce((sum, s) => sum + s.enabledSettings.length, 0);
  const totalSafe = changeSummary.reduce((sum, s) => sum + s.safetyBreakdown.Safe, 0);
  const totalModerate = changeSummary.reduce((sum, s) => sum + s.safetyBreakdown.Moderate, 0);
  const totalRisky = changeSummary.reduce((sum, s) => sum + s.safetyBreakdown.Risky, 0);
  const hasWarnings = totalModerate > 0 || totalRisky > 0;

  // Check for setting conflicts
  const allConflicts = getAllConflicts(settings);
  const hasConflicts = allConflicts.length > 0;

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h2 className="text-base font-semibold text-[var(--wpi-text)]">Preview Changes</h2>
          <p className="text-xs text-[var(--wpi-muted)]">
            Review all changes before applying
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Badge className="bg-[var(--wpi-accent)]/10 text-[var(--wpi-accent)] border-[var(--wpi-accent)]/20 text-xs">
            {totalEnabled} changes
          </Badge>
          <Button
            size="sm"
            onClick={() => {
              const config = generateConfig();
              const fullConfig = { ...config, createRestorePoint };
              const blob = new Blob([JSON.stringify(fullConfig, null, 2)], { type: "application/json" });
              const url = URL.createObjectURL(blob);
              const a = document.createElement("a");
              a.href = url;
              a.download = "WinPostInstall-Config.json";
              a.click();
              URL.revokeObjectURL(url);
            }}
            disabled={totalEnabled === 0}
            className="h-8 gap-1.5 bg-[var(--wpi-accent)] hover:bg-[var(--wpi-accent)]/90 text-[var(--wpi-accent-foreground)] font-semibold text-xs shadow-[var(--wpi-accent-glow)]"
          >
            <Download className="h-3.5 w-3.5" />
            Confirm & Apply
          </Button>
        </div>
      </div>

      {/* Restore Point Option — Apple-style toggle row */}
      {totalEnabled > 0 && (
        <motion.div
          initial={{ opacity: 0, y: -5 }}
          animate={{ opacity: 1, y: 0 }}
          className="flex items-center gap-3 rounded-lg border border-[var(--wpi-border)] bg-[var(--wpi-deep)] p-3"
        >
          <Checkbox
            id="restore-point"
            checked={createRestorePoint}
            onCheckedChange={(checked) => setCreateRestorePoint(checked === true)}
            className="border-[var(--wpi-accent)]/30 data-[state=checked]:bg-[var(--wpi-accent)] data-[state=checked]:border-[var(--wpi-accent)]"
          />
          <div className="flex-1">
            <label htmlFor="restore-point" className="text-xs font-medium text-[var(--wpi-text)] cursor-pointer flex items-center gap-1.5">
              <RotateCcw className="h-3.5 w-3.5 text-[var(--wpi-accent)]" />
              Create System Restore Point before applying
            </label>
            <p className="text-[10px] text-[var(--wpi-muted)] mt-0.5">
              Recommended. Creates a restore point so you can roll back if anything goes wrong.
            </p>
          </div>
        </motion.div>
      )}

      {/* Safety summary cards — Apple-style stat blocks */}
      {totalEnabled > 0 && (
        <div className="grid grid-cols-3 gap-3">
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ duration: 0.3, ease: [0.25, 0.1, 0.25, 1] }}
            className="rounded-xl border border-[var(--wpi-safe-20)] bg-[var(--wpi-safe-5)] p-3 text-center"
          >
            <Shield className="h-5 w-5 text-[var(--wpi-safe)] mx-auto mb-1" />
            <p className="text-lg font-bold text-[var(--wpi-safe)]">{totalSafe}</p>
            <p className="text-[10px] text-[var(--wpi-safe)]/70">Safe Changes</p>
          </motion.div>
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ delay: 0.05, duration: 0.3, ease: [0.25, 0.1, 0.25, 1] }}
            className="rounded-xl border border-[var(--wpi-moderate-20)] bg-[var(--wpi-moderate-5)] p-3 text-center"
          >
            <ShieldAlert className="h-5 w-5 text-[var(--wpi-moderate)] mx-auto mb-1" />
            <p className="text-lg font-bold text-[var(--wpi-moderate)]">{totalModerate}</p>
            <p className="text-[10px] text-[var(--wpi-moderate)]/70">Moderate Changes</p>
          </motion.div>
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ delay: 0.1, duration: 0.3, ease: [0.25, 0.1, 0.25, 1] }}
            className="rounded-xl border border-[var(--wpi-risky-20)] bg-[var(--wpi-risky-5)] p-3 text-center"
          >
            <ShieldX className="h-5 w-5 text-[var(--wpi-risky)] mx-auto mb-1" />
            <p className="text-lg font-bold text-[var(--wpi-risky)]">{totalRisky}</p>
            <p className="text-[10px] text-[var(--wpi-risky)]/70">Risky Changes</p>
          </motion.div>
        </div>
      )}

      {/* Safety warnings */}
      {hasWarnings && (
        <motion.div
          initial={{ opacity: 0, y: -10 }}
          animate={{ opacity: 1, y: 0 }}
          className="rounded-xl border border-[var(--wpi-moderate-20)] bg-[var(--wpi-moderate-5)] p-4"
        >
          <div className="flex items-start gap-3">
            <AlertTriangle className="h-5 w-5 text-[var(--wpi-moderate)] shrink-0 mt-0.5" />
            <div>
              <h3 className="text-sm font-semibold text-[var(--wpi-moderate)] mb-1">Safety Warnings</h3>
              <p className="text-xs text-[var(--wpi-moderate)]/70">
                {totalModerate > 0 && `${totalModerate} Moderate changes may affect some functionality. `}
                {totalRisky > 0 && `${totalRisky} Risky changes could cause significant issues. `}
                Please review carefully before applying.
              </p>
            </div>
          </div>
        </motion.div>
      )}

      {/* Setting conflicts */}
      {hasConflicts && (
        <motion.div
          initial={{ opacity: 0, y: -10 }}
          animate={{ opacity: 1, y: 0 }}
          className="rounded-xl border border-[var(--wpi-risky-20)] bg-[var(--wpi-risky-5)] p-4"
        >
          <div className="flex items-start gap-3">
            <AlertCircle className="h-5 w-5 text-[var(--wpi-risky)] shrink-0 mt-0.5" />
            <div className="flex-1">
              <h3 className="text-sm font-semibold text-[var(--wpi-risky)] mb-2">Setting Conflicts ({allConflicts.length})</h3>
              <div className="space-y-2">
                {allConflicts.map((c, i) => (
                  <div key={i} className="flex items-start gap-2 text-xs text-[var(--wpi-risky)]/80">
                    <Badge variant="outline" className="h-4 shrink-0 text-[9px] bg-[var(--wpi-risky-10)] border-[var(--wpi-risky-20)] text-[var(--wpi-risky)]">
                      {c.type === "conflict" ? "Conflict" : "Missing Dep"}
                    </Badge>
                    <span>{c.settingName} ↔ {c.targetName}: {c.message}</span>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </motion.div>
      )}

      {totalEnabled === 0 ? (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          className="flex flex-col items-center justify-center py-16 text-center"
        >
          <div className="h-14 w-14 rounded-2xl bg-[var(--wpi-deep)] border border-[var(--wpi-border)] flex items-center justify-center mb-4">
            <CheckCircle2 className="h-6 w-6 text-[var(--wpi-muted)]/40" />
          </div>
          <p className="text-sm text-[var(--wpi-muted)] mb-1">No changes selected</p>
          <p className="text-xs text-[var(--wpi-muted)]/50">Toggle settings to see them here</p>
        </motion.div>
      ) : (
        <ScrollArea className="max-h-[calc(100vh-400px)]">
          <div className="space-y-3 p-0.5">
            {changeSummary.map(({ section, enabledSettings, safetyBreakdown }, index) => (
              <motion.div
                key={section.id}
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: index * 0.04, duration: 0.3, ease: [0.25, 0.1, 0.25, 1] }}
                className="rounded-xl border border-[var(--wpi-border)] bg-[var(--wpi-card)] overflow-hidden"
              >
                {/* Section header */}
                <div className="flex items-center justify-between p-3 border-b border-[var(--wpi-border)] bg-[var(--wpi-deep)]">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-semibold text-[var(--wpi-text)]">{section.name}</span>
                    <Badge variant="outline" className="h-4 px-1 text-[9px] bg-[var(--wpi-accent)]/5 border-[var(--wpi-accent)]/20 text-[var(--wpi-accent)]">
                      {enabledSettings.length}
                    </Badge>
                  </div>
                  <div className="flex items-center gap-1.5">
                    {safetyBreakdown.Safe > 0 && (
                      <Badge variant="outline" className="h-4 px-1 text-[9px] bg-[var(--wpi-safe-5)] border-[var(--wpi-safe-20)] text-[var(--wpi-safe)]">
                        {safetyBreakdown.Safe} Safe
                      </Badge>
                    )}
                    {safetyBreakdown.Moderate > 0 && (
                      <Badge variant="outline" className="h-4 px-1 text-[9px] bg-[var(--wpi-moderate-5)] border-[var(--wpi-moderate-20)] text-[var(--wpi-moderate)]">
                        {safetyBreakdown.Moderate} Mod
                      </Badge>
                    )}
                    {safetyBreakdown.Risky > 0 && (
                      <Badge variant="outline" className="h-4 px-1 text-[9px] bg-[var(--wpi-risky-5)] border-[var(--wpi-risky-20)] text-[var(--wpi-risky)]">
                        {safetyBreakdown.Risky} Risk
                      </Badge>
                    )}
                  </div>
                </div>

                {/* Settings list */}
                <div className="divide-y divide-[var(--wpi-border-subtle)]">
                  {enabledSettings.map((setting) => (
                    <div
                      key={setting.id}
                      className="flex items-center gap-2 px-3 py-2"
                    >
                      <CheckCircle2 className={`h-3.5 w-3.5 shrink-0 ${
                        setting.safety === "Safe" ? "text-[var(--wpi-safe)]" :
                        setting.safety === "Moderate" ? "text-[var(--wpi-moderate)]" : "text-[var(--wpi-risky)]"
                      }`} />
                      <span className="text-xs text-[var(--wpi-text)] flex-1">{setting.name}</span>
                      <SafetyBadge safety={setting.safety} compact />
                    </div>
                  ))}
                </div>
              </motion.div>
            ))}

            {/* Software section */}
            {selectedSoftware.length > 0 && (
              <motion.div
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                className="rounded-xl border border-[var(--wpi-border)] bg-[var(--wpi-card)] overflow-hidden"
              >
                <div className="flex items-center justify-between p-3 border-b border-[var(--wpi-border)] bg-[var(--wpi-deep)]">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-semibold text-[var(--wpi-text)]">Software to Install</span>
                    <Badge variant="outline" className="h-4 px-1 text-[9px] bg-[var(--wpi-accent)]/5 border-[var(--wpi-accent)]/20 text-[var(--wpi-accent)]">
                      {selectedSoftware.length}
                    </Badge>
                  </div>
                </div>
                <div className="p-3">
                  <p className="text-xs text-[var(--wpi-muted)]">
                    {selectedSoftware.length} applications will be installed via Winget
                  </p>
                </div>
              </motion.div>
            )}
          </div>
        </ScrollArea>
      )}
    </div>
  );
}
