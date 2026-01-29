"use client";

import Link from "next/link";
import type { SeverityLevel } from "@/types/metrics";
import { SeverityBadge } from "./SeverityBadge";
import { getSeverityBorderColor } from "@/lib/severity";
import { ArrowUpRight } from "lucide-react";

interface MetricCardProps {
  title: string;
  value: string | number;
  unit?: string;
  severity: SeverityLevel;
  subtitle?: string;
  href?: string;
  trend?: "up" | "down" | "stable";
  trendValue?: string;
}

export function MetricCard({
  title,
  value,
  unit,
  severity,
  subtitle,
  href,
  trend,
  trendValue,
}: MetricCardProps) {
  const borderColor = getSeverityBorderColor(severity);

  const content = (
    <div
      className={`relative rounded-xl border-2 ${borderColor} bg-white dark:bg-gray-800 p-6 shadow-sm hover:shadow-md transition-shadow`}
    >
      {/* Header */}
      <div className="flex items-start justify-between mb-4">
        <h3 className="text-sm font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wide">
          {title}
        </h3>
        <SeverityBadge severity={severity} size="sm" />
      </div>

      {/* Value */}
      <div className="flex items-baseline gap-2">
        <span className="text-3xl font-bold text-gray-900 dark:text-white">
          {typeof value === "number" ? value.toLocaleString() : value}
        </span>
        {unit && (
          <span className="text-lg text-gray-500 dark:text-gray-400">{unit}</span>
        )}
      </div>

      {/* Subtitle / Trend */}
      {(subtitle || trend) && (
        <div className="mt-2 flex items-center gap-2 text-sm">
          {trend && (
            <span
              className={`flex items-center ${
                trend === "up"
                  ? "text-green-500"
                  : trend === "down"
                  ? "text-red-500"
                  : "text-gray-400"
              }`}
            >
              {trend === "up" && "↑"}
              {trend === "down" && "↓"}
              {trend === "stable" && "→"}
              {trendValue && <span className="ml-1">{trendValue}</span>}
            </span>
          )}
          {subtitle && (
            <span className="text-gray-500 dark:text-gray-400">{subtitle}</span>
          )}
        </div>
      )}

      {/* Link indicator */}
      {href && (
        <div className="absolute top-4 right-12">
          <ArrowUpRight className="w-4 h-4 text-gray-400" />
        </div>
      )}
    </div>
  );

  if (href) {
    return (
      <Link href={href} className="block">
        {content}
      </Link>
    );
  }

  return content;
}
