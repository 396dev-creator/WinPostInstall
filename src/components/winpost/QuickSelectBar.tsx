"use client";

import React, { useState } from "react";
import { motion } from "framer-motion";
import {
  Shield, ShieldAlert, ShieldX, CheckCircle2,
  XCircle, Zap,
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
    toggleBySafety(["Safe", "Moderate", "Risky"], false);
    toggleBySafety(["Safe"], true);
  };

  const handleSelectSafeModerate = () => {
    toggleBySafety(["Safe", "Moderate", "Risky"], false);
    toggleBySafety(["Safe", "Moderate"], true);
  };

  const handleSelectAll = () => {
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
        transition={{ duration: 0.3, ease: [0.25, 0.1, 0.25, 1] }}
        className="rounded-xl border border-[var(--wpi-border)] bg-[var(--wpi-deep)] p-3"
      >
        <div className="flex items-center gap-2 flex-wrap">
          {/* Label */}
          <div className="flex items-center gap-1.5 shrink-0 mr-1">
            <Zap className="h-3.5 w-3.5 text-[var(--wpi-accent)]" />
            <span className="text-xs font-semibold text-[var(--wpi-text)]">Quick Select</span>
          </div>

          <div className="h-4 w-px bg-[var(--wpi-border)] shrink-0" />

          {/* All Safe button — Material-style segmented control */}
          <TooltipProvider delayDuration={300}>
            <Tooltip>
              <TooltipTrigger asChild>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={handleSelectSafe}
                  className={`h-7 gap-1.5 text-[10px] transition-all duration-200 ${
                    allSafeEnabled
                      ? "bg-[var(--wpi-safe-15)] border-[var(--wpi-safe-30)] text-[var(--wpi-safe)] hover:bg-[var(--wpi-safe-20)] hover:border-[var(--wpi-safe-40)]"
                      : someSafeEnabled
                        ? "bg-[var(--wpi-safe-5)] border-[var(--wpi-safe-15)] text-[var(--wpi-safe)]/80 hover:bg-[var(--wpi-safe-10)]"
                        : "bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:bg-[var(--wpi-card)] hover:border-[var(--wpi-safe-30)] hover:text-[var(--wpi-safe)]"
                  }`}
                >
                  <Shield className="h-3 w-3" />
                  <span>All Safe</span>
                  <Badge variant="secondary" className="h-3.5 px-1 text-[9px] bg-[var(--wpi-safe-10)] text-[var(--wpi-safe)] border-0">
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
          <TooltipProvider delayDuration={300}>
            <Tooltip>
              <TooltipTrigger asChild>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={handleSelectSafeModerate}
                  className={`h-7 gap-1.5 text-[10px] transition-all duration-200 ${
                    allSafeModEnabled
                      ? "bg-[var(--wpi-moderate-15)] border-[var(--wpi-moderate-30)] text-[var(--wpi-moderate)] hover:bg-[var(--wpi-moderate-20)] hover:border-[var(--wpi-moderate-40)]"
                      : someSafeModEnabled
                        ? "bg-[var(--wpi-moderate-5)] border-[var(--wpi-moderate-15)] text-[var(--wpi-moderate)]/80 hover:bg-[var(--wpi-moderate-10)]"
                        : "bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:bg-[var(--wpi-card)] hover:border-[var(--wpi-moderate-30)] hover:text-[var(--wpi-moderate)]"
                  }`}
                >
                  <ShieldAlert className="h-3 w-3" />
                  <span>Safe + Mod</span>
                  <Badge variant="secondary" className="h-3.5 px-1 text-[9px] bg-[var(--wpi-moderate-10)] text-[var(--wpi-moderate)] border-0">
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
          <TooltipProvider delayDuration={300}>
            <Tooltip>
              <TooltipTrigger asChild>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={handleSelectAll}
                  className={`h-7 gap-1.5 text-[10px] transition-all duration-200 ${
                    allEnabled
                      ? "bg-[var(--wpi-risky-15)] border-[var(--wpi-risky-30)] text-[var(--wpi-risky)] hover:bg-[var(--wpi-risky-20)] hover:border-[var(--wpi-risky-40)]"
                      : "bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:bg-[var(--wpi-card)] hover:border-[var(--wpi-risky-30)] hover:text-[var(--wpi-risky)]"
                  }`}
                >
                  <ShieldX className="h-3 w-3" />
                  <span>All</span>
                  <Badge variant="secondary" className="h-3.5 px-1 text-[9px] bg-[var(--wpi-risky-10)] text-[var(--wpi-risky)] border-0">
                    {totalSettings}
                  </Badge>
                </Button>
              </TooltipTrigger>
              <TooltipContent side="bottom" className="bg-[var(--wpi-card)] border-[var(--wpi-border)] text-[var(--wpi-text)] text-xs">
                Enable ALL settings including Risky ones ({totalSettings} settings). Confirmation required.
              </TooltipContent>
            </Tooltip>
          </TooltipProvider>

          <div className="h-4 w-px bg-[var(--wpi-border)] shrink-0" />

          {/* Deselect All */}
          <TooltipProvider delayDuration={300}>
            <Tooltip>
              <TooltipTrigger asChild>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={handleDeselectAll}
                  disabled={totalEnabled === 0}
                  className="h-7 gap-1.5 text-[10px] bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:bg-[var(--wpi-card)] hover:border-[var(--wpi-risky-30)] hover:text-[var(--wpi-risky)] disabled:opacity-30 transition-all duration-200"
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

          {/* Stats summary — Apple-style inline metrics */}
          <div className="ml-auto flex items-center gap-2.5 shrink-0">
            <div className="flex items-center gap-1">
              <div className="h-1.5 w-1.5 rounded-full bg-[var(--wpi-safe)]" />
              <span className="text-[10px] text-[var(--wpi-muted)] tabular-nums">{enabledCounts.Safe}/{totalCounts.Safe}</span>
            </div>
            <div className="flex items-center gap-1">
              <div className="h-1.5 w-1.5 rounded-full bg-[var(--wpi-moderate)]" />
              <span className="text-[10px] text-[var(--wpi-muted)] tabular-nums">{enabledCounts.Moderate}/{totalCounts.Moderate}</span>
            </div>
            <div className="flex items-center gap-1">
              <div className="h-1.5 w-1.5 rounded-full bg-[var(--wpi-risky)]" />
              <span className="text-[10px] text-[var(--wpi-muted)] tabular-nums">{enabledCounts.Risky}/{totalCounts.Risky}</span>
            </div>
            <div className="h-3.5 w-px bg-[var(--wpi-border)]" />
            <span className="text-[10px] font-semibold text-[var(--wpi-accent)] tabular-nums">
              {totalEnabled}/{totalSettings}
            </span>
          </div>
        </div>

        {/* Safety breakdown progress bar — Apple-style thin */}
        <div className="mt-2.5 flex h-1 rounded-full overflow-hidden bg-[var(--wpi-border)]/50">
          {totalSettings > 0 && (
            <>
              <motion.div
                className="bg-[var(--wpi-safe)]"
                animate={{ width: `${(enabledCounts.Safe / totalSettings) * 100}%` }}
                transition={{ duration: 0.4, ease: [0.25, 0.1, 0.25, 1] }}
              />
              <motion.div
                className="bg-[var(--wpi-moderate)]"
                animate={{ width: `${(enabledCounts.Moderate / totalSettings) * 100}%` }}
                transition={{ duration: 0.4, ease: [0.25, 0.1, 0.25, 1] }}
              />
              <motion.div
                className="bg-[var(--wpi-risky)]"
                animate={{ width: `${(enabledCounts.Risky / totalSettings) * 100}%` }}
                transition={{ duration: 0.4, ease: [0.25, 0.1, 0.25, 1] }}
              />
            </>
          )}
        </div>
      </motion.div>

      {/* Confirmation dialog for risky actions */}
      <Dialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <DialogContent className="bg-[var(--wpi-surface-elevated)] border-[var(--wpi-border)] text-[var(--wpi-text)]">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2 text-[var(--wpi-risky)]">
              <ShieldX className="h-5 w-5" />
              Confirm Risky Action
            </DialogTitle>
            <DialogDescription className="text-[var(--wpi-muted)]">
              You are about to <strong className="text-[var(--wpi-risky)]">{pendingAction?.label}</strong>.
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
              className="bg-[var(--wpi-risky)] hover:bg-[var(--wpi-risky)]/90 text-white"
            >
              Yes, Enable All
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
