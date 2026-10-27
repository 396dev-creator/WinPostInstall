import { create } from "zustand";
import { sections, builtinProfiles, clientScenarios, softwareApps, getAllConflicts, type Profile, type ClientScenario } from "@/data/settings";

interface UndoEntry {
  id: string;
  settingId: string;
  settingName: string;
  sectionName: string;
  timestamp: string;
  action: "enabled" | "disabled";
}

interface SafetyCounts {
  Safe: number;
  Moderate: number;
  Risky: number;
}

interface ApplyResult {
  success: boolean;
  message: string;
  configPath: string;
  stdout: string;
  stderr: string;
}

interface AppState {
  // Hydration flag
  hydrated: boolean;
  // Settings state: record of setting id -> enabled
  settings: Record<string, boolean>;
  // Software selections
  selectedSoftware: string[];
  // Profiles
  profiles: Profile[];
  activeProfileId: string | null;
  // Active scenario
  activeScenarioId: string | null;
  // Search
  searchQuery: string;
  // Undo log
  undoLog: UndoEntry[];
  // Section detail panel
  activeSectionId: string | null;
  // Scenario picker visibility
  scenarioPickerOpen: boolean;
  // Execution state (Tauri live-apply)
  isApplying: boolean;
  applyResult: ApplyResult | null;
  applyResultDialogOpen: boolean;

  // Actions
  hydrate: () => void;
  toggleSetting: (settingId: string) => void;
  toggleSectionAll: (sectionId: string, enabled: boolean) => void;
  toggleBySafety: (safetyLevels: Array<"Safe" | "Moderate" | "Risky">, enabled: boolean) => void;
  toggleSectionBySafety: (sectionId: string, safetyLevels: Array<"Safe" | "Moderate" | "Risky">, enabled: boolean) => void;
  toggleAllSettings: (enabled: boolean) => void;
  toggleSoftware: (softwareId: string) => void;
  setSearchQuery: (query: string) => void;
  setActiveSectionId: (sectionId: string | null) => void;
  loadProfile: (profileId: string) => void;
  saveProfile: (name: string, description: string) => void;
  deleteProfile: (profileId: string) => void;
  exportProfile: (profileId: string) => string;
  importProfile: (json: string) => boolean;
  applyChanges: (createRestorePoint?: boolean) => Promise<boolean>;
  updateProfile: (profileId: string) => void;
  applyScenario: (scenarioId: string) => void;
  setScenarioPickerOpen: (open: boolean) => void;
  setApplyResultDialogOpen: (open: boolean) => void;
  clearApplyResult: () => void;
  undoChange: (undoId: string) => void;
  undoAll: () => void;
  undoBySafety: (safetyLevels: Array<"Safe" | "Moderate" | "Risky">) => void;
  getEnabledCount: (sectionId: string) => number;
  getTotalCount: (sectionId: string) => number;
  getGlobalSafetyCounts: () => SafetyCounts;
  getGlobalEnabledSafetyCounts: () => SafetyCounts;
  getSectionSafetyCounts: (sectionId: string) => SafetyCounts;
  getSectionEnabledSafetyCounts: (sectionId: string) => SafetyCounts;
  generateConfig: () => object;
}

const STORAGE_KEY = "winpostinstall-profiles";
const SETTINGS_KEY = "winpostinstall-settings";
const SOFTWARE_KEY = "winpostinstall-software";
const UNDO_KEY = "winpostinstall-undo";
const ACTIVE_PROFILE_KEY = "winpostinstall-active-profile";

function loadFromStorage<T>(key: string, fallback: T): T {
  try {
    const stored = localStorage.getItem(key);
    if (stored) return JSON.parse(stored);
  } catch {
    // ignore
  }
  return fallback;
}

function saveToStorage(key: string, value: unknown) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // ignore
  }
}

// Initialize default settings (all off)
function getDefaultSettings(): Record<string, boolean> {
  const settings: Record<string, boolean> = {};
  sections.forEach((section) => {
    section.settings.forEach((s) => {
      settings[s.id] = false;
    });
  });
  return settings;
}

