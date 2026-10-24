"use client";

import React, { useState, useEffect, useCallback } from "react";
import { motion } from "framer-motion";
import {
  LayoutDashboard, Package, Users, Undo2, Eye, Scan, Disc3,
} from "lucide-react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useAppStore } from "@/store/useAppStore";
import { AppHeader } from "@/components/winpost/AppHeader";
import { DashboardTab } from "@/components/winpost/DashboardTab";
import { SectionDetailPanel } from "@/components/winpost/SectionDetailPanel";
import { SoftwareInstallTab } from "@/components/winpost/SoftwareInstallTab";
import { ProfilesTab } from "@/components/winpost/ProfilesTab";
import { UndoCenterTab } from "@/components/winpost/UndoCenterTab";
import { PreviewTab } from "@/components/winpost/PreviewTab";
import { RegistryScanTab } from "@/components/winpost/RegistryScanTab";
import { ISOBuilderTab } from "@/components/winpost/ISOBuilderTab";
import { ScenarioPicker } from "@/components/winpost/ScenarioPicker";

const tabTriggerClass = "data-[state=active]:bg-[var(--wpi-card)] data-[state=active]:text-[var(--wpi-accent)] data-[state=active]:shadow-sm text-[var(--wpi-muted)] gap-1.5 px-3 text-xs rounded-md transition-all duration-200";

