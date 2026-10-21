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
          className="flex items-center gap-3 rounded-xl border p-3.5 cursor-pointer transition-all duration-200 hover:shadow-sm"
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

      {/* Section Cards Grid — Apple HIG style: generous spacing, clear hierarchy */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3.5 p-0.5">
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
              initial={{ opacity: 0, y: 16 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: index * 0.04, duration: 0.35, ease: [0.25, 0.1, 0.25, 1] }}
              onClick={() => onSectionClick(section.id)}
              className="group relative cursor-pointer rounded-xl border border-[var(--wpi-border)] bg-[var(--wpi-card)] transition-all duration-200 hover:border-[var(--wpi-accent)]/25 hover:shadow-[var(--wpi-accent-glow-lg)]"
            >
              <div className="p-4 pb-3">
                <div className="flex items-start gap-3">
                  {/* Icon — Apple-style with subtle gradient fill */}
                  <div className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-xl transition-all duration-200 ${allEnabled ? "bg-[var(--wpi-safe-15)] border border-[var(--wpi-safe-30)]" : "bg-[var(--wpi-deep)] border border-[var(--wpi-border)]"}`}>
                    <Icon className={`h-5 w-5 transition-colors duration-200 ${allEnabled ? "text-[var(--wpi-safe)]" : "text-[var(--wpi-muted)] group-hover:text-[var(--wpi-text-secondary)]"}`} />
                  </div>

                  <div className="flex-1 min-w-0">
                    {/* Title row */}
                    <div className="flex items-center gap-2 mb-0.5">
                      <h3 className="text-sm font-semibold text-[var(--wpi-text)] truncate leading-tight">
                        {section.name}
                      </h3>
                      <SafetyBadge safety={safety} compact />
                    </div>

                    {/* Description */}
                    <p className="text-xs text-[var(--wpi-muted)] line-clamp-1 leading-relaxed">
                      {section.description}
                    </p>
                  </div>

                  {/* Toggle — consistent with shadcn Switch style */}
                  <div className="shrink-0 pt-0.5" onClick={(e) => e.stopPropagation()}>
                    <button
                      role="switch"
                      aria-checked={allEnabled}
                      onClick={(e) => { e.stopPropagation(); toggleSectionAll(section.id, !allEnabled); }}
                      className={`relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-all duration-200 ease-[cubic-bezier(0.25,0.1,0.25,1)] focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--wpi-accent)]/50 focus-visible:ring-offset-2 focus-visible:ring-offset-[var(--wpi-card)] ${allEnabled ? "bg-[var(--wpi-accent)]" : "bg-[var(--wpi-border)]"}`}
                    >
                      <span className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow-sm ring-0 transition-all duration-200 ease-[cubic-bezier(0.25,0.1,0.25,1)] ${allEnabled ? "translate-x-5" : "translate-x-0"}`} />
                    </button>
                  </div>
                </div>
              </div>

              {/* Bottom progress bar — Apple-style clean minimal */}
              <div className="border-t border-[var(--wpi-border-subtle)] px-4 py-2.5">
                <div className="flex items-center gap-3">
                  {/* Segmented progress bar */}
                  <div className="flex-1 h-1.5 rounded-full bg-[var(--wpi-deep)] overflow-hidden">
                    <div className="flex h-full">
                      <motion.div
                        className="bg-[var(--wpi-safe)]"
                        initial={{ width: 0 }}
                        animate={{ width: `${total > 0 ? (eCounts.Safe / total) * 100 : 0}%` }}
                        transition={{ duration: 0.6, ease: [0.25, 0.1, 0.25, 1] }}
                      />
                      <motion.div
                        className="bg-[var(--wpi-moderate)]"
                        initial={{ width: 0 }}
                        animate={{ width: `${total > 0 ? (eCounts.Moderate / total) * 100 : 0}%` }}
                        transition={{ duration: 0.6, ease: [0.25, 0.1, 0.25, 1] }}
                      />
                      <motion.div
                        className="bg-[var(--wpi-risky)]"
                        initial={{ width: 0 }}
                        animate={{ width: `${total > 0 ? (eCounts.Risky / total) * 100 : 0}%` }}
                        transition={{ duration: 0.6, ease: [0.25, 0.1, 0.25, 1] }}
                      />
                    </div>
                  </div>

                  {/* Count — clean, readable with accent color when active */}
                  <span className={`text-xs font-medium tabular-nums whitespace-nowrap transition-colors duration-200 ${percentage > 0 ? "text-[var(--wpi-accent)]" : "text-[var(--wpi-muted)]"}`}>
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
