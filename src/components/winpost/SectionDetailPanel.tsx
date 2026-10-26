"use client";

import React, { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import {
  Shield, Trash2, FolderOpen, Settings, Zap, Lock,
  Wifi, RefreshCw, HardDrive, Package, FileSpreadsheet,
  Globe, Cloud, Gamepad2, CalendarClock, ShieldCheck,
  Sparkles, Puzzle, X, ShieldAlert, ShieldX, Filter,
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
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { sections, type SafetyLevel, settingDependencies, checkSettingConflicts } from "@/data/settings";
import { useAppStore } from "@/store/useAppStore";
import { SafetyBadge } from "./SafetyBadge";

const iconMap: Record<string, React.ComponentType<{ className?: string }>> = {
  Shield, Trash2, FolderOpen, Settings, Zap, Lock,
  Wifi, RefreshCw, HardDrive, Package, FileSpreadsheet,
  Globe, Cloud, Gamepad2, CalendarClock, ShieldCheck,
  Sparkles, Puzzle,
};

type SafetyFilter = "all" | "Safe" | "Moderate" | "Risky";

export function SectionDetailPanel() {
  const {
    activeSectionId, setActiveSectionId, settings,
    toggleSetting, toggleSectionAll, toggleSectionBySafety,
    searchQuery, getSectionSafetyCounts, getSectionEnabledSafetyCounts,
  } = useAppStore();

  // Safety filter state
  const [safetyFilter, setSafetyFilter] = useState<SafetyFilter>("all");

  // Confirmation dialog for risky section actions
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [pendingAction, setPendingAction] = useState<{
    label: string;
    action: () => void;
  } | null>(null);

  const section = activeSectionId ? sections.find((s) => s.id === activeSectionId) : null;
  const Icon = section ? (iconMap[section.icon] || Settings) : Settings;
  const enabledCount = section ? section.settings.filter((s) => settings[s.id]).length : 0;
  const totalCount = section ? section.settings.length : 0;

  // Safety counts for this section
  const safetyCounts = section ? getSectionSafetyCounts(section.id) : { Safe: 0, Moderate: 0, Risky: 0 };
  const enabledSafetyCounts = section ? getSectionEnabledSafetyCounts(section.id) : { Safe: 0, Moderate: 0, Risky: 0 };

  // Filtered settings (by search AND safety filter)
  const filteredSettings = section
    ? section.settings.filter((s) => {
        // Search filter
        if (searchQuery) {
          const q = searchQuery.toLowerCase();
          const matchesSearch = s.name.toLowerCase().includes(q) || s.desc.toLowerCase().includes(q);
          if (!matchesSearch) return false;
        }
        // Safety filter
        if (safetyFilter !== "all" && s.safety !== safetyFilter) return false;
        return true;
      })
    : [];

  // Per-section safety selector handlers
  const handleSelectSafe = () => {
    if (!section) return;
    toggleSectionAll(section.id, false);
    toggleSectionBySafety(section.id, ["Safe"], true);
  };

  const handleSelectSafeModerate = () => {
    if (!section) return;
    toggleSectionAll(section.id, false);
    toggleSectionBySafety(section.id, ["Safe", "Moderate"], true);
  };

  const handleSelectAllSection = () => {
    if (!section) return;
    if (safetyCounts.Risky > 0) {
      setPendingAction({
        label: `Enable ALL settings in ${section.name} (including Risky)`,
        action: () => {
          toggleSectionAll(section!.id, true);
          setConfirmOpen(false);
          setPendingAction(null);
        },
      });
      setConfirmOpen(true);
    } else {
      toggleSectionAll(section.id, true);
    }
  };

  const handleDeselectAllSection = () => {
    if (!section) return;
    toggleSectionAll(section.id, false);
  };

  // Check selection states for the section
  const allSafeEnabled = enabledSafetyCounts.Safe === safetyCounts.Safe && safetyCounts.Safe > 0;
  const allSafeModEnabled =
    enabledSafetyCounts.Safe === safetyCounts.Safe &&
    enabledSafetyCounts.Moderate === safetyCounts.Moderate &&
    (safetyCounts.Safe > 0 || safetyCounts.Moderate > 0);
  const allSectionEnabled = enabledCount === totalCount && totalCount > 0;

  return (
    <AnimatePresence>
      {activeSectionId && section && (
        <>
          {/* Backdrop — Apple-style frosted glass */}
          <motion.div
            key="backdrop"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={() => {
              setActiveSectionId(null);
              setSafetyFilter("all");
            }}
            className="fixed inset-0 z-50 bg-[var(--wpi-backdrop)] backdrop-blur-md"
          />

          {/* Panel — Apple-style side sheet */}
          <motion.div
            key="panel"
            initial={{ x: "100%" }}
            animate={{ x: 0 }}
            exit={{ x: "100%" }}
            transition={{ type: "spring", damping: 30, stiffness: 250 }}
            className="fixed right-0 top-0 bottom-0 z-50 w-full max-w-lg bg-[var(--wpi-bg)] border-l border-[var(--wpi-border)] shadow-2xl flex flex-col"
          >
            {/* Header */}
            <div className="p-5 border-b border-[var(--wpi-border)]">
              <div className="flex items-center justify-between mb-3">
                <div className="flex items-center gap-3">
                  <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-[var(--wpi-accent)]/10 border border-[var(--wpi-accent)]/20">
                    <Icon className="h-5 w-5 text-[var(--wpi-accent)]" />
                  </div>
                  <div>
                    <h2 className="text-base font-bold text-[var(--wpi-text)] leading-tight">{section.name}</h2>
                    <p className="text-xs text-[var(--wpi-muted)] mt-0.5">{section.description}</p>
                  </div>
                </div>
                <Button
                  variant="ghost"
                  size="icon"
                  onClick={() => {
                    setActiveSectionId(null);
                    setSafetyFilter("all");
                  }}
                  className="h-8 w-8 text-[var(--wpi-muted)] hover:text-[var(--wpi-text)] hover:bg-[var(--wpi-card)]"
                >
                  <X className="h-4 w-4" />
                </Button>
              </div>

              {/* Stats row — Apple-style inline metrics */}
              <div className="flex items-center gap-2 flex-wrap mb-3">
                <div className="flex items-center gap-1.5">
                  <span className="text-xs text-[var(--wpi-muted)]">Enabled:</span>
                  <span className="text-xs font-semibold text-[var(--wpi-accent)]">{enabledCount}/{totalCount}</span>
                </div>
                <div className="h-3 w-px bg-[var(--wpi-border)]" />
                {safetyCounts.Safe > 0 && (
                  <Badge variant="outline" className="h-5 text-[10px] bg-[var(--wpi-safe-5)] border-[var(--wpi-safe-20)] text-[var(--wpi-safe)]">
                    {enabledSafetyCounts.Safe}/{safetyCounts.Safe} Safe
                  </Badge>
                )}
                {safetyCounts.Moderate > 0 && (
                  <Badge variant="outline" className="h-5 text-[10px] bg-[var(--wpi-moderate-5)] border-[var(--wpi-moderate-20)] text-[var(--wpi-moderate)]">
                    {enabledSafetyCounts.Moderate}/{safetyCounts.Moderate} Mod
                  </Badge>
                )}
                {safetyCounts.Risky > 0 && (
                  <Badge variant="outline" className="h-5 text-[10px] bg-[var(--wpi-risky-5)] border-[var(--wpi-risky-20)] text-[var(--wpi-risky)]">
                    {enabledSafetyCounts.Risky}/{safetyCounts.Risky} Risk
                  </Badge>
                )}
              </div>

              {/* Safety Quick Select row — Material-style segmented pills */}
              <div className="flex items-center gap-1.5 flex-wrap">
                <span className="text-[10px] text-[var(--wpi-muted)] shrink-0 mr-0.5">Select:</span>

                <Button
                  variant="outline"
                  size="sm"
                  onClick={handleSelectSafe}
                  className={`h-6 gap-1 text-[9px] px-2 transition-all duration-200 ${
                    allSafeEnabled && !allSafeModEnabled
                      ? "bg-[var(--wpi-safe-15)] border-[var(--wpi-safe-30)] text-[var(--wpi-safe)]"
                      : "bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:border-[var(--wpi-safe-30)] hover:text-[var(--wpi-safe)]"
                  }`}
                >
                  <Shield className="h-2.5 w-2.5" />
                  Safe
                </Button>

                <Button
                  variant="outline"
                  size="sm"
                  onClick={handleSelectSafeModerate}
                  className={`h-6 gap-1 text-[9px] px-2 transition-all duration-200 ${
                    allSafeModEnabled && !allSectionEnabled
                      ? "bg-[var(--wpi-moderate-15)] border-[var(--wpi-moderate-30)] text-[var(--wpi-moderate)]"
                      : "bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:border-[var(--wpi-moderate-30)] hover:text-[var(--wpi-moderate)]"
                  }`}
                >
                  <ShieldAlert className="h-2.5 w-2.5" />
                  Safe+Mod
                </Button>

                <Button
                  variant="outline"
                  size="sm"
                  onClick={handleSelectAllSection}
                  className={`h-6 gap-1 text-[9px] px-2 transition-all duration-200 ${
                    allSectionEnabled
                      ? "bg-[var(--wpi-risky-15)] border-[var(--wpi-risky-30)] text-[var(--wpi-risky)]"
                      : "bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:border-[var(--wpi-risky-30)] hover:text-[var(--wpi-risky)]"
                  }`}
                >
                  <ShieldX className="h-2.5 w-2.5" />
                  All
                </Button>

                <Button
                  variant="outline"
                  size="sm"
                  onClick={handleDeselectAllSection}
                  disabled={enabledCount === 0}
                  className="h-6 gap-1 text-[9px] px-2 bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:border-[var(--wpi-border)] hover:text-[var(--wpi-text)] disabled:opacity-30"
                >
                  None
                </Button>
              </div>
            </div>

            {/* Safety Filter Bar — Apple-style inline filter chips */}
            <div className="px-5 py-2 border-b border-[var(--wpi-border)] bg-[var(--wpi-bg-deep)]">
              <div className="flex items-center gap-1.5">
                <Filter className="h-3 w-3 text-[var(--wpi-muted)]" />
                <span className="text-[10px] text-[var(--wpi-muted)] shrink-0">Filter:</span>
                {(["all", "Safe", "Moderate", "Risky"] as SafetyFilter[]).map((filter) => (
                  <Button
                    key={filter}
                    variant="ghost"
                    size="sm"
                    onClick={() => setSafetyFilter(filter)}
                    className={`h-5 text-[9px] px-2 rounded transition-all duration-200 ${
                      safetyFilter === filter
                        ? filter === "all"
                          ? "bg-[var(--wpi-accent)]/15 text-[var(--wpi-accent)]"
                          : filter === "Safe"
                            ? "bg-[var(--wpi-safe-15)] text-[var(--wpi-safe)]"
                            : filter === "Moderate"
                              ? "bg-[var(--wpi-moderate-15)] text-[var(--wpi-moderate)]"
                              : "bg-[var(--wpi-risky-15)] text-[var(--wpi-risky)]"
                        : "text-[var(--wpi-muted)] hover:text-[var(--wpi-text)] hover:bg-[var(--wpi-card)]"
                    }`}
                  >
                    {filter === "all" ? "All" : filter}
                    {filter !== "all" && (
                      <span className="ml-1 opacity-60">
                        {safetyCounts[filter as "Safe" | "Moderate" | "Risky"]}
                      </span>
                    )}
                  </Button>
                ))}
              </div>
            </div>

            {/* Settings list — Apple-style rows with generous spacing */}
            <ScrollArea className="flex-1 overflow-hidden">
              <div className="p-3 space-y-1">
                {filteredSettings.map((setting, index) => {
                  const isEnabled = settings[setting.id] ?? false;
                  const conflicts = isEnabled ? checkSettingConflicts(setting.id, settings) : [];
                  const hasConflicts = conflicts.length > 0;
                  const hasDeps = !!settingDependencies[setting.id];
                  return (
                    <motion.div
                      key={setting.id}
                      initial={{ opacity: 0, x: 16 }}
                      animate={{ opacity: 1, x: 0 }}
                      transition={{ delay: index * 0.025, duration: 0.25, ease: [0.25, 0.1, 0.25, 1] }}
                      className={`group flex items-center gap-3 rounded-lg p-3 transition-all duration-200 cursor-pointer min-h-[44px] ${
                        hasConflicts
                          ? "bg-[var(--wpi-risky-5)] border border-[var(--wpi-risky-15)]"
                          : isEnabled
                            ? "bg-[var(--wpi-accent)]/5 border border-[var(--wpi-accent)]/10"
                            : "bg-[var(--wpi-deep)] border border-[var(--wpi-border)] hover:border-[var(--wpi-border-subtle)] hover:bg-[var(--wpi-card)]/50"
                      }`}
                    >
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 mb-0.5">
                          <span className={`text-sm font-medium leading-tight ${hasConflicts ? "text-[var(--wpi-risky)]" : isEnabled ? "text-[var(--wpi-text)]" : "text-[var(--wpi-muted)]"}`}>
                            {setting.name}
                          </span>
                          <SafetyBadge safety={setting.safety} compact />
                          {hasDeps && !hasConflicts && (
                            <TooltipProvider delayDuration={300}>
                              <Tooltip>
                                <TooltipTrigger asChild>
                                  <div className="h-4 w-4 rounded-full bg-[var(--wpi-moderate-15)] border border-[var(--wpi-moderate-30)] flex items-center justify-center cursor-help">
                                    <span className="text-[9px] text-[var(--wpi-moderate)] font-bold">!</span>
                                  </div>
                                </TooltipTrigger>
                                <TooltipContent side="bottom" className="bg-[var(--wpi-card)] border-[var(--wpi-border)] text-[var(--wpi-text)] text-xs max-w-xs">
                                  This setting has dependency rules. Conflicts may appear when other related settings are enabled.
                                </TooltipContent>
                              </Tooltip>
                            </TooltipProvider>
                          )}
                        </div>
                        {hasConflicts && (
                          <div className="mb-1 flex flex-wrap gap-1">
                            {conflicts.map((c, ci) => (
                              <Badge key={ci} variant="outline" className="h-4 text-[9px] bg-[var(--wpi-risky-10)] border-[var(--wpi-risky-20)] text-[var(--wpi-risky)]">
                                {c.type === "conflict" ? "Conflicts" : "Requires"}: {c.settingName}
                              </Badge>
                            ))}
                          </div>
                        )}
                        <TooltipProvider delayDuration={300}>
                          <Tooltip>
                            <TooltipTrigger asChild>
                              <p className={`text-xs line-clamp-1 cursor-help ${hasConflicts ? "text-[var(--wpi-risky)]/70" : "text-[var(--wpi-muted)]"}`}>
                                {hasConflicts ? conflicts[0].message : setting.desc}
                              </p>
                            </TooltipTrigger>
                            <TooltipContent
                              side="bottom"
                              align="start"
                              className="max-w-xs bg-[var(--wpi-card)] border-[var(--wpi-border)] text-[var(--wpi-text)] text-xs"
                            >
                              {setting.desc}
                            </TooltipContent>
                          </Tooltip>
                        </TooltipProvider>
                      </div>

                      {setting.exclusiveGroup ? (
                        /* Radio-style indicator for mutually exclusive groups */
                        <button
                          role="radio"
                          aria-checked={isEnabled}
                          onClick={() => toggleSetting(setting.id)}
                          className={`shrink-0 flex h-5 w-5 items-center justify-center rounded-full border-2 transition-all duration-200 ${
                            isEnabled
                              ? "border-[var(--wpi-accent)] bg-[var(--wpi-accent)]"
                              : "border-[var(--wpi-border)] bg-[var(--wpi-deep)] hover:border-[var(--wpi-accent)]/40"
                          }`}
                        >
                          {isEnabled && (
                            <span className="h-2 w-2 rounded-full bg-white" />
                          )}
                        </button>
                      ) : (
                        <Switch
                          checked={isEnabled}
                          onCheckedChange={() => toggleSetting(setting.id)}
                          className="data-[state=checked]:bg-[var(--wpi-accent)] data-[state=unchecked]:bg-[var(--wpi-border)] shrink-0 scale-110"
                        />
                      )}
                    </motion.div>
                  );
                })}

                {filteredSettings.length === 0 && (
                  <div className="py-16 text-center">
                    <div className="h-12 w-12 rounded-xl bg-[var(--wpi-deep)] border border-[var(--wpi-border)] flex items-center justify-center mx-auto mb-3">
                      <Filter className="h-5 w-5 text-[var(--wpi-muted)]/50" />
                    </div>
                    <p className="text-sm text-[var(--wpi-muted)] mb-1">
                      {safetyFilter !== "all" ? `No ${safetyFilter} settings found` : "No settings match your search"}
                    </p>
                    <p className="text-xs text-[var(--wpi-muted)]/50">Try adjusting your filters</p>
                  </div>
                )}
              </div>
            </ScrollArea>

            {/* Footer — Apple-style clean with progress */}
            <div className="p-4 border-t border-[var(--wpi-border)] bg-[var(--wpi-deep)]">
              <div className="flex items-center justify-between">
                <span className="text-xs text-[var(--wpi-muted)]">
                  {enabledCount} of {totalCount} settings enabled
                  {safetyFilter !== "all" && (
                    <span className="text-[var(--wpi-muted)]/50">
                      {" "}(showing {safetyFilter})
                    </span>
                  )}
                </span>
                <div className="h-1.5 w-32 rounded-full bg-[var(--wpi-border)] overflow-hidden">
                  {/* Segmented progress bar */}
                  <div className="flex h-full">
                    <motion.div
                      className="bg-[var(--wpi-safe)]"
                      animate={{ width: `${(enabledSafetyCounts.Safe / totalCount) * 128}px` }}
                      transition={{ duration: 0.4, ease: [0.25, 0.1, 0.25, 1] }}
                    />
                    <motion.div
                      className="bg-[var(--wpi-moderate)]"
                      animate={{ width: `${(enabledSafetyCounts.Moderate / totalCount) * 128}px` }}
                      transition={{ duration: 0.4, ease: [0.25, 0.1, 0.25, 1] }}
                    />
                    <motion.div
                      className="bg-[var(--wpi-risky)]"
                      animate={{ width: `${(enabledSafetyCounts.Risky / totalCount) * 128}px` }}
                      transition={{ duration: 0.4, ease: [0.25, 0.1, 0.25, 1] }}
                    />
                  </div>
                </div>
              </div>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
}
