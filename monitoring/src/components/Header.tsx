"use client";

import { useEffect, useState } from "react";
import { Bell, RotateCcw, ChevronRight, Menu } from "lucide-react";
import type { SeverityLevel, CurrentMetricsResponse } from "@/types/metrics";

interface HeaderProps {
  title: string;
  breadcrumb?: string;
}

const severityLabels: Record<SeverityLevel, { label: string; color: string }> = {
  0: { label: "System Normal", color: "emerald" },
  1: { label: "Elevated Risk", color: "amber" },
  2: { label: "Critical", color: "orange" },
  3: { label: "Emergency", color: "red" },
};

export function Header({ title, breadcrumb = "Risk Overview" }: HeaderProps) {
  const [metrics, setMetrics] = useState<CurrentMetricsResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const fetchMetrics = async () => {
    try {
      const response = await fetch("/api/metrics");
      if (response.ok) {
        const data = await response.json();
        setMetrics(data);
      }
    } catch (error) {
      console.error("Failed to fetch metrics:", error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchMetrics();
    const interval = setInterval(fetchMetrics, 5 * 60 * 1000);
    return () => clearInterval(interval);
  }, []);

  const handleRefresh = async () => {
    setRefreshing(true);
    await fetchMetrics();
    setRefreshing(false);
  };

  const severity = metrics?.overall ?? 0;
  const statusInfo = severityLabels[severity as SeverityLevel];

  return (
    <header className="h-20 border-b border-midnight-700/50 flex items-center justify-between px-4 sm:px-8 bg-midnight-950/80 backdrop-blur-md sticky top-0 z-40 w-full">
      <div className="flex items-center gap-4">
        <button className="md:hidden p-2 text-slate-400 hover:text-white">
          <Menu className="w-6 h-6" />
        </button>
        <div className="flex items-center gap-2 text-sm text-slate-400">
          <span className="hover:text-white cursor-pointer transition-colors">
            Dashboard
          </span>
          <ChevronRight className="w-4 h-4 text-slate-600" />
          <span className="text-white font-medium">{breadcrumb}</span>
        </div>
      </div>

      <div className="flex items-center gap-4">
        {/* Status Badge */}
        {!loading && (
          <div
            className={`flex items-center gap-2 px-3 py-1.5 rounded-full bg-${statusInfo.color}-500/5 border border-${statusInfo.color}-500/20 shadow-[0_0_10px_rgba(16,185,129,0.1)]`}
            style={{
              backgroundColor: `rgba(${statusInfo.color === "emerald" ? "16,185,129" : statusInfo.color === "amber" ? "245,158,11" : statusInfo.color === "orange" ? "249,115,22" : "239,68,68"},0.05)`,
              borderColor: `rgba(${statusInfo.color === "emerald" ? "16,185,129" : statusInfo.color === "amber" ? "245,158,11" : statusInfo.color === "orange" ? "249,115,22" : "239,68,68"},0.2)`,
            }}
          >
            <div
              className={`w-1.5 h-1.5 rounded-full animate-pulse`}
              style={{
                backgroundColor: statusInfo.color === "emerald" ? "#34d399" : statusInfo.color === "amber" ? "#fbbf24" : statusInfo.color === "orange" ? "#fb923c" : "#f87171",
                boxShadow: `0 0 8px ${statusInfo.color === "emerald" ? "#34d399" : statusInfo.color === "amber" ? "#fbbf24" : statusInfo.color === "orange" ? "#fb923c" : "#f87171"}`,
              }}
            />
            <span
              className={`text-xs font-semibold tracking-wide uppercase`}
              style={{
                color: statusInfo.color === "emerald" ? "#34d399" : statusInfo.color === "amber" ? "#fbbf24" : statusInfo.color === "orange" ? "#fb923c" : "#f87171",
              }}
            >
              {statusInfo.label}
            </span>
          </div>
        )}

        <div className="h-6 w-px bg-midnight-700" />

        {/* Notification Bell */}
        <button className="relative p-2 text-slate-400 hover:text-white transition-colors">
          <div className="absolute top-2 right-2 w-2 h-2 rounded-full bg-indigo-500 border-2 border-midnight-950" />
          <Bell className="w-5 h-5" />
        </button>

        {/* Refresh Button */}
        <button
          onClick={handleRefresh}
          disabled={refreshing}
          className="p-2 text-slate-400 hover:text-white transition-colors disabled:opacity-50"
          title="Refresh metrics"
        >
          <RotateCcw className={`w-5 h-5 ${refreshing ? "animate-spin" : ""}`} />
        </button>
      </div>
    </header>
  );
}
