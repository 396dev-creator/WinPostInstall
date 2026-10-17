"use client";

import React from "react";
import { motion } from "framer-motion";
import { Download, AlertTriangle, CheckCircle2, Shield, ShieldAlert, ShieldX } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";
import { sections } from "@/data/settings";
import { useAppStore } from "@/store/useAppStore";
import { SafetyBadge } from "./SafetyBadge";

export function PreviewTab() {
  const { settings, selectedSoftware, applyChanges, generateConfig } = useAppStore();

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

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h2 className="text-base font-semibold text-[#e0e0e0]">Preview Changes</h2>
          <p className="text-xs text-[#8888a0]">
            Review all changes before applying
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Badge className="bg-[#00d4ff]/10 text-[#00d4ff] border-[#00d4ff]/20 text-xs">
            {totalEnabled} changes
          </Badge>
          <Button
            size="sm"
            onClick={applyChanges}
            disabled={totalEnabled === 0}
            className="h-8 gap-1.5 bg-[#00d4ff] hover:bg-[#00d4ff]/90 text-[#0a0a0f] font-semibold text-xs shadow-[0_0_20px_rgba(0,212,255,0.15)]"
          >
            <Download className="h-3.5 w-3.5" />
            Confirm & Apply
          </Button>
        </div>
      </div>

      {/* Safety summary cards */}
      {totalEnabled > 0 && (
        <div className="grid grid-cols-3 gap-3">
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            className="rounded-xl border border-[#22c55e]/20 bg-[#22c55e]/5 p-3 text-center"
          >
            <Shield className="h-5 w-5 text-[#22c55e] mx-auto mb-1" />
            <p className="text-lg font-bold text-[#22c55e]">{totalSafe}</p>
            <p className="text-[10px] text-[#22c55e]/70">Safe Changes</p>
          </motion.div>
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ delay: 0.05 }}
            className="rounded-xl border border-[#eab308]/20 bg-[#eab308]/5 p-3 text-center"
          >
            <ShieldAlert className="h-5 w-5 text-[#eab308] mx-auto mb-1" />
            <p className="text-lg font-bold text-[#eab308]">{totalModerate}</p>
            <p className="text-[10px] text-[#eab308]/70">Moderate Changes</p>
          </motion.div>
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ delay: 0.1 }}
            className="rounded-xl border border-[#ef4444]/20 bg-[#ef4444]/5 p-3 text-center"
          >
            <ShieldX className="h-5 w-5 text-[#ef4444] mx-auto mb-1" />
            <p className="text-lg font-bold text-[#ef4444]">{totalRisky}</p>
            <p className="text-[10px] text-[#ef4444]/70">Risky Changes</p>
          </motion.div>
        </div>
      )}

      {/* Safety warnings */}
      {hasWarnings && (
        <motion.div
          initial={{ opacity: 0, y: -10 }}
          animate={{ opacity: 1, y: 0 }}
          className="rounded-xl border border-[#eab308]/20 bg-[#eab308]/5 p-4"
        >
          <div className="flex items-start gap-3">
            <AlertTriangle className="h-5 w-5 text-[#eab308] shrink-0 mt-0.5" />
            <div>
              <h3 className="text-sm font-semibold text-[#eab308] mb-1">Safety Warnings</h3>
              <p className="text-xs text-[#eab308]/70">
                {totalModerate > 0 && `${totalModerate} Moderate changes may affect some functionality. `}
                {totalRisky > 0 && `${totalRisky} Risky changes could cause significant issues. `}
                Please review carefully before applying.
              </p>
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
          <div className="h-16 w-16 rounded-2xl bg-[#12121a] border border-[#2a2a3e] flex items-center justify-center mb-4">
            <CheckCircle2 className="h-8 w-8 text-[#8888a0]/50" />
          </div>
          <p className="text-sm text-[#8888a0] mb-1">No changes selected</p>
          <p className="text-xs text-[#8888a0]/50">Toggle settings to see them here</p>
        </motion.div>
      ) : (
        <ScrollArea className="max-h-[calc(100vh-400px)]">
          <div className="space-y-4 p-1">
            {changeSummary.map(({ section, enabledSettings, safetyBreakdown }, index) => (
              <motion.div
                key={section.id}
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: index * 0.05 }}
                className="rounded-xl border border-[#2a2a3e] bg-[#1a1a2e] overflow-hidden"
              >
                {/* Section header */}
                <div className="flex items-center justify-between p-3 border-b border-[#2a2a3e] bg-[#12121a]">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-semibold text-[#e0e0e0]">{section.name}</span>
                    <Badge variant="outline" className="h-4 px-1 text-[9px] bg-[#00d4ff]/5 border-[#00d4ff]/20 text-[#00d4ff]">
                      {enabledSettings.length}
                    </Badge>
                  </div>
                  <div className="flex items-center gap-1.5">
                    {safetyBreakdown.Safe > 0 && (
                      <Badge variant="outline" className="h-4 px-1 text-[9px] bg-[#22c55e]/5 border-[#22c55e]/20 text-[#22c55e]">
                        {safetyBreakdown.Safe} Safe
                      </Badge>
                    )}
                    {safetyBreakdown.Moderate > 0 && (
                      <Badge variant="outline" className="h-4 px-1 text-[9px] bg-[#eab308]/5 border-[#eab308]/20 text-[#eab308]">
                        {safetyBreakdown.Moderate} Mod
                      </Badge>
                    )}
                    {safetyBreakdown.Risky > 0 && (
                      <Badge variant="outline" className="h-4 px-1 text-[9px] bg-[#ef4444]/5 border-[#ef4444]/20 text-[#ef4444]">
                        {safetyBreakdown.Risky} Risk
                      </Badge>
                    )}
                  </div>
                </div>

                {/* Settings list */}
                <div className="divide-y divide-[#2a2a3e]/50">
                  {enabledSettings.map((setting) => (
                    <div
                      key={setting.id}
                      className="flex items-center gap-2 px-3 py-2"
                    >
                      <CheckCircle2 className={`h-3.5 w-3.5 shrink-0 ${
                        setting.safety === "Safe" ? "text-[#22c55e]" :
                        setting.safety === "Moderate" ? "text-[#eab308]" : "text-[#ef4444]"
                      }`} />
                      <span className="text-xs text-[#e0e0e0] flex-1">{setting.name}</span>
                      <SafetyBadge safety={setting.safety} compact />
                    </div>
                  ))}
                </div>
              </motion.div>
            ))}

            {/* Software section */}
            {selectedSoftware.length > 0 && (
              <motion.div
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                className="rounded-xl border border-[#2a2a3e] bg-[#1a1a2e] overflow-hidden"
              >
                <div className="flex items-center justify-between p-3 border-b border-[#2a2a3e] bg-[#12121a]">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-semibold text-[#e0e0e0]">Software to Install</span>
                    <Badge variant="outline" className="h-4 px-1 text-[9px] bg-[#00d4ff]/5 border-[#00d4ff]/20 text-[#00d4ff]">
                      {selectedSoftware.length}
                    </Badge>
                  </div>
                </div>
                <div className="p-3">
                  <p className="text-xs text-[#8888a0]">
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
