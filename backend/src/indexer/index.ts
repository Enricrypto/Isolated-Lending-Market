/**
 * Indexer Orchestrator
 * --------------------
 * Starts the deterministic block-based indexer for all active markets.
 *
 * On startup:
 *   1. Load active markets from DB
 *   2. Read SyncState — find last processed block
 *   3. Catch up all missed blocks up to (tip - CONFIRMATIONS)
 *   4. Subscribe to new block headers via watchBlockNumber
 *   5. For each new confirmed block, process via processBlockRange
 *
 * The system survives restarts — SyncState persists the cursor.
 * Periodic snapshots are handled by node-cron jobs (src/jobs/index.ts).
 */

import "dotenv/config"
import { prisma } from "../lib/db"
import { client, CONFIRMATIONS, DEPLOYMENT_BLOCK } from "../lib/rpc"
import { processBlockRange, getSyncState } from "./block-processor"
import { seedMarketParams } from "../lib/seedMarketParams"
import { logger } from "../lib/logger"
import type { MarketConfig } from "./listener"
import type { WatchBlockNumberReturnType } from "viem"

let running    = false
let startedAt: Date | null = null
let unwatchers: WatchBlockNumberReturnType[] = []

/** Loaded markets — shared with cron jobs */
export let activeMarkets: MarketConfig[] = []

export async function startIndexer() {
  if (running) {
    logger.info("[indexer] Already running")
    return { alreadyRunning: true }
  }

  logger.info("[indexer] Starting...")

  // 1. Load markets from DB
  const markets = await prisma.market.findMany({ where: { isActive: true } })
  if (markets.length === 0) {
    logger.warn("[indexer] No active markets found. Run seed first.")
    return { error: "No active markets" }
  }

  logger.info({ count: markets.length }, "[indexer] Loaded active markets")

  activeMarkets = markets.map((m) => ({
    marketId:            m.id,
    vaultAddress:        m.vaultAddress        as `0x${string}`,
    marketAddress:       m.marketAddress       as `0x${string}`,
    irmAddress:          m.irmAddress          as `0x${string}`,
    oracleRouterAddress: m.oracleRouterAddress  as `0x${string}`,
    loanAsset:           m.loanAsset           as `0x${string}`,
    loanAssetDecimals:   m.loanAssetDecimals,
  }))

  // Seed IRM + risk params from chain (non-blocking — failures are logged)
  seedMarketParams(activeMarkets).catch((err) =>
    logger.error({ err }, "[indexer] seedMarketParams failed")
  )

  // 2. Determine start block from SyncState
  const syncState    = await getSyncState()
  const currentBlock = await client.getBlockNumber()
  const safeHead     = currentBlock - BigInt(CONFIRMATIONS)
  const startBlock   = syncState
    ? BigInt(syncState.lastProcessedBlock) + 1n
    : DEPLOYMENT_BLOCK

  // 3. Catch up missed blocks
  if (startBlock <= safeHead) {
    logger.info(
      { from: Number(startBlock), to: Number(safeHead) },
      "[indexer] Catching up missed blocks"
    )
    await processBlockRange(startBlock, safeHead, activeMarkets)
  } else {
    logger.info({ block: Number(safeHead) }, "[indexer] Already at safe head — no catch-up needed")
  }

  // 4. Track confirmed block cursor
  let lastProcessed = safeHead

  // 5. Watch for new confirmed blocks
  const unwatch = client.watchBlockNumber({
    onBlockNumber: async (tip) => {
      const confirmed = tip - BigInt(CONFIRMATIONS)
      if (confirmed <= lastProcessed) return

      const from = lastProcessed + 1n
      try {
        await processBlockRange(from, confirmed, activeMarkets)
        lastProcessed = confirmed
      } catch (err) {
        logger.error({ from: Number(from), to: Number(confirmed), err }, "[indexer] Block range error")
      }
    },
    onError: (err) => {
      logger.error({ err }, "[indexer] watchBlockNumber error")
    },
  })

  unwatchers.push(unwatch)
  running   = true
  startedAt = new Date()

  logger.info("[indexer] Running")
  return {
    started: true,
    markets: markets.map((m) => ({ id: m.id, label: m.label, symbol: m.symbol })),
  }
}

export function stopIndexer() {
  if (!running) return { alreadyStopped: true }

  for (const unwatch of unwatchers) {
    unwatch()
  }
  unwatchers    = []
  activeMarkets = []

  running = false
  const uptime = startedAt ? Date.now() - startedAt.getTime() : 0
  startedAt = null

  logger.info({ uptimeMs: uptime }, "[indexer] Stopped")
  return { stopped: true, uptimeMs: uptime }
}

export function getIndexerStatus() {
  return {
    running,
    startedAt:     startedAt?.toISOString() ?? null,
    watcherCount:  unwatchers.length,
    activeMarkets: activeMarkets.length,
  }
}
