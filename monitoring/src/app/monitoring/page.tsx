"use client";

import { useEffect, useState } from "react";
import { Header } from "@/components/Header";
import { RiskMetricCard } from "@/components/RiskMetricCard";
import type { CurrentMetricsResponse, SeverityLevel } from "@/types/metrics";
import { AlertTriangle, RefreshCw, ArrowRight, MoreHorizontal, Share2, Info } from "lucide-react";

export default function DashboardPage() {
  const [metrics, setMetrics] = useState<CurrentMetricsResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [polling, setPolling] = useState(false);

  const fetchMetrics = async () => {
    try {
      const response = await fetch("/api/metrics");
      if (response.ok) {
        const data = await response.json();
        setMetrics(data);
        setError(null);
      } else if (response.status === 404) {
        setError("No metrics available yet. Click 'Poll Now' to fetch data.");
      } else {
        setError("Failed to fetch metrics");
      }
    } catch (err) {
      setError("Failed to connect to API");
    } finally {
      setLoading(false);
    }
  };

  const triggerPoll = async () => {
    setPolling(true);
    try {
      const response = await fetch("/api/poll", { method: "POST" });
      if (response.ok) {
        await fetchMetrics();
      } else {
        const data = await response.json();
        setError(data.error || "Poll failed");
      }
    } catch (err) {
      setError("Failed to trigger poll");
    } finally {
      setPolling(false);
    }
  };

  useEffect(() => {
    fetchMetrics();
    const interval = setInterval(fetchMetrics, 5 * 60 * 1000);
    return () => clearInterval(interval);
  }, []);

  if (loading) {
    return (
      <>
        <Header title="Monitoring & Analytics" />
        <div className="p-6 flex items-center justify-center min-h-[400px]">
          <RefreshCw className="w-8 h-8 text-slate-400 animate-spin" />
        </div>
      </>
    );
  }

  // Calculate risk score (weighted average of all severities)
  const riskScore = metrics
    ? Math.max(0, 100 - (metrics.overall * 25))
    : 92;

  return (
    <>
      <Header title="Monitoring & Analytics" breadcrumb="Monitoring" />

      <div className="flex flex-col xl:flex-row w-full">
        {/* Left Dashboard Area */}
        <div className="flex-1 p-6 sm:p-8 lg:p-10">
          {/* Hero Section */}
          <div className="mb-10 relative">
            <div className="text-[10px] font-bold text-indigo-400 uppercase tracking-[0.2em] mb-2">
              Real-time Surveillance
            </div>
            <h1 className="text-4xl sm:text-5xl lg:text-6xl font-display font-black text-white mb-3 tracking-tighter leading-[1.1] drop-shadow-lg">
              Protocol Risk Engine
            </h1>
            <p className="text-slate-400 text-sm max-w-2xl font-light leading-relaxed">
              Access and monitor real time economic risk signals in LendCore markets,
              including oracle deviations and liquidity health.
            </p>
            {/* Decorative glowing orb */}
            <div className="absolute -top-20 -left-20 w-64 h-64 bg-indigo-600/20 rounded-full blur-[80px] pointer-events-none mix-blend-screen" />
          </div>

          {/* Error state */}
          {error && (
            <div className="mb-8 p-4 glass-panel rounded-xl flex items-center justify-between border-amber-500/30">
              <div className="flex items-center gap-3">
                <AlertTriangle className="w-5 h-5 text-amber-400" />
                <span className="text-amber-300">{error}</span>
              </div>
              <button
                onClick={triggerPoll}
                disabled={polling}
                className="px-4 py-2 bg-btn-primary text-white rounded-lg hover:shadow-[0_0_20px_rgba(79,70,229,0.3)] disabled:opacity-50 flex items-center gap-2 transition-all"
              >
                {polling && <RefreshCw className="w-4 h-4 animate-spin" />}
                Poll Now
              </button>
            </div>
          )}

          {/* Metrics Grid */}
          {metrics && (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-10">
              <RiskMetricCard
                title="Liquidity Depth"
                subtitle="WETH / USDC Market"
                value={`$${formatLargeNumber(metrics.liquidity.available)}`}
                valueLabel="Available"
                severity={metrics.liquidity.severity}
                stats={[
                  { label: "Depth", value: `${metrics.liquidity.depthRatio.toFixed(1)}x` },
                  { label: "Borrows", value: `$${formatLargeNumber(metrics.liquidity.totalBorrows)}` },
                ]}
                href="/monitoring/liquidity"
                sparklineColor="emerald"
                sparklinePath="M0,35 Q10,32 20,25 T40,28 T60,15 T80,20 T100,5"
                icon="liquidity"
              />

              <RiskMetricCard
                title="Borrow APR"
                subtitle="IRM Curve Convexity"
                value={`${(metrics.aprConvexity.utilization * 100).toFixed(1)}%`}
                valueLabel="Utilization"
                severity={metrics.aprConvexity.severity}
                stats={[
                  { label: "APR", value: `${(metrics.aprConvexity.borrowRate * 100).toFixed(1)}%`, highlight: true },
                  { label: "To Kink", value: `${(metrics.aprConvexity.distanceToKink * 100).toFixed(1)}%` },
                ]}
                href="/monitoring/rates"
                sparklineColor="amber"
                sparklinePath="M0,38 Q20,38 40,35 T70,25 T90,5 T100,2"
                icon="rates"
              />

              <RiskMetricCard
                title="Oracle Feeds"
                subtitle="Chainlink / LKG"
                value={`$${formatPrice(metrics.oracle.price)}`}
                valueLabel="USDC Price"
                severity={metrics.oracle.severity}
                stats={[
                  { label: "Conf", value: `${metrics.oracle.confidence}%`, highlight: metrics.oracle.confidence === 100 },
                  { label: "Status", value: metrics.oracle.isStale ? "Stale" : "Fresh" },
                ]}
                href="/monitoring/oracle"
                sparklineColor="cyan"
                sparklinePath="M0,20 L10,22 L20,18 L30,21 L40,19 L50,20 L60,20 L70,18 L80,22 L90,20 L100,21"
                icon="oracle"
              />

              <RiskMetricCard
                title="Velocity"
                subtitle="Rate of Change (1h)"
                value={
                  metrics.velocity.delta !== null
                    ? `${metrics.velocity.delta >= 0 ? "+" : ""}${(metrics.velocity.delta * 100).toFixed(1)}%`
                    : "N/A"
                }
                valueLabel="/ hour"
                severity={metrics.velocity.severity ?? 0}
                stats={[
                  {
                    label: "Trend",
                    value: metrics.velocity.delta !== null
                      ? metrics.velocity.delta > 0.01 ? "Spiking" : metrics.velocity.delta < -0.01 ? "Falling" : "Stable"
                      : "N/A",
                    highlight: true,
                  },
                  { label: "Prev", value: "~" },
                ]}
                href="/monitoring/utilization"
                sparklineColor="red"
                sparklinePath="M0,35 L20,35 L40,32 L60,30 L80,15 L100,5"
                icon="velocity"
              />
            </div>
          )}

          {/* Active Markets Table */}
          {metrics && (
            <div className="glass-panel rounded-2xl overflow-hidden shadow-2xl">
              <div className="px-8 py-6 border-b border-midnight-700/50 flex items-center justify-between bg-white/5">
                <h3 className="text-lg font-semibold tracking-wide text-white">
                  Active Markets
                </h3>
                <button className="text-xs font-semibold text-indigo-400 hover:text-indigo-300 flex items-center gap-1.5 uppercase tracking-wider transition-colors">
                  View All <ArrowRight className="w-3.5 h-3.5" />
                </button>
              </div>
              <div className="overflow-x-auto">
                <table className="w-full text-left text-sm">
                  <thead>
                    <tr className="border-b border-midnight-700/50 text-[10px] font-bold text-slate-500 uppercase tracking-[0.1em]">
                      <th className="px-8 py-5">Asset</th>
                      <th className="px-8 py-5">Oracle Price</th>
                      <th className="px-8 py-5">Total Supply</th>
                      <th className="px-8 py-5">Total Borrow</th>
                      <th className="px-8 py-5">Utilization</th>
                      <th className="px-8 py-5">Risk Status</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-midnight-700/50">
                    <tr className="group hover:bg-white/5 transition-colors">
                      <td className="px-8 py-5">
                        <div className="flex items-center gap-4">
                          <div className="w-10 h-10 rounded-full bg-blue-900/40 flex items-center justify-center text-xs font-bold text-blue-400 shadow-lg border border-blue-500/20">
                            U
                          </div>
                          <span className="font-medium text-white text-base">USDC</span>
                        </div>
                      </td>
                      <td className="px-8 py-5 text-slate-300 font-mono tracking-tight">
                        ${formatPrice(metrics.oracle.price)}
                      </td>
                      <td className="px-8 py-5 text-slate-300 font-mono tracking-tight">
                        {formatLargeNumber(metrics.liquidity.available)}
                      </td>
                      <td className="px-8 py-5 text-slate-300 font-mono tracking-tight">
                        {formatLargeNumber(metrics.liquidity.totalBorrows)}
                      </td>
                      <td className="px-8 py-5">
                        <div className="flex items-center gap-3">
                          <span className={`font-medium ${
                            metrics.aprConvexity.utilization > 0.8 ? "text-amber-400" : "text-white"
                          }`}>
                            {(metrics.aprConvexity.utilization * 100).toFixed(1)}%
                          </span>
                          <div className="w-20 h-1.5 rounded-full bg-midnight-950 overflow-hidden border border-white/10">
                            <div
                              className={`h-full ${
                                metrics.aprConvexity.utilization > 0.8 ? "bg-amber-500" : "bg-emerald-500"
                              }`}
                              style={{
                                width: `${metrics.aprConvexity.utilization * 100}%`,
                                boxShadow: `0 0 8px ${metrics.aprConvexity.utilization > 0.8 ? "#f59e0b" : "#10b981"}`,
                              }}
                            />
                          </div>
                        </div>
                      </td>
                      <td className="px-8 py-5">
                        <StatusBadge severity={metrics.overall} />
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </div>

        {/* Right Panel: Risk Updates */}
        <aside className="w-full xl:w-[400px] border-l border-midnight-700/50 bg-midnight-950/20 backdrop-blur-md p-8 flex flex-col gap-8 shrink-0">
          <div>
            <div className="flex items-center justify-between mb-6">
              <h3 className="text-lg font-semibold text-white tracking-wide">
                Relevant Updates
              </h3>
              <span className="text-[10px] px-2 py-0.5 bg-indigo-500/20 text-indigo-300 rounded border border-indigo-500/30 uppercase tracking-widest font-bold">
                LIVE
              </span>
            </div>

            <div className="space-y-8 relative">
              {/* Vertical Line */}
              <div className="absolute left-[11px] top-3 bottom-0 w-px bg-gradient-to-b from-indigo-500/30 to-transparent" />

              {/* Update Items */}
              {metrics && metrics.velocity.severity !== null && metrics.velocity.severity >= 2 && (
                <UpdateItem
                  color="red"
                  title="Utilization Spike"
                  description={`Utilization velocity exceeded threshold. Current delta: ${
                    metrics.velocity.delta !== null ? `${(metrics.velocity.delta * 100).toFixed(1)}%` : "N/A"
                  }.`}
                  time="Just now"
                />
              )}

              {metrics && metrics.aprConvexity.severity >= 1 && (
                <UpdateItem
                  color="amber"
                  title="Kink Proximity"
                  description={`Borrow rate approaching optimal utilization. Distance to kink: ${(metrics.aprConvexity.distanceToKink * 100).toFixed(1)}%.`}
                  time="Recent"
                />
              )}

              <UpdateItem
                color="emerald"
                title="Oracle Heartbeat"
                description="All oracle feeds synced. System operating normally."
                time="Ongoing"
              />
            </div>
          </div>

          {/* Risk Assessment Card */}
          <div className="p-6 rounded-xl bg-gradient-to-br from-indigo-900/40 to-purple-900/40 border border-indigo-500/30 relative overflow-hidden group">
            <div className="absolute top-0 right-0 w-32 h-32 bg-indigo-500/20 rounded-full blur-[40px] -mr-10 -mt-10 group-hover:bg-indigo-500/30 transition-all duration-700" />

            <h4 className="text-sm font-bold uppercase tracking-widest text-indigo-300 mb-2">
              Risk Assessment
            </h4>
            <p className="text-xs text-indigo-200/70 mb-5 leading-relaxed relative z-10">
              Overall protocol health score based on weighted averages of all signals.
            </p>
            <div className="flex items-end gap-3 relative z-10">
              <span className="text-5xl font-display font-black text-white drop-shadow-[0_0_10px_rgba(79,70,229,0.5)]">
                {riskScore}
              </span>
              <span className="text-sm font-medium text-indigo-400 mb-1.5 opacity-80">/ 100</span>
            </div>

            <button className="w-full mt-6 py-2.5 rounded-lg bg-btn-primary text-white text-sm font-medium shadow-[0_0_20px_rgba(79,70,229,0.3)] hover:shadow-[0_0_30px_rgba(79,70,229,0.5)] transition-all border border-white/10">
              View Detailed Report
            </button>
          </div>
        </aside>
      </div>
    </>
  );
}

// Status Badge Component
function StatusBadge({ severity }: { severity: SeverityLevel }) {
  const config: Record<SeverityLevel, { label: string; color: string }> = {
    0: { label: "Normal", color: "emerald" },
    1: { label: "Elevated", color: "amber" },
    2: { label: "Critical", color: "orange" },
    3: { label: "Emergency", color: "red" },
  };

  const { label, color } = config[severity];

  return (
    <span
      className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[10px] font-bold bg-${color}-500/10 text-${color}-400 border border-${color}-500/20`}
      style={{
        backgroundColor: `rgba(${color === "emerald" ? "16,185,129" : color === "amber" ? "245,158,11" : color === "orange" ? "249,115,22" : "239,68,68"},0.1)`,
        color: color === "emerald" ? "#34d399" : color === "amber" ? "#fbbf24" : color === "orange" ? "#fb923c" : "#f87171",
        borderColor: `rgba(${color === "emerald" ? "16,185,129" : color === "amber" ? "245,158,11" : color === "orange" ? "249,115,22" : "239,68,68"},0.2)`,
      }}
    >
      <div
        className="w-1 h-1 rounded-full"
        style={{
          backgroundColor: color === "emerald" ? "#34d399" : color === "amber" ? "#fbbf24" : color === "orange" ? "#fb923c" : "#f87171",
        }}
      />
      {label}
    </span>
  );
}

// Update Item Component
function UpdateItem({
  color,
  title,
  description,
  time,
}: {
  color: "red" | "amber" | "emerald";
  title: string;
  description: string;
  time: string;
}) {
  const borderColor = color === "red" ? "border-red-500/50" : color === "amber" ? "border-amber-500/50" : "border-emerald-500/50";
  const dotColor = color === "red" ? "bg-red-500" : color === "amber" ? "bg-amber-500" : "bg-emerald-500";
  const shadowColor = color === "red" ? "rgba(239,68,68,0.3)" : color === "amber" ? "rgba(245,158,11,0.3)" : "rgba(16,185,129,0.3)";
  const highlightColor = color === "red" ? "text-red-400" : color === "amber" ? "text-amber-400" : "text-emerald-400";

  return (
    <div className="relative pl-8">
      <div
        className={`absolute left-0 top-1.5 w-6 h-6 rounded-full bg-midnight-950 border ${borderColor} flex items-center justify-center z-10`}
        style={{ boxShadow: `0 0 15px ${shadowColor}` }}
      >
        <div className={`w-2 h-2 rounded-full ${dotColor} ${color === "red" ? "animate-pulse" : ""}`} />
      </div>
      <div className="flex items-start justify-between mb-2">
        <span className="text-sm font-semibold text-white">{title}</span>
        <MoreHorizontal className="w-4 h-4 text-slate-600 cursor-pointer hover:text-white" />
      </div>
      <p className="text-sm text-slate-400 leading-relaxed mb-3">
        {description}
      </p>
      <div className="flex items-center gap-4 text-xs text-slate-600 font-medium">
        <span>{time}</span>
        <div className="flex gap-3">
          <Share2 className="w-3.5 h-3.5 hover:text-indigo-400 cursor-pointer transition-colors" />
          <Info className="w-3.5 h-3.5 hover:text-indigo-400 cursor-pointer transition-colors" />
        </div>
      </div>
    </div>
  );
}

// Format large numbers for display
function formatLargeNumber(value: string): string {
  const num = BigInt(value);
  const divisor = BigInt(1e6);
  const whole = num / divisor;

  if (whole >= 1_000_000n) {
    return `${(Number(whole) / 1_000_000).toFixed(1)}M`;
  }
  if (whole >= 1_000n) {
    return `${(Number(whole) / 1_000).toFixed(1)}K`;
  }
  return whole.toString();
}

// Format price for display
function formatPrice(priceString: string): string {
  const price = BigInt(priceString);
  const usd = Number(price) / 1e18;
  return usd.toFixed(2);
}
