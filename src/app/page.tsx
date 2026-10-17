"use client";

import React, { useState, useEffect } from "react";
import { motion } from "framer-motion";
import {
  LayoutDashboard, Package, Users, Undo2, Eye,
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

export default function WinPostInstallPage() {
  const { setActiveSectionId, applyChanges, hydrate, hydrated } = useAppStore();
  const [activeTab, setActiveTab] = useState("dashboard");

  useEffect(() => {
    hydrate();
  }, [hydrate]);

  const handleSectionClick = (sectionId: string) => {
    setActiveSectionId(sectionId);
  };

  const handleApply = () => {
    applyChanges();
  };

  const handleUndo = () => {
    setActiveTab("undo");
  };

  const handlePreview = () => {
    setActiveTab("preview");
  };

  return (
    <div className="min-h-screen bg-[#0a0a0f] text-[#e0e0e0] flex flex-col">
      <AppHeader onApply={handleApply} onUndo={handleUndo} onPreview={handlePreview} />

      {/* Main content */}
      <main className="flex-1 mx-auto w-full max-w-7xl px-4 py-4">
        <Tabs value={activeTab} onValueChange={setActiveTab} className="flex flex-col gap-4">
          <TabsList className="bg-[#12121a] border border-[#2a2a3e] w-fit h-10 p-1 rounded-lg">
            <TabsTrigger
              value="dashboard"
              className="data-[state=active]:bg-[#1a1a2e] data-[state=active]:text-[#00d4ff] data-[state=active]:shadow-sm text-[#8888a0] gap-1.5 px-3 text-xs rounded-md"
            >
              <LayoutDashboard className="h-3.5 w-3.5" />
              <span className="hidden sm:inline">Dashboard</span>
            </TabsTrigger>
            <TabsTrigger
              value="software"
              className="data-[state=active]:bg-[#1a1a2e] data-[state=active]:text-[#00d4ff] data-[state=active]:shadow-sm text-[#8888a0] gap-1.5 px-3 text-xs rounded-md"
            >
              <Package className="h-3.5 w-3.5" />
              <span className="hidden sm:inline">Software</span>
            </TabsTrigger>
            <TabsTrigger
              value="profiles"
              className="data-[state=active]:bg-[#1a1a2e] data-[state=active]:text-[#00d4ff] data-[state=active]:shadow-sm text-[#8888a0] gap-1.5 px-3 text-xs rounded-md"
            >
              <Users className="h-3.5 w-3.5" />
              <span className="hidden sm:inline">Profiles</span>
            </TabsTrigger>
            <TabsTrigger
              value="undo"
              className="data-[state=active]:bg-[#1a1a2e] data-[state=active]:text-[#00d4ff] data-[state=active]:shadow-sm text-[#8888a0] gap-1.5 px-3 text-xs rounded-md"
            >
              <Undo2 className="h-3.5 w-3.5" />
              <span className="hidden sm:inline">Undo</span>
            </TabsTrigger>
            <TabsTrigger
              value="preview"
              className="data-[state=active]:bg-[#1a1a2e] data-[state=active]:text-[#00d4ff] data-[state=active]:shadow-sm text-[#8888a0] gap-1.5 px-3 text-xs rounded-md"
            >
              <Eye className="h-3.5 w-3.5" />
              <span className="hidden sm:inline">Preview</span>
            </TabsTrigger>
          </TabsList>

          <motion.div
            key={activeTab}
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.2 }}
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
          </motion.div>
        </Tabs>
      </main>

      {/* Footer */}
      <footer className="border-t border-[#2a2a3e] bg-[#0a0a0f] mt-auto">
        <div className="mx-auto max-w-7xl px-4 py-3 flex items-center justify-between">
          <p className="text-[10px] text-[#8888a0]/50">
            WinPostInstall v4.1.0 • GUI Optimizer
          </p>
          <p className="text-[10px] text-[#8888a0]/50">
            Compatible with WinPostInstall.ps1
          </p>
        </div>
      </footer>

      {/* Section Detail Panel (overlay) */}
      <SectionDetailPanel />
    </div>
  );
}
