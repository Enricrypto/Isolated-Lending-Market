import { NextResponse } from "next/server";
import { getLatestSnapshotsForAllMarkets } from "@/lib/db";
import { computeProtocolSeverity } from "@/lib/severity";
import type { VaultSummary, ProtocolOverviewResponse, SeverityLevel } from "@/types/metrics";

export async function GET() {
  try {
    const results = await getLatestSnapshotsForAllMarkets();

    const vaults: VaultSummary[] = results.map(({ market, snapshot }) => {
      if (!snapshot) {
        return {
          vaultAddress: market.vaultAddress,
          label: market.label,
          symbol: market.symbol,
          overallSeverity: 0 as SeverityLevel,
          utilization: 0,
          totalSupply: 0,
          totalBorrows: 0,
          oraclePrice: 0,
          lastUpdated: "",
        };
      }

      return {
        vaultAddress: market.vaultAddress,
        label: market.label,
        symbol: market.symbol,
        overallSeverity: snapshot.overallSeverity as SeverityLevel,
        utilization: Number(snapshot.utilizationRate),
        totalSupply: Number(snapshot.totalSupply),
        totalBorrows: Number(snapshot.totalBorrows),
        oraclePrice: Number(snapshot.oraclePrice),
        lastUpdated: snapshot.timestamp.toISOString(),
      };
    });

    const vaultSeverities = vaults
      .filter((v) => v.lastUpdated)
      .map((v) => v.overallSeverity);

    const response: ProtocolOverviewResponse = {
      vaults,
      protocolSeverity: computeProtocolSeverity(vaultSeverities),
      totalTVL: vaults.reduce((sum, v) => sum + v.totalSupply, 0),
      totalBorrows: vaults.reduce((sum, v) => sum + v.totalBorrows, 0),
      timestamp: new Date().toISOString(),
    };

    return NextResponse.json(response);
  } catch (error) {
    console.error("Error fetching vaults overview:", error);
    return NextResponse.json(
      { error: "Failed to fetch vaults overview" },
      { status: 500 }
    );
  }
}
