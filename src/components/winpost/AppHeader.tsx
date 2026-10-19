"use client";

import React from "react";
import { motion } from "framer-motion";
import { Search, Download, Undo2, Terminal, ChevronDown, Sun, Moon, Globe } from "lucide-react";
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
  const { searchQuery, setSearchQuery, profiles, activeProfileId, loadProfile } = useAppStore();
  const { theme, toggleTheme } = useTheme();
  const { locale, setLocale, t } = useI18n();

  const activeProfile = profiles.find((p) => p.id === activeProfileId);

  return (
    <motion.header
      initial={{ y: -20, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      className="sticky top-0 z-40 border-b border-[#2a2a3e] bg-[#0a0a0f]/95 backdrop-blur-md"
    >
      <div className="mx-auto max-w-7xl px-4 py-3">
        <div className="flex items-center gap-3 flex-wrap">
          {/* Logo / Title */}
          <div className="flex items-center gap-2 shrink-0">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-[#00d4ff]/10 border border-[#00d4ff]/20">
              <Terminal className="h-5 w-5 text-[#00d4ff]" />
            </div>
            <div className="hidden sm:block">
              <h1 className="text-lg font-bold text-[#e0e0e0] leading-none">
                Win<span className="text-[#00d4ff]">PostInstall</span>
              </h1>
              <p className="text-[10px] text-[#8888a0] leading-none mt-0.5">{t.appVersion}</p>
            </div>
          </div>

          {/* Search */}
          <div className="relative flex-1 min-w-[180px] max-w-md">
            <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-4 w-4 text-[#8888a0]" />
            <Input
              placeholder="Search settings..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-9 h-9 bg-[#12121a] border-[#2a2a3e] text-[#e0e0e0] placeholder:text-[#8888a0] focus-visible:ring-[#00d4ff]/30 focus-visible:border-[#00d4ff]/50 text-sm"
            />
          </div>

          {/* Profile selector */}
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button
                variant="outline"
                size="sm"
                className="h-9 gap-2 bg-[#12121a] border-[#2a2a3e] text-[#e0e0e0] hover:bg-[#1a1a2e] hover:border-[#00d4ff]/30 text-xs"
              >
                <span className="truncate max-w-[100px]">
                  {activeProfile ? activeProfile.name : "No Profile"}
                </span>
                {activeProfile && (
                  <Badge variant="secondary" className="h-4 px-1 text-[10px] bg-[#00d4ff]/10 text-[#00d4ff] border-[#00d4ff]/20">
                    Active
                  </Badge>
                )}
                <ChevronDown className="h-3 w-3" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent
              align="end"
              className="bg-[#12121a] border-[#2a2a3e] text-[#e0e0e0] min-w-[200px]"
            >
              {profiles.map((p) => (
                <DropdownMenuItem
                  key={p.id}
                  onClick={() => loadProfile(p.id)}
                  className="text-sm focus:bg-[#1a1a2e] focus:text-[#00d4ff] cursor-pointer"
                >
                  <span className="flex-1">{p.name}</span>
                  {p.isBuiltin && (
                    <Badge variant="secondary" className="h-4 px-1 text-[10px] bg-[#0ea5e9]/10 text-[#0ea5e9]">
                      Built-in
                    </Badge>
                  )}
                </DropdownMenuItem>
              ))}
              <DropdownMenuSeparator className="bg-[#2a2a3e]" />
              <DropdownMenuItem
                onClick={() => loadProfile("")}
                className="text-sm focus:bg-[#1a1a2e] focus:text-[#ef4444] cursor-pointer"
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
                className="h-9 w-9 p-0 bg-[#12121a] border-[#2a2a3e] text-[#8888a0] hover:bg-[#1a1a2e] hover:text-[#e0e0e0] hover:border-[#2a2a3e] text-xs"
              >
                <Globe className="h-4 w-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent
              align="end"
              className="bg-[#12121a] border-[#2a2a3e] text-[#e0e0e0] min-w-[120px]"
            >
              {Object.entries(localeNames).map(([key, name]) => (
                <DropdownMenuItem
                  key={key}
                  onClick={() => setLocale(key as Locale)}
                  className={`text-sm cursor-pointer ${locale === key ? "focus:bg-[#00d4ff]/10 focus:text-[#00d4ff]" : "focus:bg-[#1a1a2e] focus:text-[#e0e0e0]"}`}
                >
                  <span className="flex-1">{name}</span>
                  {locale === key && (
                    <Badge variant="secondary" className="h-4 px-1 text-[10px] bg-[#00d4ff]/10 text-[#00d4ff]">
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
            className="h-9 w-9 p-0 bg-[#12121a] border-[#2a2a3e] text-[#8888a0] hover:bg-[#1a1a2e] hover:text-[#eab308] hover:border-[#eab308]/30 text-xs"
          >
            {theme === "dark" ? <Sun className="h-4 w-4" /> : <Moon className="h-4 w-4" />}
          </Button>

          {/* Action buttons */}
          <div className="flex items-center gap-2 shrink-0">
            <Button
              variant="outline"
              size="sm"
              onClick={onPreview}
              className="h-9 gap-1.5 bg-[#12121a] border-[#2a2a3e] text-[#8888a0] hover:bg-[#1a1a2e] hover:text-[#e0e0e0] hover:border-[#2a2a3e] text-xs"
            >
              {t.tabPreview}
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={onUndo}
              className="h-9 gap-1.5 bg-[#12121a] border-[#2a2a3e] text-[#8888a0] hover:bg-[#1a1a2e] hover:text-[#eab308] hover:border-[#eab308]/30 text-xs"
            >
              <Undo2 className="h-3.5 w-3.5" />
              {t.tabUndo}
            </Button>
            <Button
              size="sm"
              onClick={onApply}
              className="h-9 gap-1.5 bg-[#00d4ff] hover:bg-[#00d4ff]/90 text-[#0a0a0f] font-semibold text-xs shadow-[0_0_20px_rgba(0,212,255,0.15)]"
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
