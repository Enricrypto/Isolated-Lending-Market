"use client";

import { useEffect, useState } from "react";
import { Header } from "@/components/Header";
import { SeverityBadge } from "@/components/SeverityBadge";
import { TimeSeriesChart, TimeRangeSelector } from "@/components/TimeSeriesChart";
import type { CurrentMetricsResponse, HistoryResponse, TimeRange, SeverityLevel } from "@/types/metrics";
import { RefreshCw, AlertTriangle, CheckCircle } from "lucide-react";

export default function OraclePage() {
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
          fetch(`/api/history?signal=oracle&range=${timeRange}`),
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
        <Header title="Oracle Status" />
        <div className="p-6 flex items-center justify-center min-h-[400px]">
          <RefreshCw className="w-8 h-8 text-gray-400 animate-spin" />
        </div>
      </>
    );
  }

  return (
    <>
      <Header title="Oracle Status" />
      <div className="p-6">
        {/* Current Status */}
        {metrics && (
          <div className="mb-8 p-6 bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700">
            <div className="flex items-start justify-between mb-6">
              <div>
                <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-1">
                  {metrics.oracle.confidence}%
                </h2>
                <p className="text-gray-500 dark:text-gray-400">
                  Oracle Confidence
                </p>
              </div>
              <SeverityBadge severity={metrics.oracle.severity as SeverityLevel} size="lg" />
            </div>

            <dl className="grid grid-cols-2 md:grid-cols-4 gap-6">
              <div>
                <dt className="text-sm text-gray-500 dark:text-gray-400">Current Price</dt>
                <dd className="text-lg font-semibold text-gray-900 dark:text-white">
                  ${formatPrice(metrics.oracle.price)}
                </dd>
              </div>
              <div>
                <dt className="text-sm text-gray-500 dark:text-gray-400">Risk Score</dt>
                <dd className="text-lg font-semibold text-gray-900 dark:text-white">
                  {metrics.oracle.riskScore}/100
                </dd>
              </div>
              <div>
                <dt className="text-sm text-gray-500 dark:text-gray-400">Data Status</dt>
                <dd className="flex items-center gap-2 text-lg font-semibold">
                  {metrics.oracle.isStale ? (
                    <>
                      <AlertTriangle className="w-5 h-5 text-orange-500" />
                      <span className="text-orange-500">Stale</span>
                    </>
                  ) : (
                    <>
                      <CheckCircle className="w-5 h-5 text-green-500" />
                      <span className="text-green-500">Fresh</span>
                    </>
                  )}
                </dd>
              </div>
              <div>
                <dt className="text-sm text-gray-500 dark:text-gray-400">Confidence Level</dt>
                <dd className="text-lg font-semibold text-gray-900 dark:text-white">
                  {getConfidenceLabel(metrics.oracle.confidence)}
                </dd>
              </div>
            </dl>
          </div>
        )}

        {/* Stale warning */}
        {metrics?.oracle.isStale && (
          <div className="mb-8 p-4 bg-orange-50 dark:bg-orange-900/20 border border-orange-200 dark:border-orange-800 rounded-lg flex items-center gap-3">
            <AlertTriangle className="w-5 h-5 text-orange-500 flex-shrink-0" />
            <div>
              <p className="font-medium text-orange-800 dark:text-orange-200">
                Oracle data is stale
              </p>
              <p className="text-sm text-orange-700 dark:text-orange-300">
                The price feed has not been updated recently. The system is using the Last Known Good (LKG) price with decayed confidence.
              </p>
            </div>
          </div>
        )}

        {/* Thresholds info */}
        <div className="mb-8 p-4 bg-blue-50 dark:bg-blue-900/20 rounded-lg">
          <h3 className="font-medium text-blue-900 dark:text-blue-100 mb-2">
            Oracle Severity Thresholds
          </h3>
          <ul className="text-sm text-blue-800 dark:text-blue-200 space-y-1">
            <li>• <span className="text-green-600">Normal (0)</span>: Confidence ≥ 95%, fresh data</li>
            <li>• <span className="text-yellow-600">Elevated (1)</span>: Confidence 80-94%, or slightly stale</li>
            <li>• <span className="text-orange-600">Critical (2)</span>: Confidence 50-79%, or moderately stale</li>
            <li>• <span className="text-red-600">Emergency (3)</span>: Confidence &lt; 50%, or oracle unavailable</li>
          </ul>
        </div>

        {/* Chart */}
        <div className="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-6">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
              Oracle Confidence History
            </h3>
            <TimeRangeSelector selected={timeRange} onChange={setTimeRange} />
          </div>

          {history && (
            <TimeSeriesChart
              data={history.data}
              title=""
              unit="%"
              thresholds={[
                { value: 95, label: "Normal", color: "#22c55e" },
                { value: 80, label: "Elevated", color: "#eab308" },
                { value: 50, label: "Critical", color: "#f97316" },
              ]}
              height={400}
            />
          )}
        </div>
      </div>
    </>
  );
}

function formatPrice(priceString: string): string {
  const price = BigInt(priceString);
  // Price is in 18 decimals, convert to USD
  const usd = Number(price) / 1e18;
  return usd.toFixed(4);
}

function getConfidenceLabel(confidence: number): string {
  if (confidence >= 95) return "High";
  if (confidence >= 80) return "Good";
  if (confidence >= 50) return "Degraded";
  return "Low";
}
