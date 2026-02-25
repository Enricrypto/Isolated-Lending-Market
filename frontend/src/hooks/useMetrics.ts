"use client"

import { useEffect, useState } from "react"
import type { CurrentMetricsResponse, HistoryResponse, TimeRange } from "@/types/metrics"
import { apiBase } from "@/lib/apiUrl"

interface UseMetricsOptions {
  vault?: string
  signal?: string
  range?: TimeRange
}

interface UseMetricsResult {
  metrics: CurrentMetricsResponse | null
  history: HistoryResponse | null
  loading: boolean
  error: string | null
}

export function useMetrics({ vault, signal, range }: UseMetricsOptions = {}): UseMetricsResult {
  const [metrics, setMetrics] = useState<CurrentMetricsResponse | null>(null)
  const [history, setHistory] = useState<HistoryResponse | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const fetchData = async () => {
      setLoading(true)
      setError(null)
      try {
        const base = apiBase()
        const vaultParam = vault ? `?vault=${vault}` : ""
        // Backend: /metrics  |  Fallback: /api/metrics
        const metricsUrl = base ? `${base}/metrics${vaultParam}` : `/api/metrics${vaultParam}`

        const promises: Promise<Response>[] = [fetch(metricsUrl)]
        if (signal && range) {
          const historyParams = new URLSearchParams({ signal, range })
          if (vault) historyParams.set("vault", vault)
          const historyUrl = base
            ? `${base}/history?${historyParams.toString()}`
            : `/api/history?${historyParams.toString()}`
          promises.push(fetch(historyUrl))
        }

        const results = await Promise.all(promises)

        if (results[0].ok) {
          setMetrics(await results[0].json())
        } else if (results[0].status === 404) {
          setError("No metrics available yet. Run a poll first.")
        } else {
          setError("Failed to fetch metrics")
        }

        if (signal && range && results[1]?.ok) {
          setHistory(await results[1].json())
        }
      } catch (err) {
        console.error("Failed to fetch data:", err)
        setError("Failed to connect to API")
      } finally {
        setLoading(false)
      }
    }

    fetchData()
  }, [vault, signal, range])

  return { metrics, history, loading, error }
}
