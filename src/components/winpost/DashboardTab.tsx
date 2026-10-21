"use client";

import React from "react";
import { motion } from "framer-motion";
import {
  Shield, Trash2, FolderOpen, Settings, Zap, Lock,
  Wifi, RefreshCw, HardDrive, Package, FileSpreadsheet,
  Globe, Cloud, Gamepad2, CalendarClock, ShieldCheck,
  Sparkles, Puzzle,
} from "lucide-react";
import { sections, type Section } from "@/data/settings";
import { useAppStore } from "@/store/useAppStore";
import { SafetyBadge } from "./SafetyBadge";
import { QuickSelectBar } from "./QuickSelectBar";
import { clientScenarios } from "@/data/settings";

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
  const { settings, searchQuery, toggleSectionAll, getEnabledCount, getTotalCount, getSectionSafetyCounts, getSectionEnabledSafetyCounts, activeScenarioId, setScenarioPickerOpen } = useAppStore();

  const activeScenario = activeScenarioId ? clientScenarios.find(s => s.id === activeScenarioId) : null;

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

      {/* Active Scenario Banner */}
      {activeScenario && (
        <motion.div
          initial={{ opacity: 0, y: -5 }}
          animate={{ opacity: 1, y: 0 }}
          className="flex items-center gap-3 rounded-xl border p-3 cursor-pointer transition-all hover:shadow-sm"
          style={{
            borderColor: `${activeScenario.color}40`,
            backgroundColor: `${activeScenario.color}08`,
          }}
          onClick={() => setScenarioPickerOpen(true)}
        >
          <Sparkles className="h-4 w-4 shrink-0" style={{ color: activeScenario.color }} />
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2">
              <span className="text-xs font-semibold" style={{ color: activeScenario.color }}>
                {activeScenario.name}
              </span>
              <span className="text-xs px-1.5 py-0.5 rounded-md font-medium" style={{ backgroundColor: `${activeScenario.color}15`, color: activeScenario.color }}>
                Active
              </span>
            </div>
            <p className="text-xs text-[var(--wpi-muted)] mt-0.5">{activeScenario.subtitle}</p>
          </div>
          <span className="text-xs text-[var(--wpi-muted)] hover:text-[var(--wpi-text)] shrink-0">Change →</span>
        </motion.div>
      )}

      {/* Section Cards Grid — Simplified Apple/Google style */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 p-1">
        {filteredSections.map((section, index) => {
          const Icon = iconMap[section.icon] || Settings;
          const enabled = getEnabledCount(section.id);
          const total = getTotalCount(section.id);
          const allEnabled = enabled === total;
          const safety = getSectionSafety(section);
          const isFiltered = !!searchQuery;

          // Safety breakdown for the progress bar
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

          const percentage = total > 0 ? Math.round((enabled / total) * 100) : 0;

          return (
            <motion.div
              key={section.id}
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: index * 0.03, duration: 0.3 }}
              onClick={() => onSectionClick(section.id)}
              className="group relative cursor-pointer rounded-xl border border-[var(--wpi-border)] bg-[var(--wpi-card)] transition-all duration-200 hover:border-[var(--wpi-accent)]/30 hover:shadow-[var(--wpi-accent-glow-lg)]"
            >
              <div className="p-4">
                <div className="flex items-start gap-3">
                  {/* Icon */}
                  <div className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-xl transition-colors ${allEnabled ? "bg-[var(--wpi-accent)]/15 border border-[var(--wpi-accent)]/30" : "bg-[var(--wpi-deep)] border border-[var(--wpi-border)]"}`}>
                    <Icon className={`h-5 w-5 ${allEnabled ? "text-[var(--wpi-accent)]" : "text-[var(--wpi-muted)]"}`} />
                  </div>

                  <div className="flex-1 min-w-0">
                    {/* Title row */}
                    <div className="flex items-center gap-2 mb-1">
                      <h3 className="text-sm font-semibold text-[var(--wpi-text)] truncate">
                        {section.name}
                      </h3>
                      <SafetyBadge safety={safety} compact />
                    </div>

                    {/* Description */}
                    <p className="text-xs text-[var(--wpi-muted)] line-clamp-1">
                      {section.description}
                    </p>
                  </div>

                  {/* Toggle — larger touch target */}
                  <div className="shrink-0 pt-0.5" onClick={(e) => e.stopPropagation()}>
                    <button
                      role="switch"
                      aria-checked={allEnabled}
                      onClick={(e) => { e.stopPropagation(); toggleSectionAll(section.id, !allEnabled); }}
                      className={`relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--wpi-accent)]/50 focus-visible:ring-offset-2 focus-visible:ring-offset-[var(--wpi-card)] ${allEnabled ? "bg-[var(--wpi-accent)]" : "bg-[var(--wpi-border)]"}`}
                    >
                      <span className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out ${allEnabled ? "translate-x-5" : "translate-x-0"}`} />
                    </button>
                  </div>
                </div>
              </div>

              {/* Bottom progress bar — clean, minimal */}
              <div className="border-t border-[var(--wpi-border)]/50 px-4 py-2.5">
                <div className="flex items-center gap-3">
                  {/* Segmented progress bar */}
                  <div className="flex-1 h-2 rounded-full bg-[var(--wpi-deep)] overflow-hidden">
                    <div className="flex h-full">
                      <motion.div
                        className="bg-[var(--wpi-safe)]"
                        initial={{ width: 0 }}
                        animate={{ width: `${total > 0 ? (eCounts.Safe / total) * 100 : 0}%` }}
                        transition={{ duration: 0.5 }}
                      />
                      <motion.div
                        className="bg-[var(--wpi-moderate)]"
                        initial={{ width: 0 }}
                        animate={{ width: `${total > 0 ? (eCounts.Moderate / total) * 100 : 0}%` }}
                        transition={{ duration: 0.5 }}
                      />
                      <motion.div
                        className="bg-[var(--wpi-risky)]"
                        initial={{ width: 0 }}
                        animate={{ width: `${total > 0 ? (eCounts.Risky / total) * 100 : 0}%` }}
                        transition={{ duration: 0.5 }}
                      />
                    </div>
                  </div>

                  {/* Count — clean, readable */}
                  <span className="text-xs font-medium text-[var(--wpi-muted)] tabular-nums whitespace-nowrap">
                    {enabled}/{total}
                  </span>
                </div>

                {/* Search match indicator */}
                {isFiltered && matchingSettings.length < total && (
                  <p className="text-xs text-[var(--wpi-accent)] mt-1">
                    {matchingSettings.length} matching
                  </p>
                )}
              </div>
            </motion.div>
          );
        })}
      </div>
    </div>
  );
}
