"use client"

import { Suspense, useEffect, useState } from "react"
import { Header } from "@/components/Header"
import {
  TimeSeriesChart,
  TimeRangeSelector,
} from "@/components/TimeSeriesChart"
import { useMetrics } from "@/hooks/useMetrics"
import { useSelectedVault } from "@/hooks/useSelectedVault"
import type {
  HistoryResponse,
  TimeRange,
  SeverityLevel,
} from "@/types/metrics"
import { RefreshCw, TrendingUp } from "lucide-react"

const severityConfig: Record<
  SeverityLevel,
  { label: string; color: string; dotColor: string }
> = {
  0: { label: "Normal", color: "#34d399", dotColor: "bg-emerald-500" },
  1: { label: "Elevated", color: "#fbbf24", dotColor: "bg-amber-500" },
  2: { label: "Critical", color: "#fb923c", dotColor: "bg-orange-500" },
  3: { label: "Emergency", color: "#f87171", dotColor: "bg-red-500" },
}

export default function RatesPage() {
  return (
    <Suspense
      fallback={
        <>
          <Header title="Interest Rates" />
          <div className="p-6 flex items-center justify-center min-h-[400px]">
            <RefreshCw className="w-8 h-8 text-slate-400 animate-spin" />
          </div>
        </>
      }
    >
      <RatesContent />
    </Suspense>
  )
}

