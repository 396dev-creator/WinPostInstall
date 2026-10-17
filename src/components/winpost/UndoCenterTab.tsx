"use client";

import React from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Undo2, Trash2, Clock } from "lucide-react";
import { Button } from "@/components/ui/button";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Badge } from "@/components/ui/badge";
import { useAppStore } from "@/store/useAppStore";

export function UndoCenterTab() {
  const { undoLog, undoChange, undoAll } = useAppStore();

  const formatTime = (date: string) => {
    const d = new Date(date);
    return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  };

  const formatDate = (date: string) => {
    const d = new Date(date);
    return d.toLocaleDateString([], { month: "short", day: "numeric" });
  };

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h2 className="text-base font-semibold text-[#e0e0e0]">Undo Center</h2>
          <p className="text-xs text-[#8888a0]">
            Review and undo individual changes
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Badge className="bg-[#eab308]/10 text-[#eab308] border-[#eab308]/20 text-xs">
            {undoLog.length} changes
          </Badge>
          {undoLog.length > 0 && (
            <Button
              size="sm"
              variant="outline"
              onClick={undoAll}
              className="h-8 gap-1.5 bg-[#ef4444]/5 border-[#ef4444]/20 text-[#ef4444] hover:bg-[#ef4444]/10 hover:text-[#ef4444] text-xs"
            >
              <Trash2 className="h-3.5 w-3.5" />
              Undo All
            </Button>
          )}
        </div>
      </div>

      {/* Undo log */}
      {undoLog.length === 0 ? (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          className="flex flex-col items-center justify-center py-16 text-center"
        >
          <div className="h-16 w-16 rounded-2xl bg-[#12121a] border border-[#2a2a3e] flex items-center justify-center mb-4">
            <Undo2 className="h-8 w-8 text-[#8888a0]/50" />
          </div>
          <p className="text-sm text-[#8888a0] mb-1">No changes to undo</p>
          <p className="text-xs text-[#8888a0]/50">Toggle settings to start making changes</p>
        </motion.div>
      ) : (
        <ScrollArea className="max-h-[calc(100vh-320px)]">
          <div className="space-y-2 p-1">
            <AnimatePresence>
              {undoLog.map((entry, index) => (
                <motion.div
                  key={entry.id}
                  initial={{ opacity: 0, x: -20 }}
                  animate={{ opacity: 1, x: 0 }}
                  exit={{ opacity: 0, x: 20, height: 0 }}
                  transition={{ delay: index * 0.02 }}
                  className="flex items-center gap-3 p-3 rounded-lg bg-[#1a1a2e] border border-[#2a2a3e] group hover:border-[#2a2a3e]/80 transition-colors"
                >
                  <div className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-lg ${
                    entry.action === "enabled"
                      ? "bg-[#22c55e]/10 border border-[#22c55e]/20"
                      : "bg-[#ef4444]/10 border border-[#ef4444]/20"
                  }`}>
                    <Undo2 className={`h-4 w-4 ${
                      entry.action === "enabled" ? "text-[#22c55e]" : "text-[#ef4444]"
                    }`} />
                  </div>

                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-medium text-[#e0e0e0] truncate">
                        {entry.settingName}
                      </span>
                      <Badge
                        variant="outline"
                        className={`h-4 px-1 text-[9px] shrink-0 ${
                          entry.action === "enabled"
                            ? "bg-[#22c55e]/5 border-[#22c55e]/20 text-[#22c55e]"
                            : "bg-[#ef4444]/5 border-[#ef4444]/20 text-[#ef4444]"
                        }`}
                      >
                        {entry.action === "enabled" ? "Enabled" : "Disabled"}
                      </Badge>
                    </div>
                    <div className="flex items-center gap-2 mt-0.5">
                      <span className="text-[11px] text-[#8888a0]/70">{entry.sectionName}</span>
                      <span className="text-[11px] text-[#8888a0]/40">•</span>
                      <span className="text-[11px] text-[#8888a0]/50">
                        <Clock className="h-3 w-3 inline mr-0.5" />
                        {formatDate(entry.timestamp)} {formatTime(entry.timestamp)}
                      </span>
                    </div>
                  </div>

                  <Button
                    size="sm"
                    variant="outline"
                    onClick={() => undoChange(entry.id)}
                    className="h-7 gap-1 text-[10px] shrink-0 bg-[#12121a] border-[#2a2a3e] text-[#eab308] hover:bg-[#eab308]/10 hover:text-[#eab308] hover:border-[#eab308]/30"
                  >
                    <Undo2 className="h-3 w-3" />
                    Undo
                  </Button>
                </motion.div>
              ))}
            </AnimatePresence>
          </div>
        </ScrollArea>
      )}
    </div>
  );
}
