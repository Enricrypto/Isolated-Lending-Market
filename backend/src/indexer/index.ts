/**
 * Indexer Orchestrator
 * --------------------
 * Starts event listeners for all active markets.
 * Periodic snapshots are handled by node-cron jobs (src/jobs/index.ts).
 */

import { prisma } from "../lib/db"
import { watchMarketEvents } from "./listener"
import type { MarketConfig } from "./listener"
import type { WatchContractEventReturnType } from "viem"

let running = false
let unwatchers: WatchContractEventReturnType[] = []
let startedAt: Date | null = null

/** Loaded markets — shared with cron jobs */
export let activeMarkets: MarketConfig[] = []

export async function startIndexer() {
  if (running) {
    console.log("[indexer] Already running")
    return { alreadyRunning: true }
  }

  console.log("[indexer] Starting...")

  const markets = await prisma.market.findMany({ where: { isActive: true } })

  if (markets.length === 0) {
    console.warn("[indexer] No active markets found. Run seed first.")
    return { error: "No active markets" }
  }

  console.log(`[indexer] Found ${markets.length} active market(s)`)

  activeMarkets = markets.map((m) => ({
    marketId: m.id,
    vaultAddress: m.vaultAddress as `0x${string}`,
    marketAddress: m.marketAddress as `0x${string}`,
    irmAddress: m.irmAddress as `0x${string}`,
    oracleRouterAddress: m.oracleRouterAddress as `0x${string}`,
    loanAsset: m.loanAsset as `0x${string}`,
    loanAssetDecimals: m.loanAssetDecimals,
  }))

  for (const market of activeMarkets) {
    const unwatch = watchMarketEvents(market)
    unwatchers.push(unwatch)
    console.log(`[indexer] Watching events for market ${market.marketAddress.slice(0, 8)}...`)
  }

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

  for (const unwatch of unwatchers) {
    unwatch()
  }
  unwatchers = []
  activeMarkets = []

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
    activeMarkets: activeMarkets.length,
  }
}
