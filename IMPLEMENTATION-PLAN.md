# WinPostInstall GUI — Implementation Plan

> **Version**: 1.0  
> **Date**: 2025-03-04  
> **Stack**: Next.js 16 · TypeScript · Tailwind CSS 4 · shadcn/ui  
> **Script**: WinPostInstall.ps1 v4.1.0 (4063 lines, 18 sections, 185 settings)

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Competitive Advantage Matrix](#2-competitive-advantage-matrix)
3. [Data Model](#3-data-model)
4. [Page Structure & Navigation](#4-page-structure--navigation)
5. [Component Hierarchy](#5-component-hierarchy)
6. [File & Folder Structure](#6-file--folder-structure)
7. [PowerShell Integration](#7-powershell-integration)
8. [Key UI Screens](#8-key-ui-screens)
9. [State Management](#9-state-management)
10. [Implementation Phases](#10-implementation-phases)

---

## 1. Architecture Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Electron Shell (Tauri v2)               │
│  ┌───────────────────────────────────────────────────────┐  │
│  │              Next.js 16 App (SSR + Client)            │  │
│  │  ┌─────────────┐  ┌──────────────┐  ┌─────────────┐  │  │
│  │  │  Settings   │  │  Profiles    │  │  Execution  │  │  │
│  │  │  Engine     │  │  Manager     │  │  Engine     │  │  │
│  │  └──────┬──────┘  └──────┬───────┘  └──────┬──────┘  │  │
│  │         │                │                  │         │  │
│  │  ┌──────┴────────────────┴──────────────────┴──────┐  │  │
│  │  │              Zustand State Store                │  │  │
│  │  └─────────────────────┬─────────────────────────┘  │  │
│  └────────────────────────┼────────────────────────────┘  │
│                           │                                │
│  ┌────────────────────────┴────────────────────────────┐  │
│  │           PowerShell Bridge (IPC Layer)             │  │
│  │  • Script generation  • Execution  • Output capture │  │
│  └─────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Core Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Framework** | Next.js 16 (App Router) | Modern React, SSR for fast initial load, API routes for PS bridge |
| **Desktop Shell** | Tauri v2 | Rust-based, ~3MB binary, native PS execution, no Chromium bundling like Electron |
| **State** | Zustand + persist middleware | Lightweight, no boilerplate, built-in persistence to localStorage/JSON |
| **UI Library** | shadcn/ui (Radix + Tailwind) | Accessible, composable, dark theme out of the box |
| **Styling** | Tailwind CSS 4 | Utility-first, design token support, CSS custom properties for theming |
| **Icons** | Lucide React | Consistent, tree-shakeable, 1500+ icons |
| **Data Source** | Static JSON catalog + script parser | Settings catalog is generated from PS1 at build time; runtime reads it |
| **Config Format** | JSON (compatible with PS1's -ConfigFile) | Direct interoperability with existing script |

### Two Deployment Modes

1. **Tauri Desktop App** (primary) — native Windows app with direct PowerShell execution
2. **Web App** (secondary) — runs in browser; generates scripts for download but cannot execute directly

---

## 2. Competitive Advantage Matrix

### Feature Comparison — What We Have That Others Don't

| Feature | Us | WinUtil | Win11Debloat | Winhance | WinScript | musman96 |
|---------|:--:|:-------:|:------------:|:--------:|:---------:|:--------:|
| **Per-setting granularity + tooltips** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **3-tier safety classification** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Granular per-setting undo** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Named profiles with descriptions** | ✅ | ❌ | ❌ | ✅* | ❌ | ❌ |
| **5-browser hardening** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **AI feature control (Copilot/Recall/ClickToDo/Paint/Notepad AI)** | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ |
| **Winget + Chocolatey** | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ |
| **3rd-party telemetry blocking** | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **Real-time change preview** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Cross-section search/filter** | ✅ | ✅* | ❌ | ❌ | ❌ | ❌ |
| **Modern web-based GUI** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Hardware-aware (SSD/HDD, laptop/desktop, RAM)** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Edge hardening (14+ policies)** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **DNS-over-HTTPS** | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **Custom ISO creator** | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| **Sysprep/deployment mode** | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ |
| **Undo script generation** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Idempotency (skip already-applied)** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **System Restore point** | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| **Registry backup** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Before/after snapshots** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |

\* Partial implementation

### Our Unique Selling Points (no competitor has ALL of these)

1. **Per-setting granularity with tooltips** — Every one of 185 settings can be individually toggled, each with a human-readable description, safety badge, and technical detail tooltip
2. **3-tier safety classification** — Visual badges (Safe=green, Moderate=amber, Risky=red) with risky defaults OFF
3. **Granular per-setting undo** — Not all-or-nothing. Undo specific changes from a selection list
4. **Named profiles** — Save/load named configurations with descriptions ("Gaming Rig", "Office Laptop", "Kiosk")
5. **Real-time change preview** — Before applying, see exactly what will change (registry paths, values, services) in a diff-like view
6. **5-browser hardening** — Chrome, Edge, Firefox, Brave, Opera with extension deployment + enterprise policies
7. **Hardware-aware execution** — SSD/HDD detection, laptop/desktop, RAM-aware settings (from the PS1 script)
8. **Modern web GUI** — Beautiful, responsive, dark-themed React app (competitors use WPF or console)

---

## 3. Data Model

### Core Types

```typescript
// ─── Safety Classification ───
type SafetyLevel = 'Safe' | 'Moderate' | 'Risky';

// ─── Section Definition ───
interface Section {
  id: string;              // "Privacy", "Debloat", "EdgeHardening", etc.
  name: string;            // Display name: "Privacy and Telemetry"
  description: string;     // Section-level tooltip/description
  icon: string;            // Lucide icon name: "shield", "trash2", "globe", etc.
  order: number;           // Display order (1-18)
  category: SectionCategory;
  safetySummary: {
    safe: number;
    moderate: number;
    risky: number;
    total: number;
  };
  requiresReboot: boolean;
  requiresNetwork: boolean; // Needs internet (e.g., Winget, Office)
  win11Only?: boolean;
  win10Only?: boolean;
}

type SectionCategory = 
  | 'privacy'      // Privacy, EdgeHardening, BrowserHardening
  | 'cleanup'      // Debloat, DiskCleanup, ScheduledTasks, WindowsFeatures
  | 'performance'  // Performance, ServiceStartup, Gaming
  | 'security'     // Security, Network, WindowsUpdate
  | 'customize'    // ExplorerUI, OneDrive, FinalTouches
  | 'install';     // Winget, OfficeActivation

// ─── Individual Setting ───
interface Setting {
  id: string;              // "Privacy_AllowTelemetry", "Debloat_Copilot", etc.
  sectionId: string;       // Foreign key to Section.id
  name: string;            // Human-readable name
  description: string;     // Tooltip description (from PS1 -Description param)
  safetyLevel: SafetyLevel;
  type: SettingType;       // What kind of change this is
  action: string;          // Technical action: "HKLM\...\AllowTelemetry = 0"
  
  // State
  enabled: boolean;        // Whether this setting is toggled ON
  applied: boolean;        // Whether this has been applied to the system
  skipped: boolean;        // Whether it was skipped (already set / risky blocked)
  failed: boolean;         // Whether it failed to apply
  
  // Optional context
  registryPath?: string;   // For registry settings
  registryName?: string;
  registryValue?: string | number;
  registryType?: 'DWord' | 'QWord' | 'String' | 'ExpandString';
  taskPath?: string;       // For scheduled task settings
  taskName?: string;
  appxName?: string;       // For AppX bloatware
  featureName?: string;    // For Windows features
  wingetId?: string;       // For Winget packages
  serviceName?: string;   // For service settings
  
  // Undo
  undoCommand?: string;    // PowerShell command to revert
  undoDescription?: string;
}

type SettingType = 
  | 'registry' 
  | 'scheduled-task' 
  | 'appx-package'
  | 'windows-feature'
  | 'winget-package'
  | 'chocolatey-package'
  | 'service'
  | 'hosts-entry'
  | 'dns-config'
  | 'power-plan'
  | 'browser-policy'
  | 'browser-extension'
  | 'custom';             // For anything else

// ─── Profile (Saved Configuration) ───
interface Profile {
  id: string;              // UUID
  name: string;            // "Gaming Rig", "Office Laptop", "Kiosk Mode"
  description: string;     // "Optimized for gaming with privacy preserved"
  createdAt: string;       // ISO 8601
  updatedAt: string;
  isBuiltIn: boolean;      // true for factory presets
  
  // The actual configuration
  sections: {
    [sectionId: string]: {
      enabled: boolean;    // Is this section included?
      settings: {
        [settingId: string]: boolean;  // true = ON, false = toggled OFF
      };
    };
  };
  
  // Metadata
  tag?: string;            // Optional tag for filtering
  author?: string;
  version?: string;        // PS1 version this profile was created for
}

// ─── Execution State ───
interface ExecutionState {
  status: 'idle' | 'preflight' | 'running' | 'paused' | 'completed' | 'failed' | 'cancelled';
  currentSection: string | null;
  currentSetting: string | null;
  progress: {
    totalSettings: number;
    appliedSettings: number;
    skippedSettings: number;
    failedSettings: number;
    percentComplete: number;
  };
  logs: LogEntry[];
  startTime: string | null;
  endTime: string | null;
  sectionStats: {
    [sectionId: string]: {
      duration: number;    // milliseconds
      changed: number;
      skipped: number;
      failed: number;
    };
  };
}

interface LogEntry {
  timestamp: string;
  level: 'info' | 'success' | 'warn' | 'error';
  section?: string;
  settingId?: string;
  message: string;
}

// ─── Pre-flight Check Results ───
interface PreflightResult {
  isAdmin: boolean;
  osVersion: string;
  osBuild: number;
  isWin11: boolean;
  chassisType: 'Laptop' | 'Desktop' | 'Unknown';
  bootDriveType: 'SSD' | 'HDD' | 'Unknown';
  totalRamGB: number;
  internetConnected: boolean;
  freeDiskSpaceGB: number;
  pendingReboot: boolean;
  batteryLevel?: number;
  onAcPower?: boolean;
  defenderExcluded: boolean;
  restorePointEnabled: boolean;
}

// ─── Undo Entry ───
interface UndoEntry {
  id: string;
  settingId: string;
  sectionId: string;
  description: string;
  undoCommand: string;
  type: SettingType;
  appliedAt: string;
  selected: boolean;      // For granular undo selection
}

// ─── Search & Filter State ───
interface FilterState {
  searchQuery: string;
  safetyFilter: SafetyLevel | 'all';
  categoryFilter: SectionCategory | 'all';
  statusFilter: 'all' | 'enabled' | 'disabled' | 'applied' | 'risky';
  sectionFilter: string | 'all';  // Section ID or 'all'
}
```

### Built-in Preset Profiles

```typescript
const BUILTIN_PROFILES: Profile[] = [
  {
    id: 'recommended',
    name: 'Recommended',
    description: 'Safe + Moderate settings. Best for most users. Risky settings skipped.',
    isBuiltIn: true,
    // ... sections with Safe+Moderate ON, Risky OFF
  },
  {
    id: 'maximum-privacy',
    name: 'Maximum Privacy',
    description: 'All privacy and security settings enabled, including risky telemetry blocking.',
    isBuiltIn: true,
    // ... all privacy/security ON including risky
  },
  {
    id: 'gaming',
    name: 'Gaming Optimized',
    description: 'Performance + gaming settings. Keeps Xbox, Game Bar, and hardware acceleration.',
    isBuiltIn: true,
    // ... gaming-optimized selections
  },
  {
    id: 'office-laptop',
    name: 'Office Laptop',
    description: 'Conservative tweaks for work laptops. Preserves OneDrive, search, and enterprise features.',
    isBuiltIn: true,
    // ... conservative selections
  },
  {
    id: 'minimal',
    name: 'Minimal',
    description: 'Only the safest settings. Zero risk of breaking anything.',
    isBuiltIn: true,
    // ... only Safe settings ON
  },
  {
    id: 'kiosk',
    name: 'Kiosk / Deployment',
    description: 'Maximum lockdown for public or kiosk machines. Sysprep-compatible.',
    isBuiltIn: true,
    // ... maximum lockdown
  },
];
```

---

## 4. Page Structure & Navigation

### Navigation Layout

```
┌─────────────────────────────────────────────────────────────┐
│  [Logo] WinPostInstall    [Search ▼]    [Profile ▼]   [⚙️] │
├────────┬────────────────────────────────────────────────────┤
│        │                                                    │
│  📊    │              Main Content Area                     │
│ Home   │                                                    │
│        │                                                    │
│ 🔒     │   (varies by page — see below)                    │
│ Privacy│                                                    │
│        │                                                    │
│ 🗑️     │                                                    │
│ Debloat│                                                    │
│        │                                                    │
│ 🖥️     │                                                    │
│ UI     │                                                    │
│        │                                                    │
│ ⚡     │                                                    │
│ Perf   │                                                    │
│        │                                                    │
│ 🛡️     │                                                    │
│ Security│                                                   │
│        │                                                    │
│ ...    │                                                    │
│        │                                                    │
│ ────── │                                                    │
│ 📦     │                                                    │
│ Install│                                                    │
│        │                                                    │
│ 🔄     │                                                    │
│ Undo   │                                                    │
│        │                                                    │
│ 💾     │                                                    │
│ Profiles│                                                   │
│        │                                                    │
├────────┴────────────────────────────────────────────────────┤
│  [▶ Apply 18 sections (155 changes)]  [Preview]  [Export]  │
└─────────────────────────────────────────────────────────────┘
```

### Page Map

| Route | Page | Description |
|-------|------|-------------|
| `/` | **Dashboard** | System overview, pre-flight status, quick-start cards, recent profile |
| `/sections/[sectionId]` | **Section Detail** | All settings in a section with toggles, safety badges, tooltips |
| `/install` | **Software Install** | Winget + Chocolatey package browser with search, categories, multi-select |
| `/undo` | **Undo Center** | Granular undo — select individual changes to revert |
| `/profiles` | **Profile Manager** | Save/load/delete/export/import named profiles |
| `/preview` | **Change Preview** | Real-time preview of all pending changes before applying |
| `/execute` | **Execution View** | Live progress, streaming logs, section-by-section status |
| `/settings` | **App Settings** | Theme, PowerShell path, log location, defaults |
| `/about` | **About** | Version, changelog, credits, license |

---

## 5. Component Hierarchy

### Component Tree

```
App
├── Layout
│   ├── Sidebar
│   │   ├── SidebarHeader (Logo + Version)
│   │   ├── SidebarNav
│   │   │   ├── NavGroup ("Optimize")
│   │   │   │   └── NavItem × 18 (one per section)
│   │   │   ├── NavGroup ("Tools")
│   │   │   │   ├── NavItem (Software Install)
│   │   │   │   ├── NavItem (Undo Center)
│   │   │   │   └── NavItem (Profiles)
│   │   │   └── NavGroup ("System")
│   │   │       ├── NavItem (Change Preview)
│   │   │       └── NavItem (Settings)
│   │   └── SidebarFooter (Apply button)
│   ├── TopBar
│   │   ├── GlobalSearch (Cmd+K / Ctrl+K)
│   │   ├── ProfileSelector (dropdown)
│   │   └── SystemBadge (admin status, OS version)
│   └── MainContent (page router)
│
├── Pages
│   ├── DashboardPage
│   │   ├── PreflightCard (system check results)
│   │   ├── QuickStartCards (preset profile cards)
│   │   ├── SectionOverviewGrid (18 section cards with safety summary)
│   │   └── RecentActivity (last run summary)
│   │
│   ├── SectionDetailPage (per section)
│   │   ├── SectionHeader (name, icon, safety summary, select all/none)
│   │   ├── SectionFilterBar (safety filter, status filter, search)
│   │   └── SettingList
│   │       └── SettingRow × N
│   │           ├── SettingToggle (switch)
│   │           ├── SafetyBadge (Safe/Moderate/Risky)
│   │           ├── SettingName
│   │           ├── SettingTooltip (hover → description + technical detail)
│   │           ├── SettingStatus (applied/skipped/failed indicator)
│   │           └── SettingActions (undo button if applied)
│   │
│   ├── InstallPage
│   │   ├── PackageSourceTabs (Winget | Chocolatey)
│   │   ├── PackageSearchBar
│   │   ├── PackageCategoryFilter
│   │   └── PackageGrid
│   │       └── PackageCard × N
│   │           ├── PackageIcon
│   │           ├── PackageName + PackageID
│   │           ├── PackageDescription
│   │           ├── InstallToggle
│   │           └── PackageStatus (installed/pending/failed)
│   │
│   ├── UndoPage
│   │   ├── UndoFilterBar (by section, by type, by date)
│   │   ├── UndoSelectAll (checkbox)
│   │   └── UndoList
│   │       └── UndoRow × N
│   │           ├── UndoCheckbox
│   │           ├── UndoDescription
│   │           ├── UndoType (Registry/Task/AppX/Feature)
│   │           ├── UndoSection
│   │           └── UndoTimestamp
│   │
│   ├── ProfilesPage
│   │   ├── ProfileList
│   │   │   └── ProfileCard × N
│   │   │       ├── ProfileName + Description
│   │   │       ├── ProfileStats (sections, settings count)
│   │   │       ├── ProfileTimestamp
│   │   │       └── ProfileActions (Load, Duplicate, Export, Delete)
│   │   ├── CreateProfileDialog
│   │   └── ImportProfileDialog
│   │
│   ├── PreviewPage
│   │   ├── PreviewSummary (total changes by section, by safety level)
│   │   ├── PreviewDiffList
│   │   │   └── PreviewDiffItem × N
│   │   │       ├── DiffAction (registry set / task disable / app remove / etc.)
│   │   │       ├── DiffTarget (path/name)
│   │   │       ├── DiffValue (old → new)
│   │   │       └── DiffSafetyBadge
│   │   └── PreviewActions (Apply, Export Script, Cancel)
│   │
│   └── ExecutePage
│       ├── ExecuteProgress (overall progress bar + stats)
│       ├── ExecuteSectionList
│       │   └── ExecuteSectionRow × N
│       │       ├── SectionName
│       │       ├── SectionStatus (pending/running/completed/failed)
│       │       ├── SectionProgress (mini progress bar)
│       │       └── SectionStats (changed/skipped/failed)
│       ├── ExecuteLog (streaming terminal-like log)
│       │   └── LogLine × N (color-coded by level)
│       └── ExecuteActions (Pause, Cancel, Restart when done)
│
└── Shared Components
    ├── SafetyBadge
    │   ├── SafeBadge (green)
    │   ├── ModerateBadge (amber)
    │   └── RiskyBadge (red)
    ├── SearchDialog (Cmd+K global search)
    ├── ConfirmDialog (for risky operations)
    ├── Toast (notifications)
    ├── Badge
    ├── Tooltip
    └── ThemeProvider (dark/light)
```

---

## 6. File & Folder Structure

```
winpostinstall-gui/
├── src/
│   ├── app/                          # Next.js App Router
│   │   ├── layout.tsx                # Root layout (sidebar, topbar, theming)
│   │   ├── page.tsx                  # Dashboard (/)
│   │   ├── globals.css               # Tailwind + custom CSS variables
│   │   │
│   │   ├── sections/
│   │   │   └── [sectionId]/
│   │   │       └── page.tsx          # Section detail page
│   │   │
│   │   ├── install/
│   │   │   └── page.tsx              # Software install page
│   │   │
│   │   ├── undo/
│   │   │   └── page.tsx              # Undo center page
│   │   │
│   │   ├── profiles/
│   │   │   └── page.tsx              # Profile manager page
│   │   │
│   │   ├── preview/
│   │   │   └── page.tsx              # Change preview page
│   │   │
│   │   ├── execute/
│   │   │   └── page.tsx              # Execution view page
│   │   │
│   │   ├── settings/
│   │   │   └── page.tsx              # App settings page
│   │   │
│   │   ├── about/
│   │   │   └── page.tsx              # About page
│   │   │
│   │   └── api/                      # API routes (PowerShell bridge)
│   │       ├── execute/
│   │       │   └── route.ts          # POST: Start execution
│   │       ├── execute/[id]/
│   │       │   └── route.ts          # GET: Stream execution output
│   │       ├── preflight/
│   │       │   └── route.ts          # GET: Run pre-flight checks
│   │       ├── generate-script/
│   │       │   └── route.ts          # POST: Generate PS1 from config
│   │       ├── undo/
│   │       │   └── route.ts          # POST: Execute undo commands
│   │       └── system-info/
│   │           └── route.ts          # GET: Get system information
│   │
│   ├── components/
│   │   ├── ui/                       # shadcn/ui primitives
│   │   │   ├── button.tsx
│   │   │   ├── switch.tsx
│   │   │   ├── badge.tsx
│   │   │   ├── dialog.tsx
│   │   │   ├── tooltip.tsx
│   │   │   ├── command.tsx           # Command palette (Cmd+K)
│   │   │   ├── card.tsx
│   │   │   ├── progress.tsx
│   │   │   ├── scroll-area.tsx
│   │   │   ├── separator.tsx
│   │   │   ├── tabs.tsx
│   │   │   ├── checkbox.tsx
│   │   │   ├── select.tsx
│   │   │   ├── input.tsx
│   │   │   ├── toast.tsx
│   │   │   ├── dropdown-menu.tsx
│   │   │   ├── accordion.tsx
│   │   │   ├── alert.tsx
│   │   │   ├── sheet.tsx             # Mobile sidebar
│   │   │   └── skeleton.tsx
│   │   │
│   │   ├── layout/
│   │   │   ├── sidebar.tsx
│   │   │   ├── sidebar-nav.tsx
│   │   │   ├── sidebar-header.tsx
│   │   │   ├── sidebar-footer.tsx
│   │   │   ├── topbar.tsx
│   │   │   ├── global-search.tsx
│   │   │   ├── profile-selector.tsx
│   │   │   └── system-badge.tsx
│   │   │
│   │   ├── settings/
│   │   │   ├── setting-row.tsx       # Single setting with toggle + tooltip
│   │   │   ├── setting-toggle.tsx    # Toggle switch with safety gate
│   │   │   ├── safety-badge.tsx      # Safe/Moderate/Risky badge
│   │   │   ├── setting-tooltip.tsx   # Rich tooltip with description + details
│   │   │   ├── setting-status.tsx    # Applied/Skipped/Failed indicator
│   │   │   ├── section-header.tsx    # Section name + safety summary
│   │   │   ├── section-filter-bar.tsx
│   │   │   └── setting-list.tsx      # Virtual list for performance
│   │   │
│   │   ├── install/
│   │   │   ├── package-card.tsx
│   │   │   ├── package-search.tsx
│   │   │   ├── package-source-tabs.tsx
│   │   │   └── package-grid.tsx
│   │   │
│   │   ├── undo/
│   │   │   ├── undo-row.tsx
│   │   │   ├── undo-list.tsx
│   │   │   └── undo-filter-bar.tsx
│   │   │
│   │   ├── profiles/
│   │   │   ├── profile-card.tsx
│   │   │   ├── create-profile-dialog.tsx
│   │   │   ├── import-profile-dialog.tsx
│   │   │   └── profile-list.tsx
│   │   │
│   │   ├── preview/
│   │   │   ├── preview-summary.tsx
│   │   │   ├── preview-diff-item.tsx
│   │   │   └── preview-diff-list.tsx
│   │   │
│   │   ├── execute/
│   │   │   ├── execute-progress.tsx
│   │   │   ├── execute-section-row.tsx
│   │   │   ├── execute-log.tsx       # Terminal-like streaming log
│   │   │   └── execute-actions.tsx
│   │   │
│   │   └── shared/
│   │       ├── confirm-dialog.tsx
│   │       ├── section-icon.tsx       # Maps section ID → Lucide icon
│   │       ├── empty-state.tsx
│   │       └── loading-skeleton.tsx
│   │
│   ├── data/
│   │   ├── sections.ts               # Section definitions (18 sections)
│   │   ├── settings-catalog.ts       # All 185 settings with metadata
│   │   ├── bloatware-list.ts         # AppX packages for debloat section
│   │   ├── winget-apps.ts            # Default Winget app catalog
│   │   ├── chocolatey-apps.ts        # Chocolatey app catalog
│   │   ├── browser-policies.ts       # Browser hardening policy definitions
│   │   ├── edge-policies.ts          # Edge-specific policies
│   │   ├── windows-features.ts       # Windows feature definitions
│   │   ├── default-profiles.ts       # Built-in preset profiles
│   │   └── icons.ts                  # Icon mapping
│   │
│   ├── lib/
│   │   ├── script-generator.ts       # Generate PS1 script from config
│   │   ├── config-generator.ts       # Generate JSON config from UI state
│   │   ├── ps-bridge.ts              # PowerShell execution bridge
│   │   ├── script-parser.ts          # Parse PS1 → settings catalog (build-time)
│   │   ├── preflight.ts              # Pre-flight check logic
│   │   ├── search.ts                 # Fuzzy search across all settings
│   │   ├── profile-io.ts             # Import/export profiles as JSON
│   │   ├── diff-engine.ts            # Compute before/after diff for preview
│   │   └── utils.ts                  # General utilities (cn, formatDate, etc.)
│   │
│   ├── stores/
│   │   ├── settings-store.ts         # Zustand: all setting toggles + section state
│   │   ├── profile-store.ts          # Zustand: active profile, saved profiles
│   │   ├── execution-store.ts        # Zustand: execution state, logs, progress
│   │   ├── filter-store.ts           # Zustand: search, safety filter, category filter
│   │   └── app-store.ts              # Zustand: theme, preferences, system info
│   │
│   ├── hooks/
│   │   ├── use-setting.ts            # Get/set individual setting state
│   │   ├── use-section.ts            # Get section with computed stats
│   │   ├── use-profile.ts            # Load/apply profile
│   │   ├── use-execute.ts            # Execute + stream output
│   │   ├── use-preflight.ts          # Run pre-flight checks
│   │   └── use-search.ts            # Global search hook
│   │
│   └── types/
│       ├── index.ts                  # All TypeScript interfaces (from Data Model)
│       ├── sections.ts               # Section-specific types
│       └── api.ts                    # API request/response types
│
├── scripts/
│   ├── parse-ps1-catalog.ts          # Build-time: extract settings from PS1 → JSON
│   ├── generate-settings-data.ts     # Build-time: generate settings-catalog.ts
│   └── validate-catalog.ts           # Validate catalog completeness
│
├── powershell/
│   ├── WinPostInstall.ps1            # The actual script (copied from scripts/)
│   ├── bridge.ps1                    # Helper: IPC bridge for execution
│   └── preflight.ps1                 # Helper: Pre-flight check script
│
├── public/
│   ├── icon.ico                      # App icon
│   └── fonts/                        # Inter font files
│
├── tauri/                            # Tauri configuration (desktop mode)
│   ├── src/
│   │   ├── main.rs                   # Tauri main
│   │   └── commands/
│   │       ├── execute_ps.rs         # Execute PowerShell commands
│   │       └── system_info.rs        # Get system info
│   ├── Cargo.toml
│   └── tauri.conf.json
│
├── next.config.ts
├── tailwind.config.ts
├── tsconfig.json
├── package.json
└── README.md
```

---

## 7. PowerShell Integration

### Architecture: How the GUI Drives the Script

The GUI does NOT modify the PS1 script directly. Instead, it generates a **JSON configuration file** that the existing `-ConfigFile` parameter consumes. The PS1 script is the single source of truth for all optimizations.

```
┌──────────────┐     JSON Config      ┌──────────────────┐
│   Next.js    │ ──────────────────→  │  WinPostInstall  │
│   GUI        │                      │  .ps1 -ConfigFile │
│              │ ←──────────────────  │                  │
│              │   Streaming Output   │                  │
└──────────────┘                      └──────────────────┘
```

### Flow: Configure → Preview → Generate → Execute

#### Step 1: UI Configuration → JSON Config

The UI state (Zustand stores) is converted to a JSON config file compatible with the PS1 script's `-ConfigFile` format:

```typescript
// lib/config-generator.ts
function generateConfig(state: SettingsStoreState): WinPostInstallConfig {
  const config: WinPostInstallConfig = {
    Sections: [],
    AppList: [],
    BloatwareList: [],
    SettingOverrides: {},   // NEW: settings toggled OFF
    AllowRisky: false,
  };

  // 1. Add sections that have any enabled settings
  for (const sectionId of ALL_SECTION_IDS) {
    const sectionSettings = state.settings.filter(
      s => s.sectionId === sectionId && s.enabled
    );
    if (sectionSettings.length > 0) {
      config.Sections.push(sectionId);
    }
  }

  // 2. Add settings toggled OFF (to pass to PS1's SettingOverrides)
  for (const setting of state.settings) {
    if (!setting.enabled) {
      config.SettingOverrides[setting.id] = true;
    }
  }

  // 3. Winget app list
  config.AppList = state.wingetApps
    .filter(a => a.selected)
    .map(a => ({ ID: a.id, Name: a.name }));

  // 4. Bloatware list
  config.BloatwareList = state.bloatwareItems
    .filter(b => b.selected)
    .map(b => b.pattern);

  // 5. Risky settings
  config.AllowRisky = state.allowRisky;

  return config;
}
```

#### Step 2: Script Generation (for Export/Preview)

For users who want to download a standalone script:

```typescript
// lib/script-generator.ts
function generateScript(config: WinPostInstallConfig): string {
  // Option A: Generate a wrapper .ps1 that calls WinPostInstall.ps1 with -ConfigFile
  // Option B: Generate a self-contained script with only selected settings inlined
  // Option A is preferred — keeps PS1 as single source of truth
  
  const configJson = JSON.stringify(config, null, 2);
  const configB64 = Buffer.from(configJson).toString('base64');
  
  return `
# WinPostInstall - Generated Configuration Wrapper
# Generated by WinPostInstall GUI on ${new Date().toISOString()}
$ConfigJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("${configB64}"))
$ConfigPath = "$env:TEMP\\WinPostInstall-Config.json"
$ConfigJson | Set-Content -Path $ConfigPath -Encoding UTF8
& "${PS1_SCRIPT_PATH}" -ConfigFile $ConfigPath
Remove-Item $ConfigPath -Force -ErrorAction SilentlyContinue
`.trim();
}
```

#### Step 3: Execution (Tauri Desktop Mode)

```typescript
// Tauri IPC: src-tauri/src/commands/execute_ps.rs
// Rust command that spawns PowerShell and streams output

#[tauri::command]
async fn execute_powershell(
    script_path: String, 
    config_path: String,
    allow_risky: bool,
) -> Result<ExecutionHandle, String> {
    let mut cmd = Command::new("powershell.exe");
    cmd.args([
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", &script_path,
        "-ConfigFile", &config_path,
    ]);
    if allow_risky {
        cmd.arg("-AllowRisky");
    }
    // Spawn and return handle for streaming output
    // ...
}
```

#### Step 4: Execution (Web Mode — No Direct Execution)

In web mode, the app can only:
1. Generate the config JSON for download
2. Generate a wrapper .bat + .ps1 for download
3. Show the user instructions to run it

```typescript
// lib/bridge.ts — Web mode fallback
function downloadExecutionPackage(config: WinPostInstallConfig) {
  const files = {
    'WinPostInstall-Config.json': JSON.stringify(config, null, 2),
    'Run-WinPostInstall.bat': generateBatLauncher(),
    'WinPostInstall.ps1': PS1_SCRIPT_SOURCE,  // bundled
  };
  
  // Create ZIP and trigger download
  downloadZip(files, 'WinPostInstall-Package.zip');
}
```

#### Step 5: Output Capture & Streaming

The PowerShell bridge captures three streams:
- **stdout** → parsed into structured log entries
- **stderr** → error entries
- **exit code** → success/failure

```typescript
// Parse PS1 output into structured entries
function parsePsOutput(line: string): LogEntry | null {
  // Match patterns from the PS1 script:
  // [OK] Registry: HKLM\...\AllowTelemetry = 0
  // [WARN] Something
  // [ERROR] Failed to set...
  // SKIPPED (risky): ...
  // SKIPPED (already set): ...
  
  if (line.includes('[OK]')) return { level: 'success', ... };
  if (line.includes('[WARN]')) return { level: 'warn', ... };
  if (line.includes('[ERROR]')) return { level: 'error', ... };
  if (line.includes('SKIPPED')) return { level: 'info', ... };
  return { level: 'info', message: line };
}
```

### Build-Time: Settings Catalog Extraction

A build-time script parses the PS1 to extract all settings metadata:

```typescript
// scripts/parse-ps1-catalog.ts
interface ParsedSetting {
  settingId: string;
  section: string;
  safetyLevel: SafetyLevel;
  description: string;
  action: string;       // e.g., "HKLM\SOFTWARE\...\AllowTelemetry = 0"
  type: 'registry' | 'scheduled-task';
  registryPath?: string;
  registryName?: string;
  registryValue?: string;
}

// Parse all Set-Registry calls:
// Set-Registry -Path "HKLM:\..." -Name "AllowTelemetry" -Value 0 
//   -Type DWord -SafetyLevel "Safe" 
//   -Description "Stops Windows telemetry" 
//   -SettingID "Privacy_AllowTelemetry"
//
// → Extract: { id, section, safety, desc, action, path, name, value }

// Parse all Disable-AppTask calls similarly
```

This runs at build time and generates `src/data/settings-catalog.ts`, which the UI imports as static data.

---

## 8. Key UI Screens

### Screen 1: Dashboard

```
┌──────────────────────────────────────────────────────────────┐
│  WinPostInstall v4.1.0                                      │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─ System Status ──────────────────────────────────────┐    │
│  │ ✅ Administrator  ✅ Windows 11 23H2  ✅ SSD         │    │
│  │ ✅ Internet OK    ✅ 245 GB Free     ⚠️ Pending Reboot│   │
│  └──────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌─ Quick Start ────────────────────────────────────────┐    │
│  │  [🟢 Recommended]  [🔴 Max Privacy]  [🎮 Gaming]   │    │
│  │  [💼 Office]       [⚡ Minimal]      [🖥️ Kiosk]     │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌─ All Sections ──────────────────────────────────────┐    │
│  │                                                      │    │
│  │  🔒 Privacy & Telemetry     [Safe]  24 items  [✓]  │    │
│  │  🗑️ Debloat                 [Mixed] 38 items  [✓]  │    │
│  │  🖥️ Explorer & UI           [Safe]  12 items  [✓]  │    │
│  │  ⚙️ Service & Startup       [Mixed] 15 items  [✓]  │    │
│  │  ⚡ Performance & Power     [Mixed] 18 items  [✓]  │    │
│  │  🛡️ Security               [Mixed] 22 items  [✓]  │    │
│  │  🌐 Network                [Safe]  10 items  [✓]  │    │
│  │  🔄 Windows Update         [Safe]   6 items  [✓]  │    │
│  │  🧹 Disk Cleanup           [Safe]   8 items  [✓]  │    │
│  │  📦 Software (Winget)      [Safe]   9 items  [✓]  │    │
│  │  📋 Office 365             [Safe]   3 items  [ ]  │    │
│  │  🌐 Edge Hardening         [Safe]  14 items  [✓]  │    │
│  │  ☁️ OneDrive               [Mixed]  5 items  [✓]  │    │
│  │  🎮 Gaming / DVR           [Safe]   6 items  [✓]  │    │
│  │  📅 Scheduled Tasks        [Safe]  12 items  [✓]  │    │
│  │  🌍 Browser Privacy        [Safe]  10 items  [✓]  │    │
│  │  ✨ Final Touches          [Safe]   8 items  [✓]  │    │
│  │  🪟 Windows Features       [Mixed] 11 items  [✓]  │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  [▶ Apply 18 sections (155 changes)]  [Preview]     │    │
│  └──────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────┘
```

### Screen 2: Section Detail (Privacy & Telemetry)

```
┌──────────────────────────────────────────────────────────────┐
│  ← Back    Privacy and Telemetry        [Safe] 24 items     │
│                                              [Select All]   │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  Filter: [All ▼] [Safety: All ▼] [Status: All ▼] [🔍 ...] │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  │ 🟢 [ON]  AllowTelemetry = 0                          │    │
│  │         Stops Windows from sending telemetry data     │    │
│  │         HKLM\SOFTWARE\Policies\...\AllowTelemetry     │    │
│  ├──────────────────────────────────────────────────────┤    │
│  │ 🟢 [ON]  NoFeedback = 1                             │    │
│  │         Removes Feedback Hub notifications            │    │
│  ├──────────────────────────────────────────────────────┤    │
│  │ 🟡 [ON]  DisableOneSettingsSync = 2                 │    │
│  │         Disables cloud sync of settings              │    │
│  │         ⚠️ Moderate: Some users rely on settings sync│    │
│  ├──────────────────────────────────────────────────────┤    │
│  │ 🔴 [OFF] DisableCortana = 1                        │    │
│  │         Disables Cortana digital assistant           │    │
│  │         ⛔ Risky: May break search integration       │    │
│  ├──────────────────────────────────────────────────────┤    │
│  │ ... (20 more settings)                              │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                              │
│  Summary: 20 Safe · 3 Moderate · 1 Risky                    │
│           20 ON · 1 OFF (risky default) · 3 not applied     │
└──────────────────────────────────────────────────────────────┘
```

### Screen 3: Change Preview (Real-time Diff)

```
┌──────────────────────────────────────────────────────────────┐
│  ← Back    Change Preview            155 changes across 18   │
│                                             sections         │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─ Summary ────────────────────────────────────────────┐    │
│  │  🟢 132 Safe    🟡 18 Moderate    🔴 5 Risky         │    │
│  │  📋 Registry: 120  Tasks: 18  AppX: 8  Features: 5  │    │
│  │  ⚠️  5 risky settings will be SKIPPED (enable?)     │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌─ Privacy & Telemetry (24 changes) ──────────────────┐    │
│  │  🟢 SET  HKLM\...\AllowTelemetry      1 → 0        │    │
│  │  🟢 SET  HKLM\...\NoFeedback          0 → 1        │    │
│  │  🟡 SET  HKCU\...\DisableSync         0 → 2        │    │
│  │  ...                                                │    │
│  ├─ Debloat (38 changes) ─────────────────────────────┤    │
│  │  🟢 REMOVE  Microsoft.BingFinance                   │    │
│  │  🟢 REMOVE  Microsoft.Getstarted                    │    │
│  │  🔴 REMOVE  Microsoft.WindowsCamera  ⛔ SKIPPED     │    │
│  │  ...                                                │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                              │
│  [✅ Apply All Safe+Moderate]  [⚠️ Apply Including Risky]   │
│  [📥 Export Script]           [💾 Save as Profile]          │
└──────────────────────────────────────────────────────────────┘
```

### Screen 4: Execution View (Live)

```
┌──────────────────────────────────────────────────────────────┐
│  Executing...                           67% (104/155)        │
│  ████████████████████████░░░░░░░░░░░                       │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─ Sections ─────────────────────────────────────────┐     │
│  │ ✅ Privacy & Telemetry       24/24  (0:32)         │     │
│  │ ✅ Debloat                   38/38  (1:05)         │     │
│  │ ✅ Explorer & UI             12/12  (0:08)         │     │
│  │ ✅ Service & Startup         15/15  (0:21)         │     │
│  │ 🔄 Performance & Power      8/18   (running...)   │     │
│  │ ⏳ Security                  0/22   (pending)      │     │
│  │ ⏳ Network                   0/10   (pending)      │     │
│  │ ...                                                │     │
│  └────────────────────────────────────────────────────┘     │
│                                                              │
│  ┌─ Live Output ──────────────────────────────────────┐     │
│  │ [14:32:05] [OK] Registry: ...\AllowTelemetry = 0  │     │
│  │ [14:32:05] [OK] Registry: ...\NoFeedback = 1      │     │
│  │ [14:32:06] Already set: ...\DisableInventory = 1  │     │
│  │ [14:32:07] [MODERATE] Disabling cloud sync...     │     │
│  │ [14:32:07] [OK] Registry: ...\DisableSync = 2     │     │
│  │ [14:32:08] [OK] Removed AppX: Microsoft.BingFinance│    │
│  │ ...                                                │     │
│  └────────────────────────────────────────────────────┘     │
│                                                              │
│  [⏸ Pause]  [⏹ Cancel]                                     │
└──────────────────────────────────────────────────────────────┘
```

### Screen 5: Undo Center

```
┌──────────────────────────────────────────────────────────────┐
│  Undo Center                    155 changes available        │
│                                               to revert     │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  Filter: [All Sections ▼]  [All Types ▼]  [🔍 ...]        │
│  [☑ Select All]  [☐ Deselect All]                           │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  │ ☑ 🟢 Privacy   AllowTelemetry = 0 → 1    10:32 AM  │    │
│  │ ☑ 🟢 Privacy   NoFeedback = 1 → 0       10:32 AM  │    │
│  │ ☐ 🟡 Privacy   DisableSync = 2 → 0      10:32 AM  │    │
│  │ ☑ 🟢 Debloat   Removed Microsoft.BingFinance       10:33 AM  │    │
│  │ ☑ 🔴 Service   Disabled WSearch              10:34 AM  │    │
│  │ ...                                                 │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                              │
│  [↩ Undo 42 Selected Changes]  [↩ Undo All 155]           │
│  ⚠️  A System Restore point was created before changes.     │
└──────────────────────────────────────────────────────────────┘
```

### Screen 6: Profile Manager

```
┌──────────────────────────────────────────────────────────────┐
│  Profile Manager                          [+ New Profile]    │
│                                          [📥 Import]        │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─ Built-in Presets ──────────────────────────────────┐    │
│  │                                                     │    │
│  │  🟢 Recommended        155 settings · 18 sections   │    │
│  │     "Safe + Moderate. Best for most users."         │    │
│  │     [Load]                                            │    │
│  │                                                     │    │
│  │  🔴 Maximum Privacy    160 settings · 18 sections   │    │
│  │     "All privacy + security. Includes risky."       │    │
│  │     [Load]                                            │    │
│  │                                                     │    │
│  │  🎮 Gaming Optimized   120 settings · 15 sections   │    │
│  │     "Performance + gaming. Keeps Xbox."             │    │
│  │     [Load]                                            │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌─ My Profiles ───────────────────────────────────────┐    │
│  │                                                     │    │
│  │  💼 Work Laptop        130 settings · 16 sections   │    │
│  │     "Conservative. Keeps OneDrive + search."        │    │
│  │     Created: 2025-02-28 · Updated: 2025-03-01      │    │
│  │     [Load] [Duplicate] [📤 Export] [🗑 Delete]     │    │
│  │                                                     │    │
│  │  🖥️ Gaming Desktop     148 settings · 17 sections   │    │
│  │     "Max performance. No Xbox/Game Bar."            │    │
│  │     Created: 2025-03-02                             │    │
│  │     [Load] [Duplicate] [📤 Export] [🗑 Delete]     │    │
│  └─────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────┘
```

---

## 9. State Management

### Zustand Stores

#### Settings Store (Core State)

```typescript
// stores/settings-store.ts
interface SettingsStore {
  // All settings (loaded from catalog at startup)
  settings: Map<string, Setting>;
  
  // Section-level toggle state
  sections: Map<string, { enabled: boolean }>;
  
  // Risky settings gate
  allowRisky: boolean;
  
  // Actions
  toggleSetting: (id: string) => void;
  toggleSection: (id: string) => void;
  enableAllSafe: () => void;
  enableAllSafeModerate: () => void;
  enableAllIncludingRisky: () => void;
  resetToDefaults: () => void;
  applyProfile: (profile: Profile) => void;
  
  // Computed (via selectors)
  getSettingsBySection: (sectionId: string) => Setting[];
  getEnabledSettingsCount: () => number;
  getSafetySummary: (sectionId: string) => { safe: number; moderate: number; risky: number };
}
```

#### Profile Store

```typescript
// stores/profile-store.ts
interface ProfileStore {
  profiles: Profile[];
  activeProfileId: string | null;
  
  // Actions
  saveProfile: (name: string, description: string) => void;
  loadProfile: (id: string) => void;
  duplicateProfile: (id: string) => void;
  deleteProfile: (id: string) => void;
  exportProfile: (id: string) => string; // JSON string
  importProfile: (json: string) => void;
}
```

#### Execution Store

```typescript
// stores/execution-store.ts
interface ExecutionStore {
  state: ExecutionState;
  
  // Actions
  startExecution: (config: WinPostInstallConfig) => Promise<void>;
  pauseExecution: () => void;
  cancelExecution: () => void;
  appendLog: (entry: LogEntry) => void;
  updateProgress: (update: Partial<ExecutionState['progress']>) => void;
  completeSection: (sectionId: string, stats: SectionStats) => void;
}
```

### Persistence

- **Settings store**: Persisted to `localStorage` (auto-save on every toggle)
- **Profile store**: Persisted to `localStorage` + exportable as JSON files
- **Execution store**: NOT persisted (ephemeral, per-session)
- **Tauri mode**: Can persist to `%APPDATA%\WinPostGUI\` instead of localStorage

---

## 10. Implementation Phases

### Phase 1: Foundation (Week 1)

**Goal**: Runnable Next.js app with settings catalog and toggle UI

| Task | Details | Est. |
|------|---------|------|
| Project scaffold | Next.js 16 + TypeScript + Tailwind 4 + shadcn/ui | 2h |
| Build-time catalog parser | Parse PS1 → `settings-catalog.ts` (185 settings) | 4h |
| Section data definitions | 18 sections with icons, descriptions, categories | 2h |
| Type definitions | All TypeScript interfaces from Data Model | 2h |
| Zustand settings store | Toggle, section, safety state + persistence | 3h |
| Layout shell | Sidebar + Topbar + responsive shell | 4h |
| Dashboard page | System info cards + section overview grid | 4h |
| Section detail page | Setting list with toggles + safety badges | 6h |
| Setting row component | Toggle + tooltip + safety badge + status | 3h |

**Deliverable**: App that displays all 18 sections and 185 settings with working toggles

### Phase 2: Core Features (Week 2)

**Goal**: Profiles, search, preview, and script generation

| Task | Details | Est. |
|------|---------|------|
| Profile store + manager | Save/load/duplicate/delete/import/export | 6h |
| Built-in preset profiles | 6 presets: Recommended, MaxPrivacy, Gaming, Office, Minimal, Kiosk | 3h |
| Global search (Cmd+K) | Fuzzy search across all settings + sections | 4h |
| Section filter bar | Safety filter, status filter, search within section | 3h |
| Change preview page | Real-time diff of all pending changes | 6h |
| Config generator | UI state → JSON config (compatible with PS1 -ConfigFile) | 3h |
| Script generator | Config → downloadable .ps1/.bat wrapper | 3h |
| Software install page | Winget package browser + search + multi-select | 6h |
| Profile selector in topbar | Quick-switch between profiles | 2h |

**Deliverable**: Full configuration experience with profiles, search, preview, and export

### Phase 3: Execution Engine (Week 3)

**Goal**: Live PowerShell execution with streaming output

| Task | Details | Est. |
|------|---------|------|
| Tauri setup | Rust shell with PowerShell IPC commands | 8h |
| Execute API routes | POST /execute, GET /execute/[id] (SSE streaming) | 4h |
| Pre-flight check | System info collection via PowerShell | 3h |
| Execution page | Live progress, section-by-section status | 6h |
| Streaming log component | Terminal-like output with color-coded entries | 4h |
| PS output parser | Parse PS1 console output into structured LogEntry | 3h |
| Undo center page | Granular undo with per-setting selection | 6h |
| Undo execution | Run selected undo commands via PowerShell | 3h |
| Error handling + retry | Failed settings → retry, skip, or abort | 2h |

**Deliverable**: Full execution pipeline with live feedback and granular undo

### Phase 4: Polish & Distribution (Week 4)

**Goal**: Production-ready desktop app

| Task | Details | Est. |
|------|---------|------|
| Dark theme refinement | Color system, hover states, animations | 4h |
| Responsive design | Mobile sidebar (sheet), responsive grids | 4h |
| Loading skeletons | Skeleton loaders for all pages | 2h |
| Empty states | Illustrated empty states for undo, profiles | 2h |
| Keyboard shortcuts | Cmd+K search, Cmd+S save profile, etc. | 3h |
| Auto-update | Tauri updater configuration | 3h |
| System tray | Minimize to tray, background execution | 3h |
| Chocolatey integration | Chocolatey package source tab | 4h |
| Custom ISO creator | WinUtil-style ISO customization (stretch) | 8h |
| Sysprep mode | Deployment mode for sysprep scenarios | 4h |
| Installer | WiX/NSIS installer for distribution | 4h |
| Documentation | README + user guide | 3h |

**Deliverable**: Production-ready desktop app with installer

### Total Estimate: ~4 weeks (160 hours)

---

## Appendix A: Section Mapping (18 Sections)

| # | PS1 Key | Display Name | Category | Icon | Settings | Safety |
|---|---------|-------------|----------|------|----------|--------|
| 1 | Privacy | Privacy and Telemetry | privacy | Shield | 24 | Mixed |
| 2 | Debloat | Debloat | cleanup | Trash2 | 38 | Mixed |
| 3 | ExplorerUI | Explorer and UI | customize | Monitor | 12 | Safe |
| 4 | ServiceStartup | Service and Startup | performance | Settings | 15 | Mixed |
| 5 | Performance | Performance and Power | performance | Zap | 18 | Mixed |
| 6 | Security | Security | security | ShieldCheck | 22 | Mixed |
| 7 | Network | Network | security | Globe | 10 | Safe |
| 8 | WindowsUpdate | Windows Update | security | RefreshCw | 6 | Safe |
| 9 | DiskCleanup | Disk Cleanup | cleanup | HardDrive | 8 | Safe |
| 10 | Winget | Software (Winget) | install | Package | 9 | Safe |
| 11 | OfficeActivation | Office 365 | install | FileSpreadsheet | 3 | Safe |
| 12 | EdgeHardening | Edge Hardening | privacy | Globe | 14 | Safe |
| 13 | OneDrive | OneDrive | customize | Cloud | 5 | Mixed |
| 14 | Gaming | Gaming / DVR | performance | Gamepad2 | 6 | Safe |
| 15 | ScheduledTasks | Scheduled Tasks | cleanup | Calendar | 12 | Safe |
| 16 | BrowserHardening | Browser Privacy | privacy | Lock | 10 | Safe |
| 17 | FinalTouches | Final Touches | customize | Sparkles | 8 | Safe |
| 18 | WindowsFeatures | Windows Features | cleanup | Box | 11 | Mixed |

**Total: ~185 settings (155 Safe · 12 Moderate · 18 Risky)**

---

## Appendix B: Color System (Dark Theme)

```css
:root {
  /* Base */
  --background:       222 47% 11%;    /* Slate 900 */
  --foreground:       210 40% 98%;    /* Slate 50 */
  --card:             222 47% 14%;    /* Slate 800 */
  --border:           217 33% 17%;    /* Slate 700 */
  --muted:            217 33% 17%;
  
  /* Safety Colors */
  --safe:             142 71% 45%;    /* Green 500 */
  --safe-muted:       142 71% 45% / 0.15;
  --moderate:         38 92% 50%;     /* Amber 500 */
  --moderate-muted:   38 92% 50% / 0.15;
  --risky:            0 84% 60%;      /* Red 500 */
  --risky-muted:      0 84% 60% / 0.15;
  
  /* Accent */
  --primary:          217 91% 60%;    /* Blue 500 */
  --primary-hover:    217 91% 65%;
  --accent:           262 83% 58%;    /* Purple 500 — for gaming */
  
  /* Status */
  --success:          142 71% 45%;
  --warning:          38 92% 50%;
  --error:            0 84% 60%;
  --info:             199 89% 48%;    /* Cyan 500 */
}
```

---

## Appendix C: Key shadcn/ui Components Needed

| Component | Usage |
|-----------|-------|
| `Button` | Apply, Cancel, Save, Toggle actions |
| `Switch` | Setting toggles |
| `Badge` | Safety level badges (Safe/Moderate/Risky) |
| `Card` | Section cards, profile cards, package cards |
| `Command` | Cmd+K global search palette |
| `Dialog` | Confirm dialogs, create profile, import profile |
| `Tooltip` | Setting descriptions on hover |
| `Progress` | Execution progress bars |
| `Tabs` | Winget/Chocolatey, Safety level tabs |
| `Checkbox` | Undo selection, section selection |
| `Select` | Filter dropdowns |
| `Input` | Search, profile name, description |
| `ScrollArea` | Settings list, log output |
| `Accordion` | Section groups in preview |
| `Sheet` | Mobile sidebar |
| `Toast` | Notifications (save, error, complete) |
| `Alert` | Risky setting warnings, system warnings |
| `Separator` | Dividers between sections |
| `Skeleton` | Loading states |
| `DropdownMenu` | Profile actions, settings menu |

---

## Appendix D: Extending the PS1 Script for GUI Support

The existing PS1 script already supports `-ConfigFile` with JSON. To fully support the GUI, we need to add one enhancement:

### New: `-SettingOverrides` support in config JSON

Currently the PS1 script has `$script:SettingOverrides` populated only by the interactive menu. To support GUI-driven overrides via config file:

```json
{
  "Sections": ["Privacy", "Debloat"],
  "SettingOverrides": {
    "Privacy_DisableCortana": true,
    "Debloat_WindowsCamera": true
  },
  "AllowRisky": false,
  "AppList": [...],
  "BloatwareList": [...]
}
```

This requires a small PS1 modification to read `SettingOverrides` from the config file:

```powershell
# In the -ConfigFile loading block, add:
if ($config.SettingOverrides) {
    foreach ($key in $config.SettingOverrides.PSObject.Properties) {
        if ($key.Value -eq $true) {
            $script:SettingOverrides[$key.Name] = $true
        }
    }
}
if ($config.AllowRisky -eq $true) {
    $script:AllowRisky = $true
}
```

This is a **15-line change** to the PS1 script and maintains full backward compatibility (existing config files without these fields still work).

---

## Appendix E: Web-Only Mode Fallback

For users who can't install Tauri (e.g., running from a network share), the web app provides:

1. **Configure** in browser → all toggle/preview/profile features work
2. **Export Package** → downloads a ZIP containing:
   - `WinPostInstall-Config.json` (the generated configuration)
   - `WinPostInstall.ps1` (the full script)
   - `Run-GUI-Config.bat` (launcher that runs PS1 with -ConfigFile)
3. **One-click download** → user runs the .bat file

This means the web app is useful even without direct PowerShell execution.

---

*End of Implementation Plan*
