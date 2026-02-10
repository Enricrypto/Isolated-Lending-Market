"use client"

import { useEffect, useState } from "react"
import type { ProtocolOverviewResponse } from "@/types/metrics"

export function useVaults() {
  const [data, setData] = useState<ProtocolOverviewResponse | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    fetch("/api/vaults")
      .then((res) => (res.ok ? res.json() : Promise.reject("Failed to fetch vaults")))
      .then(setData)
      .catch((err) => setError(String(err)))
      .finally(() => setLoading(false))
  }, [])

  return { data, loading, error }
}
