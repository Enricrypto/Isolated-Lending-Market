import { client, toNumber } from "./rpc";
import { prisma, getLatestSnapshot } from "./db";
import {
  computeLiquiditySeverity,
  computeAPRConvexitySeverity,
  computeOracleSeverity,
  computeVelocitySeverity,
  computeOverallSeverity,
} from "./severity";
import {
  MARKET_ABI,
  VAULT_ABI,
  IRM_ABI,
  ORACLE_ROUTER_ABI,
  getContractAddresses,
} from "./contracts";
import type { SeverityLevel } from "@/types/metrics";
import { Prisma } from "@prisma/client";

const Decimal = Prisma.Decimal;

// Polling interval in milliseconds (5 minutes)
export const POLLING_INTERVAL = 5 * 60 * 1000;

interface RawMetrics {
  // Liquidity
  availableLiquidity: bigint;
  totalBorrows: bigint;
  totalAssets: bigint;

  // IRM
  utilizationRate: bigint;
  borrowRate: bigint;
  optimalUtilization: bigint;

  // Oracle
  oraclePrice: bigint;
  oracleConfidence: number;
  oracleRiskScore: number;
  oracleIsStale: boolean;
  oracleDeviation: bigint;
}

// Fetch all metrics from contracts in a single batch
export async function fetchMetrics(): Promise<RawMetrics> {
  const addresses = getContractAddresses();

  // Batch all contract calls together for efficiency
  const results = await client.multicall({
    contracts: [
      // Vault calls
      {
        address: addresses.vault,
        abi: VAULT_ABI,
        functionName: "availableLiquidity",
      },
      {
        address: addresses.vault,
        abi: VAULT_ABI,
        functionName: "totalAssets",
      },
      // Market calls
      {
        address: addresses.market,
        abi: MARKET_ABI,
        functionName: "totalBorrows",
      },
      // IRM calls
      {
        address: addresses.irm,
        abi: IRM_ABI,
        functionName: "getUtilizationRate",
      },
      {
        address: addresses.irm,
        abi: IRM_ABI,
        functionName: "getDynamicBorrowRate",
      },
      {
        address: addresses.irm,
        abi: IRM_ABI,
        functionName: "optimalUtilization",
      },
      // Oracle calls
      {
        address: addresses.oracleRouter,
        abi: ORACLE_ROUTER_ABI,
        functionName: "evaluate",
        args: [addresses.loanAsset],
      },
    ],
  });

  // Extract results (handle potential failures)
  const availableLiquidity = results[0].status === "success" ? (results[0].result as bigint) : 0n;
  const totalAssets = results[1].status === "success" ? (results[1].result as bigint) : 0n;
  const totalBorrows = results[2].status === "success" ? (results[2].result as bigint) : 0n;
  const utilizationRate = results[3].status === "success" ? (results[3].result as bigint) : 0n;
  const borrowRate = results[4].status === "success" ? (results[4].result as bigint) : 0n;
  const optimalUtilization = results[5].status === "success" ? (results[5].result as bigint) : 0n;

  // Oracle evaluation result is a struct
  let oraclePrice = 0n;
  let oracleConfidence = 0;
  let oracleRiskScore = 100;
  let oracleIsStale = true;
  let oracleDeviation = 0n;

  if (results[6].status === "success") {
    const oracleEval = results[6].result as {
      resolvedPrice: bigint;
      confidence: bigint;
      sourceUsed: number;
      oracleRiskScore: number;
      isStale: boolean;
      deviation: bigint;
    };
    oraclePrice = oracleEval.resolvedPrice;
    oracleConfidence = Number(oracleEval.confidence * 100n / BigInt(1e18)); // Convert to 0-100
    oracleRiskScore = oracleEval.oracleRiskScore;
    oracleIsStale = oracleEval.isStale;
    oracleDeviation = oracleEval.deviation;
  }

  return {
    availableLiquidity,
    totalBorrows,
    totalAssets,
    utilizationRate,
    borrowRate,
    optimalUtilization,
    oraclePrice,
    oracleConfidence,
    oracleRiskScore,
    oracleIsStale,
    oracleDeviation,
  };
}

