"use client";

import React, { useState } from "react";
import { motion } from "framer-motion";
import { Search, Download, Undo2, Terminal, ChevronDown, Sun, Moon, Globe, Sparkles, Save, CheckCircle2, AlertCircle, Loader2, Zap, Trash2, AlertTriangle, Wrench } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
  DropdownMenuSeparator,
} from "@/components/ui/dropdown-menu";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { useAppStore } from "@/store/useAppStore";
import { useTheme } from "./ThemeProvider";
import { useI18n, localeNames, type Locale } from "@/lib/i18n";
import { toast } from "@/hooks/use-toast";
import { getAllConflicts, sections } from "@/data/settings";

interface AppHeaderProps {
  onApply: () => Promise<boolean>;
  onUndo: () => void;
  onPreview: () => void;
  onResolveAndApply?: () => Promise<boolean>;
}

export function AppHeader({ onApply, onUndo, onPreview, onResolveAndApply }: AppHeaderProps) {
  const {
    searchQuery, setSearchQuery, profiles, activeProfileId,
    loadProfile, saveProfile, updateProfile, activeScenarioId,
    setScenarioPickerOpen, settings, selectedSoftware,
    isApplying, applyResult, applyResultDialogOpen, setApplyResultDialogOpen, clearApplyResult,
    toggleSetting,
  } = useAppStore();
  const { theme, toggleTheme } = useTheme();
  const { locale, setLocale, t } = useI18n();

  const activeProfile = profiles.find((p) => p.id === activeProfileId);
  const enabledCount = Object.values(settings).filter(Boolean).length;

  // Save profile dialog state
  const [saveDialogOpen, setSaveDialogOpen] = useState(false);
  const [profileName, setProfileName] = useState("");
  const [profileDesc, setProfileDesc] = useState("");
  const [saveMode, setSaveMode] = useState<"new" | "update">("new");
  const [conflictDialogOpen, setConflictDialogOpen] = useState(false);

  const handleSaveProfile = () => {
    if (saveMode === "update" && activeProfileId && !activeProfile?.isBuiltin) {
      updateProfile(activeProfileId);
      toast({
        title: "Profile Updated",
        description: `"${activeProfile?.name}" has been updated with your current settings.`,
      });
      setSaveDialogOpen(false);
    } else {
      if (!profileName.trim()) return;
      saveProfile(profileName.trim(), profileDesc.trim());
      toast({
        title: "Profile Saved",
        description: `"${profileName.trim()}" has been saved with ${enabledCount} settings and ${selectedSoftware.length} apps.`,
      });
      setProfileName("");
      setProfileDesc("");
      setSaveDialogOpen(false);
    }
  };

  const isTauri = typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;

  // Check for conflicts to show badge on Apply button
  const allConflicts = getAllConflicts(settings);
  const hasConflicts = allConflicts.length > 0;

  // Helper: get safety level for a setting ID
  const getSafetyForId = (id: string): "Safe" | "Moderate" | "Risky" => {
    for (const section of sections) {
      const found = section.settings.find((s) => s.id === id);
      if (found) return found.safety;
    }
    return "Safe";
  };

  const handleApplyWithFeedback = async () => {
    if (isApplying) return; // prevent double-click
    if (enabledCount === 0 && selectedSoftware.length === 0) {
      toast({
        title: "Nothing to apply",
        description: "Select some settings or software first, then click Apply.",
        variant: "destructive",
      });
      return;
    }
    // Check for conflicts before applying
    const conflicts = getAllConflicts(settings);
    if (conflicts.length > 0) {
      setConflictDialogOpen(true);
      return;
    }
    try {
      const success = await onApply();
      if (success === false) {
        toast({
          title: "Nothing to apply",
          description: "No settings or software were selected.",
          variant: "destructive",
        });
        return;
      }
      // In Tauri mode, the result dialog will show automatically
      // In browser mode, show a simple toast
      if (!isTauri) {
        toast({
          title: "Config Exported!",
          description: `${enabledCount} settings + ${selectedSoftware.length} software exported. Check Downloads for the .json file.`,
        });
      }
    } catch (err) {
      console.error("Apply failed:", err);
      toast({
        title: "Apply Failed",
        description: "Could not apply config. Check the browser console for details.",
        variant: "destructive",
      });
    }
  };

  return (
    <motion.header
      initial={{ y: -20, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      transition={{ duration: 0.3, ease: [0.25, 0.1, 0.25, 1] }}
      className="sticky top-0 z-40 border-b border-[var(--wpi-border)] bg-[var(--wpi-bg)]/80 backdrop-blur-xl"
    >
      <div className="mx-auto max-w-7xl px-4 py-2.5">
        <div className="flex items-center gap-3">
          {/* Logo / Title — Apple-style brand */}
          <div className="flex items-center gap-2.5 shrink-0">
            <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-[var(--wpi-accent)]/10 border border-[var(--wpi-accent)]/20">
              <Terminal className="h-4.5 w-4.5 text-[var(--wpi-accent)]" />
            </div>
            <div className="hidden sm:block">
              <h1 className="text-base font-bold text-[var(--wpi-text)] leading-none tracking-tight">
                Win<span className="text-[var(--wpi-accent)]">PostInstall</span>
              </h1>
              <p className="text-[10px] text-[var(--wpi-muted)] leading-none mt-0.5">{t.appVersion}</p>
            </div>
          </div>

          {/* Search — Apple-style prominent, centered */}
          <div className="relative flex-1 min-w-[160px] max-w-sm">
            <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-4 w-4 text-[var(--wpi-muted)]" />
            <Input
              placeholder="Search settings..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-9 h-8 bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-text)] text-sm placeholder:text-[var(--wpi-muted)] focus-visible:ring-[var(--wpi-accent)]/30 focus-visible:border-[var(--wpi-accent)]/40"
            />
          </div>

          {/* Context controls — Scenario + Profile */}
          <div className="flex items-center gap-1.5">
            <Button
              variant="outline"
              size="sm"
              onClick={() => setScenarioPickerOpen(true)}
              className={`h-8 gap-1.5 text-xs ${
                activeScenarioId
                  ? "bg-[var(--wpi-accent)]/10 border-[var(--wpi-accent)]/25 text-[var(--wpi-accent)] hover:bg-[var(--wpi-accent)]/15 hover:border-[var(--wpi-accent)]/35"
                  : "bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:bg-[var(--wpi-card)] hover:text-[var(--wpi-text-secondary)] hover:border-[var(--wpi-accent)]/25"
              }`}
            >
              <Sparkles className="h-3.5 w-3.5" />
              <span className="hidden md:inline">Scenario</span>
              {activeScenarioId && (
                <Badge variant="secondary" className="h-4 px-1 text-[9px] bg-[var(--wpi-accent)]/15 text-[var(--wpi-accent)] border-0">
                  Active
                </Badge>
              )}
            </Button>

            {/* Profile selector */}
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button
                  variant="outline"
                  size="sm"
                  className="h-8 gap-1.5 bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-text)] hover:bg-[var(--wpi-card)] hover:border-[var(--wpi-accent)]/25 text-xs"
                >
                  <span className="truncate max-w-[80px]">
                    {activeProfile ? activeProfile.name : "Profile"}
                  </span>
                  {activeProfile && (
                    <Badge variant="secondary" className="h-4 px-1 text-[9px] bg-[var(--wpi-accent)]/10 text-[var(--wpi-accent)] border-[var(--wpi-accent)]/20">
                      On
                    </Badge>
                  )}
                  <ChevronDown className="h-3 w-3 text-[var(--wpi-muted)]" />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent
                align="end"
                className="bg-[var(--wpi-surface-elevated)] border-[var(--wpi-border)] text-[var(--wpi-text)] min-w-[200px]"
              >
                {profiles.map((p) => (
                  <DropdownMenuItem
                    key={p.id}
                    onClick={() => loadProfile(p.id)}
                    className="text-sm focus:bg-[var(--wpi-accent)]/10 focus:text-[var(--wpi-accent)] cursor-pointer"
                  >
                    <span className="flex-1">{p.name}</span>
                    {p.isBuiltin && (
                      <Badge variant="secondary" className="h-4 px-1 text-[9px] bg-[var(--wpi-info)]/10 text-[var(--wpi-info)]">
                        Built-in
                      </Badge>
                    )}
                  </DropdownMenuItem>
                ))}
                <DropdownMenuSeparator className="bg-[var(--wpi-border)]" />
                <DropdownMenuItem
                  onClick={() => loadProfile("")}
                  className="text-sm focus:bg-[var(--wpi-risky)]/10 focus:text-[var(--wpi-risky)] cursor-pointer"
                >
                  Clear Profile
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>

          {/* Preferences — Locale + Theme */}
          <div className="flex items-center gap-1">
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button
                  variant="outline"
                  size="sm"
                  className="h-8 w-8 p-0 bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:bg-[var(--wpi-card)] hover:text-[var(--wpi-text)] hover:border-[var(--wpi-border)]"
                >
                  <Globe className="h-3.5 w-3.5" />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent
                align="end"
                className="bg-[var(--wpi-surface-elevated)] border-[var(--wpi-border)] text-[var(--wpi-text)] min-w-[120px]"
              >
                {Object.entries(localeNames).map(([key, name]) => (
                  <DropdownMenuItem
                    key={key}
                    onClick={() => setLocale(key as Locale)}
                    className={`text-sm cursor-pointer ${locale === key ? "focus:bg-[var(--wpi-accent)]/10 focus:text-[var(--wpi-accent)]" : "focus:bg-[var(--wpi-card)] focus:text-[var(--wpi-text)]"}`}
                  >
                    <span className="flex-1">{name}</span>
                    {locale === key && (
                      <Badge variant="secondary" className="h-4 px-1 text-[9px] bg-[var(--wpi-accent)]/10 text-[var(--wpi-accent)]">
                        Active
                      </Badge>
                    )}
                  </DropdownMenuItem>
                ))}
              </DropdownMenuContent>
            </DropdownMenu>

            <Button
              variant="outline"
              size="sm"
              onClick={toggleTheme}
              className="h-8 w-8 p-0 bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:bg-[var(--wpi-card)] hover:text-[var(--wpi-moderate)] hover:border-[var(--wpi-moderate)]/25"
            >
              {theme === "dark" ? <Sun className="h-3.5 w-3.5" /> : <Moon className="h-3.5 w-3.5" />}
            </Button>
          </div>

          {/* Separator */}
          <div className="h-5 w-px bg-[var(--wpi-border)] shrink-0" />

          {/* Actions — Save Profile, Preview, Undo, Apply */}
          <div className="flex items-center gap-1.5 shrink-0">
            <Button
              variant="ghost"
              size="sm"
              onClick={() => {
                // If active custom profile, default to update mode; otherwise new
                if (activeProfileId && !activeProfile?.isBuiltin) {
                  setSaveMode("update");
                } else {
                  setSaveMode("new");
                }
                setSaveDialogOpen(true);
              }}
              className="h-8 gap-1.5 text-[var(--wpi-muted)] hover:text-[var(--wpi-accent)] hover:bg-[var(--wpi-accent)]/10 text-xs"
            >
              <Save className="h-3.5 w-3.5" />
              <span className="hidden lg:inline">Save</span>
            </Button>
            <Button
              variant="ghost"
              size="sm"
              onClick={onPreview}
              className="h-8 gap-1.5 text-[var(--wpi-muted)] hover:text-[var(--wpi-text)] hover:bg-[var(--wpi-card)] text-xs"
            >
              {t.tabPreview}
            </Button>
            <Button
              variant="ghost"
              size="sm"
              onClick={onUndo}
              className="h-8 gap-1.5 text-[var(--wpi-muted)] hover:text-[var(--wpi-moderate)] hover:bg-[var(--wpi-moderate)]/10 text-xs"
            >
              <Undo2 className="h-3.5 w-3.5" />
              {t.tabUndo}
            </Button>
            <Button
              size="sm"
              onClick={handleApplyWithFeedback}
              disabled={isApplying}
              className={`h-8 gap-1.5 font-semibold text-xs shadow-[var(--wpi-accent-glow)] disabled:opacity-60 ${
                hasConflicts
                  ? "bg-[var(--wpi-risky)] hover:bg-[var(--wpi-risky)]/90 text-white"
                  : "bg-[var(--wpi-accent)] hover:bg-[var(--wpi-accent)]/90 text-[var(--wpi-accent-foreground)]"
              }`}
            >
              {isApplying ? (
                <>
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  Applying...
                </>
              ) : hasConflicts ? (
                <>
                  <AlertTriangle className="h-3.5 w-3.5" />
                  Apply
                  <Badge variant="secondary" className="h-4 px-1 text-[9px] bg-white/20 text-white border-0 ml-0.5">
                    {allConflicts.length}
                  </Badge>
                </>
              ) : isTauri ? (
                <>
                  <Zap className="h-3.5 w-3.5" />
                  Apply
                </>
              ) : (
                <>
                  <Download className="h-3.5 w-3.5" />
                  Apply
                </>
              )}
            </Button>
            {/* Wipe & Exit — only in Tauri desktop mode (burn after reading) */}
            {isTauri && (
              <Button
                variant="ghost"
                size="sm"
                onClick={async () => {
                  try {
                    const { invoke } = await import("@tauri-apps/api/core");
                    localStorage.clear();
                    await invoke("cleanup_and_exit");
                  } catch {
                    window.close();
                  }
                }}
                className="h-8 gap-1.5 text-[var(--wpi-muted)] hover:text-[var(--wpi-risky)] hover:bg-[var(--wpi-risky)]/10 text-xs"
              >
                <Trash2 className="h-3.5 w-3.5" />
                <span className="hidden lg:inline">Wipe</span>
              </Button>
            )}
          </div>
        </div>
      </div>

      {/* Save Profile Dialog */}
      <Dialog open={saveDialogOpen} onOpenChange={setSaveDialogOpen}>
        <DialogContent className="bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-text)]">
          <DialogHeader>
            <DialogTitle className="text-[var(--wpi-text)]">Save as Profile</DialogTitle>
            <DialogDescription className="text-[var(--wpi-muted)]">
              Save your current configuration so you can reload it anytime
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-2">
            {/* Stats summary */}
            <div className="flex items-center gap-2 rounded-lg bg-[var(--wpi-card)] border border-[var(--wpi-border)] p-3">
              <CheckCircle2 className="h-4 w-4 text-[var(--wpi-accent)] shrink-0" />
              <span className="text-xs text-[var(--wpi-muted)]">
                <span className="font-semibold text-[var(--wpi-text)]">{enabledCount}</span> settings +{" "}
                <span className="font-semibold text-[var(--wpi-text)]">{selectedSoftware.length}</span> software selected
              </span>
            </div>

            {/* Update existing profile option */}
            {activeProfileId && !activeProfile?.isBuiltin && (
              <div
                onClick={() => setSaveMode("update")}
                className={`flex items-center gap-3 rounded-lg border p-3 cursor-pointer transition-all ${
                  saveMode === "update"
                    ? "bg-[var(--wpi-accent)]/5 border-[var(--wpi-accent)]/30"
                    : "bg-[var(--wpi-card)] border-[var(--wpi-border)] hover:border-[var(--wpi-accent)]/20"
                }`}
              >
                <div className={`flex h-8 w-8 items-center justify-center rounded-lg shrink-0 ${
                  saveMode === "update" ? "bg-[var(--wpi-accent)]/15" : "bg-[var(--wpi-deep)]"
                }`}>
                  <Save className={`h-4 w-4 ${saveMode === "update" ? "text-[var(--wpi-accent)]" : "text-[var(--wpi-muted)]"}`} />
                </div>
                <div className="flex-1 min-w-0">
                  <p className={`text-sm font-medium ${saveMode === "update" ? "text-[var(--wpi-text)]" : "text-[var(--wpi-muted)]"}`}>
                    Update &quot;{activeProfile?.name}&quot;
                  </p>
                  <p className="text-[11px] text-[var(--wpi-muted)]/70">
                    Replace the current profile&apos;s settings with your selection
                  </p>
                </div>
                {saveMode === "update" && (
                  <CheckCircle2 className="h-4 w-4 text-[var(--wpi-accent)] shrink-0" />
                )}
              </div>
            )}

            {/* Save as new profile option */}
            <div
              onClick={() => setSaveMode("new")}
              className={`flex items-center gap-3 rounded-lg border p-3 cursor-pointer transition-all ${
                saveMode === "new"
                  ? "bg-[var(--wpi-accent)]/5 border-[var(--wpi-accent)]/30"
                  : "bg-[var(--wpi-card)] border-[var(--wpi-border)] hover:border-[var(--wpi-accent)]/20"
              }`}
            >
              <div className={`flex h-8 w-8 items-center justify-center rounded-lg shrink-0 ${
                saveMode === "new" ? "bg-[var(--wpi-accent)]/15" : "bg-[var(--wpi-deep)]"
              }`}>
                <Save className={`h-4 w-4 ${saveMode === "new" ? "text-[var(--wpi-accent)]" : "text-[var(--wpi-muted)]"}`} />
              </div>
              <div className="flex-1 min-w-0">
                <p className={`text-sm font-medium ${saveMode === "new" ? "text-[var(--wpi-text)]" : "text-[var(--wpi-muted)]"}`}>
                  Save as new profile
                </p>
                <p className="text-[11px] text-[var(--wpi-muted)]/70">
                  Create a new named profile from your current settings
                </p>
              </div>
              {saveMode === "new" && (
                <CheckCircle2 className="h-4 w-4 text-[var(--wpi-accent)] shrink-0" />
              )}
            </div>

            {/* New profile name/desc inputs (only in "new" mode) */}
            {saveMode === "new" && (
              <motion.div
                initial={{ opacity: 0, height: 0 }}
                animate={{ opacity: 1, height: "auto" }}
                exit={{ opacity: 0, height: 0 }}
                className="space-y-2 overflow-hidden"
              >
                <Input
                  placeholder="Profile name"
                  value={profileName}
                  onChange={(e) => setProfileName(e.target.value)}
                  autoFocus
                  className="bg-[var(--wpi-card)] border-[var(--wpi-border)] text-[var(--wpi-text)] placeholder:text-[var(--wpi-muted)]"
                />
                <Input
                  placeholder="Description (optional)"
                  value={profileDesc}
                  onChange={(e) => setProfileDesc(e.target.value)}
                  className="bg-[var(--wpi-card)] border-[var(--wpi-border)] text-[var(--wpi-text)] placeholder:text-[var(--wpi-muted)]"
                />
              </motion.div>
            )}
          </div>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setSaveDialogOpen(false)}
              className="bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:text-[var(--wpi-text)]"
            >
              Cancel
            </Button>
            <Button
              onClick={handleSaveProfile}
              disabled={saveMode === "new" && !profileName.trim()}
              className="bg-[var(--wpi-accent)] hover:bg-[var(--wpi-accent)]/90 text-[var(--wpi-bg)]"
            >
              <Save className="h-3.5 w-3.5 mr-1.5" />
              {saveMode === "update" ? "Update Profile" : "Save Profile"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Apply Result Dialog — shows PowerShell execution output */}
      <Dialog open={applyResultDialogOpen} onOpenChange={(open) => { if (!open) clearApplyResult(); }}>
        <DialogContent className="bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-text)] max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2 text-[var(--wpi-text)]">
              {applyResult?.success ? (
                <CheckCircle2 className="h-5 w-5 text-[var(--wpi-safe)]" />
              ) : (
                <AlertCircle className="h-5 w-5 text-[var(--wpi-risky)]" />
              )}
              {applyResult?.success ? "Settings Applied Successfully" : "Apply Failed"}
            </DialogTitle>
            <DialogDescription className="text-[var(--wpi-muted)]">
              {applyResult?.message}
            </DialogDescription>
          </DialogHeader>

          {applyResult && (
            <div className="space-y-3 py-2">
              {/* Config path */}
              <div className="flex items-center gap-2 rounded-lg bg-[var(--wpi-card)] border border-[var(--wpi-border)] p-3">
                <Terminal className="h-4 w-4 text-[var(--wpi-accent)] shrink-0" />
                <div className="flex-1 min-w-0">
                  <p className="text-[10px] text-[var(--wpi-muted)]">Config saved to</p>
                  <p className="text-xs font-mono text-[var(--wpi-text)] truncate">{applyResult.configPath}</p>
                </div>
              </div>

              {/* PowerShell output */}
              {applyResult.stdout && (
                <div>
                  <p className="text-[10px] font-medium text-[var(--wpi-muted)] mb-1.5">Output</p>
                  <pre className="text-[11px] font-mono text-[var(--wpi-safe)] bg-[var(--wpi-card)] border border-[var(--wpi-border)] rounded-lg p-3 max-h-[200px] overflow-auto whitespace-pre-wrap break-words">
                    {applyResult.stdout}
                  </pre>
                </div>
              )}

              {/* Error output */}
              {applyResult.stderr && (
                <div>
                  <p className="text-[10px] font-medium text-[var(--wpi-risky)] mb-1.5">Errors</p>
                  <pre className="text-[11px] font-mono text-[var(--wpi-risky)] bg-[var(--wpi-risky-5)] border border-[var(--wpi-risky-20)] rounded-lg p-3 max-h-[120px] overflow-auto whitespace-pre-wrap break-words">
                    {applyResult.stderr}
                  </pre>
                </div>
              )}
            </div>
          )}

          <DialogFooter className="flex-col gap-2 sm:flex-row">
            {isTauri && (
              <Button
                variant="outline"
                onClick={async () => {
                  try {
                    const { invoke } = await import("@tauri-apps/api/core");
                    // Clear localStorage before cleanup
                    localStorage.clear();
                    await invoke("cleanup_and_exit");
                  } catch {
                    // fallback: just close
                    window.close();
                  }
                }}
                className="bg-[var(--wpi-risky-5)] border-[var(--wpi-risky-20)] text-[var(--wpi-risky)] hover:bg-[var(--wpi-risky)]/15 hover:text-[var(--wpi-risky)]"
              >
                <Trash2 className="h-3.5 w-3.5 mr-1.5" />
                Wipe & Exit
              </Button>
            )}
            <Button
              onClick={clearApplyResult}
              className="bg-[var(--wpi-accent)] hover:bg-[var(--wpi-accent)]/90 text-[var(--wpi-bg)]"
            >
              <CheckCircle2 className="h-3.5 w-3.5 mr-1.5" />
              Done
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Conflict Warning Dialog — shown when Apply is clicked with unresolved conflicts */}
      <Dialog open={conflictDialogOpen} onOpenChange={setConflictDialogOpen}>
        <DialogContent className="bg-[var(--wpi-deep)] border-[var(--wpi-risky-20)] text-[var(--wpi-text)] max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2 text-[var(--wpi-risky)]">
              <AlertTriangle className="h-5 w-5" />
              Unresolved Setting Conflicts
            </DialogTitle>
            <DialogDescription className="text-[var(--wpi-muted)]">
              You have {allConflicts.length} conflict{allConflicts.length !== 1 ? "s" : ""} that need to be resolved before applying. Applying with conflicts may cause unexpected behavior.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-3 py-2">
            {/* Conflict summary list */}
            <div className="max-h-[180px] overflow-auto space-y-2">
              {allConflicts.slice(0, 5).map((c, i) => (
                <div
                  key={i}
                  className="flex items-start gap-2 rounded-lg bg-[var(--wpi-risky-5)] border border-[var(--wpi-risky-15)] p-2.5"
                >
                  <Badge variant="outline" className="h-4 shrink-0 text-[9px] bg-[var(--wpi-risky-10)] border-[var(--wpi-risky-20)] text-[var(--wpi-risky)] mt-0.5">
                    {c.type === "conflict" ? "Conflict" : "Dep"}
                  </Badge>
                  <span className="text-[11px] text-[var(--wpi-risky)]/80 leading-relaxed">{c.message}</span>
                </div>
              ))}
              {allConflicts.length > 5 && (
                <p className="text-[10px] text-[var(--wpi-muted)] text-center">
                  +{allConflicts.length - 5} more conflict{allConflicts.length - 5 !== 1 ? "s" : ""}…
                </p>
              )}
            </div>
          </div>

          <DialogFooter className="flex-col gap-2 sm:flex-row">
            <Button
              variant="outline"
              onClick={() => setConflictDialogOpen(false)}
              className="bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:text-[var(--wpi-text)]"
            >
              Cancel
            </Button>
            <Button
              variant="outline"
              onClick={() => {
                setConflictDialogOpen(false);
                onPreview();
              }}
              className="bg-[var(--wpi-card)] border-[var(--wpi-accent)]/30 text-[var(--wpi-accent)] hover:bg-[var(--wpi-accent)]/10 hover:border-[var(--wpi-accent)]/40"
            >
              <AlertCircle className="h-3.5 w-3.5 mr-1.5" />
              Go to Preview
            </Button>
            <Button
              onClick={async () => {
                // Auto-resolve conflicts then apply
                const resolved = new Set<string>();
                for (const conflict of allConflicts) {
                  if (conflict.type === "conflict") {
                    const settingSafety = getSafetyForId(conflict.settingId);
                    const targetSafety = getSafetyForId(conflict.targetId);
                    if (settingSafety === "Risky" || (settingSafety === "Moderate" && targetSafety === "Safe")) {
                      if (!resolved.has(conflict.settingId)) {
                        toggleSetting(conflict.settingId);
                        resolved.add(conflict.settingId);
                      }
                    } else {
                      if (!resolved.has(conflict.targetId)) {
                        toggleSetting(conflict.targetId);
                        resolved.add(conflict.targetId);
                      }
                    }
                  } else if (conflict.type === "unmet_require") {
                    if (!resolved.has(conflict.targetId)) {
                      toggleSetting(conflict.targetId);
                      resolved.add(conflict.targetId);
                    }
                  }
                }
                setConflictDialogOpen(false);
                toast({
                  title: "Conflicts Resolved",
                  description: `${resolved.size} settings adjusted. Applying now…`,
                });
                // Small delay to let state settle, then apply
                setTimeout(async () => {
                  try {
                    await onApply();
                    if (!isTauri) {
                      toast({
                        title: "Config Exported!",
                        description: "Conflicts resolved and config exported. Check Downloads for the .json file.",
                      });
                    }
                  } catch (err) {
                    console.error("Apply after resolve failed:", err);
                  }
                }, 100);
              }}
              className="bg-[var(--wpi-accent)] hover:bg-[var(--wpi-accent)]/90 text-[var(--wpi-bg)]"
            >
              <Wrench className="h-3.5 w-3.5 mr-1.5" />
              Auto-Resolve & Apply
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </motion.header>
  );
}
