import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  try {
    const limit = Math.min(
      Number(request.nextUrl.searchParams.get("limit") || "20"),
      100
    );

    const liquidations = await prisma.liquidationEvent.findMany({
      orderBy: { timestamp: "desc" },
      take: limit,
      include: {
        market: { select: { label: true, symbol: true, vaultAddress: true } },
      },
    });

    return NextResponse.json({
      liquidations: liquidations.map((l) => ({
        id: l.id,
        market: l.market.label,
        symbol: l.market.symbol,
        borrower: l.borrower,
        liquidator: l.liquidator,
        debtCovered: Number(l.debtCovered),
        collateralSeized: Number(l.collateralSeized),
        badDebt: Number(l.badDebt),
        txHash: l.txHash,
        blockNumber: l.blockNumber,
        timestamp: l.timestamp.toISOString(),
      })),
      count: liquidations.length,
    });
  } catch (error) {
    console.error("Error fetching liquidations:", error);
    return NextResponse.json(
      { error: "Failed to fetch liquidations" },
      { status: 500 }
    );
  }
}
