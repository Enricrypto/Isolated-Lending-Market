"use client";

import { Suspense, useState } from "react";
import { Header } from "@/components/Header";
import { TimeSeriesChart, TimeRangeSelector } from "@/components/TimeSeriesChart";
import { useMetrics } from "@/hooks/useMetrics";
import { useSelectedVault } from "@/hooks/useSelectedVault";
import type { TimeRange, SeverityLevel } from "@/types/metrics";
import { RefreshCw, Activity, TrendingUp, TrendingDown, Minus } from "lucide-react";

const severityConfig: Record<SeverityLevel, { label: string; color: string; dotColor: string }> = {
  0: { label: "Normal", color: "#34d399", dotColor: "bg-emerald-500" },
  1: { label: "Elevated", color: "#fbbf24", dotColor: "bg-amber-500" },
  2: { label: "Critical", color: "#fb923c", dotColor: "bg-orange-500" },
  3: { label: "Emergency", color: "#f87171", dotColor: "bg-red-500" },
};

export default function UtilizationPage() {
  return (
    <Suspense
      fallback={
        <>
          <Header title="Utilization Velocity" />
          <div className="p-6 flex items-center justify-center min-h-[400px]">
            <RefreshCw className="w-8 h-8 text-slate-400 animate-spin" />
          </div>
        </>
      }
    >
      <UtilizationContent />
    </Suspense>
  );
}

