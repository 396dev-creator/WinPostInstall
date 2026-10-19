"use client";

import React from "react";
import { motion } from "framer-motion";
import {
  Shield, Trash2, FolderOpen, Settings, Zap, Lock,
  Wifi, RefreshCw, HardDrive, Package, FileSpreadsheet,
  Globe, Cloud, Gamepad2, CalendarClock, ShieldCheck,
  Sparkles, Puzzle,
} from "lucide-react";
import { Switch } from "@/components/ui/switch";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { sections, type Section } from "@/data/settings";
import { useAppStore } from "@/store/useAppStore";
import { SafetyBadge } from "./SafetyBadge";
import { QuickSelectBar } from "./QuickSelectBar";

const iconMap: Record<string, React.ComponentType<{ className?: string }>> = {
  Shield, Trash2, FolderOpen, Settings, Zap, Lock,
  Wifi, RefreshCw, HardDrive, Package, FileSpreadsheet,
  Globe, Cloud, Gamepad2, CalendarClock, ShieldCheck,
  Sparkles, Puzzle,
};

function getSectionSafety(section: Section): "Safe" | "Moderate" | "Risky" {
  const settings = section.settings;
  if (settings.some((s) => s.safety === "Risky")) return "Risky";
  if (settings.some((s) => s.safety === "Moderate")) return "Moderate";
  return "Safe";
}

interface DashboardTabProps {
  onSectionClick: (sectionId: string) => void;
}

