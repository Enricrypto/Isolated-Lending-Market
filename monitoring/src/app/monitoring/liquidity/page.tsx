"use client";

import { useEffect, useState } from "react";
import { Header } from "@/components/Header";
import { SeverityBadge } from "@/components/SeverityBadge";
import { TimeSeriesChart, TimeRangeSelector } from "@/components/TimeSeriesChart";
import type { CurrentMetricsResponse, HistoryResponse, TimeRange, SeverityLevel } from "@/types/metrics";
import { RefreshCw } from "lucide-react";

export default function LiquidityPage() {
  const [metrics, setMetrics] = useState<CurrentMetricsResponse | null>(null);
  const [history, setHistory] = useState<HistoryResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [timeRange, setTimeRange] = useState<TimeRange>("24h");

  useEffect(() => {
    const fetchData = async () => {
      setLoading(true);
      try {
        const [metricsRes, historyRes] = await Promise.all([
          fetch("/api/metrics"),
          fetch(`/api/history?signal=liquidity&range=${timeRange}`),
        ]);

        if (metricsRes.ok) {
          setMetrics(await metricsRes.json());
        }
        if (historyRes.ok) {
          setHistory(await historyRes.json());
        }
      } catch (error) {
        console.error("Failed to fetch data:", error);
      } finally {
        setLoading(false);
      }
    };

    fetchData();
  }, [timeRange]);

  if (loading) {
    return (
      <>
        <Header title="Liquidity Depth" />
        <div className="p-6 flex items-center justify-center min-h-[400px]">
          <RefreshCw className="w-8 h-8 text-gray-400 animate-spin" />
        </div>
      </>
    );
  }

  return (
    <>
      <Header title="Liquidity Depth" />
      <div className="p-6">
        {/* Current Status */}
        {metrics && (
          <div className="mb-8 p-6 bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700">
            <div className="flex items-start justify-between mb-6">
              <div>
                <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-1">
                  {metrics.liquidity.depthRatio.toFixed(2)}x
                </h2>
                <p className="text-gray-500 dark:text-gray-400">
                  Depth Coverage Ratio
                </p>
              </div>
              <SeverityBadge severity={metrics.liquidity.severity as SeverityLevel} size="lg" />
            </div>

            <dl className="grid grid-cols-2 gap-6">
              <div>
                <dt className="text-sm text-gray-500 dark:text-gray-400">Available Liquidity</dt>
                <dd className="text-lg font-semibold text-gray-900 dark:text-white">
                  {formatLargeNumber(metrics.liquidity.available)}
                </dd>
              </div>
              <div>
                <dt className="text-sm text-gray-500 dark:text-gray-400">Total Borrows</dt>
                <dd className="text-lg font-semibold text-gray-900 dark:text-white">
                  {formatLargeNumber(metrics.liquidity.totalBorrows)}
                </dd>
              </div>
            </dl>
          </div>
        )}

        {/* Thresholds info */}
        <div className="mb-8 p-4 bg-blue-50 dark:bg-blue-900/20 rounded-lg">
          <h3 className="font-medium text-blue-900 dark:text-blue-100 mb-2">
            Severity Thresholds
          </h3>
          <ul className="text-sm text-blue-800 dark:text-blue-200 space-y-1">
            <li>• <span className="text-green-600">Normal (0)</span>: Depth ratio &gt; 3.0x</li>
            <li>• <span className="text-yellow-600">Elevated (1)</span>: Depth ratio 1.5x - 3.0x</li>
            <li>• <span className="text-orange-600">Critical (2)</span>: Depth ratio &lt; 1.0x</li>
          </ul>
        </div>

        {/* Chart */}
        <div className="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-6">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
              Historical Depth Ratio
            </h3>
            <TimeRangeSelector selected={timeRange} onChange={setTimeRange} />
          </div>

          {history && (
            <TimeSeriesChart
              data={history.data}
              title=""
              unit="x"
              thresholds={[
                { value: 3.0, label: "Normal", color: "#22c55e" },
                { value: 1.5, label: "Elevated", color: "#eab308" },
                { value: 1.0, label: "Critical", color: "#f97316" },
              ]}
              height={400}
            />
          )}
        </div>
      </div>
    </>
  );
}

function formatLargeNumber(value: string): string {
  const num = BigInt(value);
  const divisor = BigInt(1e6);
  const whole = num / divisor;

  if (whole >= 1_000_000n) {
    return `$${(Number(whole) / 1_000_000).toFixed(2)}M`;
  }
  if (whole >= 1_000n) {
    return `$${(Number(whole) / 1_000).toFixed(2)}K`;
  }
  return `$${whole.toString()}`;
}
