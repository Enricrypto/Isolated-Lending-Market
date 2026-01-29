"use client";

import type { SeverityLevel } from "@/types/metrics";
import { getSeverityColor, getSeverityLabel } from "@/lib/severity";

interface SeverityBadgeProps {
  severity: SeverityLevel;
  size?: "sm" | "md" | "lg";
  showLabel?: boolean;
}

export function SeverityBadge({
  severity,
  size = "md",
  showLabel = true,
}: SeverityBadgeProps) {
  const colorClass = getSeverityColor(severity);
  const label = getSeverityLabel(severity);

  const sizeClasses = {
    sm: "px-2 py-0.5 text-xs",
    md: "px-3 py-1 text-sm",
    lg: "px-4 py-2 text-base",
  };

  const dotSizeClasses = {
    sm: "w-2 h-2",
    md: "w-2.5 h-2.5",
    lg: "w-3 h-3",
  };

  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full font-medium text-white ${colorClass} ${sizeClasses[size]}`}
    >
      <span className={`${dotSizeClasses[size]} rounded-full bg-white/30 animate-pulse`} />
      {showLabel && label}
    </span>
  );
}

// Compact version - just the colored dot
export function SeverityDot({ severity, size = "md" }: { severity: SeverityLevel; size?: "sm" | "md" | "lg" }) {
  const colorClass = getSeverityColor(severity);

  const sizeClasses = {
    sm: "w-2 h-2",
    md: "w-3 h-3",
    lg: "w-4 h-4",
  };

  return (
    <span
      className={`inline-block rounded-full ${colorClass} ${sizeClasses[size]}`}
      title={getSeverityLabel(severity)}
    />
  );
}
