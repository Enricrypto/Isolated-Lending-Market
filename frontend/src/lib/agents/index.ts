/**
 * Metrics Polling Orchestrator
 * ---------------------------
 * This file coordinates the **end-to-end ingestion pipeline** for protocol metrics.
 * It is the only place where on-chain data, historical state, risk computation,
 * and persistence are combined.
 *
 * High-level flow:
 * 1. Iterate over all registered vaults in VAULT_REGISTRY
 * 2. Fetch current on-chain state via agents:
 *    - Vault Agent     → liquidity, utilization, rates
 *    - Strategy Agent  → capital deployment & strategy state
 *    - Oracle Agent    → price, confidence, oracle health
 * 3. Load the previous snapshot (if any) for time-based comparisons
 * 4. Derive risk signals and severities from normalized inputs
 * 5. Persist a single, fully-derived MetricSnapshot per vault
 *
 * Architectural boundaries:
 * - Agents are responsible ONLY for raw on-chain reads + normalization
 * - This file is responsible for:
 *   • cross-agent composition
 *   • temporal comparisons (velocity)
 *   • severity computation
 *   • persistence to the database
 *
 * What this file DOES:
 * - Orchestrates polling across all vaults
 * - Ensures only one poll runs at a time (pollingInFlight guard)
 * - Computes derived metrics (depth ratio, distance to kink, velocity)
 * - Computes per-dimension and overall severity
 * - Writes normalized, human-readable values to the DB
 *
 * What this file does NOT do:
 * - Does NOT perform RPC calls directly
 * - Does NOT normalize raw blockchain values
 * - Does NOT contain UI logic or formatting
 * - Does NOT expose HTTP endpoints (handled by API routes)
 *
 * Normalization & storage guarantees:
 * - All agent outputs are already normalized before use
 * - Token amounts stored as decimals (e.g. "1500.500000")
 * - Rates stored as 0–1 floats
 * - Velocity is computed per-hour from historical snapshots
 *
 * Concurrency & safety:
 * - pollAndStore() is guarded to prevent overlapping runs
 * - Partial failures are tolerated (Promise.allSettled)
 * - Failed vaults do not block successful ones
 *
 * Downstream consumers:
 * - API routes read MetricSnapshots for Monitoring & Analytics UI
 * - Protocol/Vault/Strategy views are derived exclusively from stored snapshots
 *
 * IMPORTANT:
 * - Any logic change here impacts historical data and risk interpretation
 * - Treat this file as a critical system boundary
 */

import { fetchVaultMetrics } from "./vault-agent"
import { fetchOracleMetrics } from "./oracle-agent"
import { prisma, getLatestSnapshot } from "../db"
import {
  computeLiquiditySeverity,
  computeAPRConvexitySeverity,
  computeOracleSeverity,
  computeVelocitySeverity,
  computeOverallSeverity
} from "../severity"
import { VAULT_REGISTRY } from "../vault-registry"
import type { VaultConfig, SeverityLevel } from "@/types/metrics"

export const POLLING_INTERVAL = 5 * 60 * 1000

let pollingInFlight = false

// All inputs are already normalized numbers (e.g. 1500.5 USDC, 200.0 USDC)
function calculateDepthRatio(
  availableLiquidity: number,
  totalBorrows: number
): number {
  if (totalBorrows === 0) return 10.0
  return Math.min(availableLiquidity / totalBorrows, 10.0)
}

function calculateVelocity(
  currentUtilization: number,
  previousSnapshot: {
    utilizationRate: { toNumber(): number } | number
    timestamp: Date
  } | null
): { delta: number | null; severity: SeverityLevel | null } {
  if (!previousSnapshot) return { delta: null, severity: null }

  const timeDiffMs = Date.now() - previousSnapshot.timestamp.getTime()
  const timeDiffHours = timeDiffMs / (1000 * 60 * 60)

  if (timeDiffHours < 0.01) return { delta: null, severity: null }

  // Previous utilization is stored as normalized 0-1 float in DB
  const previousUtilization = Number(previousSnapshot.utilizationRate)
  const delta = (currentUtilization - previousUtilization) / timeDiffHours

  return { delta, severity: computeVelocitySeverity(delta) }
}

