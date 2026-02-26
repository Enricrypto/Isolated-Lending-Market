"use client"

import { useEffect, useState, useCallback } from "react"
import { apiBase } from "@/lib/apiUrl"

export interface UserPosition {
  marketId: string
  label: string
  symbol: string
  vaultAddress: string
  collateralValue: number
  totalDebt: number
  healthFactor: number
  borrowingPower: number
  lastUpdated: string
}

export function usePositions(userAddress: string | undefined) {
  const [positions, setPositions] = useState<UserPosition[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const fetchPositions = useCallback(async () => {
    if (!userAddress) {
      setPositions([])
      return
    }
    setLoading(true)
    setError(null)
    try {
      const base = apiBase()
      const url = `${base}/positions?user=${userAddress.toLowerCase()}`
      const res = await fetch(url)
      if (!res.ok) throw new Error("Failed to fetch positions")
      const data = await res.json()
      setPositions(data.positions ?? [])
    } catch (err) {
      setError(String(err))
    } finally {
      setLoading(false)
    }
  }, [userAddress])

  useEffect(() => {
    fetchPositions()
  }, [fetchPositions])

  return { positions, loading, error, refetch: fetchPositions }
}
