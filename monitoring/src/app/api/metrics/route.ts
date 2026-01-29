import { NextResponse } from "next/server";
import { getLatestSnapshot } from "@/lib/db";
import type { CurrentMetricsResponse, SeverityLevel } from "@/types/metrics";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET() {
  try {
    const snapshot = await getLatestSnapshot();

    if (!snapshot) {
      return NextResponse.json(
        { error: "No metrics available. Run a poll first." },
        { status: 404 }
      );
    }

    const response: CurrentMetricsResponse = {
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
