import { NextRequest, NextResponse } from "next/server";
import { getLatestMarketSnapshot } from "@/lib/db";
import { DEFAULT_VAULT } from "@/lib/vault-registry";
import type { CurrentMetricsResponse, SeverityLevel } from "@/types/metrics";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: NextRequest) {
  try {
    const vaultAddress = request.nextUrl.searchParams.get("vault") || DEFAULT_VAULT.vaultAddress;
    const snapshot = await getLatestMarketSnapshot(vaultAddress);

    if (!snapshot) {
      return NextResponse.json(
        { error: "No metrics available. Start the indexer first." },
        { status: 404 }
      );
    }

    const response: CurrentMetricsResponse = {
      vaultAddress,
      timestamp: snapshot.timestamp.toISOString(),
      liquidity: {
        available: Number(snapshot.availableLiquidity),
        totalBorrows: Number(snapshot.totalBorrows),
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
        price: Number(snapshot.oraclePrice),
        confidence: snapshot.oracleConfidence,
        riskScore: snapshot.oracleRiskScore,
        isStale: snapshot.oracleIsStale,
        severity: snapshot.oracleSeverity as SeverityLevel,
      },
      velocity: {
        delta: null,
        severity: null,
      },
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
