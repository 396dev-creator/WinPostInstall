"use client";

import React from "react";
import { motion } from "framer-motion";
import { Search, Download, Undo2, Terminal, ChevronDown, Sun, Moon, Globe, Sparkles } from "lucide-react";
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
import { useAppStore } from "@/store/useAppStore";
import { useTheme } from "./ThemeProvider";
import { useI18n, localeNames, type Locale } from "@/lib/i18n";

interface AppHeaderProps {
  onApply: () => void;
  onUndo: () => void;
  onPreview: () => void;
}

export function AppHeader({ onApply, onUndo, onPreview }: AppHeaderProps) {
  const { searchQuery, setSearchQuery, profiles, activeProfileId, loadProfile, activeScenarioId, setScenarioPickerOpen } = useAppStore();
  const { theme, toggleTheme } = useTheme();
  const { locale, setLocale, t } = useI18n();

  const activeProfile = profiles.find((p) => p.id === activeProfileId);

  return (
    <motion.header
      initial={{ y: -20, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      className="sticky top-0 z-40 border-b border-[var(--wpi-border)] bg-[var(--wpi-bg)]/95 backdrop-blur-md"
    >
      <div className="mx-auto max-w-7xl px-4 py-3">
        <div className="flex items-center gap-3 flex-wrap">
          {/* Logo / Title */}
          <div className="flex items-center gap-2 shrink-0">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-[var(--wpi-accent)]/10 border border-[var(--wpi-accent)]/20">
              <Terminal className="h-5 w-5 text-[var(--wpi-accent)]" />
            </div>
            <div className="hidden sm:block">
              <h1 className="text-lg font-bold text-[var(--wpi-text)] leading-none">
                Win<span className="text-[var(--wpi-accent)]">PostInstall</span>
              </h1>
              <p className="text-[10px] text-[var(--wpi-muted)] leading-none mt-0.5">{t.appVersion}</p>
            </div>
          </div>

          {/* Search */}
          <div className="relative flex-1 min-w-[180px] max-w-md">
            <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-4 w-4 text-[var(--wpi-muted)]" />
            <Input
              placeholder="Search settings..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-9 h-9 bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-text)] placeholder:text-[var(--wpi-muted)] focus-visible:ring-[var(--wpi-accent)]/30 focus-visible:border-[var(--wpi-accent)]/50 text-sm"
            />
          </div>

          {/* Scenario Picker Button */}
          <Button
            variant="outline"
            size="sm"
            onClick={() => setScenarioPickerOpen(true)}
            className={`h-9 gap-1.5 text-xs ${
              activeScenarioId
                ? "bg-[var(--wpi-accent)]/10 border-[var(--wpi-accent)]/30 text-[var(--wpi-accent)] hover:bg-[var(--wpi-accent)]/15 hover:border-[var(--wpi-accent)]/40"
                : "bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:bg-[var(--wpi-card)] hover:text-[var(--wpi-accent)] hover:border-[var(--wpi-accent)]/30"
            }`}
          >
            <Sparkles className="h-3.5 w-3.5" />
            <span className="hidden sm:inline">Scenario</span>
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
                className="h-9 gap-2 bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-text)] hover:bg-[var(--wpi-card)] hover:border-[var(--wpi-accent)]/30 text-xs"
              >
                <span className="truncate max-w-[100px]">
                  {activeProfile ? activeProfile.name : "No Profile"}
                </span>
                {activeProfile && (
                  <Badge variant="secondary" className="h-4 px-1 text-[10px] bg-[var(--wpi-accent)]/10 text-[var(--wpi-accent)] border-[var(--wpi-accent)]/20">
                    Active
                  </Badge>
                )}
                <ChevronDown className="h-3 w-3" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent
              align="end"
              className="bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-text)] min-w-[200px]"
            >
              {profiles.map((p) => (
                <DropdownMenuItem
                  key={p.id}
                  onClick={() => loadProfile(p.id)}
                  className="text-sm focus:bg-[var(--wpi-card)] focus:text-[var(--wpi-accent)] cursor-pointer"
                >
                  <span className="flex-1">{p.name}</span>
                  {p.isBuiltin && (
                    <Badge variant="secondary" className="h-4 px-1 text-[10px] bg-[var(--wpi-info)]/10 text-[var(--wpi-info)]">
                      Built-in
                    </Badge>
                  )}
                </DropdownMenuItem>
              ))}
              <DropdownMenuSeparator className="bg-[var(--wpi-border)]" />
              <DropdownMenuItem
                onClick={() => loadProfile("")}
                className="text-sm focus:bg-[var(--wpi-card)] focus:text-[#ef4444] cursor-pointer"
              >
                Clear Profile
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>

          {/* Locale selector */}
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button
                variant="outline"
                size="sm"
                className="h-9 w-9 p-0 bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:bg-[var(--wpi-card)] hover:text-[var(--wpi-text)] hover:border-[var(--wpi-border)] text-xs"
              >
                <Globe className="h-4 w-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent
              align="end"
              className="bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-text)] min-w-[120px]"
            >
              {Object.entries(localeNames).map(([key, name]) => (
                <DropdownMenuItem
                  key={key}
                  onClick={() => setLocale(key as Locale)}
                  className={`text-sm cursor-pointer ${locale === key ? "focus:bg-[var(--wpi-accent)]/10 focus:text-[var(--wpi-accent)]" : "focus:bg-[var(--wpi-card)] focus:text-[var(--wpi-text)]"}`}
                >
                  <span className="flex-1">{name}</span>
                  {locale === key && (
                    <Badge variant="secondary" className="h-4 px-1 text-[10px] bg-[var(--wpi-accent)]/10 text-[var(--wpi-accent)]">
                      Active
                    </Badge>
                  )}
                </DropdownMenuItem>
              ))}
            </DropdownMenuContent>
          </DropdownMenu>

          {/* Theme toggle */}
          <Button
            variant="outline"
            size="sm"
            onClick={toggleTheme}
            className="h-9 w-9 p-0 bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:bg-[var(--wpi-card)] hover:text-[#eab308] hover:border-[#eab308]/30 text-xs"
          >
            {theme === "dark" ? <Sun className="h-4 w-4" /> : <Moon className="h-4 w-4" />}
          </Button>

          {/* Action buttons */}
          <div className="flex items-center gap-2 shrink-0">
            <Button
              variant="outline"
              size="sm"
              onClick={onPreview}
              className="h-9 gap-1.5 bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:bg-[var(--wpi-card)] hover:text-[var(--wpi-text)] hover:border-[var(--wpi-border)] text-xs"
            >
              {t.tabPreview}
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={onUndo}
              className="h-9 gap-1.5 bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)] hover:bg-[var(--wpi-card)] hover:text-[#eab308] hover:border-[#eab308]/30 text-xs"
            >
              <Undo2 className="h-3.5 w-3.5" />
              {t.tabUndo}
            </Button>
            <Button
              size="sm"
              onClick={onApply}
              className="h-9 gap-1.5 bg-[var(--wpi-accent)] hover:bg-[var(--wpi-accent)]/90 text-[var(--wpi-bg)] font-semibold text-xs shadow-[0_0_20px_rgba(0,212,255,0.15)]"
            >
              <Download className="h-3.5 w-3.5" />
              Apply
            </Button>
          </div>
        </div>
      </div>
    </motion.header>
  );
}
