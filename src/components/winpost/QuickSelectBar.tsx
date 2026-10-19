"use client";

import React, { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import {
  Shield, ShieldAlert, ShieldX, CheckCircle2,
  XCircle, Zap, Layers, ChevronDown,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
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
import { sections } from "@/data/settings";
import { useAppStore } from "@/store/useAppStore";

export function QuickSelectBar() {
  const {
    settings,
    toggleBySafety,
    toggleAllSettings,
    getGlobalSafetyCounts,
    getGlobalEnabledSafetyCounts,
  } = useAppStore();

  const [confirmOpen, setConfirmOpen] = useState(false);
  const [pendingAction, setPendingAction] = useState<{
    label: string;
    action: () => void;
  } | null>(null);

  const totalCounts = getGlobalSafetyCounts();
  const enabledCounts = getGlobalEnabledSafetyCounts();

  const totalSettings = totalCounts.Safe + totalCounts.Moderate + totalCounts.Risky;
  const totalEnabled = enabledCounts.Safe + enabledCounts.Moderate + enabledCounts.Risky;

  // Check if all settings of a given safety group are enabled
  const allSafeEnabled = enabledCounts.Safe === totalCounts.Safe && totalCounts.Safe > 0;
  const allSafeModEnabled =
    enabledCounts.Safe === totalCounts.Safe &&
    enabledCounts.Moderate === totalCounts.Moderate &&
    (totalCounts.Safe > 0 || totalCounts.Moderate > 0);
  const allEnabled = totalEnabled === totalSettings && totalSettings > 0;

  // Partially selected states (some but not all)
  const someSafeEnabled = enabledCounts.Safe > 0 && !allSafeEnabled;
  const someSafeModEnabled =
    (enabledCounts.Safe > 0 || enabledCounts.Moderate > 0) && !allSafeModEnabled;

  const handleSelectSafe = () => {
    // First disable everything, then enable only Safe
    toggleBySafety(["Safe", "Moderate", "Risky"], false);
    toggleBySafety(["Safe"], true);
  };

  const handleSelectSafeModerate = () => {
    // First disable everything, then enable Safe + Moderate
    toggleBySafety(["Safe", "Moderate", "Risky"], false);
    toggleBySafety(["Safe", "Moderate"], true);
  };

  const handleSelectAll = () => {
    // Show confirmation for enabling all including Risky
    setPendingAction({
      label: "Enable ALL settings (including Risky)",
      action: () => {
        toggleAllSettings(true);
        setConfirmOpen(false);
        setPendingAction(null);
      },
    });
    setConfirmOpen(true);
  };

  const handleDeselectAll = () => {
    toggleAllSettings(false);
  };

  return (
    <>
      <motion.div
        initial={{ opacity: 0, y: -10 }}
        animate={{ opacity: 1, y: 0 }}
        className="rounded-xl border border-[var(--wpi-border)] bg-[var(--wpi-deep)] p-3"
      >
        <div className="flex items-center gap-2 flex-wrap">
          {/* Label */}
          <div className="flex items-center gap-1.5 shrink-0 mr-1">
            <Zap className="h-3.5 w-3.5 text-[var(--wpi-accent)]" />
            <span className="text-xs font-semibold text-[var(--wpi-text)]">Quick Select</span>
          </div>

          <div className="h-5 w-px bg-[var(--wpi-border)] shrink-0" />

          {/* All Safe button */}
          <TooltipProvider delayDuration={200}>
            <Tooltip>
              <TooltipTrigger asChild>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={handleSelectSafe}
                  className={`h-7 gap-1.5 text-[10px] transition-all ${
                    allSafeEnabled
                      ? "bg-[#22c55e]/15 border-[#22c55e]/40 text-[#22c55e] hover:bg-[#22c55e]/20 hover:border-[#22c55e]/50"
                      : someSafeEnabled
                        ? "bg-[#22c55e]/8 border-[#22c55e]/20 text-[#22c55e]/80 hover:bg-[#22c55e]/15"
                        : "bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:bg-[var(--wpi-card)] hover:border-[#22c55e]/30 hover:text-[#22c55e]"
                  }`}
                >
                  <Shield className="h-3 w-3" />
                  <span>All Safe</span>
                  <Badge variant="secondary" className="h-3.5 px-1 text-[9px] bg-[#22c55e]/10 text-[#22c55e] border-0">
                    {totalCounts.Safe}
                  </Badge>
                </Button>
              </TooltipTrigger>
              <TooltipContent side="bottom" className="bg-[var(--wpi-card)] border-[var(--wpi-border)] text-[var(--wpi-text)] text-xs">
                Enable only Safe settings across all categories ({totalCounts.Safe} settings)
              </TooltipContent>
            </Tooltip>
          </TooltipProvider>

          {/* Safe + Moderate button */}
          <TooltipProvider delayDuration={200}>
            <Tooltip>
              <TooltipTrigger asChild>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={handleSelectSafeModerate}
                  className={`h-7 gap-1.5 text-[10px] transition-all ${
                    allSafeModEnabled
                      ? "bg-[#eab308]/15 border-[#eab308]/40 text-[#eab308] hover:bg-[#eab308]/20 hover:border-[#eab308]/50"
                      : someSafeModEnabled
                        ? "bg-[#eab308]/8 border-[#eab308]/20 text-[#eab308]/80 hover:bg-[#eab308]/15"
                        : "bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:bg-[var(--wpi-card)] hover:border-[#eab308]/30 hover:text-[#eab308]"
                  }`}
                >
                  <ShieldAlert className="h-3 w-3" />
                  <span>Safe + Moderate</span>
                  <Badge variant="secondary" className="h-3.5 px-1 text-[9px] bg-[#eab308]/10 text-[#eab308] border-0">
                    {totalCounts.Safe + totalCounts.Moderate}
                  </Badge>
                </Button>
              </TooltipTrigger>
              <TooltipContent side="bottom" className="bg-[var(--wpi-card)] border-[var(--wpi-border)] text-[var(--wpi-text)] text-xs">
                Enable Safe and Moderate settings across all categories ({totalCounts.Safe + totalCounts.Moderate} settings)
              </TooltipContent>
            </Tooltip>
          </TooltipProvider>

          {/* All (including Risky) button */}
          <TooltipProvider delayDuration={200}>
            <Tooltip>
              <TooltipTrigger asChild>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={handleSelectAll}
                  className={`h-7 gap-1.5 text-[10px] transition-all ${
                    allEnabled
                      ? "bg-[#ef4444]/15 border-[#ef4444]/40 text-[#ef4444] hover:bg-[#ef4444]/20 hover:border-[#ef4444]/50"
                      : "bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:bg-[var(--wpi-card)] hover:border-[#ef4444]/30 hover:text-[#ef4444]"
                  }`}
                >
                  <ShieldX className="h-3 w-3" />
                  <span>All</span>
                  <Badge variant="secondary" className="h-3.5 px-1 text-[9px] bg-[#ef4444]/10 text-[#ef4444] border-0">
                    {totalSettings}
                  </Badge>
                </Button>
              </TooltipTrigger>
              <TooltipContent side="bottom" className="bg-[var(--wpi-card)] border-[var(--wpi-border)] text-[var(--wpi-text)] text-xs">
                Enable ALL settings including Risky ones ({totalSettings} settings). Confirmation required.
              </TooltipContent>
            </Tooltip>
          </TooltipProvider>

          <div className="h-5 w-px bg-[var(--wpi-border)] shrink-0" />

          {/* Deselect All */}
          <TooltipProvider delayDuration={200}>
            <Tooltip>
              <TooltipTrigger asChild>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={handleDeselectAll}
                  disabled={totalEnabled === 0}
                  className="h-7 gap-1.5 text-[10px] bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:bg-[var(--wpi-card)] hover:border-[#ef4444]/30 hover:text-[#ef4444] disabled:opacity-30"
                >
                  <XCircle className="h-3 w-3" />
                  <span>None</span>
                </Button>
              </TooltipTrigger>
              <TooltipContent side="bottom" className="bg-[var(--wpi-card)] border-[var(--wpi-border)] text-[var(--wpi-text)] text-xs">
                Disable all settings across all categories
              </TooltipContent>
            </Tooltip>
          </TooltipProvider>

          {/* Stats summary */}
          <div className="ml-auto flex items-center gap-2 shrink-0">
            <div className="flex items-center gap-1">
              <div className="h-1.5 w-1.5 rounded-full bg-[#22c55e]" />
              <span className="text-[10px] text-[var(--wpi-muted)] tabular-nums">{enabledCounts.Safe}/{totalCounts.Safe}</span>
            </div>
            <div className="flex items-center gap-1">
              <div className="h-1.5 w-1.5 rounded-full bg-[#eab308]" />
              <span className="text-[10px] text-[var(--wpi-muted)] tabular-nums">{enabledCounts.Moderate}/{totalCounts.Moderate}</span>
            </div>
            <div className="flex items-center gap-1">
              <div className="h-1.5 w-1.5 rounded-full bg-[#ef4444]" />
              <span className="text-[10px] text-[var(--wpi-muted)] tabular-nums">{enabledCounts.Risky}/{totalCounts.Risky}</span>
            </div>
            <div className="h-4 w-px bg-[var(--wpi-border)]" />
            <span className="text-[10px] font-semibold text-[var(--wpi-accent)] tabular-nums">
              {totalEnabled}/{totalSettings}
            </span>
          </div>
        </div>

        {/* Safety breakdown progress bar */}
        <div className="mt-2 flex h-1.5 rounded-full overflow-hidden bg-[var(--wpi-border)]">
          {totalSettings > 0 && (
            <>
              <motion.div
                className="bg-[#22c55e]"
                animate={{ width: `${(enabledCounts.Safe / totalSettings) * 100}%` }}
                transition={{ duration: 0.3 }}
              />
              <motion.div
                className="bg-[#eab308]"
                animate={{ width: `${(enabledCounts.Moderate / totalSettings) * 100}%` }}
                transition={{ duration: 0.3 }}
              />
              <motion.div
                className="bg-[#ef4444]"
                animate={{ width: `${(enabledCounts.Risky / totalSettings) * 100}%` }}
                transition={{ duration: 0.3 }}
              />
            </>
          )}
        </div>
      </motion.div>

      {/* Confirmation dialog for risky actions */}
      <Dialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <DialogContent className="bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-text)]">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2 text-[#ef4444]">
              <ShieldX className="h-5 w-5" />
              Confirm Risky Action
            </DialogTitle>
            <DialogDescription className="text-[var(--wpi-muted)]">
              You are about to <strong className="text-[#ef4444]">{pendingAction?.label}</strong>.
              This includes <strong>{totalCounts.Risky} Risky settings</strong> that could cause
              significant issues and may be difficult to reverse. Are you sure?
            </DialogDescription>
          </DialogHeader>
          <DialogFooter className="gap-2">
            <Button
              variant="outline"
              onClick={() => {
                setConfirmOpen(false);
                setPendingAction(null);
              }}
              className="bg-[var(--wpi-card)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:bg-[var(--wpi-card)]"
            >
              Cancel
            </Button>
            <Button
              onClick={pendingAction?.action}
              className="bg-[#ef4444] hover:bg-[#ef4444]/90 text-white"
            >
              Yes, Enable All
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
