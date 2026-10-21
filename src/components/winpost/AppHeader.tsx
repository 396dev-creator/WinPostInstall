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

          {/* Actions — Apple-style grouped, prominent CTA */}
          <div className="flex items-center gap-1.5 shrink-0">
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
              onClick={onApply}
              className="h-8 gap-1.5 bg-[var(--wpi-accent)] hover:bg-[var(--wpi-accent)]/90 text-[var(--wpi-accent-foreground)] font-semibold text-xs shadow-[var(--wpi-accent-glow)]"
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