export function DashboardTab({ onSectionClick }: DashboardTabProps) {
  const { settings, searchQuery, toggleSectionAll, getEnabledCount, getTotalCount, getSectionSafetyCounts, getSectionEnabledSafetyCounts } = useAppStore();

  const filteredSections = sections.filter((section) => {
    if (!searchQuery) return true;
    const q = searchQuery.toLowerCase();
    return (
      section.name.toLowerCase().includes(q) ||
      section.settings.some(
        (s) => s.name.toLowerCase().includes(q) || s.desc.toLowerCase().includes(q)
      )
    );
  });

  return (
    <div className="space-y-4">
      {/* Quick Select Bar */}
      <QuickSelectBar />

      {/* Section Cards Grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 p-1">
        {filteredSections.map((section, index) => {
          const Icon = iconMap[section.icon] || Settings;
          const enabled = getEnabledCount(section.id);
          const total = getTotalCount(section.id);
          const allEnabled = enabled === total;
          const safety = getSectionSafety(section);
          const isFiltered = !!searchQuery;

          // Safety breakdown for this section
          const sCounts = getSectionSafetyCounts(section.id);
          const eCounts = getSectionEnabledSafetyCounts(section.id);

          // Count filtered settings for search
          const matchingSettings = isFiltered
            ? section.settings.filter(
                (s) =>
                  s.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
                  s.desc.toLowerCase().includes(searchQuery.toLowerCase())
              )
            : section.settings;

          return (
            <motion.div
              key={section.id}
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: index * 0.03, duration: 0.3 }}
              onClick={() => onSectionClick(section.id)}
              className="group relative cursor-pointer rounded-xl border border-[var(--wpi-border)] bg-[var(--wpi-card)] p-4 transition-all duration-200 hover:border-[var(--wpi-accent)]/30 hover:bg-[var(--wpi-card)]/80 hover:shadow-[0_0_30px_rgba(0,212,255,0.05)]"
            >
              {/* Glow effect on hover */}
              <div className="absolute inset-0 rounded-xl bg-gradient-to-br from-[var(--wpi-accent)]/5 to-transparent opacity-0 transition-opacity group-hover:opacity-100" />

              <div className="relative flex items-start gap-3">
                {/* Icon */}
                <div className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-lg ${allEnabled ? "bg-[var(--wpi-accent)]/15 border border-[var(--wpi-accent)]/30" : "bg-[var(--wpi-deep)] border border-[var(--wpi-border)]"} transition-colors`}>
                  <Icon className={`h-5 w-5 ${allEnabled ? "text-[var(--wpi-accent)]" : "text-[var(--wpi-muted)]"}`} />
                </div>

                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <h3 className="text-sm font-semibold text-[var(--wpi-text)] truncate">
                      {section.name}
                    </h3>
                    <SafetyBadge safety={safety} compact />
                  </div>

                  <p className="text-xs text-[var(--wpi-muted)] mb-2 line-clamp-1">
                    {section.description}
                  </p>

                  {/* Segmented progress bar with safety colors */}
                  <div className="flex items-center gap-2">
                    <div className="flex-1 h-1.5 rounded-full bg-[var(--wpi-deep)] overflow-hidden">
                      <div className="flex h-full">
                        <motion.div
                          className="bg-[#22c55e]"
                          initial={{ width: 0 }}
                          animate={{ width: `${total > 0 ? (eCounts.Safe / total) * 100 : 0}%` }}
                          transition={{ duration: 0.5 }}
                        />
                        <motion.div
                          className="bg-[#eab308]"
                          initial={{ width: 0 }}
                          animate={{ width: `${total > 0 ? (eCounts.Moderate / total) * 100 : 0}%` }}
                          transition={{ duration: 0.5 }}
                        />
                        <motion.div
                          className="bg-[#ef4444]"
                          initial={{ width: 0 }}
                          animate={{ width: `${total > 0 ? (eCounts.Risky / total) * 100 : 0}%` }}
                          transition={{ duration: 0.5 }}
                        />
                      </div>
                    </div>
                    <span className="text-[10px] text-[var(--wpi-muted)] tabular-nums">
                      {enabled}/{total}
                    </span>
                  </div>

                  {/* Safety breakdown labels */}
                  <div className="flex items-center gap-1.5 mt-1.5">
                    {sCounts.Safe > 0 && (
                      <TooltipProvider delayDuration={200}>
                        <Tooltip>
                          <TooltipTrigger asChild>
                            <div className="flex items-center gap-0.5 cursor-default">
                              <div className="h-1.5 w-1.5 rounded-full bg-[#22c55e]" />
                              <span className="text-[9px] text-[var(--wpi-muted)] tabular-nums">{eCounts.Safe}/{sCounts.Safe}</span>
                            </div>
                          </TooltipTrigger>
                          <TooltipContent side="bottom" className="bg-[var(--wpi-card)] border-[var(--wpi-border)] text-[var(--wpi-text)] text-xs">
                            {eCounts.Safe} of {sCounts.Safe} Safe settings enabled
                          </TooltipContent>
                        </Tooltip>
                      </TooltipProvider>
                    )}
                    {sCounts.Moderate > 0 && (
                      <TooltipProvider delayDuration={200}>
                        <Tooltip>
                          <TooltipTrigger asChild>
                            <div className="flex items-center gap-0.5 cursor-default">
                              <div className="h-1.5 w-1.5 rounded-full bg-[#eab308]" />
                              <span className="text-[9px] text-[var(--wpi-muted)] tabular-nums">{eCounts.Moderate}/{sCounts.Moderate}</span>
                            </div>
                          </TooltipTrigger>
                          <TooltipContent side="bottom" className="bg-[var(--wpi-card)] border-[var(--wpi-border)] text-[var(--wpi-text)] text-xs">
                            {eCounts.Moderate} of {sCounts.Moderate} Moderate settings enabled
                          </TooltipContent>
                        </Tooltip>
                      </TooltipProvider>
                    )}
                    {sCounts.Risky > 0 && (
                      <TooltipProvider delayDuration={200}>
                        <Tooltip>
                          <TooltipTrigger asChild>
                            <div className="flex items-center gap-0.5 cursor-default">
                              <div className="h-1.5 w-1.5 rounded-full bg-[#ef4444]" />
                              <span className="text-[9px] text-[var(--wpi-muted)] tabular-nums">{eCounts.Risky}/{sCounts.Risky}</span>
                            </div>
                          </TooltipTrigger>
                          <TooltipContent side="bottom" className="bg-[var(--wpi-card)] border-[var(--wpi-border)] text-[var(--wpi-text)] text-xs">
                            {eCounts.Risky} of {sCounts.Risky} Risky settings enabled
                          </TooltipContent>
                        </Tooltip>
                      </TooltipProvider>
                    )}
                  </div>

                  {/* Search match count */}
                  {isFiltered && matchingSettings.length < total && (
                    <p className="text-[10px] text-[var(--wpi-accent)] mt-1">
                      {matchingSettings.length} matching
                    </p>
                  )}
                </div>

                {/* Toggle all switch */}
                <div className="shrink-0" onClick={(e) => e.stopPropagation()}>
                  <Switch
                    checked={allEnabled}
                    onCheckedChange={(checked) => toggleSectionAll(section.id, checked)}
                    className="data-[state=checked]:bg-[var(--wpi-accent)] data-[state=unchecked]:bg-[var(--wpi-border)]"
                  />
                </div>
              </div>
            </motion.div>
          );
        })}
      </div>
    </div>
  );
}