// Calculate depth ratio (available liquidity / total borrows)
// This is a simplified approximation of depthCoverageRatio
function calculateDepthRatio(availableLiquidity: bigint, totalBorrows: bigint): number {
  if (totalBorrows === 0n) {
    return 10.0; // No borrows = infinite depth, cap at 10
  }
  const ratio = Number(availableLiquidity) / Number(totalBorrows);
  return Math.min(ratio, 10.0); // Cap at 10 for display
}

// Calculate utilization velocity (change per hour)
async function calculateVelocity(
  currentUtilization: number,
  previousSnapshot: Awaited<ReturnType<typeof getLatestSnapshot>>
): Promise<{ delta: number | null; severity: SeverityLevel | null }> {
  if (!previousSnapshot) {
    return { delta: null, severity: null };
  }

  const timeDiffMs = Date.now() - previousSnapshot.timestamp.getTime();
  const timeDiffHours = timeDiffMs / (1000 * 60 * 60);

  if (timeDiffHours < 0.01) {
    // Less than ~36 seconds, skip velocity calculation
    return { delta: null, severity: null };
  }

  const previousUtilization = Number(previousSnapshot.utilizationRate);
  const delta = (currentUtilization - previousUtilization) / timeDiffHours;

  return {
    delta,
    severity: computeVelocitySeverity(delta),
  };
}

// Main polling function - fetches, calculates, and stores snapshot
export async function pollAndStore() {
  console.log(`[${new Date().toISOString()}] Starting metrics poll...`);

  try {
    // Fetch raw metrics from contracts
    const raw = await fetchMetrics();

    // Get previous snapshot for velocity calculation
    const previousSnapshot = await getLatestSnapshot();

    // Calculate derived values
    const utilizationRate = toNumber(raw.utilizationRate);
    const optimalUtilization = toNumber(raw.optimalUtilization);
    const borrowRate = toNumber(raw.borrowRate);
    const distanceToKink = optimalUtilization - utilizationRate;
    const depthRatio = calculateDepthRatio(raw.availableLiquidity, raw.totalBorrows);

    // Calculate severities
    const liquiditySeverity = computeLiquiditySeverity(depthRatio);
    const aprConvexitySeverity = computeAPRConvexitySeverity(utilizationRate, optimalUtilization);
    const oracleSeverity = computeOracleSeverity(
      raw.oracleConfidence,
      raw.oracleIsStale,
      raw.oracleRiskScore
    );

    // Calculate velocity
    const velocity = await calculateVelocity(utilizationRate, previousSnapshot);

    // Calculate overall severity
    const overallSeverity = computeOverallSeverity(
      liquiditySeverity,
      aprConvexitySeverity,
      oracleSeverity,
      velocity.severity
    );

    // Store snapshot
    const snapshot = await prisma.metricSnapshot.create({
      data: {
        // Liquidity
        availableLiquidity: new Decimal(raw.availableLiquidity.toString()),
        totalBorrows: new Decimal(raw.totalBorrows.toString()),
        liquidityDepthRatio: new Decimal(depthRatio.toFixed(6)),
        liquiditySeverity,

        // APR Convexity
        utilizationRate: new Decimal(utilizationRate.toFixed(6)),
        borrowRate: new Decimal(borrowRate.toFixed(6)),
        optimalUtilization: new Decimal(optimalUtilization.toFixed(6)),
        distanceToKink: new Decimal(distanceToKink.toFixed(6)),
        aprConvexitySeverity,

        // Oracle
        oraclePrice: new Decimal(raw.oraclePrice.toString()),
        oracleConfidence: raw.oracleConfidence,
        oracleRiskScore: raw.oracleRiskScore,
        oracleIsStale: raw.oracleIsStale,
        oracleSeverity,

        // Velocity
        utilizationDelta: velocity.delta !== null ? new Decimal(velocity.delta.toFixed(6)) : null,
        velocitySeverity: velocity.severity,

        // Overall
        overallSeverity,
      },
    });

    console.log(`[${new Date().toISOString()}] Snapshot stored: ID=${snapshot.id}, Severity=${overallSeverity}`);

    return snapshot;
  } catch (error) {
    console.error(`[${new Date().toISOString()}] Polling error:`, error);
    throw error;
  }
}
