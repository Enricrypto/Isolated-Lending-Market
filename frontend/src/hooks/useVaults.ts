"use client"

import { useEffect, useState } from "react"
import type { ProtocolOverviewResponse } from "@/types/metrics"
import { apiBase } from "@/lib/apiUrl"

export function useVaults() {
  const [data, setData] = useState<ProtocolOverviewResponse | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const base = apiBase()
    // Backend: GET /markets  |  Fallback (no NEXT_PUBLIC_API_URL): GET /api/vaults
    const url = base ? `${base}/markets` : "/api/vaults"
    fetch(url)
      .then((res) => (res.ok ? res.json() : Promise.reject("Failed to fetch vaults")))
      .then(setData)
      .catch((err) => setError(String(err)))
      .finally(() => setLoading(false))
  }, [])

  return { data, loading, error }
}
