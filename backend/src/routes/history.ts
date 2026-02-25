import { Router, Request, Response } from "express"
import { getMarketSnapshotsInRange, getTimeRangeStart } from "../lib/db"
import type { SeverityLevel } from "../lib/severity"

const DEFAULT_VAULT = process.env.DEFAULT_VAULT_ADDRESS ?? ""

type SignalType = "liquidity" | "utilization" | "borrowRate" | "oracle" | "velocity"
const VALID_SIGNALS: SignalType[] = ["liquidity", "utilization", "borrowRate", "oracle", "velocity"]

const router = Router()

router.get("/", async (req: Request, res: Response) => {
  try {
    const signal = req.query.signal as SignalType | undefined
    const range = (req.query.range as string) || "24h"
    const vaultAddress = (req.query.vault as string) || DEFAULT_VAULT

    if (!signal) {
      res.status(400).json({
        error: "Missing 'signal' parameter. Options: liquidity, utilization, borrowRate, oracle, velocity",
      })
      return
    }

    if (!VALID_SIGNALS.includes(signal)) {
      res.status(400).json({ error: `Invalid signal. Options: ${VALID_SIGNALS.join(", ")}` })
      return
    }

    if (!vaultAddress) {
      res.status(400).json({ error: "Missing 'vault' query parameter" })
      return
    }

    const startTime = getTimeRangeStart(range)
    const snapshots = await getMarketSnapshotsInRange(vaultAddress, startTime)

    const data = snapshots.map((snapshot) => {
      let value: number
      let severity: SeverityLevel

      switch (signal) {
        case "liquidity":
          value = Number(snapshot.liquidityDepthRatio)
          severity = snapshot.liquiditySeverity as SeverityLevel
          break
        case "utilization":
          value = Number(snapshot.utilizationRate) * 100
          severity = snapshot.aprConvexitySeverity as SeverityLevel
          break
        case "borrowRate":
          value = Number(snapshot.borrowRate) * 100
          severity = snapshot.aprConvexitySeverity as SeverityLevel
          break
        case "oracle":
          value = snapshot.oracleConfidence
          severity = snapshot.oracleSeverity as SeverityLevel
          break
        case "velocity":
          value = 0
          severity = 0
          break
        default:
          value = 0
          severity = 0
      }

      return {
        timestamp: snapshot.timestamp.toISOString(),
        value,
        severity,
      }
    })

    res.json({ signal, range, data })
  } catch (error) {
    console.error("[routes/history] Error:", error)
    res.status(500).json({ error: "Failed to fetch history" })
  }
})

export default router
