"use client";

import React, { useState } from "react";
import { motion } from "framer-motion";
import { Search } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Checkbox } from "@/components/ui/checkbox";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";
import { softwareApps, softwareCategories } from "@/data/settings";
import { useAppStore } from "@/store/useAppStore";

export function SoftwareInstallTab() {
  const { selectedSoftware, toggleSoftware } = useAppStore();
  const [searchQuery, setSearchQuery] = useState("");
  const [activeCategory, setActiveCategory] = useState<string | null>(null);

  const filteredApps = softwareApps.filter((app) => {
    const matchesSearch = !searchQuery || 
      app.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
      app.desc.toLowerCase().includes(searchQuery.toLowerCase());
    const matchesCategory = !activeCategory || app.category === activeCategory;
    return matchesSearch && matchesCategory;
  });

  const categoryCounts = softwareCategories.map((cat) => ({
    name: cat,
    count: softwareApps.filter((a) => a.category === cat).length,
    selected: softwareApps.filter((a) => a.category === cat && selectedSoftware.includes(a.id)).length,
  }));

  const totalSelected = selectedSoftware.length;

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h2 className="text-base font-semibold text-[var(--wpi-text)]">Software Installation</h2>
          <p className="text-xs text-[var(--wpi-muted)]">
            Select applications to install via Winget package manager
          </p>
        </div>
        <Badge className="bg-[var(--wpi-accent)]/10 text-[var(--wpi-accent)] border-[var(--wpi-accent)]/20 text-xs">
          {totalSelected} selected
        </Badge>
      </div>

      {/* Search + Category filters */}
      <div className="flex gap-3 flex-wrap">
        <div className="relative flex-1 min-w-[180px] max-w-sm">
          <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-4 w-4 text-[var(--wpi-muted)]" />
          <Input
            placeholder="Search software..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="pl-9 h-9 bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-text)] placeholder:text-[var(--wpi-muted)] focus-visible:ring-[var(--wpi-accent)]/30 focus-visible:border-[var(--wpi-accent)]/50 text-sm"
          />
        </div>
        <div className="flex gap-1.5 flex-wrap">
          <button
            onClick={() => setActiveCategory(null)}
            className={`h-9 px-3 rounded-lg text-xs font-medium transition-colors ${
              activeCategory === null
                ? "bg-[var(--wpi-accent)]/10 text-[var(--wpi-accent)] border border-[var(--wpi-accent)]/20"
                : "bg-[var(--wpi-deep)] text-[var(--wpi-muted)] border border-[var(--wpi-border)] hover:bg-[var(--wpi-card)]"
            }`}
          >
            All
          </button>
          {softwareCategories.map((cat) => (
            <button
              key={cat}
              onClick={() => setActiveCategory(activeCategory === cat ? null : cat)}
              className={`h-9 px-3 rounded-lg text-xs font-medium transition-colors ${
                activeCategory === cat
                  ? "bg-[var(--wpi-accent)]/10 text-[var(--wpi-accent)] border border-[var(--wpi-accent)]/20"
                  : "bg-[var(--wpi-deep)] text-[var(--wpi-muted)] border border-[var(--wpi-border)] hover:bg-[var(--wpi-card)]"
              }`}
            >
              {cat}
            </button>
          ))}
        </div>
      </div>

      {/* App grid */}
      <ScrollArea className="max-h-[calc(100vh-320px)]">
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 p-1">
          {filteredApps.map((app, index) => {
            const isSelected = selectedSoftware.includes(app.id);
            return (
              <motion.div
                key={app.id}
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: index * 0.02 }}
                onClick={() => toggleSoftware(app.id)}
                className={`flex items-center gap-3 p-3 rounded-lg cursor-pointer transition-all border ${
                  isSelected
                    ? "bg-[var(--wpi-accent)]/5 border-[var(--wpi-accent)]/20"
                    : "bg-[var(--wpi-deep)] border-[var(--wpi-border)] hover:border-[var(--wpi-border)]/80 hover:bg-[var(--wpi-card)]/50"
                }`}
              >
                <Checkbox
                  checked={isSelected}
                  onCheckedChange={() => toggleSoftware(app.id)}
                  className="border-[var(--wpi-border)] data-[state=checked]:bg-[var(--wpi-accent)] data-[state=checked]:border-[var(--wpi-accent)]"
                />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className={`text-sm font-medium ${isSelected ? "text-[var(--wpi-text)]" : "text-[var(--wpi-muted)]"}`}>
                      {app.name}
                    </span>
                    <Badge variant="outline" className="h-4 px-1 text-[9px] bg-[var(--wpi-deep)] border-[var(--wpi-border)] text-[var(--wpi-muted)]">
                      {app.category}
                    </Badge>
                  </div>
                  <p className="text-[11px] text-[var(--wpi-muted)]/70 truncate">{app.desc}</p>
                  <p className="text-[10px] text-[var(--wpi-muted)]/40 font-mono truncate">{app.wingetId}</p>
                </div>
              </motion.div>
            );
          })}
        </div>
      </ScrollArea>
    </div>
  );
}
