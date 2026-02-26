"use client";

import { Info } from "lucide-react";

interface TooltipProps {
  /** Tooltip body text */
  content: string;
  /** Optional label shown inline before the info icon */
  children?: React.ReactNode;
  /** Which side the bubble opens on (default: top) */
  side?: "top" | "bottom";
  /** Width class (default: w-60) */
  width?: string;
}

/**
 * Inline tooltip with an Info icon trigger.
 *
 * Usage:
 *   <Tooltip content="Explanation...">Label</Tooltip>
 *   <Tooltip content="Explanation..." />   // icon-only
 */
export function Tooltip({ content, children, side = "top", width = "w-60" }: TooltipProps) {
  const bubblePos =
    side === "top"
      ? "bottom-full mb-2"
      : "top-full mt-2";

  const arrowPos =
    side === "top"
      ? "top-full border-t-[#0d1117]"
      : "bottom-full border-b-[#0d1117]";

  return (
    <span className="relative group inline-flex items-center gap-1 cursor-default">
      {children}
      <Info className="w-3 h-3 text-slate-500 group-hover:text-indigo-400 transition-colors cursor-help flex-shrink-0" />

      {/* Bubble */}
      <span
        className={`absolute left-1/2 -translate-x-1/2 ${bubblePos} ${width}
          p-2.5 rounded-lg bg-[#0d1117] border border-indigo-500/20 shadow-xl
          text-[11px] text-slate-300 leading-relaxed font-normal
          opacity-0 group-hover:opacity-100 transition-opacity duration-150
          pointer-events-none z-50 whitespace-normal text-left`}
      >
        {content}
        {/* Arrow */}
        <span
          className={`absolute left-1/2 -translate-x-1/2 ${arrowPos}
            border-[5px] border-transparent`}
        />
      </span>
    </span>
  );
}
