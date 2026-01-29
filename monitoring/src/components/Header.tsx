"use client";

import { useEffect, useState } from "react";
import { ChevronRight, RefreshCw, Menu } from "lucide-react";
import { useSimulationStore } from "@/store/useSimulationStore";
import { useAppStore } from "@/store/useAppStore";
import { ConnectWallet } from "./ConnectWallet";
import type { SeverityLevel, CurrentMetricsResponse } from "@/types/metrics";

interface HeaderProps {
  title?: string;
  breadcrumb?: string;
  showModeToggle?: boolean;
}

const severityLabels: Record<SeverityLevel, { label: string; color: string }> = {
  0: { label: "System Normal", color: "emerald" },
  1: { label: "Elevated Risk", color: "amber" },
  2: { label: "Critical", color: "orange" },
  3: { label: "Emergency", color: "red" },
};

export function Header({
  title,
  breadcrumb = "Dashboard",
  showModeToggle = true,
}: HeaderProps) {
  const [metrics, setMetrics] = useState<CurrentMetricsResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const { isSimulation, toggleMode } = useSimulationStore();
  const { triggerRefresh } = useAppStore();

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
    triggerRefresh();
    setRefreshing(false);
  };

  const severity = metrics?.overall ?? 0;
  const statusInfo = severityLabels[severity as SeverityLevel];

  return (
    <header className="h-16 border-b border-midnight-700/50 flex items-center justify-between px-4 sm:px-8 bg-midnight-950/80 backdrop-blur-md sticky top-0 z-40 w-full">
      {/* Left: Breadcrumbs */}
      <div className="flex items-center gap-4">
        <button className="md:hidden p-2 text-slate-400 hover:text-white">
          <Menu className="w-6 h-6" />
        </button>
        <div className="flex items-center gap-2 text-sm text-slate-500">
          <span className="hover:text-slate-300 cursor-pointer transition-colors">
            App
          </span>
          <ChevronRight className="w-4 h-4 text-slate-600" />
          <span className="text-slate-200 font-medium">
            {title || breadcrumb}
          </span>
        </div>
      </div>

      {/* Right: Controls */}
      <div className="flex items-center gap-4">
        {/* Simulation Toggle */}
        {showModeToggle && (
          <>
            <div className="hidden sm:flex items-center gap-1 bg-midnight-800/50 rounded-full p-1 border border-midnight-700/50">
              <button
                onClick={() => !isSimulation && toggleMode()}
                className={`px-3 py-1 text-xs font-medium rounded-full transition-all ${
                  isSimulation
                    ? "bg-indigo-500/20 text-indigo-400 shadow-sm border border-indigo-500/20"
                    : "text-slate-500 hover:text-slate-300"
                }`}
              >
                Simulation
              </button>
              <button
                onClick={() => isSimulation && toggleMode()}
                className={`px-3 py-1 text-xs font-medium rounded-full transition-all ${
                  !isSimulation
                    ? "bg-indigo-500/20 text-indigo-400 shadow-sm border border-indigo-500/20"
                    : "text-slate-500 hover:text-slate-300"
                }`}
              >
                Mainnet
              </button>
            </div>

            <div className="hidden sm:block h-4 w-px bg-midnight-700/50" />
          </>
        )}

        {/* Oracle Status */}
        <div className="hidden md:flex flex-col items-end">
          <span className="text-[10px] uppercase text-slate-500 tracking-wider font-semibold">
            Oracle Status
          </span>
          <div className="flex items-center gap-1.5">
            <span className="relative flex h-1.5 w-1.5">
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75" />
              <span className="relative inline-flex rounded-full h-1.5 w-1.5 bg-emerald-500" />
            </span>
            <span className="text-xs font-semibold text-slate-200">
              {loading ? "Loading..." : "Synced"}
            </span>
          </div>
        </div>

        <div className="hidden md:block h-4 w-px bg-midnight-700/50" />

        {/* Status Badge (for monitoring) */}
        {!loading && metrics && (
          <div
            className="hidden lg:flex items-center gap-2 px-3 py-1.5 rounded-full"
            style={{
              backgroundColor: `rgba(${statusInfo.color === "emerald" ? "16,185,129" : statusInfo.color === "amber" ? "245,158,11" : statusInfo.color === "orange" ? "249,115,22" : "239,68,68"},0.05)`,
              borderWidth: 1,
              borderColor: `rgba(${statusInfo.color === "emerald" ? "16,185,129" : statusInfo.color === "amber" ? "245,158,11" : statusInfo.color === "orange" ? "249,115,22" : "239,68,68"},0.2)`,
            }}
          >
            <div
              className="w-1.5 h-1.5 rounded-full animate-pulse"
              style={{
                backgroundColor:
                  statusInfo.color === "emerald"
                    ? "#34d399"
                    : statusInfo.color === "amber"
                    ? "#fbbf24"
                    : statusInfo.color === "orange"
                    ? "#fb923c"
                    : "#f87171",
              }}
            />
            <span
              className="text-xs font-semibold tracking-wide uppercase"
              style={{
                color:
                  statusInfo.color === "emerald"
                    ? "#34d399"
                    : statusInfo.color === "amber"
                    ? "#fbbf24"
                    : statusInfo.color === "orange"
                    ? "#fb923c"
                    : "#f87171",
              }}
            >
              {statusInfo.label}
            </span>
          </div>
        )}

        {/* Refresh Button */}
        <button
          onClick={handleRefresh}
          disabled={refreshing}
          className="flex items-center gap-2 px-3 py-1.5 text-xs font-medium text-slate-300 bg-midnight-800/50 border border-midnight-700/50 rounded-lg hover:bg-midnight-700/50 transition-all disabled:opacity-50"
          title="Refresh data"
        >
          <RefreshCw
            className={`w-3.5 h-3.5 ${refreshing ? "animate-spin" : ""}`}
          />
          <span className="hidden sm:inline">Refresh</span>
        </button>

        {/* Wallet Connect */}
        <ConnectWallet />
      </div>
    </header>
  );
}
