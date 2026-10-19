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
          <h2 className="text-base font-semibold text-[#e0e0e0]">Software Installation</h2>
          <p className="text-xs text-[#8888a0]">
            Select applications to install via Winget package manager
          </p>
        </div>
        <Badge className="bg-[#00d4ff]/10 text-[#00d4ff] border-[#00d4ff]/20 text-xs">
          {totalSelected} selected
        </Badge>
      </div>

      {/* Search + Category filters */}
      <div className="flex gap-3 flex-wrap">
        <div className="relative flex-1 min-w-[180px] max-w-sm">
          <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-4 w-4 text-[#8888a0]" />
          <Input
            placeholder="Search software..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="pl-9 h-9 bg-[#12121a] border-[#2a2a3e] text-[#e0e0e0] placeholder:text-[#8888a0] focus-visible:ring-[#00d4ff]/30 focus-visible:border-[#00d4ff]/50 text-sm"
          />
        </div>
        <div className="flex gap-1.5 flex-wrap">
          <button
            onClick={() => setActiveCategory(null)}
            className={`h-9 px-3 rounded-lg text-xs font-medium transition-colors ${
              activeCategory === null
                ? "bg-[#00d4ff]/10 text-[#00d4ff] border border-[#00d4ff]/20"
                : "bg-[#12121a] text-[#8888a0] border border-[#2a2a3e] hover:bg-[#1a1a2e]"
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
                  ? "bg-[#00d4ff]/10 text-[#00d4ff] border border-[#00d4ff]/20"
                  : "bg-[#12121a] text-[#8888a0] border border-[#2a2a3e] hover:bg-[#1a1a2e]"
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
                    ? "bg-[#00d4ff]/5 border-[#00d4ff]/20"
                    : "bg-[#12121a] border-[#2a2a3e] hover:border-[#2a2a3e]/80 hover:bg-[#1a1a2e]/50"
                }`}
              >
                <Checkbox
                  checked={isSelected}
                  onCheckedChange={() => toggleSoftware(app.id)}
                  className="border-[#2a2a3e] data-[state=checked]:bg-[#00d4ff] data-[state=checked]:border-[#00d4ff]"
                />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className={`text-sm font-medium ${isSelected ? "text-[#e0e0e0]" : "text-[#8888a0]"}`}>
                      {app.name}
                    </span>
                    <Badge variant="outline" className="h-4 px-1 text-[9px] bg-[#12121a] border-[#2a2a3e] text-[#8888a0]">
                      {app.category}
                    </Badge>
                  </div>
                  <p className="text-[11px] text-[#8888a0]/70 truncate">{app.desc}</p>
                  <p className="text-[10px] text-[#8888a0]/40 font-mono truncate">{app.wingetId}</p>
                </div>
              </motion.div>
            );
          })}
        </div>
      </ScrollArea>
    </div>
  );
}
