import { Router, Request, Response } from "express"
import { prisma } from "../lib/db"
import { computeProtocolSeverity, type SeverityLevel } from "../lib/severity"

const router = Router()

/** Raw-SQL lookup for market params — bypasses the un-regenerated Prisma client. */
async function getMarketParams(marketId: string) {
  try {
    const rows = await prisma.$queryRaw<Array<{
      base_rate: string; slope1: string; slope2: string;
      optimal_utilization: string; lltv: string;
      liquidation_penalty: string; protocol_fee: string;
    }>>`
      SELECT base_rate, slope1, slope2, optimal_utilization,
             lltv, liquidation_penalty, protocol_fee
      FROM "MarketParams"
      WHERE market_id = ${marketId}
      LIMIT 1
    `
    return rows[0] ?? null
  } catch {
    return null
  }
}

router.get("/", async (_req: Request, res: Response) => {
  try {
    const markets = await prisma.market.findMany({ where: { isActive: true } })

    const vaults = await Promise.all(
      markets.map(async (market) => {
        const [snapshot, rawParams] = await Promise.all([
          prisma.marketSnapshot.findFirst({
            where:   { marketId: market.id },
            orderBy: { timestamp: "desc" },
          }),
          getMarketParams(market.id),
        ])

        const base = {
          vaultAddress:  market.vaultAddress,
          marketAddress: market.marketAddress,
          label:         market.label,
          symbol:        market.symbol,
        }

        // IRM params — DB overrides snapshot defaults
        const baseRate           = rawParams ? Number(rawParams.base_rate)            : 0.02
        const slope1             = rawParams ? Number(rawParams.slope1)               : 0.04
        const slope2             = rawParams ? Number(rawParams.slope2)               : 0.60
        const optimalUtilization = rawParams
          ? Number(rawParams.optimal_utilization)
          : snapshot ? Number(snapshot.optimalUtilization) : 0.80
        const lltv               = rawParams ? Number(rawParams.lltv)                 : 0.85
        const liquidationPenalty = rawParams ? Number(rawParams.liquidation_penalty)  : 0.05
        const protocolFee        = rawParams ? Number(rawParams.protocol_fee)         : 0.10

        if (!snapshot) {
          return {
            ...base,
            overallSeverity:    0 as SeverityLevel,
            utilization:        0,
            totalSupply:        0,
            totalBorrows:       0,
            oraclePrice:        0,
            borrowRate:         baseRate,
            lendingRate:        0,
            optimalUtilization,
            baseRate,
            slope1,
            slope2,
            lltv,
            liquidationPenalty,
            protocolFee,
            lastUpdated:        "",
          }
        }

        return {
          ...base,
          overallSeverity:    snapshot.overallSeverity as SeverityLevel,
          utilization:        Number(snapshot.utilizationRate),
          totalSupply:        Number(snapshot.totalSupply),
          totalBorrows:       Number(snapshot.totalBorrows),
          oraclePrice:        Number(snapshot.oraclePrice),
          borrowRate:         Number(snapshot.borrowRate),
          lendingRate:        Number(snapshot.lendingRate),
          optimalUtilization: Number(snapshot.optimalUtilization) || optimalUtilization,
          baseRate,
          slope1,
          slope2,
          lltv,
          liquidationPenalty,
          protocolFee,
          lastUpdated:        snapshot.timestamp.toISOString(),
        }
      })
    )

    const vaultSeverities = vaults
      .filter((v) => v.lastUpdated)
      .map((v) => v.overallSeverity)

    res.json({
      vaults,
      protocolSeverity: computeProtocolSeverity(vaultSeverities),
      totalTVL:         vaults.reduce((sum, v) => sum + v.totalSupply, 0),
      totalBorrows:     vaults.reduce((sum, v) => sum + v.totalBorrows, 0),
      timestamp:        new Date().toISOString(),
    })
  } catch (error) {
    console.error("[routes/markets] Error:", error)
    res.status(500).json({ error: "Failed to fetch markets" })
  }
})

export default router
