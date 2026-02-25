import { Router, Request, Response } from "express"
import { getLatestMarketSnapshot } from "../lib/db"
import type { SeverityLevel } from "../lib/severity"

const DEFAULT_VAULT = process.env.DEFAULT_VAULT_ADDRESS ?? ""

const router = Router()

router.get("/", async (req: Request, res: Response) => {
  try {
    const vaultAddress = (req.query.vault as string) || DEFAULT_VAULT

    if (!vaultAddress) {
      res.status(400).json({ error: "Missing 'vault' query parameter and no DEFAULT_VAULT_ADDRESS set" })
      return
    }

    const snapshot = await getLatestMarketSnapshot(vaultAddress)

    if (!snapshot) {
      res.status(404).json({ error: "No metrics available. Start the indexer first." })
      return
    }

    res.json({
      vaultAddress,
      timestamp: snapshot.timestamp.toISOString(),
      liquidity: {
        available: Number(snapshot.availableLiquidity),
        totalBorrows: Number(snapshot.totalBorrows),
        depthRatio: Number(snapshot.liquidityDepthRatio),
        severity: snapshot.liquiditySeverity as SeverityLevel,
      },
      aprConvexity: {
        utilization: Number(snapshot.utilizationRate),
        borrowRate: Number(snapshot.borrowRate),
        distanceToKink: Number(snapshot.distanceToKink),
        severity: snapshot.aprConvexitySeverity as SeverityLevel,
      },
      oracle: {
        price: Number(snapshot.oraclePrice),
        confidence: snapshot.oracleConfidence,
        riskScore: snapshot.oracleRiskScore,
        isStale: snapshot.oracleIsStale,
        severity: snapshot.oracleSeverity as SeverityLevel,
      },
      velocity: {
        delta: null,
        severity: null,
      },
      overall: snapshot.overallSeverity as SeverityLevel,
    })
  } catch (error) {
    console.error("[routes/metrics] Error:", error)
    res.status(500).json({ error: "Failed to fetch metrics" })
  }
})

export default router
