import { NextRequest, NextResponse } from "next/server";
import { getLatestSnapshot } from "@/lib/db";
import { DEFAULT_VAULT } from "@/lib/vault-registry";
import type { CurrentMetricsResponse, SeverityLevel } from "@/types/metrics";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: NextRequest) {
  try {
    const vaultAddress = request.nextUrl.searchParams.get("vault") || DEFAULT_VAULT.vaultAddress;
    const snapshot = await getLatestSnapshot(vaultAddress);

    if (!snapshot) {
      return NextResponse.json(
        { error: "No metrics available. Run a poll first." },
        { status: 404 }
      );
    }

    const response: CurrentMetricsResponse = {
      vaultAddress: snapshot.vaultAddress,
      timestamp: snapshot.timestamp.toISOString(),
      liquidity: {
        available: snapshot.availableLiquidity.toString(),
        totalBorrows: snapshot.totalBorrows.toString(),
        depthRatio: Number(snapshot.liquidityDepthRatio),
        severity: snapshot.liquiditySeverity as SeverityLevel,
      },
      aprConvexity: {
        utilization: Number(snapshot.utilizationRate),
        borrowRate: Number(snapshot.borrowRate),
        distanceToKink: Number(snapshot.distanceToKink),
        severity: snapshot.aprConvexitySeverity as SeverityLevel,
      },
      oracle: {
        price: snapshot.oraclePrice.toString(),
        confidence: snapshot.oracleConfidence,
        riskScore: snapshot.oracleRiskScore,
        isStale: snapshot.oracleIsStale,
        severity: snapshot.oracleSeverity as SeverityLevel,
      },
      velocity: {
        delta: snapshot.utilizationDelta ? Number(snapshot.utilizationDelta) : null,
        severity: snapshot.velocitySeverity as SeverityLevel | null,
      },
      strategy: snapshot.strategyTotalAssets ? {
        totalAssets: snapshot.strategyTotalAssets.toString(),
        allocationPct: Number(snapshot.strategyAllocPct),
        isChanging: snapshot.isStrategyChanging,
      } : null,
      overall: snapshot.overallSeverity as SeverityLevel,
    };

    return NextResponse.json(response);
  } catch (error) {
    console.error("Error fetching metrics:", error);
    return NextResponse.json(
      { error: "Failed to fetch metrics" },
      { status: 500 }
    );
  }
}
