import { Router, Request, Response } from "express"
import { prisma } from "../lib/db"

const router = Router()

router.get("/", async (req: Request, res: Response) => {
  try {
    const limit = Math.min(Number(req.query.limit || "20"), 100)

    const liquidations = await prisma.liquidationEvent.findMany({
      orderBy: { timestamp: "desc" },
      take: limit,
      include: {
        market: { select: { label: true, symbol: true, vaultAddress: true } },
      },
    })

    res.json({
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
    })
  } catch (error) {
    console.error("[routes/liquidations] Error:", error)
    res.status(500).json({ error: "Failed to fetch liquidations" })
  }
})

export default router
