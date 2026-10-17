"use client";

import React from "react";
import { type SafetyLevel } from "@/data/settings";

const safetyConfig: Record<SafetyLevel, { color: string; bg: string; border: string; label: string }> = {
  Safe: { color: "text-[#22c55e]", bg: "bg-[#22c55e]/10", border: "border-[#22c55e]/20", label: "Safe" },
  Moderate: { color: "text-[#eab308]", bg: "bg-[#eab308]/10", border: "border-[#eab308]/20", label: "Moderate" },
  Risky: { color: "text-[#ef4444]", bg: "bg-[#ef4444]/10", border: "border-[#ef4444]/20", label: "Risky" },
};

interface SafetyBadgeProps {
  safety: SafetyLevel;
  compact?: boolean;
}

export function SafetyBadge({ safety, compact = false }: SafetyBadgeProps) {
  const config = safetyConfig[safety];
  if (compact) {
    return (
      <span className={`inline-flex items-center justify-center rounded-full ${config.bg} ${config.border} border ${config.color} font-semibold ${compact ? "h-5 w-5 text-[9px]" : "h-5 px-1.5 text-[10px]"}`}>
        {safety === "Safe" ? "S" : safety === "Moderate" ? "M" : "R"}
      </span>
    );
  }
  return (
    <span className={`inline-flex items-center rounded-md ${config.bg} ${config.border} border px-1.5 py-0.5 ${config.color} text-[10px] font-semibold`}>
      {config.label}
    </span>
  );
}

export function SafetyDot({ safety }: { safety: SafetyLevel }) {
  const config = safetyConfig[safety];
  return <span className={`inline-block h-2 w-2 rounded-full ${config.bg} ${config.border} border`} />;
}
