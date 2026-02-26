/**
 * Block Processor
 * ---------------
 * Deterministic, block-by-block log fetching and processing.
 *
 * Design:
 *   - Fetches logs via getLogs per block range (NOT raw watchContractEvent callbacks)
 *   - Checks for reorgs by comparing block parentHash to stored IndexedBlock hashes
 *   - On reorg: rolls back derived state and replays deterministically
 *   - Updates SyncState after each successful block
 *   - Safe to replay — all writes are idempotent or upsert-based
 */

import { decodeEventLog } from "viem"
import { client, CONFIRMATIONS, REORG_BUFFER, CHAIN_ID, DEPLOYMENT_BLOCK } from "../lib/rpc"
import { MARKET_EVENTS_ABI } from "./events"
import { processEventLog } from "./listener"
import { prisma } from "../lib/db"
import { logger } from "../lib/logger"
import type { MarketConfig } from "./listener"

// ─── Sync State ──────────────────────────────────────────────────────────────

export async function getSyncState() {
  return prisma.syncState.findFirst({ where: { chainId: CHAIN_ID } })
}

// ─── Reorg Detection ─────────────────────────────────────────────────────────

/**
 * Check if the block's parentHash matches our stored hash for the previous block.
 * Returns the reorg start block number if a reorg is detected, null if clean.
 */
async function checkReorg(
  blockNumber: bigint,
  parentHash: string
): Promise<bigint | null> {
  const prevBlockNumber = Number(blockNumber) - 1
  if (prevBlockNumber < Number(DEPLOYMENT_BLOCK)) return null

  const stored = await prisma.indexedBlock.findUnique({
    where: { blockNumber: prevBlockNumber },
  })

  if (!stored) return null // No stored hash means we haven't processed that block yet

  if (stored.blockHash !== parentHash) {
    logger.warn(
      { blockNumber: Number(blockNumber), stored: stored.blockHash, observed: parentHash },
      "[block-processor] Reorg detected"
    )
    // Roll back to REORG_BUFFER blocks before the reorg
    return BigInt(Math.max(prevBlockNumber - REORG_BUFFER, Number(DEPLOYMENT_BLOCK)))
  }

  return null
}

// ─── Rollback ────────────────────────────────────────────────────────────────

/**
 * Delete all derived state at or after reorgStart, reset SyncState.
 * After rollback, the caller should re-process from reorgStart.
 */
export async function rollbackFrom(reorgStart: bigint): Promise<void> {
  const from = Number(reorgStart)
  logger.warn({ from }, "[block-processor] Rolling back state from block")

  await prisma.$transaction([
    prisma.indexedBlock.deleteMany({ where: { blockNumber: { gte: from } } }),
    prisma.liquidationEvent.deleteMany({ where: { blockNumber: { gte: from } } }),
    // MarketSnapshot and UserPositionSnapshot don't store blockNumber — they're
    // time-series snapshots driven by events. Rolling back IndexedBlock is sufficient
    // to prevent re-processing since we track which blocks we've processed.
    prisma.syncState.updateMany({
      where: { chainId: CHAIN_ID },
      data: {
        lastProcessedBlock: Math.max(from - 1, Number(DEPLOYMENT_BLOCK) - 1),
        lastProcessedHash: "0x0000000000000000000000000000000000000000000000000000000000000000",
      },
    }),
  ])

  logger.info({ from }, "[block-processor] Rollback complete")
}

// ─── Single Block Processing ──────────────────────────────────────────────────

