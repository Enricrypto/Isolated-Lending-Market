import { Router, Request, Response } from "express"
import { getLatestSnapshotsForAllMarkets } from "../lib/db"
import { computeProtocolSeverity, type SeverityLevel } from "../lib/severity"

const router = Router()

router.get("/", async (_req: Request, res: Response) => {
  try {
    const results = await getLatestSnapshotsForAllMarkets()

    const vaults = results.map(({ market, snapshot }) => {
      if (!snapshot) {
        return {
          vaultAddress: market.vaultAddress,
          label: market.label,
          symbol: market.symbol,
          overallSeverity: 0 as SeverityLevel,
          utilization: 0,
          totalSupply: 0,
          totalBorrows: 0,
          oraclePrice: 0,
          lastUpdated: "",
        }
      }

      return {
        vaultAddress: market.vaultAddress,
        label: market.label,
        symbol: market.symbol,
        overallSeverity: snapshot.overallSeverity as SeverityLevel,
        utilization: Number(snapshot.utilizationRate),
        totalSupply: Number(snapshot.totalSupply),
        totalBorrows: Number(snapshot.totalBorrows),
        oraclePrice: Number(snapshot.oraclePrice),
        lastUpdated: snapshot.timestamp.toISOString(),
      }
    })

    const vaultSeverities = vaults
      .filter((v) => v.lastUpdated)
      .map((v) => v.overallSeverity)

    res.json({
      vaults,
      protocolSeverity: computeProtocolSeverity(vaultSeverities),
      totalTVL: vaults.reduce((sum, v) => sum + v.totalSupply, 0),
      totalBorrows: vaults.reduce((sum, v) => sum + v.totalBorrows, 0),
      timestamp: new Date().toISOString(),
    })
  } catch (error) {
    console.error("[routes/markets] Error:", error)
    res.status(500).json({ error: "Failed to fetch markets" })
  }
})

export default router
