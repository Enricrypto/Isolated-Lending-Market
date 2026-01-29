"use client";

import { useEffect, useState } from "react";
import { Header } from "@/components/Header";
import { SeverityBadge } from "@/components/SeverityBadge";
import { TimeSeriesChart, TimeRangeSelector } from "@/components/TimeSeriesChart";
import type { CurrentMetricsResponse, HistoryResponse, TimeRange, SeverityLevel } from "@/types/metrics";
import { RefreshCw } from "lucide-react";

export default function RatesPage() {
  const [metrics, setMetrics] = useState<CurrentMetricsResponse | null>(null);
  const [utilizationHistory, setUtilizationHistory] = useState<HistoryResponse | null>(null);
  const [rateHistory, setRateHistory] = useState<HistoryResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [timeRange, setTimeRange] = useState<TimeRange>("24h");

  useEffect(() => {
    const fetchData = async () => {
      setLoading(true);
      try {
        const [metricsRes, utilizationRes, rateRes] = await Promise.all([
          fetch("/api/metrics"),
          fetch(`/api/history?signal=utilization&range=${timeRange}`),
          fetch(`/api/history?signal=borrowRate&range=${timeRange}`),
        ]);

        if (metricsRes.ok) {
          setMetrics(await metricsRes.json());
        }
        if (utilizationRes.ok) {
          setUtilizationHistory(await utilizationRes.json());
        }
        if (rateRes.ok) {
          setRateHistory(await rateRes.json());
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
        <Header title="Interest Rates" />
        <div className="p-6 flex items-center justify-center min-h-[400px]">
          <RefreshCw className="w-8 h-8 text-gray-400 animate-spin" />
        </div>
      </>
    );
  }

  return (
    <>
      <Header title="Interest Rates" />
      <div className="p-6">
        {/* Current Status */}
        {metrics && (
          <div className="mb-8 grid grid-cols-1 md:grid-cols-2 gap-6">
            {/* Utilization Card */}
            <div className="p-6 bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700">
              <div className="flex items-start justify-between mb-4">
                <div>
                  <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-1">
                    {(metrics.aprConvexity.utilization * 100).toFixed(2)}%
                  </h2>
                  <p className="text-gray-500 dark:text-gray-400">
                    Utilization Rate
                  </p>
                </div>
                <SeverityBadge severity={metrics.aprConvexity.severity as SeverityLevel} size="lg" />
              </div>

              <div className="mt-4 p-3 bg-gray-50 dark:bg-gray-700 rounded-lg">
                <p className="text-sm text-gray-600 dark:text-gray-300">
                  <span className="font-medium">{(metrics.aprConvexity.distanceToKink * 100).toFixed(1)}%</span>
                  {" "}away from the kink point (optimal utilization)
                </p>
              </div>
            </div>

            {/* Borrow Rate Card */}
            <div className="p-6 bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700">
              <div className="flex items-start justify-between mb-4">
                <div>
                  <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-1">
                    {(metrics.aprConvexity.borrowRate * 100).toFixed(2)}%
                  </h2>
                  <p className="text-gray-500 dark:text-gray-400">
                    Borrow APR
                  </p>
                </div>
              </div>

              <div className="mt-4 p-3 bg-gray-50 dark:bg-gray-700 rounded-lg">
                <p className="text-sm text-gray-600 dark:text-gray-300">
                  Annual interest rate for borrowers
                </p>
              </div>
            </div>
          </div>
        )}

        {/* Thresholds info */}
        <div className="mb-8 p-4 bg-blue-50 dark:bg-blue-900/20 rounded-lg">
          <h3 className="font-medium text-blue-900 dark:text-blue-100 mb-2">
            APR Convexity Severity (Distance to Kink)
          </h3>
          <ul className="text-sm text-blue-800 dark:text-blue-200 space-y-1">
            <li>• <span className="text-green-600">Normal (0)</span>: More than 15% below kink</li>
            <li>• <span className="text-yellow-600">Elevated (1)</span>: 5-15% below kink</li>
            <li>• <span className="text-orange-600">Critical (2)</span>: Within 5% of kink</li>
            <li>• <span className="text-red-600">Emergency (3)</span>: Above kink (steep rate increase)</li>
          </ul>
        </div>

        {/* Charts */}
        <div className="space-y-6">
          <div className="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-6">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
                Utilization Rate History
              </h3>
              <TimeRangeSelector selected={timeRange} onChange={setTimeRange} />
            </div>

            {utilizationHistory && (
              <TimeSeriesChart
                data={utilizationHistory.data}
                title=""
                unit="%"
                thresholds={[
                  { value: 80, label: "Kink (80%)", color: "#f97316" },
                ]}
                height={300}
              />
            )}
          </div>

          <div className="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-6">
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-4">
              Borrow Rate History
            </h3>

            {rateHistory && (
              <TimeSeriesChart
                data={rateHistory.data}
                title=""
                unit="%"
                height={300}
              />
            )}
          </div>
        </div>
      </div>
    </>
  );
}
