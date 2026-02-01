import { NextRequest, NextResponse } from "next/server";
import { getSnapshotsInRange, getTimeRangeStart } from "@/lib/db";
import { DEFAULT_VAULT } from "@/lib/vault-registry";
import type { HistoryResponse, HistoryDataPoint, SeverityLevel, TimeRange } from "@/types/metrics";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const revalidate = 0;

type SignalType = "liquidity" | "utilization" | "borrowRate" | "oracle" | "velocity" | "strategy";

export async function GET(request: NextRequest) {
  try {
    const searchParams = request.nextUrl.searchParams;
    const signal = searchParams.get("signal") as SignalType | null;
    const range = (searchParams.get("range") || "24h") as TimeRange;
    const vaultAddress = searchParams.get("vault") || DEFAULT_VAULT.vaultAddress;

    if (!signal) {
      return NextResponse.json(
        { error: "Missing 'signal' parameter. Options: liquidity, utilization, borrowRate, oracle, velocity, strategy" },
        { status: 400 }
      );
    }

    const validSignals: SignalType[] = ["liquidity", "utilization", "borrowRate", "oracle", "velocity", "strategy"];
    if (!validSignals.includes(signal)) {
      return NextResponse.json(
        { error: `Invalid signal. Options: ${validSignals.join(", ")}` },
        { status: 400 }
      );
    }

    const startTime = getTimeRangeStart(range);
    const snapshots = await getSnapshotsInRange(startTime, new Date(), vaultAddress);

    // Map snapshots to the requested signal
    const data: HistoryDataPoint[] = snapshots.map((snapshot) => {
      let value: number;
      let severity: SeverityLevel;

      switch (signal) {
        case "liquidity":
          value = Number(snapshot.liquidityDepthRatio);
          severity = snapshot.liquiditySeverity as SeverityLevel;
          break;
        case "utilization":
          value = Number(snapshot.utilizationRate) * 100; // Convert to percentage
          severity = snapshot.aprConvexitySeverity as SeverityLevel;
          break;
        case "borrowRate":
          value = Number(snapshot.borrowRate) * 100; // Convert to percentage
          severity = snapshot.aprConvexitySeverity as SeverityLevel;
          break;
        case "oracle":
          value = snapshot.oracleConfidence;
          severity = snapshot.oracleSeverity as SeverityLevel;
          break;
        case "velocity":
          value = snapshot.utilizationDelta ? Number(snapshot.utilizationDelta) * 100 : 0;
          severity = (snapshot.velocitySeverity ?? 0) as SeverityLevel;
          break;
        case "strategy":
          value = snapshot.strategyAllocPct ? Number(snapshot.strategyAllocPct) * 100 : 0;
          severity = 0;
          break;
        default:
          value = 0;
          severity = 0;
      }

      return {
        timestamp: snapshot.timestamp.toISOString(),
        value,
        severity,
      };
    });

    const response: HistoryResponse = {
      signal,
      range,
      data,
    };

    return NextResponse.json(response);
  } catch (error) {
    console.error("Error fetching history:", error);
    return NextResponse.json(
      { error: "Failed to fetch history" },
      { status: 500 }
    );
  }
}
