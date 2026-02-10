/**
 * Indexer Orchestrator
 * --------------------
 * Starts event listeners for all active markets and runs periodic snapshots.
 *
 * Lifecycle:
 *   startIndexer()  → subscribes to events + starts periodic loop
 *   stopIndexer()   → unsubscribes + clears interval
 *   getStatus()     → returns running state
 */

import { prisma } from "../db"
import { watchMarketEvents } from "./listener"
import { computeAndSaveMarketSnapshot } from "./snapshot"
import type { WatchContractEventReturnType } from "viem"

// Default: snapshot every 60 seconds
const SNAPSHOT_INTERVAL = 60_000

// Event polling every 15 seconds
const EVENT_POLLING_INTERVAL = 15_000

let running = false
let unwatchers: WatchContractEventReturnType[] = []
let snapshotTimer: ReturnType<typeof setInterval> | null = null
let startedAt: Date | null = null

export async function startIndexer() {
  if (running) {
    console.log("[indexer] Already running, skipping start")
    return { alreadyRunning: true }
  }

  console.log("[indexer] Starting...")

  // Load active markets from DB
  const markets = await prisma.market.findMany({
    where: { isActive: true },
  })

  if (markets.length === 0) {
    console.warn("[indexer] No active markets found. Run seed first.")
    return { error: "No active markets" }
  }

  console.log(`[indexer] Found ${markets.length} active market(s)`)

  // Subscribe to events for each market
  for (const m of markets) {
    const config = {
      marketId: m.id,
      vaultAddress: m.vaultAddress as `0x${string}`,
      marketAddress: m.marketAddress as `0x${string}`,
      irmAddress: m.irmAddress as `0x${string}`,
      oracleRouterAddress: m.oracleRouterAddress as `0x${string}`,
      loanAsset: m.loanAsset as `0x${string}`,
      loanAssetDecimals: m.loanAssetDecimals,
    }

    const unwatch = watchMarketEvents(config, EVENT_POLLING_INTERVAL)
    unwatchers.push(unwatch)
    console.log(`[indexer] Watching events for ${m.label} (${m.marketAddress.slice(0, 8)}...)`)

    // Take an initial snapshot
    try {
      await computeAndSaveMarketSnapshot(config)
      console.log(`[indexer] Initial snapshot saved for ${m.label}`)
    } catch (err) {
      console.error(`[indexer] Initial snapshot failed for ${m.label}:`, err)
    }
  }

  // Periodic snapshot loop
  snapshotTimer = setInterval(async () => {
    for (const m of markets) {
      try {
        await computeAndSaveMarketSnapshot({
          marketId: m.id,
          vaultAddress: m.vaultAddress as `0x${string}`,
          marketAddress: m.marketAddress as `0x${string}`,
          irmAddress: m.irmAddress as `0x${string}`,
          oracleRouterAddress: m.oracleRouterAddress as `0x${string}`,
          loanAsset: m.loanAsset as `0x${string}`,
          loanAssetDecimals: m.loanAssetDecimals,
        })
      } catch (err) {
        console.error(`[indexer] Periodic snapshot failed for ${m.label}:`, err)
      }
    }
  }, SNAPSHOT_INTERVAL)

  running = true
  startedAt = new Date()

  console.log("[indexer] Running")
  return {
    started: true,
    markets: markets.map((m) => ({ id: m.id, label: m.label, symbol: m.symbol })),
  }
}

export function stopIndexer() {
  if (!running) return { alreadyStopped: true }

  // Unsubscribe from all event watchers
  for (const unwatch of unwatchers) {
    unwatch()
  }
  unwatchers = []

  // Clear periodic timer
  if (snapshotTimer) {
    clearInterval(snapshotTimer)
    snapshotTimer = null
  }

  running = false
  const uptime = startedAt ? Date.now() - startedAt.getTime() : 0
  startedAt = null

  console.log(`[indexer] Stopped (uptime: ${Math.round(uptime / 1000)}s)`)
  return { stopped: true, uptimeMs: uptime }
}

export function getIndexerStatus() {
  return {
    running,
    startedAt: startedAt?.toISOString() ?? null,
    watcherCount: unwatchers.length,
    snapshotIntervalMs: SNAPSHOT_INTERVAL,
    eventPollingMs: EVENT_POLLING_INTERVAL,
  }
}