export const useAppStore = create<AppState>((set, get) => ({
  hydrated: false,
  settings: getDefaultSettings(),
  selectedSoftware: [],
  profiles: [...builtinProfiles],
  activeProfileId: null,
  activeScenarioId: null,
  searchQuery: "",
  undoLog: [],
  activeSectionId: null,
  scenarioPickerOpen: false,
  isApplying: false,
  applyResult: null,
  applyResultDialogOpen: false,

  hydrate: () => {
    if (get().hydrated) return;
    const savedSettings = loadFromStorage(SETTINGS_KEY, getDefaultSettings());
    const savedSoftware = loadFromStorage<string[]>(SOFTWARE_KEY, []);
    const savedUndo = loadFromStorage<UndoEntry[]>(UNDO_KEY, []);
    const customProfiles = loadFromStorage<Profile[]>(STORAGE_KEY, []);
    const savedActiveProfileId = loadFromStorage<string | null>(ACTIVE_PROFILE_KEY, null);

    set({
      hydrated: true,
      settings: savedSettings,
      selectedSoftware: savedSoftware,
      undoLog: savedUndo,
      profiles: [...builtinProfiles, ...customProfiles],
      activeProfileId: savedActiveProfileId,
    });
  },

  toggleSetting: (settingId: string) => {
    set((state) => {
      const current = state.settings[settingId] ?? false;
      const newSettings = { ...state.settings, [settingId]: !current };

      // Enforce exclusive groups (radio behavior):
      // When enabling a setting that belongs to an exclusiveGroup,
      // auto-disable all other settings in the same group.
      if (!current) {
        let exclusiveGroup: string | undefined;
        for (const section of sections) {
          const found = section.settings.find((s) => s.id === settingId);
          if (found?.exclusiveGroup) {
            exclusiveGroup = found.exclusiveGroup;
            break;
          }
        }
        if (exclusiveGroup) {
          for (const section of sections) {
            for (const s of section.settings) {
              if (s.exclusiveGroup === exclusiveGroup && s.id !== settingId) {
                newSettings[s.id] = false;
              }
            }
          }
        }
      }

      saveToStorage(SETTINGS_KEY, newSettings);

      // Find setting info for undo log
      let settingName = settingId;
      let sectionName = "";
      for (const section of sections) {
        const found = section.settings.find((s) => s.id === settingId);
        if (found) {
          settingName = found.name;
          sectionName = section.name;
          break;
        }
      }

      const undoEntry: UndoEntry = {
        id: `undo_${Date.now()}_${Math.random().toString(36).slice(2)}`,
        settingId,
        settingName,
        sectionName,
        timestamp: new Date().toISOString(),
        action: current ? "disabled" : "enabled",
      };

      const newUndoLog = [undoEntry, ...state.undoLog].slice(0, 100);
      saveToStorage(UNDO_KEY, newUndoLog);

      return { settings: newSettings, undoLog: newUndoLog };
    });
  },

  toggleSectionAll: (sectionId: string, enabled: boolean) => {
    set((state) => {
      const section = sections.find((s) => s.id === sectionId);
      if (!section) return state;
      const newSettings = { ...state.settings };
      section.settings.forEach((s) => {
        newSettings[s.id] = enabled;
      });
      saveToStorage(SETTINGS_KEY, newSettings);
      return { settings: newSettings };
    });
  },

  toggleBySafety: (safetyLevels: Array<"Safe" | "Moderate" | "Risky">, enabled: boolean) => {
    set((state) => {
      const newSettings = { ...state.settings };
      sections.forEach((section) => {
        section.settings.forEach((s) => {
          if (safetyLevels.includes(s.safety)) {
            newSettings[s.id] = enabled;
          }
        });
      });
      saveToStorage(SETTINGS_KEY, newSettings);
      return { settings: newSettings };
    });
  },

  toggleSectionBySafety: (sectionId: string, safetyLevels: Array<"Safe" | "Moderate" | "Risky">, enabled: boolean) => {
    set((state) => {
      const section = sections.find((s) => s.id === sectionId);
      if (!section) return state;
      const newSettings = { ...state.settings };
      section.settings.forEach((s) => {
        if (safetyLevels.includes(s.safety)) {
          newSettings[s.id] = enabled;
        }
      });
      saveToStorage(SETTINGS_KEY, newSettings);
      return { settings: newSettings };
    });
  },

  toggleAllSettings: (enabled: boolean) => {
    set((state) => {
      const newSettings = { ...state.settings };
      sections.forEach((section) => {
        section.settings.forEach((s) => {
          newSettings[s.id] = enabled;
        });
      });
      saveToStorage(SETTINGS_KEY, newSettings);
      return { settings: newSettings };
    });
  },

  toggleSoftware: (softwareId: string) => {
    set((state) => {
      const current = state.selectedSoftware.includes(softwareId);
      const newSelected = current
        ? state.selectedSoftware.filter((id) => id !== softwareId)
        : [...state.selectedSoftware, softwareId];
      saveToStorage(SOFTWARE_KEY, newSelected);
      return { selectedSoftware: newSelected };
    });
  },

  setSearchQuery: (query: string) => set({ searchQuery: query }),
  setActiveSectionId: (sectionId: string | null) => set({ activeSectionId: sectionId }),
  setScenarioPickerOpen: (open: boolean) => set({ scenarioPickerOpen: open }),

  applyScenario: (scenarioId: string) => {
    const scenario = clientScenarios.find((s) => s.id === scenarioId);
    if (!scenario) return;

    // Load the associated profile
    const profile = builtinProfiles.find((p) => p.id === scenario.profileId);
    if (!profile) return;

    const newSettings = getDefaultSettings();
    Object.entries(profile.settings).forEach(([key, value]) => {
      if (key in newSettings) {
        newSettings[key] = value;
      }
    });
    saveToStorage(SETTINGS_KEY, newSettings);
    saveToStorage(SOFTWARE_KEY, profile.software);
    saveToStorage(ACTIVE_PROFILE_KEY, scenario.profileId);
    set({
      settings: newSettings,
      selectedSoftware: [...profile.software],
      activeProfileId: scenario.profileId,
      activeScenarioId: scenarioId,
      scenarioPickerOpen: false,
    });
  },

  loadProfile: (profileId: string) => {
    const state = get();
    if (!profileId) {
      saveToStorage(ACTIVE_PROFILE_KEY, null);
      set({ activeProfileId: null });
      return;
    }
    const profile = state.profiles.find((p) => p.id === profileId);
    if (!profile) return;

    const newSettings = getDefaultSettings();
    Object.entries(profile.settings).forEach(([key, value]) => {
      if (key in newSettings) {
        newSettings[key] = value;
      }
    });
    saveToStorage(SETTINGS_KEY, newSettings);
    saveToStorage(SOFTWARE_KEY, profile.software);
    saveToStorage(ACTIVE_PROFILE_KEY, profileId);
    set({
      settings: newSettings,
      selectedSoftware: [...profile.software],
      activeProfileId: profileId,
    });
  },

  saveProfile: (name: string, description: string) => {
    set((state) => {
      const enabledSettings: Record<string, boolean> = {};
      Object.entries(state.settings).forEach(([key, value]) => {
        if (value) enabledSettings[key] = true;
      });

      const newProfile: Profile = {
        id: `custom_${Date.now()}`,
        name,
        description,
        isBuiltin: false,
        settings: enabledSettings,
        software: [...state.selectedSoftware],
      };

      const customProfiles = loadFromStorage<Profile[]>(STORAGE_KEY, []);
      customProfiles.push(newProfile);
      saveToStorage(STORAGE_KEY, customProfiles);
      saveToStorage(ACTIVE_PROFILE_KEY, newProfile.id);

      return {
        profiles: [...builtinProfiles, ...customProfiles],
        activeProfileId: newProfile.id,
      };
    });
  },

  deleteProfile: (profileId: string) => {
    set((state) => {
      const customProfiles = loadFromStorage<Profile[]>(STORAGE_KEY, []);
      const filtered = customProfiles.filter((p) => p.id !== profileId);
      saveToStorage(STORAGE_KEY, filtered);
      const newActiveId = state.activeProfileId === profileId ? null : state.activeProfileId;
      if (state.activeProfileId === profileId) {
        saveToStorage(ACTIVE_PROFILE_KEY, null);
      }
      return {
        profiles: [...builtinProfiles, ...filtered],
        activeProfileId: newActiveId,
      };
    });
  },

  updateProfile: (profileId: string) => {
    set((state) => {
      const enabledSettings: Record<string, boolean> = {};
      Object.entries(state.settings).forEach(([key, value]) => {
        if (value) enabledSettings[key] = true;
      });

      const customProfiles = loadFromStorage<Profile[]>(STORAGE_KEY, []);
      const profileIndex = customProfiles.findIndex((p) => p.id === profileId);
      if (profileIndex === -1) return state;

      customProfiles[profileIndex] = {
        ...customProfiles[profileIndex],
        settings: enabledSettings,
        software: [...state.selectedSoftware],
      };
      saveToStorage(STORAGE_KEY, customProfiles);

      return {
        profiles: [...builtinProfiles, ...customProfiles],
      };
    });
  },

  exportProfile: (profileId: string) => {
    const state = get();
    const profile = state.profiles.find((p) => p.id === profileId);
    if (!profile) return "{}";
    return JSON.stringify(profile, null, 2);
  },

  importProfile: (json: string) => {
    try {
      const profile = JSON.parse(json) as Profile;
      if (!profile.name || !profile.settings) return false;
      profile.id = `imported_${Date.now()}`;
      profile.isBuiltin = false;

      const customProfiles = loadFromStorage<Profile[]>(STORAGE_KEY, []);
      customProfiles.push(profile);
      saveToStorage(STORAGE_KEY, customProfiles);

      set({ profiles: [...builtinProfiles, ...customProfiles] });
      return true;
    } catch {
      return false;
    }
  },

  setApplyResultDialogOpen: (open: boolean) => set({ applyResultDialogOpen: open }),

  clearApplyResult: () => set({ applyResult: null, applyResultDialogOpen: false }),

  applyChanges: async (createRestorePoint: boolean = true) => {
    const state = get();
    const totalEnabled = Object.values(state.settings).filter(Boolean).length;
    if (totalEnabled === 0 && state.selectedSoftware.length === 0) return false;

    // Safety guard: refuse to apply if there are unresolved conflicts
    const conflicts = getAllConflicts(state.settings);
    if (conflicts.length > 0) {
      return false as unknown as boolean; // callers should check for false
    }

    const config = state.generateConfig();
    const fullConfig = { ...config, createRestorePoint };
    const configJson = JSON.stringify(fullConfig, null, 2);

    // Generate timestamped filename for receipt/download
    const now = new Date();
    const ts = `${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}-${String(now.getDate()).padStart(2,'0')}_${String(now.getHours()).padStart(2,'0')}${String(now.getMinutes()).padStart(2,'0')}${String(now.getSeconds()).padStart(2,'0')}`;
    const filename = `WinPostInstall-Config_${ts}.json`;

    const downloadConfig = (json: string, fname: string) => {
      try {
        const blob = new Blob([json], { type: "application/json" });
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.style.display = "none";
        a.href = url;
        a.download = fname;
        document.body.appendChild(a);
        a.click();
        setTimeout(() => {
          document.body.removeChild(a);
          URL.revokeObjectURL(url);
        }, 100);
      } catch (err) {
        console.error("Download failed:", err);
      }
    };

    // ──── Tauri desktop mode: save config AND execute the PowerShell script ────
    if (typeof window !== "undefined" && "__TAURI_INTERNALS__" in window) {
      set({ isApplying: true, applyResult: null });
      try {
        const { invoke } = await import("@tauri-apps/api/core");

        // Call the apply_config Tauri command: saves JSON + runs WinPostInstall.ps1
        const result = await invoke<ApplyResult>("apply_config", {
          configJson,
          createRestorePoint,
        });

        // Also download a timestamped receipt copy
        downloadConfig(configJson, filename);

        set({
          isApplying: false,
          applyResult: result,
          applyResultDialogOpen: true,
        });
        return result.success;
      } catch (err) {
        // Tauri invoke failed — fall back to just saving + downloading
        console.error("Tauri apply_config failed, falling back to save-only:", err);
        try {
          const { invoke } = await import("@tauri-apps/api/core");
          await invoke("save_config", { configJson, filename: "WinPostInstall-Config.json" });
        } catch {
          // ignore
        }
        downloadConfig(configJson, filename);
        set({ isApplying: false });
        return true;
      }
    }

    // ──── Web/browser mode: download config JSON (manual apply) ────
    downloadConfig(configJson, filename);
    return true;
  },

  undoChange: (undoId: string) => {
    set((state) => {
      const entry = state.undoLog.find((e) => e.id === undoId);
      if (!entry) return state;

      const wasEnabled = entry.action === "enabled";
      const newSettings = { ...state.settings, [entry.settingId]: !wasEnabled };
      saveToStorage(SETTINGS_KEY, newSettings);

      const newUndoLog = state.undoLog.filter((e) => e.id !== undoId);
      saveToStorage(UNDO_KEY, newUndoLog);

      return { settings: newSettings, undoLog: newUndoLog };
    });
  },

  undoAll: () => {
    const newSettings = getDefaultSettings();
    saveToStorage(SETTINGS_KEY, newSettings);
    saveToStorage(UNDO_KEY, []);
    saveToStorage(SOFTWARE_KEY, []);
    set({ settings: newSettings, undoLog: [], selectedSoftware: [] });
  },

  undoBySafety: (safetyLevels: Array<"Safe" | "Moderate" | "Risky">) => {
    set((state) => {
      const newSettings = { ...state.settings };
      sections.forEach((section) => {
        section.settings.forEach((s) => {
          if (safetyLevels.includes(s.safety) && newSettings[s.id]) {
            newSettings[s.id] = false;
          }
        });
      });
      saveToStorage(SETTINGS_KEY, newSettings);
      return { settings: newSettings };
    });
  },

  getEnabledCount: (sectionId: string) => {
    const state = get();
    const section = sections.find((s) => s.id === sectionId);
    if (!section) return 0;
    return section.settings.filter((s) => state.settings[s.id]).length;
  },

  getTotalCount: (sectionId: string) => {
    const section = sections.find((s) => s.id === sectionId);
    return section?.settings.length ?? 0;
  },

  getGlobalSafetyCounts: () => {
    const counts: SafetyCounts = { Safe: 0, Moderate: 0, Risky: 0 };
    sections.forEach((section) => {
      section.settings.forEach((s) => {
        counts[s.safety]++;
      });
    });
    return counts;
  },

  getGlobalEnabledSafetyCounts: () => {
    const state = get();
    const counts: SafetyCounts = { Safe: 0, Moderate: 0, Risky: 0 };
    sections.forEach((section) => {
      section.settings.forEach((s) => {
        if (state.settings[s.id]) counts[s.safety]++;
      });
    });
    return counts;
  },

  getSectionSafetyCounts: (sectionId: string) => {
    const section = sections.find((s) => s.id === sectionId);
    const counts: SafetyCounts = { Safe: 0, Moderate: 0, Risky: 0 };
    if (section) {
      section.settings.forEach((s) => counts[s.safety]++);
    }
    return counts;
  },

  getSectionEnabledSafetyCounts: (sectionId: string) => {
    const state = get();
    const section = sections.find((s) => s.id === sectionId);
    const counts: SafetyCounts = { Safe: 0, Moderate: 0, Risky: 0 };
    if (section) {
      section.settings.forEach((s) => {
        if (state.settings[s.id]) counts[s.safety]++;
      });
    }
    return counts;
  },

  generateConfig: () => {
    const state = get();
    const configSections: Record<string, Record<string, boolean>> = {};

    sections.forEach((section) => {
      const sectionSettings: Record<string, boolean> = {};
      section.settings.forEach((s) => {
        sectionSettings[s.id] = state.settings[s.id] ?? false;
      });
      configSections[section.id] = sectionSettings;
    });

    // Build software list with wingetId mapping so the PS1 can install them
    const enabledSoftware = state.selectedSoftware;
    const softwareWithIds = enabledSoftware
      .map((id) => {
        const app = softwareApps.find((a) => a.id === id);
        if (!app) return null;
        return { id: app.id, name: app.name, wingetId: app.wingetId, category: app.category };
      })
      .filter(Boolean);

    return {
      version: "4.1.7",
      generatedAt: new Date().toISOString(),
      sections: configSections,
      software: softwareWithIds,
      activeProfile: state.activeProfileId,
      activeScenario: state.activeScenarioId,
    };
  },
}));
