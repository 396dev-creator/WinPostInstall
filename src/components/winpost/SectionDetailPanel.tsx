"use client";

import React from "react";
import { motion, AnimatePresence } from "framer-motion";
import {
  Shield, Trash2, FolderOpen, Settings, Zap, Lock,
  Wifi, RefreshCw, HardDrive, Package, FileSpreadsheet,
  Globe, Cloud, Gamepad2, CalendarClock, ShieldCheck,
  Sparkles, Puzzle, X,
} from "lucide-react";
import { Switch } from "@/components/ui/switch";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { sections } from "@/data/settings";
import { useAppStore } from "@/store/useAppStore";
import { SafetyBadge } from "./SafetyBadge";

const iconMap: Record<string, React.ComponentType<{ className?: string }>> = {
  Shield, Trash2, FolderOpen, Settings, Zap, Lock,
  Wifi, RefreshCw, HardDrive, Package, FileSpreadsheet,
  Globe, Cloud, Gamepad2, CalendarClock, ShieldCheck,
  Sparkles, Puzzle,
};

export function SectionDetailPanel() {
  const { activeSectionId, setActiveSectionId, settings, toggleSetting, toggleSectionAll, searchQuery } = useAppStore();

  const section = activeSectionId ? sections.find((s) => s.id === activeSectionId) : null;

  const Icon = section ? (iconMap[section.icon] || Settings) : Settings;
  const enabledCount = section ? section.settings.filter((s) => settings[s.id]).length : 0;
  const totalCount = section ? section.settings.length : 0;

  const filteredSettings = section && searchQuery
    ? section.settings.filter(
        (s) =>
          s.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
          s.desc.toLowerCase().includes(searchQuery.toLowerCase())
      )
    : (section?.settings ?? []);

  const safetyCounts = section ? {
    Safe: section.settings.filter((s) => s.safety === "Safe").length,
    Moderate: section.settings.filter((s) => s.safety === "Moderate").length,
    Risky: section.settings.filter((s) => s.safety === "Risky").length,
  } : { Safe: 0, Moderate: 0, Risky: 0 };

  return (
    <AnimatePresence>
      {activeSectionId && section && (
        <>
          {/* Backdrop */}
          <motion.div
            key="backdrop"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={() => setActiveSectionId(null)}
            className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm"
          />

          {/* Panel */}
          <motion.div
            key="panel"
            initial={{ x: "100%" }}
            animate={{ x: 0 }}
            exit={{ x: "100%" }}
            transition={{ type: "spring", damping: 25, stiffness: 200 }}
            className="fixed right-0 top-0 bottom-0 z-50 w-full max-w-lg bg-[#0a0a0f] border-l border-[#2a2a3e] shadow-2xl flex flex-col"
          >
            {/* Header */}
            <div className="p-5 border-b border-[#2a2a3e]">
              <div className="flex items-center justify-between mb-3">
                <div className="flex items-center gap-3">
                  <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-[#00d4ff]/10 border border-[#00d4ff]/20">
                    <Icon className="h-5 w-5 text-[#00d4ff]" />
                  </div>
                  <div>
                    <h2 className="text-base font-bold text-[#e0e0e0]">{section.name}</h2>
                    <p className="text-xs text-[#8888a0]">{section.description}</p>
                  </div>
                </div>
                <Button
                  variant="ghost"
                  size="icon"
                  onClick={() => setActiveSectionId(null)}
                  className="h-8 w-8 text-[#8888a0] hover:text-[#e0e0e0] hover:bg-[#1a1a2e]"
                >
                  <X className="h-4 w-4" />
                </Button>
              </div>

              {/* Stats row */}
              <div className="flex items-center gap-3 flex-wrap">
                <div className="flex items-center gap-1.5">
                  <span className="text-xs text-[#8888a0]">Enabled:</span>
                  <span className="text-xs font-semibold text-[#00d4ff]">{enabledCount}/{totalCount}</span>
                </div>
                <div className="h-3 w-px bg-[#2a2a3e]" />
                {safetyCounts.Safe > 0 && (
                  <Badge variant="outline" className="h-5 text-[10px] bg-[#22c55e]/5 border-[#22c55e]/20 text-[#22c55e]">
                    {safetyCounts.Safe} Safe
                  </Badge>
                )}
                {safetyCounts.Moderate > 0 && (
                  <Badge variant="outline" className="h-5 text-[10px] bg-[#eab308]/5 border-[#eab308]/20 text-[#eab308]">
                    {safetyCounts.Moderate} Moderate
                  </Badge>
                )}
                {safetyCounts.Risky > 0 && (
                  <Badge variant="outline" className="h-5 text-[10px] bg-[#ef4444]/5 border-[#ef4444]/20 text-[#ef4444]">
                    {safetyCounts.Risky} Risky
                  </Badge>
                )}

                <div className="ml-auto">
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => toggleSectionAll(section.id, enabledCount < totalCount)}
                    className="h-7 text-[10px] text-[#00d4ff] hover:bg-[#00d4ff]/10 hover:text-[#00d4ff]"
                  >
                    {enabledCount === totalCount ? "Disable All" : "Enable All"}
                  </Button>
                </div>
              </div>
            </div>

            {/* Settings list */}
            <ScrollArea className="flex-1">
              <div className="p-4 space-y-2">
                {filteredSettings.map((setting, index) => {
                  const isEnabled = settings[setting.id] ?? false;
                  return (
                    <motion.div
                      key={setting.id}
                      initial={{ opacity: 0, x: 20 }}
                      animate={{ opacity: 1, x: 0 }}
                      transition={{ delay: index * 0.02 }}
                      className={`group flex items-center gap-3 rounded-lg p-3 transition-colors ${
                        isEnabled
                          ? "bg-[#00d4ff]/5 border border-[#00d4ff]/10"
                          : "bg-[#12121a] border border-[#2a2a3e] hover:border-[#2a2a3e]/80"
                      }`}
                    >
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 mb-0.5">
                          <span className={`text-sm font-medium ${isEnabled ? "text-[#e0e0e0]" : "text-[#8888a0]"}`}>
                            {setting.name}
                          </span>
                          <SafetyBadge safety={setting.safety} compact />
                        </div>
                        <TooltipProvider delayDuration={200}>
                          <Tooltip>
                            <TooltipTrigger asChild>
                              <p className="text-[11px] text-[#8888a0]/70 line-clamp-1 cursor-help">
                                {setting.desc}
                              </p>
                            </TooltipTrigger>
                            <TooltipContent
                              side="bottom"
                              align="start"
                              className="max-w-xs bg-[#1a1a2e] border-[#2a2a3e] text-[#e0e0e0] text-xs"
                            >
                              {setting.desc}
                            </TooltipContent>
                          </Tooltip>
                        </TooltipProvider>
                      </div>

                      <Switch
                        checked={isEnabled}
                        onCheckedChange={() => toggleSetting(setting.id)}
                        className="data-[state=checked]:bg-[#00d4ff] data-[state=unchecked]:bg-[#2a2a3e] shrink-0"
                      />
                    </motion.div>
                  );
                })}

                {filteredSettings.length === 0 && (
                  <div className="py-12 text-center">
                    <p className="text-sm text-[#8888a0]">No settings match your search</p>
                  </div>
                )}
              </div>
            </ScrollArea>

            {/* Footer */}
            <div className="p-4 border-t border-[#2a2a3e] bg-[#12121a]">
              <div className="flex items-center justify-between">
                <span className="text-xs text-[#8888a0]">
                  {enabledCount} of {totalCount} settings enabled
                </span>
                <div className="h-2 w-32 rounded-full bg-[#2a2a3e] overflow-hidden">
                  <motion.div
                    className="h-full rounded-full bg-[#00d4ff]"
                    animate={{ width: `${totalCount > 0 ? (enabledCount / totalCount) * 100 : 0}%` }}
                    transition={{ duration: 0.3 }}
                  />
                </div>
              </div>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
}
