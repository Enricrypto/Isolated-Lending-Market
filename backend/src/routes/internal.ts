/**
 * Internal Routes
 * ---------------
 * Secured endpoints for operational recovery and scheduled aggregation.
 * Never expose these publicly — always require Authorization: Bearer <SECRET>.
 *
 * POST /internal/resync
 *   Replays from lastProcessedBlock - REORG_BUFFER to current safeHead.
 *   Use when you suspect missed blocks or after a manual DB repair.
 *   Secured with ADMIN_SECRET.
 *
 * POST /internal/recompute-markets
 *   Recomputes MarketSnapshot for all active markets via on-chain multicall.
 *   Called by GitHub Actions cron every 5 minutes.
 *   Secured with CRON_SECRET.
 */

import { Router, Request, Response } from "express"
import { client, CONFIRMATIONS, REORG_BUFFER, DEPLOYMENT_BLOCK, CHAIN_ID } from "../lib/rpc"
import { processBlockRange, getSyncState } from "../indexer/block-processor"
import { computeAndSaveMarketSnapshot } from "../indexer/snapshot"
import { activeMarkets } from "../indexer/index"
import { logger } from "../lib/logger"

const router = Router()

// ─── Auth middleware ──────────────────────────────────────────────────────────

function requireBearer(secret: string | undefined) {
  return (req: Request, res: Response, next: () => void) => {
    if (!secret) {
      res.status(503).json({ error: "Secret not configured on server" })
      return
    }
    const auth = req.headers.authorization ?? ""
    if (auth !== `Bearer ${secret}`) {
      res.status(401).json({ error: "Unauthorized" })
      return
    }
    next()
  }
}

// ─── POST /internal/resync ────────────────────────────────────────────────────

router.post(
  "/resync",
  requireBearer(process.env.ADMIN_SECRET),
  async (_req: Request, res: Response) => {
    const started = Date.now()
    logger.info("[internal/resync] Starting resync")

    try {
      const syncState    = await getSyncState()
      const currentBlock = await client.getBlockNumber()
      const safeHead     = currentBlock - BigInt(CONFIRMATIONS)

      // Replay from lastProcessedBlock - REORG_BUFFER (or DEPLOYMENT_BLOCK, whichever is later)
      const replayFrom = syncState
        ? BigInt(Math.max(syncState.lastProcessedBlock - REORG_BUFFER, Number(DEPLOYMENT_BLOCK)))
        : DEPLOYMENT_BLOCK

      if (activeMarkets.length === 0) {
        res.status(503).json({ error: "No active markets loaded — start the indexer first" })
        return
      }

      logger.info(
        { from: Number(replayFrom), to: Number(safeHead) },
        "[internal/resync] Replaying blocks"
      )

      await processBlockRange(replayFrom, safeHead, activeMarkets)

      const durationMs = Date.now() - started
      logger.info({ durationMs }, "[internal/resync] Complete")

      res.json({
        ok: true,
        from: Number(replayFrom),
        to: Number(safeHead),
        durationMs,
      })
    } catch (err) {
      logger.error({ err }, "[internal/resync] Error")
      res.status(500).json({
        error: "Resync failed",
        details: err instanceof Error ? err.message : "Unknown",
      })
    }
  }
)

// ─── POST /internal/recompute-markets ────────────────────────────────────────

router.post(
  "/recompute-markets",
  requireBearer(process.env.CRON_SECRET),
  async (_req: Request, res: Response) => {
    const started = Date.now()
    logger.info("[internal/recompute-markets] Starting")

    if (activeMarkets.length === 0) {
      res.status(503).json({ error: "No active markets loaded — start the indexer first" })
      return
    }

    const results: Array<{ symbol: string; ok: boolean; error?: string }> = []

    for (const market of activeMarkets) {
      try {
        await computeAndSaveMarketSnapshot(market)
        results.push({ symbol: market.marketId, ok: true })
      } catch (err) {
        const msg = err instanceof Error ? err.message : "Unknown"
        logger.error({ market: market.marketAddress.slice(0, 10), err }, "[internal/recompute-markets] Snapshot failed")
        results.push({ symbol: market.marketId, ok: false, error: msg })
      }
    }

    const durationMs = Date.now() - started
    logger.info({ recomputed: results.length, durationMs }, "[internal/recompute-markets] Complete")

    res.json({ ok: true, recomputed: results.length, durationMs, results })
  }
)

export default router
