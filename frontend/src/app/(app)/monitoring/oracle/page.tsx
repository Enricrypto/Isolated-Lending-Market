"use client";

import { Suspense, useState } from "react";
import { Header } from "@/components/Header";
import { TimeSeriesChart, TimeRangeSelector } from "@/components/TimeSeriesChart";
import { useMetrics } from "@/hooks/useMetrics";
import { useSelectedVault } from "@/hooks/useSelectedVault";
import { formatPrice, getConfidenceLabel } from "@/lib/format";
import type { TimeRange, SeverityLevel } from "@/types/metrics";
import { RefreshCw, Radio, AlertTriangle, CheckCircle } from "lucide-react";

const severityConfig: Record<SeverityLevel, { label: string; color: string; dotColor: string }> = {
  0: { label: "Normal", color: "#34d399", dotColor: "bg-emerald-500" },
  1: { label: "Elevated", color: "#fbbf24", dotColor: "bg-amber-500" },
  2: { label: "Critical", color: "#fb923c", dotColor: "bg-orange-500" },
  3: { label: "Emergency", color: "#f87171", dotColor: "bg-red-500" },
};

export default function OraclePage() {
  return (
    <Suspense
      fallback={
        <>
          <Header title="Oracle Status" />
          <div className="p-6 flex items-center justify-center min-h-[400px]">
            <RefreshCw className="w-8 h-8 text-slate-400 animate-spin" />
          </div>
        </>
      }
    >
      <OracleContent />
    </Suspense>
  );
}

