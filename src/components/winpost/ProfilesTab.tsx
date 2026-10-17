"use client";

import React, { useState } from "react";
import { motion } from "framer-motion";
import {
  Save, Download, Upload, Trash2, User, Check,
  Shield, Monitor, Minimize2, Eye, Code2,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { useAppStore } from "@/store/useAppStore";

const profileIcons: Record<string, React.ComponentType<{ className?: string }>> = {
  gaming: Shield,
  office: Monitor,
  minimal: Minimize2,
  maxprivacy: Eye,
  developer: Code2,
};

export function ProfilesTab() {
  const {
    profiles,
    activeProfileId,
    loadProfile,
    saveProfile,
    deleteProfile,
    exportProfile,
    importProfile,
    settings,
    selectedSoftware,
  } = useAppStore();

  const [newProfileName, setNewProfileName] = useState("");
  const [newProfileDesc, setNewProfileDesc] = useState("");
  const [saveDialogOpen, setSaveDialogOpen] = useState(false);
  const [importDialogOpen, setImportDialogOpen] = useState(false);
  const [importText, setImportText] = useState("");
  const [importError, setImportError] = useState(false);

  const enabledCount = Object.values(settings).filter(Boolean).length;

  const handleSave = () => {
    if (!newProfileName.trim()) return;
    saveProfile(newProfileName.trim(), newProfileDesc.trim());
    setNewProfileName("");
    setNewProfileDesc("");
    setSaveDialogOpen(false);
  };

  const handleExport = (profileId: string) => {
    const json = exportProfile(profileId);
    const blob = new Blob([json], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `profile-${profileId}.json`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const handleImport = () => {
    const success = importProfile(importText);
    setImportError(!success);
    if (success) {
      setImportText("");
      setImportDialogOpen(false);
    }
  };

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h2 className="text-base font-semibold text-[#e0e0e0]">Profiles</h2>
          <p className="text-xs text-[#8888a0]">
            Save, load, and manage configuration profiles
          </p>
        </div>
        <div className="flex gap-2">
          <Dialog open={saveDialogOpen} onOpenChange={setSaveDialogOpen}>
            <DialogTrigger asChild>
              <Button size="sm" className="h-8 gap-1.5 bg-[#00d4ff] hover:bg-[#00d4ff]/90 text-[#0a0a0f] font-semibold text-xs">
                <Save className="h-3.5 w-3.5" />
                Save Current
              </Button>
            </DialogTrigger>
            <DialogContent className="bg-[#12121a] border-[#2a2a3e] text-[#e0e0e0]">
              <DialogHeader>
                <DialogTitle className="text-[#e0e0e0]">Save Profile</DialogTitle>
                <DialogDescription className="text-[#8888a0]">
                  Save your current configuration as a new profile
                </DialogDescription>
              </DialogHeader>
              <div className="space-y-3 py-2">
                <Input
                  placeholder="Profile name"
                  value={newProfileName}
                  onChange={(e) => setNewProfileName(e.target.value)}
                  className="bg-[#1a1a2e] border-[#2a2a3e] text-[#e0e0e0] placeholder:text-[#8888a0]"
                />
                <Input
                  placeholder="Description (optional)"
                  value={newProfileDesc}
                  onChange={(e) => setNewProfileDesc(e.target.value)}
                  className="bg-[#1a1a2e] border-[#2a2a3e] text-[#e0e0e0] placeholder:text-[#8888a0]"
                />
                <p className="text-xs text-[#8888a0]">
                  {enabledCount} settings + {selectedSoftware.length} software selected
                </p>
              </div>
              <DialogFooter>
                <Button
                  onClick={handleSave}
                  disabled={!newProfileName.trim()}
                  className="bg-[#00d4ff] hover:bg-[#00d4ff]/90 text-[#0a0a0f]"
                >
                  Save
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>

          <Dialog open={importDialogOpen} onOpenChange={setImportDialogOpen}>
            <DialogTrigger asChild>
              <Button variant="outline" size="sm" className="h-8 gap-1.5 bg-[#12121a] border-[#2a2a3e] text-[#8888a0] hover:bg-[#1a1a2e] hover:text-[#e0e0e0] text-xs">
                <Upload className="h-3.5 w-3.5" />
                Import
              </Button>
            </DialogTrigger>
            <DialogContent className="bg-[#12121a] border-[#2a2a3e] text-[#e0e0e0]">
              <DialogHeader>
                <DialogTitle className="text-[#e0e0e0]">Import Profile</DialogTitle>
                <DialogDescription className="text-[#8888a0]">
                  Paste a profile JSON to import
                </DialogDescription>
              </DialogHeader>
              <div className="space-y-3 py-2">
                <textarea
                  placeholder='{"name": "My Profile", "settings": {...}}'
                  value={importText}
                  onChange={(e) => { setImportText(e.target.value); setImportError(false); }}
                  className="w-full h-32 rounded-lg bg-[#1a1a2e] border border-[#2a2a3e] text-[#e0e0e0] placeholder:text-[#8888a0] p-3 text-xs font-mono resize-none focus:outline-none focus:ring-1 focus:ring-[#00d4ff]/30"
                />
                {importError && (
                  <p className="text-xs text-[#ef4444]">Invalid JSON format</p>
                )}
              </div>
              <DialogFooter>
                <Button
                  onClick={handleImport}
                  disabled={!importText.trim()}
                  className="bg-[#00d4ff] hover:bg-[#00d4ff]/90 text-[#0a0a0f]"
                >
                  Import
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </div>
      </div>

      {/* Profile list */}
      <ScrollArea className="max-h-[calc(100vh-320px)]">
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 p-1">
          {profiles.map((profile, index) => {
            const isActive = activeProfileId === profile.id;
            const ProfileIcon = profile.isBuiltin && profileIcons[profile.id]
              ? profileIcons[profile.id]
              : User;
            const settingsCount = Object.values(profile.settings).filter(Boolean).length;

            return (
              <motion.div
                key={profile.id}
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: index * 0.03 }}
                className={`relative rounded-xl border p-4 transition-all ${
                  isActive
                    ? "bg-[#00d4ff]/5 border-[#00d4ff]/30 shadow-[0_0_30px_rgba(0,212,255,0.05)]"
                    : "bg-[#1a1a2e] border-[#2a2a3e] hover:border-[#2a2a3e]/80"
                }`}
              >
                {isActive && (
                  <div className="absolute top-2 right-2">
                    <Badge className="bg-[#00d4ff]/15 text-[#00d4ff] border-[#00d4ff]/20 text-[9px]">
                      Active
                    </Badge>
                  </div>
                )}

                <div className="flex items-start gap-3">
                  <div className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-lg ${
                    isActive ? "bg-[#00d4ff]/15 border border-[#00d4ff]/30" : "bg-[#12121a] border border-[#2a2a3e]"
                  }`}>
                    <ProfileIcon className={`h-5 w-5 ${isActive ? "text-[#00d4ff]" : "text-[#8888a0]"}`} />
                  </div>

                  <div className="flex-1 min-w-0">
                    <h3 className={`text-sm font-semibold mb-0.5 ${isActive ? "text-[#e0e0e0]" : "text-[#8888a0]"}`}>
                      {profile.name}
                    </h3>
                    <p className="text-[11px] text-[#8888a0]/70 line-clamp-2 mb-2">
                      {profile.description}
                    </p>

                    <div className="flex items-center gap-2 flex-wrap">
                      <Badge variant="outline" className="h-4 px-1 text-[9px] bg-[#12121a] border-[#2a2a3e] text-[#8888a0]">
                        {settingsCount} settings
                      </Badge>
                      <Badge variant="outline" className="h-4 px-1 text-[9px] bg-[#12121a] border-[#2a2a3e] text-[#8888a0]">
                        {profile.software.length} apps
                      </Badge>
                      {profile.isBuiltin && (
                        <Badge variant="outline" className="h-4 px-1 text-[9px] bg-[#0ea5e9]/5 border-[#0ea5e9]/20 text-[#0ea5e9]">
                          Built-in
                        </Badge>
                      )}
                    </div>
                  </div>
                </div>

                {/* Actions */}
                <div className="flex items-center gap-2 mt-3 pt-3 border-t border-[#2a2a3e]/50">
                  <Button
                    size="sm"
                    variant={isActive ? "ghost" : "outline"}
                    onClick={() => loadProfile(profile.id)}
                    className={`h-7 gap-1 text-[10px] ${
                      isActive
                        ? "text-[#00d4ff] hover:bg-[#00d4ff]/10"
                        : "bg-[#12121a] border-[#2a2a3e] text-[#8888a0] hover:bg-[#1a1a2e] hover:text-[#e0e0e0]"
                    }`}
                  >
                    <Check className="h-3 w-3" />
                    {isActive ? "Loaded" : "Load"}
                  </Button>
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={() => handleExport(profile.id)}
                    className="h-7 gap-1 text-[10px] bg-[#12121a] border-[#2a2a3e] text-[#8888a0] hover:bg-[#1a1a2e] hover:text-[#e0e0e0]"
                  >
                    <Download className="h-3 w-3" />
                    Export
                  </Button>
                  {!profile.isBuiltin && (
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => deleteProfile(profile.id)}
                      className="h-7 gap-1 text-[10px] bg-[#12121a] border-[#2a2a3e] text-[#8888a0] hover:bg-[#ef4444]/10 hover:text-[#ef4444] hover:border-[#ef4444]/30"
                    >
                      <Trash2 className="h-3 w-3" />
                      Delete
                    </Button>
                  )}
                </div>
              </motion.div>
            );
          })}
        </div>
      </ScrollArea>
    </div>
  );
}