export default function WinPostInstallPage() {
  const { setActiveSectionId, applyChanges, hydrate, hydrated, toggleBySafety, toggleAllSettings, setScenarioPickerOpen } = useAppStore();
  const [activeTab, setActiveTab] = useState("dashboard");

  useEffect(() => {
    hydrate();
  }, [hydrate]);

  // Amnesic cleanup: clear localStorage when window is about to close (Tauri mode)
  useEffect(() => {
    const isTauri = typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
    if (!isTauri) return;

    const handleBeforeUnload = () => {
      // Clear all WinPostInstall localStorage keys
      const keysToRemove = [
        "winpostinstall-profiles",
        "winpostinstall-settings",
        "winpostinstall-software",
        "winpostinstall-undo",
        "winpostinstall-active-profile",
      ];
      keysToRemove.forEach((key) => {
        try { localStorage.removeItem(key); } catch { /* ignore */ }
      });
    };

    window.addEventListener("beforeunload", handleBeforeUnload);
    return () => window.removeEventListener("beforeunload", handleBeforeUnload);
  }, []);

  const handleSectionClick = (sectionId: string) => {
    setActiveSectionId(sectionId);
  };

  const handleApply = (): Promise<boolean> => {
    return applyChanges();
  };

  const handleUndo = () => {
    setActiveTab("undo");
  };

  const handlePreview = () => {
    setActiveTab("preview");
  };

  // Keyboard shortcuts
  const handleKeyDown = useCallback((e: KeyboardEvent) => {
    // Only trigger if no input/textarea is focused
    const target = e.target as HTMLElement;
    if (target.tagName === "INPUT" || target.tagName === "TEXTAREA" || target.isContentEditable) return;

    const ctrlOrMeta = e.ctrlKey || e.metaKey;

    if (ctrlOrMeta && e.shiftKey && e.key === "a") {
      // Ctrl+Shift+A → Select All (including risky)
      e.preventDefault();
      toggleAllSettings(true);
    } else if (ctrlOrMeta && e.key === "a") {
      // Ctrl+A → Select All Safe
      e.preventDefault();
      toggleBySafety(["Safe", "Moderate", "Risky"], false);
      toggleBySafety(["Safe"], true);
    } else if (ctrlOrMeta && e.key === "m") {
      // Ctrl+M → Select Safe + Moderate
      e.preventDefault();
      toggleBySafety(["Safe", "Moderate", "Risky"], false);
      toggleBySafety(["Safe", "Moderate"], true);
    } else if (ctrlOrMeta && e.key === "d") {
      // Ctrl+D → Deselect All
      e.preventDefault();
      toggleAllSettings(false);
    } else if (ctrlOrMeta && e.key === "p") {
      // Ctrl+P → Preview
      e.preventDefault();
      setActiveTab("preview");
    } else if (ctrlOrMeta && e.key === "s") {
      // Ctrl+S → Scenario Picker
      e.preventDefault();
      setScenarioPickerOpen(true);
    } else if (e.key === "1" && ctrlOrMeta) {
      e.preventDefault();
      setActiveTab("dashboard");
    } else if (e.key === "2" && ctrlOrMeta) {
      e.preventDefault();
      setActiveTab("software");
    } else if (e.key === "3" && ctrlOrMeta) {
      e.preventDefault();
      setActiveTab("profiles");
    } else if (e.key === "4" && ctrlOrMeta) {
      e.preventDefault();
      setActiveTab("undo");
    } else if (e.key === "5" && ctrlOrMeta) {
      e.preventDefault();
      setActiveTab("preview");
    } else if (e.key === "6" && ctrlOrMeta) {
      e.preventDefault();
      setActiveTab("scanner");
    } else if (e.key === "7" && ctrlOrMeta) {
      e.preventDefault();
      setActiveTab("iso");
    }
  }, [toggleBySafety, toggleAllSettings, setScenarioPickerOpen]);

  useEffect(() => {
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [handleKeyDown]);

  return (
    <div className="min-h-screen bg-[var(--wpi-bg)] text-[var(--wpi-text)] flex flex-col">
      <AppHeader onApply={handleApply} onUndo={handleUndo} onPreview={handlePreview} />

      {/* Main content */}
      <main className="flex-1 mx-auto w-full max-w-7xl px-4 py-4">
        <Tabs value={activeTab} onValueChange={setActiveTab} className="flex flex-col gap-4">
          {/* Tab bar — Apple-style with overflow scroll on mobile */}
          <TabsList className="bg-[var(--wpi-deep)] border border-[var(--wpi-border)] w-fit h-10 p-1 rounded-lg overflow-x-auto">
            <TabsTrigger value="dashboard" className={tabTriggerClass}>
              <LayoutDashboard className="h-3.5 w-3.5" />
              <span className="hidden sm:inline">Dashboard</span>
            </TabsTrigger>
            <TabsTrigger value="software" className={tabTriggerClass}>
              <Package className="h-3.5 w-3.5" />
              <span className="hidden sm:inline">Software</span>
            </TabsTrigger>
            <TabsTrigger value="profiles" className={tabTriggerClass}>
              <Users className="h-3.5 w-3.5" />
              <span className="hidden sm:inline">Profiles</span>
            </TabsTrigger>
            <TabsTrigger value="undo" className={tabTriggerClass}>
              <Undo2 className="h-3.5 w-3.5" />
              <span className="hidden sm:inline">Undo</span>
            </TabsTrigger>
            <TabsTrigger value="preview" className={tabTriggerClass}>
              <Eye className="h-3.5 w-3.5" />
              <span className="hidden sm:inline">Preview</span>
            </TabsTrigger>
            <TabsTrigger value="scanner" className={tabTriggerClass}>
              <Scan className="h-3.5 w-3.5" />
              <span className="hidden sm:inline">Scanner</span>
            </TabsTrigger>
            <TabsTrigger value="iso" className={tabTriggerClass}>
              <Disc3 className="h-3.5 w-3.5" />
              <span className="hidden sm:inline">ISO</span>
            </TabsTrigger>
          </TabsList>

          {/* Content with Apple-style smooth fade+slide */}
          <motion.div
            key={activeTab}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.25, ease: [0.25, 0.1, 0.25, 1] }}
          >
            <TabsContent value="dashboard" className="mt-0">
              <DashboardTab onSectionClick={handleSectionClick} />
            </TabsContent>

            <TabsContent value="software" className="mt-0">
              <SoftwareInstallTab />
            </TabsContent>

            <TabsContent value="profiles" className="mt-0">
              <ProfilesTab />
            </TabsContent>

            <TabsContent value="undo" className="mt-0">
              <UndoCenterTab />
            </TabsContent>

            <TabsContent value="preview" className="mt-0">
              <PreviewTab />
            </TabsContent>

            <TabsContent value="scanner" className="mt-0">
              <RegistryScanTab />
            </TabsContent>

            <TabsContent value="iso" className="mt-0">
              <ISOBuilderTab />
            </TabsContent>
          </motion.div>
        </Tabs>
      </main>

      {/* Footer — Apple-style minimal, keyboard shortcuts as discoverable hints */}
      <footer className="border-t border-[var(--wpi-border)] bg-[var(--wpi-bg)] mt-auto">
        <div className="mx-auto max-w-7xl px-4 py-2.5 flex items-center justify-between flex-wrap gap-2">
          <p className="text-[10px] text-[var(--wpi-muted)]/50">
            WinPostInstall v4.1.2
          </p>
          <div className="flex items-center gap-3">
            <div className="flex items-center gap-1.5 text-[9px] text-[var(--wpi-muted)]/30">
              <kbd className="px-1 py-0.5 rounded bg-[var(--wpi-deep)] border border-[var(--wpi-border)] text-[8px]">Ctrl+A</kbd>
              <span>All Safe</span>
            </div>
            <div className="flex items-center gap-1.5 text-[9px] text-[var(--wpi-muted)]/30">
              <kbd className="px-1 py-0.5 rounded bg-[var(--wpi-deep)] border border-[var(--wpi-border)] text-[8px]">Ctrl+M</kbd>
              <span>Safe+Mod</span>
            </div>
            <div className="flex items-center gap-1.5 text-[9px] text-[var(--wpi-muted)]/30">
              <kbd className="px-1 py-0.5 rounded bg-[var(--wpi-deep)] border border-[var(--wpi-border)] text-[8px]">Ctrl+D</kbd>
              <span>None</span>
            </div>
            <div className="flex items-center gap-1.5 text-[9px] text-[var(--wpi-muted)]/30">
              <kbd className="px-1 py-0.5 rounded bg-[var(--wpi-deep)] border border-[var(--wpi-border)] text-[8px]">Ctrl+S</kbd>
              <span>Scenario</span>
            </div>
          </div>
        </div>
      </footer>

      {/* Section Detail Panel (overlay) */}
      <SectionDetailPanel />

      {/* Scenario Picker (overlay) */}
      <ScenarioPicker />
    </div>
  );
}