function UtilizationContent() {
  const [timeRange, setTimeRange] = useState<TimeRange>("24h");
  const { vaultAddress } = useSelectedVault();
  const { metrics, history, loading } = useMetrics({
    vault: vaultAddress,
    signal: "velocity",
    range: timeRange,
  });

  if (loading) {
    return (
      <>
        <Header title="Utilization Velocity" />
        <div className="p-6 flex items-center justify-center min-h-[400px]">
          <RefreshCw className="w-8 h-8 text-slate-400 animate-spin" />
        </div>
      </>
    );
  }

  const delta = metrics?.velocity.delta ?? 0;
  const TrendIcon =
    delta > 0.01 ? TrendingUp : delta < -0.01 ? TrendingDown : Minus;
  const trendColor =
    Math.abs(delta) < 0.01
      ? "text-slate-400"
      : delta > 0
        ? "text-red-400"
        : "text-emerald-400";
  const severity = (metrics?.velocity.severity ?? 0) as SeverityLevel;
  const sev = severityConfig[severity];

  return (
    <>
      <Header title="Utilization Velocity" />
      <div className="p-6 sm:p-8 lg:p-10">
        {/* Current Status */}
        {metrics && (
          <div className="mb-8 glass-panel rounded-2xl overflow-hidden shadow-2xl">
            <div className="px-8 py-6 border-b border-midnight-700/50 flex items-center justify-between bg-white/5">
              <div className="flex items-center gap-3">
                <Activity className="w-5 h-5 text-red-400" />
                <h3 className="text-lg font-semibold tracking-wide text-white">
                  Current Status
                </h3>
              </div>
              <span
                className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[10px] font-bold"
                style={{
                  backgroundColor: `${sev.color}1a`,
                  color: sev.color,
                  borderWidth: 1,
                  borderColor: `${sev.color}33`,
                }}
              >
                <div className={`w-1.5 h-1.5 rounded-full ${sev.dotColor}`} />
                {sev.label}
              </span>
            </div>

            <div className="px-8 py-6">
              <div className="flex items-center gap-4 mb-6">
                <TrendIcon className={`w-10 h-10 ${trendColor}`} />
                <div>
                  <p className="text-[10px] font-bold text-slate-500 uppercase tracking-[0.1em] mb-1">
                    Utilization Rate of Change
                  </p>
                  <p className="text-4xl font-display font-black text-white tracking-tight">
                    {metrics.velocity.delta !== null
                      ? `${(metrics.velocity.delta * 100).toFixed(2)}`
                      : "N/A"}
                    <span className="text-lg text-slate-500 ml-0.5">%/hr</span>
                  </p>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div className="p-4 rounded-xl bg-midnight-800/40 border border-midnight-700/30">
                  <p className="text-[10px] font-bold text-slate-500 uppercase tracking-[0.1em] mb-2">
                    Current Utilization
                  </p>
                  <p className="text-xl font-semibold text-white font-mono tracking-tight">
                    {(metrics.aprConvexity.utilization * 100).toFixed(2)}%
                  </p>
                </div>
                <div className="p-4 rounded-xl bg-midnight-800/40 border border-midnight-700/30">
                  <p className="text-[10px] font-bold text-slate-500 uppercase tracking-[0.1em] mb-2">
                    Direction
                  </p>
                  <p className={`text-xl font-semibold ${trendColor}`}>
                    {delta > 0.01
                      ? "Increasing"
                      : delta < -0.01
                        ? "Decreasing"
                        : "Stable"}
                  </p>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Explanation */}
        <div className="mb-8 glass-panel rounded-xl p-5">
          <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">
            What is Utilization Velocity?
          </h3>
          <p className="text-sm text-slate-400 leading-relaxed">
            Utilization velocity measures how quickly the utilization rate is
            changing. High velocity (rapid increases) can indicate sudden demand
            for borrowing, which may push the protocol toward the kink point and
            trigger steep interest rate increases.
          </p>
        </div>

        {/* Thresholds */}
        <div className="mb-8 glass-panel rounded-xl p-5">
          <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider mb-3">
            Velocity Severity Thresholds
          </h3>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <div className="flex items-center gap-2 text-sm">
              <div className="w-2 h-2 rounded-full bg-emerald-500" />
              <span className="text-slate-400">
                <span className="text-emerald-400 font-medium">Normal</span> — &lt;1%/hr
              </span>
            </div>
            <div className="flex items-center gap-2 text-sm">
              <div className="w-2 h-2 rounded-full bg-amber-500" />
              <span className="text-slate-400">
                <span className="text-amber-400 font-medium">Elevated</span> — 1–5%/hr
              </span>
            </div>
            <div className="flex items-center gap-2 text-sm">
              <div className="w-2 h-2 rounded-full bg-orange-500" />
              <span className="text-slate-400">
                <span className="text-orange-400 font-medium">Critical</span> — 5–10%/hr
              </span>
            </div>
            <div className="flex items-center gap-2 text-sm">
              <div className="w-2 h-2 rounded-full bg-red-500" />
              <span className="text-slate-400">
                <span className="text-red-400 font-medium">Emergency</span> — &gt;10%/hr
              </span>
            </div>
          </div>
        </div>

        {/* Chart */}
        <div className="glass-panel rounded-2xl overflow-hidden shadow-2xl">
          <div className="px-8 py-6 border-b border-midnight-700/50 flex items-center justify-between bg-white/5">
            <h3 className="text-lg font-semibold tracking-wide text-white">
              Velocity History
            </h3>
            <TimeRangeSelector selected={timeRange} onChange={setTimeRange} />
          </div>
          <div className="px-6 py-6">
            {history ? (
              <TimeSeriesChart
                data={history.data}
                title=""
                unit="%/hr"
                color="#f87171"
                thresholds={[
                  { value: 10, label: "Emergency", color: "#ef4444" },
                  { value: 5, label: "Critical", color: "#f97316" },
                  { value: 1, label: "Elevated", color: "#eab308" },
                  { value: -1, label: "Elevated", color: "#eab308" },
                  { value: -5, label: "Critical", color: "#f97316" },
                  { value: -10, label: "Emergency", color: "#ef4444" },
                ]}
                height={400}
              />
            ) : (
              <div className="flex items-center justify-center h-[400px]">
                <p className="text-slate-500 text-sm">No historical data available</p>
              </div>
            )}
          </div>
        </div>
      </div>
    </>
  );
}
