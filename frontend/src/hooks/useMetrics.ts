"use client"

import { useEffect, useState } from "react"
import type { CurrentMetricsResponse, HistoryResponse, TimeRange } from "@/types/metrics"

interface UseMetricsOptions {
  signal?: string
  range?: TimeRange
}

interface UseMetricsResult {
  metrics: CurrentMetricsResponse | null
  history: HistoryResponse | null
  loading: boolean
  error: string | null
}

export function useMetrics({ signal, range }: UseMetricsOptions = {}): UseMetricsResult {
  const [metrics, setMetrics] = useState<CurrentMetricsResponse | null>(null)
  const [history, setHistory] = useState<HistoryResponse | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const fetchData = async () => {
      setLoading(true)
      setError(null)
      try {
        const promises: Promise<Response>[] = [fetch("/api/metrics")]
        if (signal && range) {
          promises.push(fetch(`/api/history?signal=${signal}&range=${range}`))
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
  }, [signal, range])

  return { metrics, history, loading, error }
}