function RatesContent() {
  const [timeRange, setTimeRange] = useState<TimeRange>("24h")
  const { vaultAddress } = useSelectedVault()
  const { metrics, loading } = useMetrics({ vault: vaultAddress })
  const [utilizationHistory, setUtilizationHistory] =
    useState<HistoryResponse | null>(null)
  const [rateHistory, setRateHistory] = useState<HistoryResponse | null>(null)

  useEffect(() => {
    const fetchHistories = async () => {
      try {
        const [utilizationRes, rateRes] = await Promise.all([
          fetch(
            `/api/history?signal=utilization&range=${timeRange}&vault=${vaultAddress}`
          ),
          fetch(
            `/api/history?signal=borrowRate&range=${timeRange}&vault=${vaultAddress}`
          ),
        ])

        if (utilizationRes.ok)
          setUtilizationHistory(await utilizationRes.json())
        if (rateRes.ok) setRateHistory(await rateRes.json())
      } catch (error) {
        console.error("Failed to fetch history:", error)
      }
    }

    fetchHistories()
  }, [timeRange, vaultAddress])

  if (loading) {
    return (
      <>
        <Header title="Interest Rates" />
        <div className="p-6 flex items-center justify-center min-h-[400px]">
          <RefreshCw className="w-8 h-8 text-slate-400 animate-spin" />
        </div>
      </>
    )
  }

  const severity = metrics?.aprConvexity.severity ?? 0
  const sev = severityConfig[severity as SeverityLevel]

  return (
    <>
      <Header title="Interest Rates" />
      <div className="p-6 sm:p-8 lg:p-10">
        {/* Current Status */}
        {metrics && (
          <div className="mb-8 glass-panel rounded-2xl overflow-hidden shadow-2xl">
            <div className="px-8 py-6 border-b border-midnight-700/50 flex items-center justify-between bg-white/5">
              <div className="flex items-center gap-3">
                <TrendingUp className="w-5 h-5 text-amber-400" />
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
                <div
                  className={`w-1.5 h-1.5 rounded-full ${sev.dotColor}`}
                />
                {sev.label}
              </span>
            </div>

            <div className="px-8 py-6">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                {/* Utilization Card */}
                <div className="p-5 rounded-xl bg-midnight-800/40 border border-midnight-700/30">
                  <p className="text-[10px] font-bold text-slate-500 uppercase tracking-[0.1em] mb-1">
                    Utilization Rate
                  </p>
                  <p className="text-3xl font-display font-black text-white tracking-tight mb-3">
                    {(metrics.aprConvexity.utilization * 100).toFixed(2)}
                    <span className="text-lg text-slate-500 ml-0.5">%</span>
                  </p>
                  <div className="p-3 rounded-lg bg-midnight-900/50 border border-midnight-700/20">
                    <p className="text-sm text-slate-400">
                      <span className="text-white font-medium font-mono">
                        {(metrics.aprConvexity.distanceToKink * 100).toFixed(1)}%
                      </span>{" "}
                      away from kink point
                    </p>
                  </div>
                </div>

                {/* Borrow Rate Card */}
                <div className="p-5 rounded-xl bg-midnight-800/40 border border-midnight-700/30">
                  <p className="text-[10px] font-bold text-slate-500 uppercase tracking-[0.1em] mb-1">
                    Borrow APR
                  </p>
                  <p className="text-3xl font-display font-black text-white tracking-tight mb-3">
                    {(metrics.aprConvexity.borrowRate * 100).toFixed(2)}
                    <span className="text-lg text-slate-500 ml-0.5">%</span>
                  </p>
                  <div className="p-3 rounded-lg bg-midnight-900/50 border border-midnight-700/20">
                    <p className="text-sm text-slate-400">
                      Annual interest rate for borrowers
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Thresholds */}
        <div className="mb-8 glass-panel rounded-xl p-5">
          <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider mb-3">
            APR Convexity Severity (Distance to Kink)
          </h3>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <div className="flex items-center gap-2 text-sm">
              <div className="w-2 h-2 rounded-full bg-emerald-500" />
              <span className="text-slate-400">
                <span className="text-emerald-400 font-medium">Normal</span> — &gt;15%
              </span>
            </div>
            <div className="flex items-center gap-2 text-sm">
              <div className="w-2 h-2 rounded-full bg-amber-500" />
              <span className="text-slate-400">
                <span className="text-amber-400 font-medium">Elevated</span> — 5–15%
              </span>
            </div>
            <div className="flex items-center gap-2 text-sm">
              <div className="w-2 h-2 rounded-full bg-orange-500" />
              <span className="text-slate-400">
                <span className="text-orange-400 font-medium">Critical</span> — &lt;5%
              </span>
            </div>
            <div className="flex items-center gap-2 text-sm">
              <div className="w-2 h-2 rounded-full bg-red-500" />
              <span className="text-slate-400">
                <span className="text-red-400 font-medium">Emergency</span> — Above
              </span>
            </div>
          </div>
        </div>

        {/* Charts */}
        <div className="space-y-6">
          <div className="glass-panel rounded-2xl overflow-hidden shadow-2xl">
            <div className="px-8 py-6 border-b border-midnight-700/50 flex items-center justify-between bg-white/5">
              <h3 className="text-lg font-semibold tracking-wide text-white">
                Utilization Rate History
              </h3>
              <TimeRangeSelector selected={timeRange} onChange={setTimeRange} />
            </div>
            <div className="px-6 py-6">
              {utilizationHistory ? (
                <TimeSeriesChart
                  data={utilizationHistory.data}
                  title=""
                  unit="%"
                  color="#fbbf24"
                  thresholds={[
                    { value: 80, label: "Kink (80%)", color: "#f97316" },
                  ]}
                  height={350}
                />
              ) : (
                <div className="flex items-center justify-center h-[350px]">
                  <p className="text-slate-500 text-sm">No data available</p>
                </div>
              )}
            </div>
          </div>

          <div className="glass-panel rounded-2xl overflow-hidden shadow-2xl">
            <div className="px-8 py-6 border-b border-midnight-700/50 bg-white/5">
              <h3 className="text-lg font-semibold tracking-wide text-white">
                Borrow Rate History
              </h3>
            </div>
            <div className="px-6 py-6">
              {rateHistory ? (
                <TimeSeriesChart
                  data={rateHistory.data}
                  title=""
                  unit="%"
                  color="#818cf8"
                  height={350}
                />
              ) : (
                <div className="flex items-center justify-center h-[350px]">
                  <p className="text-slate-500 text-sm">No data available</p>
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    </>
  )
}
