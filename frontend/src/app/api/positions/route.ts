import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  try {
    const user = request.nextUrl.searchParams.get("user");

    if (!user) {
      return NextResponse.json(
        { error: "Missing 'user' query parameter" },
        { status: 400 }
      );
    }

    const positions = await prisma.userPositionSnapshot.findMany({
      where: { userAddress: user.toLowerCase() },
      orderBy: { timestamp: "desc" },
      distinct: ["marketId"],
      include: {
        market: { select: { label: true, symbol: true, vaultAddress: true } },
      },
    });

    return NextResponse.json({
      user,
      positions: positions.map((p) => ({
        marketId: p.marketId,
        label: p.market.label,
        symbol: p.market.symbol,
        vaultAddress: p.market.vaultAddress,
        collateralValue: Number(p.collateralValue),
        totalDebt: Number(p.totalDebt),
        healthFactor: Number(p.healthFactor),
        borrowingPower: Number(p.borrowingPower),
        lastUpdated: p.timestamp.toISOString(),
      })),
    });
  } catch (error) {
    console.error("Error fetching positions:", error);
    return NextResponse.json(
      { error: "Failed to fetch positions" },
      { status: 500 }
    );
  }
}