async function processBlock(blockNumber: bigint, markets: MarketConfig[]): Promise<void> {
  // 1. Fetch block for hash/parentHash
  const block = await client.getBlock({ blockNumber })

  // 2. Check for reorg
  const reorgStart = await checkReorg(blockNumber, block.parentHash)
  if (reorgStart !== null) {
    await rollbackFrom(reorgStart)
    // Re-process from reorgStart after rollback — caller (processBlockRange) will handle
    throw new ReorgError(reorgStart)
  }

  // 3. Fetch all logs for all market addresses in this block
  const marketAddresses = markets.map((m) => m.marketAddress) as `0x${string}`[]
  const rawLogs = await client.getLogs({
    address: marketAddresses,
    fromBlock: blockNumber,
    toBlock: blockNumber,
  })

  // 4. Sort deterministically by logIndex
  const sorted = [...rawLogs].sort((a, b) => Number(a.logIndex) - Number(b.logIndex))

  // 5. Decode and process each log
  for (const rawLog of sorted) {
    // Match log to its market
    const market = markets.find(
      (m) => m.marketAddress.toLowerCase() === (rawLog.address as string).toLowerCase()
    )
    if (!market) continue

    try {
      const decoded = decodeEventLog({
        abi: MARKET_EVENTS_ABI,
        data: rawLog.data,
        topics: rawLog.topics as [`0x${string}`, ...`0x${string}`[]],
        strict: false,
      })

      await processEventLog(
        {
          eventName: decoded.eventName as string,
          args: decoded.args as Record<string, unknown>,
          transactionHash: rawLog.transactionHash as `0x${string}`,
          blockNumber: rawLog.blockNumber ?? blockNumber,
          logIndex: Number(rawLog.logIndex),
        },
        market
      )
    } catch (err) {
      // Unknown event signatures (e.g. Transfer events from ERC20) — skip silently
      logger.debug(
        { block: Number(blockNumber), txHash: rawLog.transactionHash },
        "[block-processor] Could not decode log — skipping"
      )
    }
  }

  // 6. Upsert SyncState
  await prisma.syncState.upsert({
    where: { chainId: CHAIN_ID },
    update: {
      lastProcessedBlock: Number(blockNumber),
      lastProcessedHash: block.hash ?? "",
    },
    create: {
      chainId: CHAIN_ID,
      lastProcessedBlock: Number(blockNumber),
      lastProcessedHash: block.hash ?? "",
    },
  })

  // 7. Upsert IndexedBlock for reorg detection
  await prisma.indexedBlock.upsert({
    where: { blockNumber: Number(blockNumber) },
    update: { blockHash: block.hash ?? "" },
    create: { blockNumber: Number(blockNumber), blockHash: block.hash ?? "" },
  })

  // 8. Prune old indexed blocks — keep only REORG_BUFFER
  await prisma.indexedBlock.deleteMany({
    where: { blockNumber: { lt: Number(blockNumber) - REORG_BUFFER } },
  })
}

// ─── Block Range Processing ───────────────────────────────────────────────────

/**
 * Process a range of blocks deterministically.
 * Used by: startup replay, backfill script, reindex script, /internal/resync.
 */
export async function processBlockRange(
  fromBlock: bigint,
  toBlock: bigint,
  markets: MarketConfig[]
): Promise<void> {
  if (fromBlock > toBlock) return

  const total = Number(toBlock - fromBlock) + 1
  logger.info({ from: Number(fromBlock), to: Number(toBlock), total }, "[block-processor] Processing block range")

  let current = fromBlock
  while (current <= toBlock) {
    try {
      await processBlock(current, markets)

      if (Number(current) % 100 === 0) {
        const pct = Math.round(((Number(current - fromBlock) + 1) / total) * 100)
        logger.info(
          { block: Number(current), pct },
          "[block-processor] Progress"
        )
      }

      current++
    } catch (err) {
      if (err instanceof ReorgError) {
        // Restart range from reorg point
        logger.info(
          { restartFrom: Number(err.reorgStart) },
          "[block-processor] Restarting range after reorg rollback"
        )
        current = err.reorgStart
      } else {
        logger.error(
          { block: Number(current), err },
          "[block-processor] Error processing block — retrying once"
        )
        // Single retry after a brief wait for transient RPC errors
        await new Promise((r) => setTimeout(r, 2000))
        try {
          await processBlock(current, markets)
          current++
        } catch (retryErr) {
          logger.error(
            { block: Number(current), err: retryErr },
            "[block-processor] Block failed after retry — skipping"
          )
          current++
        }
      }
    }
  }

  logger.info(
    { from: Number(fromBlock), to: Number(toBlock) },
    "[block-processor] Block range complete"
  )
}

// ─── Internal ─────────────────────────────────────────────────────────────────

class ReorgError extends Error {
  constructor(public readonly reorgStart: bigint) {
    super(`Reorg detected — rolling back to ${reorgStart}`)
  }
}

export { CONFIRMATIONS, REORG_BUFFER, DEPLOYMENT_BLOCK }
