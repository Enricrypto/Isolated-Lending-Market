import { fetchVaultMetrics } from "./vault-agent";
import { fetchStrategyMetrics } from "./strategy-agent";
import { fetchOracleMetrics } from "./oracle-agent";
import { prisma, getLatestSnapshot } from "../db";
import {
  computeLiquiditySeverity,
  computeAPRConvexitySeverity,
  computeOracleSeverity,
  computeVelocitySeverity,
  computeOverallSeverity,
} from "../severity";
import { VAULT_REGISTRY } from "../vault-registry";
import type { VaultConfig, SeverityLevel } from "@/types/metrics";
import { Prisma } from "@prisma/client";

const Decimal = Prisma.Decimal;

export const POLLING_INTERVAL = 5 * 60 * 1000;

let pollingInFlight = false;

function calculateDepthRatio(availableLiquidity: bigint, totalBorrows: bigint): number {
  if (totalBorrows === 0n) return 10.0;
  return Math.min(Number(availableLiquidity) / Number(totalBorrows), 10.0);
}

function calculateVelocity(
  currentUtilization: number,
  previousSnapshot: { utilizationRate: Prisma.Decimal; timestamp: Date } | null
): { delta: number | null; severity: SeverityLevel | null } {
  if (!previousSnapshot) return { delta: null, severity: null };

  const timeDiffMs = Date.now() - previousSnapshot.timestamp.getTime();
  const timeDiffHours = timeDiffMs / (1000 * 60 * 60);

  if (timeDiffHours < 0.01) return { delta: null, severity: null };

  const previousUtilization = Number(previousSnapshot.utilizationRate);
  const delta = (currentUtilization - previousUtilization) / timeDiffHours;

  return { delta, severity: computeVelocitySeverity(delta) };
}

async function pollVault(config: VaultConfig) {
  const [vault, strategy, oracle] = await Promise.all([
    fetchVaultMetrics(config),
    fetchStrategyMetrics(config),
    fetchOracleMetrics(config),
  ]);

  const previousSnapshot = await getLatestSnapshot(config.vaultAddress);

  const depthRatio = calculateDepthRatio(vault.availableLiquidity, vault.totalBorrows);
  const distanceToKink = vault.optimalUtilization - vault.utilizationRate;

  const liquiditySeverity = computeLiquiditySeverity(depthRatio);
  const aprConvexitySeverity = computeAPRConvexitySeverity(vault.utilizationRate, vault.optimalUtilization);
  const oracleSeverity = computeOracleSeverity(oracle.confidence, oracle.isStale, oracle.riskScore);
  const velocity = calculateVelocity(vault.utilizationRate, previousSnapshot);
  const overallSeverity = computeOverallSeverity(
    liquiditySeverity,
    aprConvexitySeverity,
    oracleSeverity,
    velocity.severity
  );

  return prisma.metricSnapshot.create({
    data: {
      vaultAddress: config.vaultAddress,
      strategyAddress: config.strategyAddress,

      availableLiquidity: new Decimal(vault.availableLiquidity.toString()),
      totalBorrows: new Decimal(vault.totalBorrows.toString()),
      liquidityDepthRatio: new Decimal(depthRatio.toFixed(6)),
      liquiditySeverity,

      utilizationRate: new Decimal(vault.utilizationRate.toFixed(6)),
      borrowRate: new Decimal(vault.borrowRate.toFixed(6)),
      optimalUtilization: new Decimal(vault.optimalUtilization.toFixed(6)),
      distanceToKink: new Decimal(distanceToKink.toFixed(6)),
      aprConvexitySeverity,

      oraclePrice: new Decimal(oracle.price.toString()),
      oracleConfidence: oracle.confidence,
      oracleRiskScore: oracle.riskScore,
      oracleIsStale: oracle.isStale,
      oracleSeverity,

      strategyTotalAssets: new Decimal(strategy.strategyTotalAssets.toString()),
      strategyAllocPct: new Decimal(strategy.strategyAllocPct.toFixed(6)),
      isStrategyChanging: strategy.isStrategyChanging,

      utilizationDelta: velocity.delta !== null ? new Decimal(velocity.delta.toFixed(6)) : null,
      velocitySeverity: velocity.severity,

      overallSeverity,
    },
  });
}

export async function pollAndStore() {
  if (pollingInFlight) {
    console.warn("Polling skipped: already running");
    return null;
  }

  pollingInFlight = true;
  console.log(`[${new Date().toISOString()}] Starting metrics poll for ${VAULT_REGISTRY.length} vault(s)...`);

  try {
    const results = await Promise.allSettled(
      VAULT_REGISTRY.map((config) => pollVault(config))
    );

    const snapshots = results
      .filter((r) => r.status === "fulfilled")
      .map((r) => (r as PromiseFulfilledResult<Awaited<ReturnType<typeof pollVault>>>).value);

    const failed = results.filter((r) => r.status === "rejected");
    if (failed.length > 0) {
      failed.forEach((r, i) => {
        console.error(`[${new Date().toISOString()}] Vault poll failed:`, (r as PromiseRejectedResult).reason);
      });
    }

    console.log(`[${new Date().toISOString()}] Polled ${snapshots.length}/${VAULT_REGISTRY.length} vaults`);
    return snapshots;
  } catch (error) {
    console.error(`[${new Date().toISOString()}] Polling error:`, error);
    throw error;
  } finally {
    pollingInFlight = false;
  }
}
