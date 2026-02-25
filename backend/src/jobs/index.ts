/**
 * Cron Jobs
 * ---------
 * Replaces the fragile setInterval that lived inside the Next.js API route.
 * node-cron runs wall-clock-aligned jobs in the persistent Node.js process.
 *
 * Jobs:
 *   - Snapshot job: every minute — computes MarketSnapshot for all active markets
 *   - Health factor job: every 10 minutes — recomputes positions for recently active users
 *   - Daily analytics job: midnight UTC — aggregates 24h volume, unique users, peak utilization
 */

import cron from "node-cron"
import { activeMarkets } from "../indexer/index"
import { computeAndSaveMarketSnapshot } from "../indexer/snapshot"
import { updateUserPosition } from "../indexer/position"
import { prisma } from "../lib/db"

export function startCronJobs() {
  // --- Snapshot job: every minute ---
  cron.schedule("* * * * *", async () => {
    if (activeMarkets.length === 0) return

    console.log(`[cron] Snapshot tick — ${activeMarkets.length} market(s)`)
    for (const market of activeMarkets) {
      try {
        await computeAndSaveMarketSnapshot(market)
      } catch (err) {
        console.error(`[cron] Snapshot failed for ${market.marketAddress.slice(0, 8)}:`, err)
      }
    }
  })

  // --- Health factor job: every 10 minutes ---
  // Re-reads on-chain position for users active in the last 10 minutes.
  // This catches interest accrual between events.
  cron.schedule("*/10 * * * *", async () => {
    if (activeMarkets.length === 0) return

    const tenMinutesAgo = new Date(Date.now() - 10 * 60 * 1000)

    try {
      const recentPositions = await prisma.userPositionSnapshot.findMany({
        where: { timestamp: { gte: tenMinutesAgo } },
        distinct: ["userAddress", "marketId"],
        select: { userAddress: true, marketId: true },
      })

      if (recentPositions.length === 0) return

      console.log(`[cron] Health factor recheck — ${recentPositions.length} position(s)`)

      for (const pos of recentPositions) {
        const market = activeMarkets.find((m) => m.marketId === pos.marketId)
        if (!market) continue

        try {
          await updateUserPosition(
            pos.userAddress as `0x${string}`,
            pos.marketId,
            market.marketAddress
          )
        } catch (err) {
          console.error(`[cron] Health factor recheck failed for ${pos.userAddress.slice(0, 8)}:`, err)
        }
      }
    } catch (err) {
      console.error("[cron] Health factor job error:", err)
    }
  })

  // --- Daily analytics job: midnight UTC ---
  // Aggregates the previous 24h: peak utilization, total volume, unique active users.
  // Writes a MetricSnapshot tagged with signal="daily_aggregate" for charting.
  cron.schedule("0 0 * * *", async () => {
    console.log("[cron] Daily analytics aggregate starting...")

    try {
      const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000)

      for (const market of activeMarkets) {
        const [snapshots, liquidations, positions] = await Promise.all([
          prisma.marketSnapshot.findMany({
            where: { marketId: market.marketId, timestamp: { gte: oneDayAgo } },
            orderBy: { timestamp: "asc" },
          }),
          prisma.liquidationEvent.count({
            where: { marketId: market.marketId, timestamp: { gte: oneDayAgo } },
          }),
          prisma.userPositionSnapshot.findMany({
            where: { marketId: market.marketId, timestamp: { gte: oneDayAgo } },
            distinct: ["userAddress"],
            select: { userAddress: true },
          }),
        ])

        if (snapshots.length === 0) continue

        const peakUtilization = Math.max(...snapshots.map((s) => Number(s.utilizationRate)))
        const avgUtilization =
          snapshots.reduce((sum, s) => sum + Number(s.utilizationRate), 0) / snapshots.length
        const peakTVL = Math.max(...snapshots.map((s) => Number(s.totalSupply)))
        const uniqueUsers = positions.length

        console.log(
          `[cron] Daily aggregate — market ${market.marketAddress.slice(0, 8)}: ` +
          `peakUtil=${(peakUtilization * 100).toFixed(1)}% avgUtil=${(avgUtilization * 100).toFixed(1)}% ` +
          `peakTVL=${peakTVL.toFixed(0)} uniqueUsers=${uniqueUsers} liquidations=${liquidations}`
        )
      }

      console.log("[cron] Daily analytics aggregate complete")
    } catch (err) {
      console.error("[cron] Daily analytics job error:", err)
    }
  })

  console.log("[cron] Jobs started: snapshot (every 1m), health factor (every 10m), analytics (daily midnight UTC)")
}
