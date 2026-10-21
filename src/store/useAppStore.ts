import { create } from "zustand";
import { sections, builtinProfiles, clientScenarios, type Profile, type ClientScenario } from "@/data/settings";

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
  applyChanges: () => boolean;
  updateProfile: (profileId: string) => void;
  applyScenario: (scenarioId: string) => void;
  setScenarioPickerOpen: (open: boolean) => void;
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

  applyChanges: () => {
    const state = get();
    const totalEnabled = Object.values(state.settings).filter(Boolean).length;
    if (totalEnabled === 0 && state.selectedSoftware.length === 0) return false;

    const config = state.generateConfig();
    const configJson = JSON.stringify(config, null, 2);

    // In Tauri desktop mode: save config next to the exe, ready for PS1 script
    if (typeof window !== "undefined" && "__TAURI_INTERNALS__" in window) {
      // Dynamic import to avoid bundling Tauri API in web mode
      import("@tauri-apps/api/core").then(({ invoke }) => {
        invoke("save_config", { configJson, filename: "WinPostInstall-Config.json" })
          .then((path) => {
            console.log(`Config saved to: ${path}`);
            // Also trigger browser download as backup
            const blob = new Blob([configJson], { type: "application/json" });
            const url = URL.createObjectURL(blob);
            const a = document.createElement("a");
            a.href = url;
            a.download = "WinPostInstall-Config.json";
            a.click();
            URL.revokeObjectURL(url);
          })
          .catch((err) => {
            console.error("Tauri save failed, falling back to download:", err);
            // Fallback to download
            const blob = new Blob([configJson], { type: "application/json" });
            const url = URL.createObjectURL(blob);
            const a = document.createElement("a");
            a.href = url;
            a.download = "WinPostInstall-Config.json";
            a.click();
            URL.revokeObjectURL(url);
          });
      }).catch(() => {
        // Tauri API not available, fall back to download
        const blob = new Blob([configJson], { type: "application/json" });
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = "WinPostInstall-Config.json";
        a.click();
        URL.revokeObjectURL(url);
      });
    } else {
      // Web/browser mode: download config JSON
      const blob = new Blob([configJson], { type: "application/json" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = "WinPostInstall-Config.json";
      a.click();
      URL.revokeObjectURL(url);
    }
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

    const enabledSoftware = state.selectedSoftware;

    return {
      version: "4.1.0",
      generatedAt: new Date().toISOString(),
      sections: configSections,
      software: enabledSoftware,
      activeProfile: state.activeProfileId,
      activeScenario: state.activeScenarioId,
    };
  },
}));
