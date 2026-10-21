"use client";

import React from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Undo2, Trash2, Clock, Shield, ShieldAlert, ShieldX } from "lucide-react";
import { Button } from "@/components/ui/button";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Badge } from "@/components/ui/badge";
import { sections } from "@/data/settings";
import { useAppStore } from "@/store/useAppStore";

export function UndoCenterTab() {
  const { settings, undoLog, undoChange, undoAll, undoBySafety, getGlobalEnabledSafetyCounts } = useAppStore();

  const enabledSafetyCounts = getGlobalEnabledSafetyCounts();
  const totalEnabled = enabledSafetyCounts.Safe + enabledSafetyCounts.Moderate + enabledSafetyCounts.Risky;

  const formatTime = (date: string) => {
    const d = new Date(date);
    return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  };

  const formatDate = (date: string) => {
    const d = new Date(date);
    return d.toLocaleDateString([], { month: "short", day: "numeric" });
  };

  // Find safety level of a setting by ID
  const getSettingSafety = (settingId: string) => {
    for (const section of sections) {
      const found = section.settings.find((s) => s.id === settingId);
      if (found) return found.safety;
    }
    return "Safe" as const;
  };

  const safetyColorMap = {
    Safe: { bg: "bg-[var(--wpi-safe-10)]", border: "border-[var(--wpi-safe-20)]", text: "text-[var(--wpi-safe)]", buttonBg: "bg-[var(--wpi-safe-5)]", buttonBorder: "border-[var(--wpi-safe-30)]" },
    Moderate: { bg: "bg-[var(--wpi-moderate-10)]", border: "border-[var(--wpi-moderate-20)]", text: "text-[var(--wpi-moderate)]", buttonBg: "bg-[var(--wpi-moderate-5)]", buttonBorder: "border-[var(--wpi-moderate-30)]" },
    Risky: { bg: "bg-[var(--wpi-risky-10)]", border: "border-[var(--wpi-risky-20)]", text: "text-[var(--wpi-risky)]", buttonBg: "bg-[var(--wpi-risky-5)]", buttonBorder: "border-[var(--wpi-risky-30)]" },
  };

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h2 className="text-base font-semibold text-[var(--wpi-text)]">Undo Center</h2>
          <p className="text-xs text-[var(--wpi-muted)]">
            Review and undo individual or grouped changes
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Badge className="bg-[var(--wpi-moderate-10)] text-[var(--wpi-moderate)] border-[var(--wpi-moderate-20)] text-xs">
            {totalEnabled} enabled
          </Badge>
          {totalEnabled > 0 && (
            <Button
              size="sm"
              variant="outline"
              onClick={undoAll}
              className="h-8 gap-1.5 bg-[var(--wpi-risky-5)] border-[var(--wpi-risky-20)] text-[var(--wpi-risky)] hover:bg-[var(--wpi-risky-10)] hover:text-[var(--wpi-risky)] text-xs"
            >
              <Trash2 className="h-3.5 w-3.5" />
              Undo All
            </Button>
          )}
        </div>
      </div>

      {/* Batch undo by safety level */}
      {totalEnabled > 0 && (
        <motion.div
          initial={{ opacity: 0, y: -10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.3, ease: [0.25, 0.1, 0.25, 1] }}
          className="rounded-xl border border-[var(--wpi-border)] bg-[var(--wpi-deep)] p-4"
        >
          <h3 className="text-sm font-semibold text-[var(--wpi-text)] mb-3">Undo by Safety Level</h3>
          <div className="flex items-center gap-2 flex-wrap">
            {enabledSafetyCounts.Risky > 0 && (
              <Button
                variant="outline"
                size="sm"
                onClick={() => undoBySafety(["Risky"])}
                className="h-8 gap-1.5 text-xs bg-[var(--wpi-risky-5)] border-[var(--wpi-risky-30)] text-[var(--wpi-risky)] hover:bg-[var(--wpi-risky-10)] hover:text-[var(--wpi-risky)]"
              >
                <ShieldX className="h-3.5 w-3.5" />
                Undo Risky ({enabledSafetyCounts.Risky})
              </Button>
            )}
            {enabledSafetyCounts.Moderate > 0 && (
              <Button
                variant="outline"
                size="sm"
                onClick={() => undoBySafety(["Moderate"])}
                className="h-8 gap-1.5 text-xs bg-[var(--wpi-moderate-5)] border-[var(--wpi-moderate-30)] text-[var(--wpi-moderate)] hover:bg-[var(--wpi-moderate-10)] hover:text-[var(--wpi-moderate)]"
              >
                <ShieldAlert className="h-3.5 w-3.5" />
                Undo Moderate ({enabledSafetyCounts.Moderate})
              </Button>
            )}
            {enabledSafetyCounts.Safe > 0 && (
              <Button
                variant="outline"
                size="sm"
                onClick={() => undoBySafety(["Safe"])}
                className="h-8 gap-1.5 text-xs bg-[var(--wpi-safe-5)] border-[var(--wpi-safe-30)] text-[var(--wpi-safe)] hover:bg-[var(--wpi-safe-10)] hover:text-[var(--wpi-safe)]"
              >
                <Shield className="h-3.5 w-3.5" />
                Undo Safe ({enabledSafetyCounts.Safe})
              </Button>
            )}
            {(enabledSafetyCounts.Moderate > 0 || enabledSafetyCounts.Risky > 0) && (
              <Button
                variant="outline"
                size="sm"
                onClick={() => undoBySafety(["Moderate", "Risky"])}
                className="h-8 gap-1.5 text-xs bg-[var(--wpi-moderate-5)] border-[var(--wpi-border)] text-[var(--wpi-moderate)] hover:bg-[var(--wpi-moderate-10)] hover:text-[var(--wpi-moderate)]"
              >
                <ShieldAlert className="h-3.5 w-3.5" />
                Undo Mod+Risky ({enabledSafetyCounts.Moderate + enabledSafetyCounts.Risky})
              </Button>
            )}
          </div>
        </motion.div>
      )}

      {/* Undo log */}
      {undoLog.length === 0 ? (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          className="flex flex-col items-center justify-center py-16 text-center"
        >
          <div className="h-14 w-14 rounded-2xl bg-[var(--wpi-deep)] border border-[var(--wpi-border)] flex items-center justify-center mb-4">
            <Undo2 className="h-6 w-6 text-[var(--wpi-muted)]/40" />
          </div>
          <p className="text-sm text-[var(--wpi-muted)] mb-1">No changes to undo</p>
          <p className="text-xs text-[var(--wpi-muted)]/50">Toggle settings to start making changes</p>
        </motion.div>
      ) : (
        <ScrollArea className="max-h-[calc(100vh-380px)]">
          <div className="space-y-1.5 p-0.5">
            <AnimatePresence>
              {undoLog.map((entry, index) => {
                const safety = getSettingSafety(entry.settingId);
                const colors = safetyColorMap[safety];
                return (
                  <motion.div
                    key={entry.id}
                    initial={{ opacity: 0, x: -16 }}
                    animate={{ opacity: 1, x: 0 }}
                    exit={{ opacity: 0, x: 16, height: 0 }}
                    transition={{ delay: index * 0.02, duration: 0.25, ease: [0.25, 0.1, 0.25, 1] }}
                    className="flex items-center gap-3 p-3 rounded-lg bg-[var(--wpi-card)] border border-[var(--wpi-border)] group hover:border-[var(--wpi-border-subtle)] transition-colors duration-200"
                  >
                    <div className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-lg border ${
                      entry.action === "enabled"
                        ? `${colors.bg} ${colors.border}`
                        : "bg-[var(--wpi-muted)]/10 border-[var(--wpi-muted)]/20"
                    }`}>
                      <Undo2 className={`h-4 w-4 ${
                        entry.action === "enabled" ? colors.text : "text-[var(--wpi-muted)]"
                      }`} />
                    </div>

                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="text-sm font-medium text-[var(--wpi-text)] truncate">
                          {entry.settingName}
                        </span>
                        <Badge
                          variant="outline"
                          className={`h-4 px-1 text-[9px] shrink-0 ${
                            entry.action === "enabled"
                              ? "bg-[var(--wpi-safe-5)] border-[var(--wpi-safe-20)] text-[var(--wpi-safe)]"
                              : "bg-[var(--wpi-risky-5)] border-[var(--wpi-risky-20)] text-[var(--wpi-risky)]"
                          }`}
                        >
                          {entry.action === "enabled" ? "Enabled" : "Disabled"}
                        </Badge>
                        <Badge
                          variant="outline"
                          className={`h-4 px-1 text-[9px] shrink-0 ${colors.bg} ${colors.border} ${colors.text}`}
                        >
                          {safety}
                        </Badge>
                      </div>
                      <div className="flex items-center gap-2 mt-0.5">
                        <span className="text-[11px] text-[var(--wpi-muted)]/70">{entry.sectionName}</span>
                        <span className="text-[11px] text-[var(--wpi-muted)]/40">•</span>
                        <span className="text-[11px] text-[var(--wpi-muted)]/50">
                          <Clock className="h-3 w-3 inline mr-0.5" />
                          {formatDate(entry.timestamp)} {formatTime(entry.timestamp)}
                        </span>
                      </div>
                    </div>

                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => undoChange(entry.id)}
                      className="h-7 gap-1 text-[10px] shrink-0 bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-moderate)] hover:bg-[var(--wpi-moderate-10)] hover:text-[var(--wpi-moderate)] hover:border-[var(--wpi-moderate-30)]"
                    >
                      <Undo2 className="h-3 w-3" />
                      Undo
                    </Button>
                  </motion.div>
                );
              })}
            </AnimatePresence>
          </div>
        </ScrollArea>
      )}
    </div>
  );
}