// pollVault writes snapshots for a single vault
async function pollVault(config: VaultConfig) {
  const [vault, oracle] = await Promise.all([
    fetchVaultMetrics(config),
    fetchOracleMetrics(config)
  ])

  const previousSnapshot = await getLatestSnapshot(config.vaultAddress)

  // All values are already normalized by agents
  const depthRatio = calculateDepthRatio(
    vault.availableLiquidity,
    vault.totalBorrows
  )
  const distanceToKink = vault.optimalUtilization - vault.utilizationRate

  const liquiditySeverity = computeLiquiditySeverity(depthRatio)
  const aprConvexitySeverity = computeAPRConvexitySeverity(
    vault.utilizationRate,
    vault.optimalUtilization
  )
  const oracleSeverity = computeOracleSeverity(
    oracle.confidence,
    oracle.isStale,
    oracle.riskScore
  )
  const velocity = calculateVelocity(vault.utilizationRate, previousSnapshot)
  const overallSeverity = computeOverallSeverity(
    liquiditySeverity,
    aprConvexitySeverity,
    oracleSeverity,
    velocity.severity
  )

  // Store normalized values in DB
  return prisma.metricSnapshot.create({
    data: {
      vaultAddress: config.vaultAddress,

      // Token amounts stored as normalized numbers (e.g. 1500.5 not 1500500000)
      availableLiquidity: vault.availableLiquidity.toFixed(6),
      totalBorrows: vault.totalBorrows.toFixed(6),
      liquidityDepthRatio: depthRatio.toFixed(6),
      liquiditySeverity,

      // Rates stored as 0-1 floats
      utilizationRate: vault.utilizationRate.toFixed(6),
      borrowRate: vault.borrowRate.toFixed(6),
      optimalUtilization: vault.optimalUtilization.toFixed(6),
      distanceToKink: distanceToKink.toFixed(6),
      aprConvexitySeverity,

      // Oracle price stored as normalized number (e.g. 1.0002)
      oraclePrice: oracle.price.toFixed(6),
      oracleConfidence: oracle.confidence,
      oracleRiskScore: oracle.riskScore,
      oracleIsStale: oracle.isStale,
      oracleSeverity,

      utilizationDelta:
        velocity.delta !== null ? velocity.delta.toFixed(6) : null,
      velocitySeverity: velocity.severity,

      overallSeverity
    }
  })
}

// pollAndStore coordinates polling for all vaults and manages concurrency, logging, and error handling
export async function pollAndStore() {
  if (pollingInFlight) {
    console.warn("Polling skipped: already running")
    return null
  }

  pollingInFlight = true
  console.log(
    `[${new Date().toISOString()}] Starting metrics poll for ${VAULT_REGISTRY.length} vault(s)...`
  )

  try {
    const results = await Promise.allSettled(
      VAULT_REGISTRY.map((config) => pollVault(config))
    )

    const snapshots = results
      .filter((r) => r.status === "fulfilled")
      .map(
        (r) =>
          (r as PromiseFulfilledResult<Awaited<ReturnType<typeof pollVault>>>)
            .value
      )

    const failed = results.filter((r) => r.status === "rejected")
    if (failed.length > 0) {
      failed.forEach((r) => {
        console.error(
          `[${new Date().toISOString()}] Vault poll failed:`,
          (r as PromiseRejectedResult).reason
        )
      })
    }

    console.log(
      `[${new Date().toISOString()}] Polled ${snapshots.length}/${VAULT_REGISTRY.length} vaults`
    )
    return snapshots
  } catch (error) {
    console.error(`[${new Date().toISOString()}] Polling error:`, error)
    throw error
  } finally {
    pollingInFlight = false
  }
}
