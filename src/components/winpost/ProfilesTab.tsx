"use client";

import React, { useState } from "react";
import { motion } from "framer-motion";
import {
  Save, Download, Upload, Trash2, User, Check,
  Shield, Monitor, Minimize2, Eye, Code2, GitCompare,
  ShieldCheck, Package,
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
import { ProfileComparison } from "./ProfileComparison";

const profileIcons: Record<string, React.ComponentType<{ className?: string }>> = {
  gaming: Shield,
  office: Monitor,
  minimal: Minimize2,
  maxprivacy: Eye,
  developer: Code2,
  privacysecurity: ShieldCheck,
  appsetup: Package,
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
  const [compareDialogOpen, setCompareDialogOpen] = useState(false);
  const [compareA, setCompareA] = useState<string | null>(null);
  const [compareB, setCompareB] = useState<string | null>(null);

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

  const openCompare = (idA: string, idB: string) => {
    setCompareA(idA);
    setCompareB(idB);
    setCompareDialogOpen(true);
  };

  const profileA = compareA ? profiles.find((p) => p.id === compareA) : null;
  const profileB = compareB ? profiles.find((p) => p.id === compareB) : null;

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h2 className="text-base font-semibold text-[var(--wpi-text)]">Profiles</h2>
          <p className="text-xs text-[var(--wpi-muted)]">
            Save, load, compare, and manage configuration profiles
          </p>
        </div>
        <div className="flex gap-2">
          <Dialog open={saveDialogOpen} onOpenChange={setSaveDialogOpen}>
            <DialogTrigger asChild>
              <Button size="sm" className="h-8 gap-1.5 bg-[var(--wpi-accent)] hover:bg-[var(--wpi-accent)]/90 text-[var(--wpi-bg)] font-semibold text-xs">
                <Save className="h-3.5 w-3.5" />
                Save Current
              </Button>
            </DialogTrigger>
            <DialogContent className="bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-text)]">
              <DialogHeader>
                <DialogTitle className="text-[var(--wpi-text)]">Save Profile</DialogTitle>
                <DialogDescription className="text-[var(--wpi-muted)]">
                  Save your current configuration as a new profile
                </DialogDescription>
              </DialogHeader>
              <div className="space-y-3 py-2">
                <Input
                  placeholder="Profile name"
                  value={newProfileName}
                  onChange={(e) => setNewProfileName(e.target.value)}
                  className="bg-[var(--wpi-card)] border-[var(--wpi-border)] text-[var(--wpi-text)] placeholder:text-[var(--wpi-muted)]"
                />
                <Input
                  placeholder="Description (optional)"
                  value={newProfileDesc}
                  onChange={(e) => setNewProfileDesc(e.target.value)}
                  className="bg-[var(--wpi-card)] border-[var(--wpi-border)] text-[var(--wpi-text)] placeholder:text-[var(--wpi-muted)]"
                />
                <p className="text-xs text-[var(--wpi-muted)]">
                  {enabledCount} settings + {selectedSoftware.length} software selected
                </p>
              </div>
              <DialogFooter>
                <Button
                  onClick={handleSave}
                  disabled={!newProfileName.trim()}
                  className="bg-[var(--wpi-accent)] hover:bg-[var(--wpi-accent)]/90 text-[var(--wpi-bg)]"
                >
                  Save
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>

          <Dialog open={importDialogOpen} onOpenChange={setImportDialogOpen}>
            <DialogTrigger asChild>
              <Button variant="outline" size="sm" className="h-8 gap-1.5 bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:bg-[var(--wpi-card)] hover:text-[var(--wpi-text)] text-xs">
                <Upload className="h-3.5 w-3.5" />
                Import
              </Button>
            </DialogTrigger>
            <DialogContent className="bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-text)]">
              <DialogHeader>
                <DialogTitle className="text-[var(--wpi-text)]">Import Profile</DialogTitle>
                <DialogDescription className="text-[var(--wpi-muted)]">
                  Paste a profile JSON to import
                </DialogDescription>
              </DialogHeader>
              <div className="space-y-3 py-2">
                <textarea
                  placeholder='{"name": "My Profile", "settings": {...}}'
                  value={importText}
                  onChange={(e) => { setImportText(e.target.value); setImportError(false); }}
                  className="w-full h-32 rounded-lg bg-[var(--wpi-card)] border border-[var(--wpi-border)] text-[var(--wpi-text)] placeholder:text-[var(--wpi-muted)] p-3 text-xs font-mono resize-none focus:outline-none focus:ring-1 focus:ring-[var(--wpi-accent)]/30"
                />
                {importError && (
                  <p className="text-xs text-[var(--wpi-risky)]">Invalid JSON format</p>
                )}
              </div>
              <DialogFooter>
                <Button
                  onClick={handleImport}
                  disabled={!importText.trim()}
                  className="bg-[var(--wpi-accent)] hover:bg-[var(--wpi-accent)]/90 text-[var(--wpi-bg)]"
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
                    ? "bg-[var(--wpi-accent)]/5 border-[var(--wpi-accent)]/30 shadow-[0_0_30px_rgba(0,212,255,0.05)]"
                    : "bg-[var(--wpi-card)] border-[var(--wpi-border)] hover:border-[var(--wpi-border)]/80"
                }`}
              >
                {isActive && (
                  <div className="absolute top-2 right-2">
                    <Badge className="bg-[var(--wpi-accent)]/15 text-[var(--wpi-accent)] border-[var(--wpi-accent)]/20 text-[9px]">
                      Active
                    </Badge>
                  </div>
                )}

                <div className="flex items-start gap-3">
                  <div className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-lg ${
                    isActive ? "bg-[var(--wpi-accent)]/15 border border-[var(--wpi-accent)]/30" : "bg-[var(--wpi-deep)] border border-[var(--wpi-border)]"
                  }`}>
                    <ProfileIcon className={`h-5 w-5 ${isActive ? "text-[var(--wpi-accent)]" : "text-[var(--wpi-muted)]"}`} />
                  </div>

                  <div className="flex-1 min-w-0">
                    <h3 className={`text-sm font-semibold mb-0.5 ${isActive ? "text-[var(--wpi-text)]" : "text-[var(--wpi-muted)]"}`}>
                      {profile.name}
                    </h3>
                    <p className="text-[11px] text-[var(--wpi-muted)]/70 line-clamp-2 mb-2">
                      {profile.description}
                    </p>

                    <div className="flex items-center gap-2 flex-wrap">
                      <Badge variant="outline" className="h-4 px-1 text-[9px] bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)]">
                        {settingsCount} settings
                      </Badge>
                      <Badge variant="outline" className="h-4 px-1 text-[9px] bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)]">
                        {profile.software.length} apps
                      </Badge>
                      {profile.isBuiltin && (
                        <Badge variant="outline" className="h-4 px-1 text-[9px] bg-[var(--wpi-info)]/5 border-[var(--wpi-info)]/20 text-[var(--wpi-info)]">
                          Built-in
                        </Badge>
                      )}
                    </div>
                  </div>
                </div>

                {/* Actions */}
                <div className="flex items-center gap-2 mt-3 pt-3 border-t border-[var(--wpi-border)]/50">
                  <Button
                    size="sm"
                    variant={isActive ? "ghost" : "outline"}
                    onClick={() => loadProfile(profile.id)}
                    className={`h-7 gap-1 text-[10px] ${
                      isActive
                        ? "text-[var(--wpi-accent)] hover:bg-[var(--wpi-accent)]/10"
                        : "bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:bg-[var(--wpi-card)] hover:text-[var(--wpi-text)]"
                    }`}
                  >
                    <Check className="h-3 w-3" />
                    {isActive ? "Loaded" : "Load"}
                  </Button>
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={() => handleExport(profile.id)}
                    className="h-7 gap-1 text-[10px] bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:bg-[var(--wpi-card)] hover:text-[var(--wpi-text)]"
                  >
                    <Download className="h-3 w-3" />
                    Export
                  </Button>
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={() => {
                      // Compare with the next different profile, or first profile
                      const other = profiles.find((p) => p.id !== profile.id);
                      if (other) openCompare(profile.id, other.id);
                    }}
                    className="h-7 gap-1 text-[10px] bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:bg-[var(--wpi-card)] hover:text-[var(--wpi-accent)] hover:border-[var(--wpi-accent)]/30"
                  >
                    <GitCompare className="h-3 w-3" />
                    Compare
                  </Button>
                  {!profile.isBuiltin && (
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => deleteProfile(profile.id)}
                      className="h-7 gap-1 text-[10px] bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:bg-[var(--wpi-risky-10)] hover:text-[var(--wpi-risky)] hover:border-[var(--wpi-risky-30)]"
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

      {/* Compare Dialog */}
      <Dialog open={compareDialogOpen} onOpenChange={setCompareDialogOpen}>
        <DialogContent className="bg-[var(--wpi-bg)] border-[var(--wpi-border)] text-[var(--wpi-text)] max-w-2xl max-h-[80vh]">
          {profileA && profileB ? (
            <ProfileComparison profileA={profileA} profileB={profileB} />
          ) : (
            <div className="py-8 text-center">
              <p className="text-sm text-[var(--wpi-muted)]">Select two profiles to compare</p>
              <div className="mt-4 grid grid-cols-2 gap-3">
                <div>
                  <p className="text-xs text-[var(--wpi-muted)] mb-2">Profile A:</p>
                  <select
                    value={compareA ?? ""}
                    onChange={(e) => setCompareA(e.target.value)}
                    className="w-full rounded-lg bg-[var(--wpi-deep)] border border-[var(--wpi-border)] text-[var(--wpi-text)] p-2 text-xs"
                  >
                    {profiles.map((p) => (
                      <option key={p.id} value={p.id}>{p.name}</option>
                    ))}
                  </select>
                </div>
                <div>
                  <p className="text-xs text-[var(--wpi-muted)] mb-2">Profile B:</p>
                  <select
                    value={compareB ?? ""}
                    onChange={(e) => setCompareB(e.target.value)}
                    className="w-full rounded-lg bg-[var(--wpi-deep)] border border-[var(--wpi-border)] text-[var(--wpi-text)] p-2 text-xs"
                  >
                    {profiles.map((p) => (
                      <option key={p.id} value={p.id}>{p.name}</option>
                    ))}
                  </select>
                </div>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
