"use client";

import { useEffect, useState } from "react";
import { Header } from "@/components/Header";
import { SeverityBadge } from "@/components/SeverityBadge";
import { TimeSeriesChart, TimeRangeSelector } from "@/components/TimeSeriesChart";
import type { CurrentMetricsResponse, HistoryResponse, TimeRange, SeverityLevel } from "@/types/metrics";
import { RefreshCw, TrendingUp, TrendingDown, Minus } from "lucide-react";

export default function UtilizationPage() {
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
          fetch(`/api/history?signal=velocity&range=${timeRange}`),
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
        <Header title="Utilization Velocity" />
        <div className="p-6 flex items-center justify-center min-h-[400px]">
          <RefreshCw className="w-8 h-8 text-gray-400 animate-spin" />
        </div>
      </>
    );
  }

  const delta = metrics?.velocity.delta ?? 0;
  const TrendIcon = delta > 0.01 ? TrendingUp : delta < -0.01 ? TrendingDown : Minus;
  const trendColor = Math.abs(delta) < 0.01 ? "text-gray-500" : delta > 0 ? "text-red-500" : "text-green-500";

  return (
    <>
      <Header title="Utilization Velocity" />
      <div className="p-6">
        {/* Current Status */}
        {metrics && (
          <div className="mb-8 p-6 bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700">
            <div className="flex items-start justify-between mb-6">
              <div className="flex items-center gap-4">
                <TrendIcon className={`w-10 h-10 ${trendColor}`} />
                <div>
                  <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-1">
                    {metrics.velocity.delta !== null
                      ? `${(metrics.velocity.delta * 100).toFixed(2)}%/hr`
                      : "N/A"}
                  </h2>
                  <p className="text-gray-500 dark:text-gray-400">
                    Utilization Rate of Change
                  </p>
                </div>
              </div>
              <SeverityBadge
                severity={(metrics.velocity.severity ?? 0) as SeverityLevel}
                size="lg"
              />
            </div>

            <div className="grid grid-cols-2 gap-6">
              <div className="p-4 bg-gray-50 dark:bg-gray-700 rounded-lg">
                <p className="text-sm text-gray-500 dark:text-gray-400 mb-1">Current Utilization</p>
                <p className="text-xl font-semibold text-gray-900 dark:text-white">
                  {(metrics.aprConvexity.utilization * 100).toFixed(2)}%
                </p>
              </div>
              <div className="p-4 bg-gray-50 dark:bg-gray-700 rounded-lg">
                <p className="text-sm text-gray-500 dark:text-gray-400 mb-1">Direction</p>
                <p className={`text-xl font-semibold ${trendColor}`}>
                  {delta > 0.01 ? "Increasing" : delta < -0.01 ? "Decreasing" : "Stable"}
                </p>
              </div>
            </div>
          </div>
        )}

        {/* Explanation */}
        <div className="mb-8 p-4 bg-gray-50 dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700">
          <h3 className="font-medium text-gray-900 dark:text-white mb-2">
            What is Utilization Velocity?
          </h3>
          <p className="text-sm text-gray-600 dark:text-gray-300">
            Utilization velocity measures how quickly the utilization rate is changing.
            High velocity (rapid increases) can indicate sudden demand for borrowing,
            which may push the protocol toward the kink point and trigger steep interest rate increases.
            Monitoring velocity helps predict and prepare for these conditions.
          </p>
        </div>

        {/* Thresholds info */}
        <div className="mb-8 p-4 bg-blue-50 dark:bg-blue-900/20 rounded-lg">
          <h3 className="font-medium text-blue-900 dark:text-blue-100 mb-2">
            Velocity Severity Thresholds
          </h3>
          <ul className="text-sm text-blue-800 dark:text-blue-200 space-y-1">
            <li>• <span className="text-green-600">Normal (0)</span>: &lt; 1%/hour change</li>
            <li>• <span className="text-yellow-600">Elevated (1)</span>: 1-5%/hour change</li>
            <li>• <span className="text-orange-600">Critical (2)</span>: 5-10%/hour change</li>
            <li>• <span className="text-red-600">Emergency (3)</span>: &gt; 10%/hour change</li>
          </ul>
        </div>

        {/* Chart */}
        <div className="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-6">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
              Velocity History
            </h3>
            <TimeRangeSelector selected={timeRange} onChange={setTimeRange} />
          </div>

          {history && (
            <TimeSeriesChart
              data={history.data}
              title=""
              unit="%/hr"
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
          )}
        </div>
      </div>
    </>
  );
}