function OracleContent() {
  const [timeRange, setTimeRange] = useState<TimeRange>("24h");
  const { vaultAddress } = useSelectedVault();
  const { metrics, history, loading } = useMetrics({
    vault: vaultAddress,
    signal: "oracle",
    range: timeRange,
  });

  if (loading) {
    return (
      <>
        <Header title="Oracle Status" />
        <div className="p-6 flex items-center justify-center min-h-[400px]">
          <RefreshCw className="w-8 h-8 text-slate-400 animate-spin" />
        </div>
      </>
    );
  }

  const severity = metrics?.oracle.severity ?? 0;
  const sev = severityConfig[severity as SeverityLevel];

  return (
    <>
      <Header title="Oracle Status" />
      <div className="p-6 sm:p-8 lg:p-10">
        {/* Current Status */}
        {metrics && (
          <div className="mb-8 glass-panel rounded-2xl overflow-hidden shadow-2xl">
            <div className="px-8 py-6 border-b border-midnight-700/50 flex items-center justify-between bg-white/5">
              <div className="flex items-center gap-3">
                <Radio className="w-5 h-5 text-cyan-400" />
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
              <div className="mb-6">
                <p className="text-[10px] font-bold text-slate-500 uppercase tracking-[0.1em] mb-1">
                  Oracle Confidence
                </p>
                <p className="text-4xl font-display font-black text-white tracking-tight">
                  {metrics.oracle.confidence}
                  <span className="text-lg text-slate-500 ml-0.5">%</span>
                </p>
              </div>

              <dl className="grid grid-cols-2 md:grid-cols-4 gap-4">
                <div className="p-4 rounded-xl bg-midnight-800/40 border border-midnight-700/30">
                  <dt className="text-[10px] font-bold text-slate-500 uppercase tracking-[0.1em] mb-2">
                    Current Price
                  </dt>
                  <dd className="text-lg font-semibold text-white font-mono tracking-tight">
                    ${formatPrice(metrics.oracle.price)}
                  </dd>
                </div>
                <div className="p-4 rounded-xl bg-midnight-800/40 border border-midnight-700/30">
                  <dt className="text-[10px] font-bold text-slate-500 uppercase tracking-[0.1em] mb-2">
                    Risk Score
                  </dt>
                  <dd className="text-lg font-semibold text-white font-mono tracking-tight">
                    {metrics.oracle.riskScore}
                    <span className="text-slate-500 text-sm">/100</span>
                  </dd>
                </div>
                <div className="p-4 rounded-xl bg-midnight-800/40 border border-midnight-700/30">
                  <dt className="text-[10px] font-bold text-slate-500 uppercase tracking-[0.1em] mb-2">
                    Data Status
                  </dt>
                  <dd className="flex items-center gap-2">
                    {metrics.oracle.isStale ? (
                      <>
                        <AlertTriangle className="w-4 h-4 text-orange-400" />
                        <span className="text-lg font-semibold text-orange-400">Stale</span>
                      </>
                    ) : (
                      <>
                        <CheckCircle className="w-4 h-4 text-emerald-400" />
                        <span className="text-lg font-semibold text-emerald-400">Fresh</span>
                      </>
                    )}
                  </dd>
                </div>
                <div className="p-4 rounded-xl bg-midnight-800/40 border border-midnight-700/30">
                  <dt className="text-[10px] font-bold text-slate-500 uppercase tracking-[0.1em] mb-2">
                    Confidence Level
                  </dt>
                  <dd className="text-lg font-semibold text-white">
                    {getConfidenceLabel(metrics.oracle.confidence)}
                  </dd>
                </div>
              </dl>
            </div>
          </div>
        )}

        {/* Stale warning */}
        {metrics?.oracle.isStale && (
          <div className="mb-8 glass-panel rounded-xl p-5 border-orange-500/30 flex items-start gap-3">
            <AlertTriangle className="w-5 h-5 text-orange-400 mt-0.5 shrink-0" />
            <div>
              <p className="font-semibold text-orange-300 text-sm mb-1">
                Oracle data is stale
              </p>
              <p className="text-sm text-slate-400 leading-relaxed">
                The price feed has not been updated recently. The system is using
                the Last Known Good (LKG) price with decayed confidence.
              </p>
            </div>
          </div>
        )}

        {/* Thresholds */}
        <div className="mb-8 glass-panel rounded-xl p-5">
          <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider mb-3">
            Oracle Severity Thresholds
          </h3>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <div className="flex items-center gap-2 text-sm">
              <div className="w-2 h-2 rounded-full bg-emerald-500" />
              <span className="text-slate-400">
                <span className="text-emerald-400 font-medium">Normal</span> — ≥95%
              </span>
            </div>
            <div className="flex items-center gap-2 text-sm">
              <div className="w-2 h-2 rounded-full bg-amber-500" />
              <span className="text-slate-400">
                <span className="text-amber-400 font-medium">Elevated</span> — 80–94%
              </span>
            </div>
            <div className="flex items-center gap-2 text-sm">
              <div className="w-2 h-2 rounded-full bg-orange-500" />
              <span className="text-slate-400">
                <span className="text-orange-400 font-medium">Critical</span> — 50–79%
              </span>
            </div>
            <div className="flex items-center gap-2 text-sm">
              <div className="w-2 h-2 rounded-full bg-red-500" />
              <span className="text-slate-400">
                <span className="text-red-400 font-medium">Emergency</span> — &lt;50%
              </span>
            </div>
          </div>
        </div>

        {/* Chart */}
        <div className="glass-panel rounded-2xl overflow-hidden shadow-2xl">
          <div className="px-8 py-6 border-b border-midnight-700/50 flex items-center justify-between bg-white/5">
            <h3 className="text-lg font-semibold tracking-wide text-white">
              Oracle Confidence History
            </h3>
            <TimeRangeSelector selected={timeRange} onChange={setTimeRange} />
          </div>
          <div className="px-6 py-6">
            {history ? (
              <TimeSeriesChart
                data={history.data}
                title=""
                unit="%"
                color="#22d3ee"
                thresholds={[
                  { value: 95, label: "Normal", color: "#22c55e" },
                  { value: 80, label: "Elevated", color: "#eab308" },
                  { value: 50, label: "Critical", color: "#f97316" },
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
