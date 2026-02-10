"use client";

import type { VaultConfig, SeverityLevel } from "@/types/metrics";
import { SeverityDot } from "./SeverityBadge";
import { ChevronDown } from "lucide-react";
import { useState, useRef, useEffect } from "react";

interface VaultSelectorProps {
  vaults: VaultConfig[];
  selected: string;
  onSelect: (address: string) => void;
  severities?: Map<string, SeverityLevel>;
}

export function VaultSelector({
  vaults,
  selected,
  onSelect,
  severities,
}: VaultSelectorProps) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  const current = vaults.find(
    (v) => v.vaultAddress.toLowerCase() === selected.toLowerCase()
  );

  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, []);

  return (
    <div ref={ref} className="relative">
      <button
        onClick={() => setOpen(!open)}
        className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-midnight-800/60 border border-midnight-700/50 hover:border-midnight-600/50 transition-colors text-sm"
      >
        {severities && current && (
          <SeverityDot
            severity={severities.get(current.vaultAddress) ?? 0}
            size="sm"
          />
        )}
        <span className="font-medium text-white">
          {current?.label ?? "Select Market"}
        </span>
        <span className="text-slate-500 text-xs">
          {current?.vaultAddress.slice(0, 6)}...{current?.vaultAddress.slice(-4)}
        </span>
        <ChevronDown
          className={`w-4 h-4 text-slate-400 transition-transform ${open ? "rotate-180" : ""}`}
        />
      </button>

      {open && (
        <div className="absolute top-full left-0 mt-1 w-72 rounded-lg bg-midnight-900 border border-midnight-700/50 shadow-xl z-50 overflow-hidden">
          {vaults.map((vault) => {
            const isActive =
              vault.vaultAddress.toLowerCase() === selected.toLowerCase();
            return (
              <button
                key={vault.vaultAddress}
                onClick={() => {
                  onSelect(vault.vaultAddress);
                  setOpen(false);
                }}
                className={`w-full flex items-center gap-3 px-4 py-2.5 text-left hover:bg-midnight-800/60 transition-colors ${
                  isActive ? "bg-midnight-800/40" : ""
                }`}
              >
                {severities && (
                  <SeverityDot
                    severity={severities.get(vault.vaultAddress) ?? 0}
                    size="sm"
                  />
                )}
                <div className="flex-1 min-w-0">
                  <div className="text-sm font-medium text-white">
                    {vault.label}
                  </div>
                  <div className="text-xs text-slate-500">
                    {vault.symbol}
                  </div>
                </div>
                <span className="text-xs text-slate-600 font-mono">
                  {vault.vaultAddress.slice(0, 6)}...{vault.vaultAddress.slice(-4)}
                </span>
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}
