"use client";

import React from "react";
import { type SafetyLevel } from "@/data/settings";

const safetyConfig: Record<SafetyLevel, { color: string; bg: string; border: string; label: string }> = {
  Safe: { color: "text-[var(--wpi-safe)]", bg: "bg-[var(--wpi-safe-10)]", border: "border-[var(--wpi-safe-20)]", label: "Safe" },
  Moderate: { color: "text-[var(--wpi-moderate)]", bg: "bg-[var(--wpi-moderate-10)]", border: "border-[var(--wpi-moderate-20)]", label: "Moderate" },
  Risky: { color: "text-[var(--wpi-risky)]", bg: "bg-[var(--wpi-risky-10)]", border: "border-[var(--wpi-risky-20)]", label: "Risky" },
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
