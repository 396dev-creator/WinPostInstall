"use client";

import React, { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import {
  ShieldCheck, Package, CheckCircle2, X, ChevronRight,
  Shield, ArrowRight, Sparkles, Info,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";
import { clientScenarios, builtinProfiles, type ClientScenario } from "@/data/settings";
import { useAppStore } from "@/store/useAppStore";

const iconMap: Record<string, React.ComponentType<{ className?: string }>> = {
  ShieldCheck,
  Package,
};

export function ScenarioPicker() {
  const { scenarioPickerOpen, setScenarioPickerOpen, applyScenario, activeScenarioId } = useAppStore();
  const [selectedScenario, setSelectedScenario] = useState<ClientScenario | null>(null);
  const [step, setStep] = useState<"choose" | "confirm">("choose");

  if (!scenarioPickerOpen) return null;

  const handleSelectScenario = (scenario: ClientScenario) => {
    setSelectedScenario(scenario);
    setStep("confirm");
  };

  const handleApply = () => {
    if (selectedScenario) {
      applyScenario(selectedScenario.id);
    }
  };

  const handleClose = () => {
    setScenarioPickerOpen(false);
    setSelectedScenario(null);
    setStep("choose");
  };

  const handleBack = () => {
    setSelectedScenario(null);
    setStep("choose");
  };

  // Get profile stats for the selected scenario
  const getProfileStats = (profileId: string) => {
    const profile = builtinProfiles.find((p) => p.id === profileId);
    if (!profile) return { settingsCount: 0, softwareCount: 0 };
    return {
      settingsCount: Object.values(profile.settings).filter(Boolean).length,
      softwareCount: profile.software.length,
    };
  };

  return (
    <AnimatePresence>
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        exit={{ opacity: 0 }}
        className="fixed inset-0 z-50 bg-[var(--wpi-backdrop)] backdrop-blur-sm"
        onClick={handleClose}
      >
        <motion.div
          initial={{ opacity: 0, scale: 0.95, y: 20 }}
          animate={{ opacity: 1, scale: 1, y: 0 }}
          exit={{ opacity: 0, scale: 0.95, y: 20 }}
          transition={{ type: "spring", damping: 28, stiffness: 280 }}
          onClick={(e) => e.stopPropagation()}
          className="absolute inset-4 sm:inset-8 md:inset-16 lg:inset-24 rounded-2xl border border-[var(--wpi-border)] bg-[var(--wpi-bg)] overflow-hidden flex flex-col shadow-2xl backdrop-blur-xl"
        >
          {/* Header */}
          <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--wpi-border)] bg-[var(--wpi-bg-deep)]">
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-[var(--wpi-accent)]/10 border border-[var(--wpi-accent)]/20">
                <Sparkles className="h-5 w-5 text-[var(--wpi-accent)]" />
              </div>
              <div>
                <h2 className="text-lg font-bold text-[var(--wpi-text)]">
                  {step === "choose" ? "Choose Client Scenario" : "Confirm Scenario"}
                </h2>
                <p className="text-xs text-[var(--wpi-muted)]">
                  {step === "choose"
                    ? "Select the type of client installation to pre-configure settings"
                    : "Review and confirm the selected scenario"}
                </p>
              </div>
            </div>
            <Button
              variant="ghost"
              size="sm"
              onClick={handleClose}
              className="h-8 w-8 p-0 text-[var(--wpi-muted)] hover:text-[var(--wpi-text)] hover:bg-[var(--wpi-card)]"
            >
              <X className="h-4 w-4" />
            </Button>
          </div>

          {/* Content */}
          <ScrollArea className="flex-1">
            <div className="p-6">
              <AnimatePresence mode="wait">
                {step === "choose" ? (
                  <motion.div
                    key="choose"
                    initial={{ opacity: 0, x: -20 }}
                    animate={{ opacity: 1, x: 0 }}
                    exit={{ opacity: 0, x: -20 }}
                    transition={{ duration: 0.2 }}
                  >
                    {/* Intro text */}
                    <div className="mb-6 rounded-xl border border-[var(--wpi-accent)]/20 bg-[var(--wpi-accent)]/5 p-4">
                      <div className="flex items-start gap-3">
                        <Info className="h-5 w-5 text-[var(--wpi-accent)] shrink-0 mt-0.5" />
                        <div>
                          <p className="text-sm text-[var(--wpi-text)] mb-1">
                            Different clients need different approaches. Choose a scenario to quickly configure the right settings for your client&apos;s needs.
                          </p>
                          <p className="text-xs text-[var(--wpi-muted)]">
                            You can always customize individual settings after applying a scenario.
                          </p>
                        </div>
                      </div>
                    </div>

                    {/* Active scenario indicator */}
                    {activeScenarioId && (
                      <div className="mb-4 flex items-center gap-2 text-xs text-[var(--wpi-muted)]">
                        <CheckCircle2 className="h-3.5 w-3.5 text-[var(--wpi-accent)]" />
                        <span>Current scenario: <strong className="text-[var(--wpi-accent)]">{clientScenarios.find(s => s.id === activeScenarioId)?.name}</strong></span>
                      </div>
                    )}

                    {/* Scenario Cards */}
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                      {clientScenarios.map((scenario, index) => {
                        const Icon = iconMap[scenario.icon] || Shield;
                        const stats = getProfileStats(scenario.profileId);
                        const isActive = activeScenarioId === scenario.id;

                        return (
                          <motion.div
                            key={scenario.id}
                            initial={{ opacity: 0, y: 20 }}
                            animate={{ opacity: 1, y: 0 }}
                            transition={{ delay: index * 0.1, duration: 0.3 }}
                            onClick={() => handleSelectScenario(scenario)}
                            className={`group relative cursor-pointer rounded-xl border p-5 transition-all duration-200 ${
                              isActive
                                ? `border-[${scenario.color}]/40 bg-[${scenario.color}]/5 shadow-[0_0_30px_${scenario.color}10]`
                                : "border-[var(--wpi-border)] bg-[var(--wpi-card)] hover:border-[var(--wpi-accent)]/30 hover:shadow-[0_0_30px_rgba(0,212,255,0.05)]"
                            }`}
                            style={isActive ? {
                              borderColor: `${scenario.color}66`,
                              backgroundColor: `${scenario.color}0d`,
                              boxShadow: `0 0 30px ${scenario.color}15`,
                            } : undefined}
                          >
                            {/* Recommended badge */}
                            {scenario.recommended && (
                              <div className="absolute -top-2 right-4">
                                <Badge className="bg-[var(--wpi-accent)] text-[var(--wpi-bg)] text-[9px] px-2 shadow-sm">
                                  Recommended
                                </Badge>
                              </div>
                            )}

                            {/* Active indicator */}
                            {isActive && (
                              <div className="absolute top-3 right-3">
                                <CheckCircle2 className="h-5 w-5" style={{ color: scenario.color }} />
                              </div>
                            )}

                            <div className="flex items-start gap-4">
                              {/* Icon */}
                              <div
                                className={`flex h-12 w-12 shrink-0 items-center justify-center rounded-xl border transition-colors ${
                                  isActive ? "" : "bg-[var(--wpi-deep)] border-[var(--wpi-border)] group-hover:border-[var(--wpi-accent)]/30"
                                }`}
                                style={isActive ? {
                                  backgroundColor: `${scenario.color}15`,
                                  borderColor: `${scenario.color}40`,
                                } : undefined}
                              >
                                <Icon
                                  className={`h-6 w-6 ${isActive ? "" : "text-[var(--wpi-muted)] group-hover:text-[var(--wpi-accent)]"}`}
                                  style={isActive ? { color: scenario.color } : undefined}
                                />
                              </div>

                              <div className="flex-1 min-w-0">
                                <h3 className="text-base font-bold text-[var(--wpi-text)] mb-0.5">
                                  {scenario.name}
                                </h3>
                                <p className="text-xs font-medium mb-2" style={{ color: scenario.color }}>
                                  {scenario.subtitle}
                                </p>
                                <p className="text-xs text-[var(--wpi-muted)] line-clamp-3 mb-3">
                                  {scenario.description}
                                </p>

                                {/* Stats */}
                                <div className="flex items-center gap-2 mb-3">
                                  <Badge variant="outline" className="h-5 px-1.5 text-[9px] bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)]">
                                    {stats.settingsCount} settings
                                  </Badge>
                                  <Badge variant="outline" className="h-5 px-1.5 text-[9px] bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)]">
                                    {stats.softwareCount} apps
                                  </Badge>
                                </div>

                                {/* Highlights preview (first 3) */}
                                <div className="space-y-1">
                                  {scenario.highlights.slice(0, 3).map((h, i) => (
                                    <div key={i} className="flex items-start gap-1.5">
                                      <CheckCircle2 className="h-3 w-3 shrink-0 mt-0.5" style={{ color: scenario.color }} />
                                      <span className="text-[11px] text-[var(--wpi-muted)]">{h}</span>
                                    </div>
                                  ))}
                                  {scenario.highlights.length > 3 && (
                                    <p className="text-[10px] text-[var(--wpi-muted)]/60 pl-4">
                                      +{scenario.highlights.length - 3} more...
                                    </p>
                                  )}
                                </div>
                              </div>
                            </div>

                            {/* Hover arrow */}
                            <div className="absolute bottom-4 right-4 opacity-0 group-hover:opacity-100 transition-opacity">
                              <ArrowRight className="h-4 w-4 text-[var(--wpi-accent)]" />
                            </div>
                          </motion.div>
                        );
                      })}
                    </div>

                    {/* Skip option */}
                    <div className="mt-6 text-center">
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={handleClose}
                        className="text-xs text-[var(--wpi-muted)] hover:text-[var(--wpi-text)]"
                      >
                        Skip — I&apos;ll configure manually
                      </Button>
                    </div>
                  </motion.div>
                ) : selectedScenario ? (
                  <motion.div
                    key="confirm"
                    initial={{ opacity: 0, x: 20 }}
                    animate={{ opacity: 1, x: 0 }}
                    exit={{ opacity: 0, x: 20 }}
                    transition={{ duration: 0.2 }}
                  >
                    {/* Confirmation view */}
                    <div className="max-w-2xl mx-auto space-y-6">
                      {/* Scenario header */}
                      <div className="flex items-center gap-4">
                        <div
                          className="flex h-14 w-14 shrink-0 items-center justify-center rounded-xl border"
                          style={{
                            backgroundColor: `${selectedScenario.color}15`,
                            borderColor: `${selectedScenario.color}40`,
                          }}
                        >
                          {React.createElement(iconMap[selectedScenario.icon] || Shield, {
                            className: "h-7 w-7",
                            style: { color: selectedScenario.color },
                          })}
                        </div>
                        <div>
                          <h3 className="text-xl font-bold text-[var(--wpi-text)]">
                            {selectedScenario.name}
                          </h3>
                          <p className="text-sm font-medium" style={{ color: selectedScenario.color }}>
                            {selectedScenario.subtitle}
                          </p>
                        </div>
                      </div>

                      {/* Description */}
                      <p className="text-sm text-[var(--wpi-muted)]">
                        {selectedScenario.description}
                      </p>

                      {/* What this does */}
                      <div className="rounded-xl border border-[var(--wpi-border)] bg-[var(--wpi-card)] overflow-hidden">
                        <div className="px-4 py-3 border-b border-[var(--wpi-border)] bg-[var(--wpi-deep)]">
                          <h4 className="text-sm font-semibold text-[var(--wpi-text)] flex items-center gap-2">
                            <CheckCircle2 className="h-4 w-4" style={{ color: selectedScenario.color }} />
                            What this scenario does
                          </h4>
                        </div>
                        <div className="p-4 space-y-2">
                          {selectedScenario.highlights.map((h, i) => (
                            <div key={i} className="flex items-start gap-2">
                              <CheckCircle2 className="h-3.5 w-3.5 shrink-0 mt-0.5" style={{ color: selectedScenario.color }} />
                              <span className="text-xs text-[var(--wpi-text)]">{h}</span>
                            </div>
                          ))}
                        </div>
                      </div>

                      {/* What this does NOT do */}
                      <div className="rounded-xl border border-[var(--wpi-border)] bg-[var(--wpi-card)] overflow-hidden">
                        <div className="px-4 py-3 border-b border-[var(--wpi-border)] bg-[var(--wpi-deep)]">
                          <h4 className="text-sm font-semibold text-[var(--wpi-muted)] flex items-center gap-2">
                            <X className="h-4 w-4" />
                            What this scenario does NOT do
                          </h4>
                        </div>
                        <div className="p-4 space-y-2">
                          {selectedScenario.excludes.map((e, i) => (
                            <div key={i} className="flex items-start gap-2">
                              <X className="h-3.5 w-3.5 shrink-0 mt-0.5 text-[var(--wpi-muted)]" />
                              <span className="text-xs text-[var(--wpi-muted)]">{e}</span>
                            </div>
                          ))}
                        </div>
                      </div>

                      {/* Profile stats */}
                      {(() => {
                        const stats = getProfileStats(selectedScenario.profileId);
                        return (
                          <div className="flex items-center gap-3">
                            <Badge variant="outline" className="h-6 px-2 text-xs border-[var(--wpi-border)] text-[var(--wpi-text)]">
                              {stats.settingsCount} settings will be enabled
                            </Badge>
                            <Badge variant="outline" className="h-6 px-2 text-xs border-[var(--wpi-border)] text-[var(--wpi-text)]">
                              {stats.softwareCount} apps will be installed
                            </Badge>
                          </div>
                        );
                      })()}

                      {/* Action buttons */}
                      <div className="flex items-center gap-3 pt-2">
                        <Button
                          variant="outline"
                          onClick={handleBack}
                          className="bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:bg-[var(--wpi-card)] hover:text-[var(--wpi-text)]"
                        >
                          Back
                        </Button>
                        <Button
                          onClick={handleApply}
                          className="gap-2 font-semibold shadow-lg"
                          style={{
                            backgroundColor: selectedScenario.color,
                            boxShadow: `0 0 20px ${selectedScenario.color}30`,
                          }}
                        >
                          <CheckCircle2 className="h-4 w-4" />
                          Apply Scenario
                        </Button>
                        <p className="text-[10px] text-[var(--wpi-muted)] ml-2">
                          You can customize settings after applying
                        </p>
                      </div>
                    </div>
                  </motion.div>
                ) : null}
              </AnimatePresence>
            </div>
          </ScrollArea>
        </motion.div>
      </motion.div>
    </AnimatePresence>
  );
}
