/**
 * Cron Jobs
 * ---------
 * Replaces the fragile setInterval that lived inside the Next.js API route.
 * node-cron runs wall-clock-aligned jobs in the persistent Node.js process.
 *
 * Jobs:
 *   - Snapshot job: every minute — computes MarketSnapshot for all active markets
 *   - Health factor job: every 10 minutes — recomputes positions for recently active users
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

  console.log("[cron] Jobs started: snapshot (every 1m), health factor (every 10m)")
}
