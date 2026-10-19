"use client";

import React from "react";
import { motion } from "framer-motion";
import { GitCompare, CheckCircle2, XCircle, Minus } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";
import { sections, type Profile } from "@/data/settings";

interface ProfileComparisonProps {
  profileA: Profile;
  profileB: Profile;
}

export function ProfileComparison({ profileA, profileB }: ProfileComparisonProps) {
  // Build diff across all sections
  const diffSections = sections.map((section) => {
    const diffs = section.settings.map((setting) => {
      const inA = profileA.settings[setting.id] ?? false;
      const inB = profileB.settings[setting.id] ?? false;
      if (inA === inB) return { setting, status: "same" as const, value: inA };
      return { setting, status: "diff" as const, inA, inB };
    });
    const hasDiffs = diffs.some((d) => d.status === "diff");
    return { section, diffs, hasDiffs };
  }).filter((s) => s.hasDiffs);

  // Summary stats
  const totalDiffs = diffSections.reduce((sum, s) => sum + s.diffs.filter((d) => d.status === "diff").length, 0);
  const onlyA = diffSections.reduce((sum, s) => sum + s.diffs.filter((d) => d.status === "diff" && d.inA && !d.inB).length, 0);
  const onlyB = diffSections.reduce((sum, s) => sum + s.diffs.filter((d) => d.status === "diff" && !d.inA && d.inB).length, 0);

  // Software diff
  const softwareOnlyA = profileA.software.filter((s) => !profileB.software.includes(s));
  const softwareOnlyB = profileB.software.filter((s) => !profileA.software.includes(s));

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <GitCompare className="h-4 w-4 text-[#00d4ff]" />
          <span className="text-sm font-semibold text-[#e0e0e0]">Profile Comparison</span>
        </div>
        <Badge className="bg-[#00d4ff]/10 text-[#00d4ff] border-[#00d4ff]/20 text-xs">
          {totalDiffs} differences
        </Badge>
      </div>

      {/* Legend */}
      <div className="flex items-center gap-4 text-xs text-[#8888a0]">
        <div className="flex items-center gap-1.5">
          <div className="h-2 w-2 rounded-full bg-[#22c55e]" />
          <span>Only in {profileA.name} ({onlyA})</span>
        </div>
        <div className="flex items-center gap-1.5">
          <div className="h-2 w-2 rounded-full bg-[#00d4ff]" />
          <span>Only in {profileB.name} ({onlyB})</span>
        </div>
      </div>

      {/* Setting diffs by section */}
      <ScrollArea className="max-h-[calc(100vh-420px)]">
        <div className="space-y-3">
          {diffSections.map(({ section, diffs }) => (
            <div key={section.id} className="rounded-lg border border-[#2a2a3e] bg-[#1a1a2e] overflow-hidden">
              <div className="px-3 py-2 border-b border-[#2a2a3e] bg-[#12121a]">
                <span className="text-xs font-semibold text-[#e0e0e0]">{section.name}</span>
              </div>
              <div className="divide-y divide-[#2a2a3e]/50">
                {diffs.filter((d) => d.status === "diff").map(({ setting, inA, inB }) => (
                  <div key={setting.id} className="flex items-center gap-3 px-3 py-2">
                    <span className="text-xs text-[#e0e0e0] flex-1">{setting.name}</span>
                    <div className="flex items-center gap-2 shrink-0">
                      <div className={`flex items-center gap-1 ${inA ? "text-[#22c55e]" : "text-[#8888a0]/30"}`}>
                        {inA ? <CheckCircle2 className="h-3 w-3" /> : <XCircle className="h-3 w-3" />}
                        <span className="text-[9px] w-12 text-right">{profileA.name.slice(0, 8)}</span>
                      </div>
                      <Minus className="h-3 w-3 text-[#2a2a3e]" />
                      <div className={`flex items-center gap-1 ${inB ? "text-[#00d4ff]" : "text-[#8888a0]/30"}`}>
                        <span className="text-[9px] w-12">{profileB.name.slice(0, 8)}</span>
                        {inB ? <CheckCircle2 className="h-3 w-3" /> : <XCircle className="h-3 w-3" />}
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ))}

          {/* Software diff */}
          {(softwareOnlyA.length > 0 || softwareOnlyB.length > 0) && (
            <div className="rounded-lg border border-[#2a2a3e] bg-[#1a1a2e] overflow-hidden">
              <div className="px-3 py-2 border-b border-[#2a2a3e] bg-[#12121a]">
                <span className="text-xs font-semibold text-[#e0e0e0]">Software Differences</span>
              </div>
              <div className="p-3 space-y-2 text-xs">
                {softwareOnlyA.length > 0 && (
                  <div>
                    <span className="text-[#22c55e] font-medium">Only in {profileA.name}:</span>
                    <span className="text-[#8888a0] ml-2">{softwareOnlyA.join(", ")}</span>
                  </div>
                )}
                {softwareOnlyB.length > 0 && (
                  <div>
                    <span className="text-[#00d4ff] font-medium">Only in {profileB.name}:</span>
                    <span className="text-[#8888a0] ml-2">{softwareOnlyB.join(", ")}</span>
                  </div>
                )}
              </div>
            </div>
          )}

          {diffSections.length === 0 && softwareOnlyA.length === 0 && softwareOnlyB.length === 0 && (
            <div className="py-12 text-center">
              <p className="text-sm text-[#8888a0]">Profiles are identical</p>
            </div>
          )}
        </div>
      </ScrollArea>
    </div>
  );
}
