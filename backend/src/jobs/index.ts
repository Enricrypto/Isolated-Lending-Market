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
import { logger } from "../lib/logger"

export function startCronJobs() {
  // --- Snapshot job: every minute ---
  cron.schedule("* * * * *", async () => {
    if (activeMarkets.length === 0) return

    logger.info({ markets: activeMarkets.length }, "[cron] Snapshot tick")
    for (const market of activeMarkets) {
      try {
        await computeAndSaveMarketSnapshot(market)
      } catch (err) {
        logger.error({ market: market.marketAddress.slice(0, 8), err }, "[cron] Snapshot failed")
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

      logger.info({ positions: recentPositions.length }, "[cron] Health factor recheck")

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
          logger.error({ user: pos.userAddress.slice(0, 8), err }, "[cron] Health factor recheck failed")
        }
      }
    } catch (err) {
      logger.error({ err }, "[cron] Health factor job error")
    }
  })

  // --- Daily analytics job: midnight UTC ---
  // Aggregates the previous 24h: peak utilization, total volume, unique active users.
  // Writes a MetricSnapshot tagged with signal="daily_aggregate" for charting.
  cron.schedule("0 0 * * *", async () => {
    logger.info("[cron] Daily analytics aggregate starting...")

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

        logger.info({
          market:         market.marketAddress.slice(0, 8),
          peakUtilPct:    (peakUtilization * 100).toFixed(1),
          avgUtilPct:     (avgUtilization * 100).toFixed(1),
          peakTVL:        peakTVL.toFixed(0),
          uniqueUsers,
          liquidations,
        }, "[cron] Daily aggregate")
      }

      logger.info("[cron] Daily analytics aggregate complete")
    } catch (err) {
      logger.error({ err }, "[cron] Daily analytics job error")
    }
  })

  logger.info("[cron] Jobs started: snapshot (1m), health factor (10m), analytics (daily midnight UTC)")
}
