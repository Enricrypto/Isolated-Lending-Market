"use client";

import Link from "next/link";
import type { SeverityLevel } from "@/types/metrics";
import { Droplets, TrendingUp, Eye, Zap, LucideIcon } from "lucide-react";

interface RiskMetricCardProps {
  title: string;
  subtitle: string;
  value: string;
  valueLabel: string;
  severity: SeverityLevel;
  stats: { label: string; value: string; highlight?: boolean }[];
  href?: string;
  sparklineColor: "emerald" | "amber" | "cyan" | "red";
  sparklinePath: string;
  icon: "liquidity" | "rates" | "oracle" | "velocity";
}

const severityConfig: Record<SeverityLevel, { label: string; bgClass: string; textClass: string }> = {
  0: { label: "Healthy", bgClass: "bg-emerald-500/10", textClass: "text-emerald-400" },
  1: { label: "Elevated", bgClass: "bg-amber-500/10", textClass: "text-amber-400" },
  2: { label: "Critical", bgClass: "bg-orange-500/10", textClass: "text-orange-400" },
  3: { label: "Emergency", bgClass: "bg-red-500/10", textClass: "text-red-400" },
};

const iconConfig: Record<string, { Icon: LucideIcon; gradient: string; border: string; text: string }> = {
  liquidity: {
    Icon: Droplets,
    gradient: "from-indigo-500/10 to-purple-500/10",
    border: "border-indigo-500/20",
    text: "text-indigo-400",
  },
  rates: {
    Icon: TrendingUp,
    gradient: "from-amber-500/10 to-orange-500/10",
    border: "border-amber-500/20",
    text: "text-amber-400",
  },
  oracle: {
    Icon: Eye,
    gradient: "from-cyan-500/10 to-blue-500/10",
    border: "border-cyan-500/20",
    text: "text-cyan-400",
  },
  velocity: {
    Icon: Zap,
    gradient: "from-red-500/10 to-pink-500/10",
    border: "border-red-500/20",
    text: "text-red-400",
  },
};

const sparklineColors = {
  emerald: { stroke: "#34d399", fill: "url(#gradEmerald)" },
  amber: { stroke: "#fbbf24", fill: "url(#gradAmber)" },
  cyan: { stroke: "#64748b", fill: "none" },
  red: { stroke: "#ef4444", fill: "url(#gradRed)" },
};

export function RiskMetricCard({
  title,
  subtitle,
  value,
  valueLabel,
  severity,
  stats,
  href,
  sparklineColor,
  sparklinePath,
  icon,
}: RiskMetricCardProps) {
  const severityInfo = severityConfig[severity];
  const iconInfo = iconConfig[icon];
  const Icon = iconInfo.Icon;
  const colors = sparklineColors[sparklineColor];

  const hoverBorderClass =
    sparklineColor === "emerald"
      ? "hover:border-emerald-500/40"
      : sparklineColor === "amber"
      ? "hover:border-amber-500/40"
      : sparklineColor === "cyan"
      ? "hover:border-indigo-500/40"
      : "hover:border-red-500/40";

  const content = (
    <div
      className={`group relative glass-panel rounded-2xl p-6 ${hoverBorderClass} transition-all duration-300 hover:shadow-[0_0_30px_rgba(79,70,229,0.1)]`}
    >
      {/* Header */}
      <div className="flex items-start justify-between mb-5">
        <div className="flex items-center gap-4">
          <div
            className={`w-10 h-10 rounded-xl bg-gradient-to-br ${iconInfo.gradient} border ${iconInfo.border} flex items-center justify-center ${iconInfo.text} group-hover:text-white group-hover:bg-gradient-to-br group-hover:from-indigo-500 group-hover:to-purple-500 transition-all duration-300 shadow-inner`}
          >
            <Icon className="w-5 h-5" />
          </div>
          <div>
            <h3 className="text-sm font-semibold text-white tracking-wide">{title}</h3>
            <p className="text-[10px] uppercase tracking-wider text-slate-500 font-medium">
              {subtitle}
            </p>
          </div>
        </div>
        <span
          className={`inline-flex items-center px-2.5 py-1 rounded-md text-[10px] font-bold uppercase tracking-wide ${severityInfo.bgClass} ${severityInfo.textClass} border ${severityInfo.bgClass.replace("/10", "/20")} shadow-[0_0_10px_rgba(52,211,153,0.1)]`}
        >
          {severityInfo.label}
        </span>
      </div>

      {/* Value */}
      <div className="flex items-baseline gap-2 mb-2">
        <span className="text-3xl font-bold tracking-tight text-white drop-shadow-md">
          {value}
        </span>
        <span className="text-xs font-medium text-slate-500">{valueLabel}</span>
      </div>

      {/* Stats */}
      <div className="flex items-center gap-4 text-xs text-slate-500 mb-6">
        {stats.map((stat, index) => (
          <span key={stat.label} className="flex items-center gap-1.5">
            {index > 0 && <span className="w-1 h-1 rounded-full bg-slate-700 mr-2" />}
            {stat.label}:{" "}
            <span className={stat.highlight ? `${severityInfo.textClass} font-semibold` : "text-slate-200 font-semibold"}>
              {stat.value}
            </span>
          </span>
        ))}
      </div>

      {/* Sparkline */}
      <div className="h-16 w-full -mb-2">
        <svg
          className="w-full h-full sparkline overflow-visible"
          viewBox="0 0 100 40"
          preserveAspectRatio="none"
        >
          <defs>
            <linearGradient id="gradEmerald" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#34d399" stopOpacity="0.2" />
              <stop offset="100%" stopColor="#34d399" stopOpacity="0" />
            </linearGradient>
            <linearGradient id="gradAmber" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#fbbf24" stopOpacity="0.2" />
              <stop offset="100%" stopColor="#fbbf24" stopOpacity="0" />
            </linearGradient>
            <linearGradient id="gradRed" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#ef4444" stopOpacity="0.2" />
              <stop offset="100%" stopColor="#ef4444" stopOpacity="0" />
            </linearGradient>
          </defs>
          <path
            d={sparklinePath}
            fill="none"
            stroke={colors.stroke}
            strokeWidth="2"
            vectorEffect="non-scaling-stroke"
            filter={`drop-shadow(0 0 4px ${colors.stroke}40)`}
          />
          {colors.fill !== "none" && (
            <path
              d={`${sparklinePath} V40 H0 Z`}
              fill={colors.fill}
              stroke="none"
            />
          )}
        </svg>
      </div>
    </div>
  );

  if (href) {
    return <Link href={href}>{content}</Link>;
  }

  return content;
}
