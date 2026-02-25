import { Router, Request, Response } from "express"
import { prisma } from "../lib/db"

const router = Router()

router.get("/", async (req: Request, res: Response) => {
  try {
    const user = req.query.user as string | undefined

    if (!user) {
      res.status(400).json({ error: "Missing 'user' query parameter" })
      return
    }

    const positions = await prisma.userPositionSnapshot.findMany({
      where: { userAddress: user.toLowerCase() },
      orderBy: { timestamp: "desc" },
      distinct: ["marketId"],
      include: {
        market: { select: { label: true, symbol: true, vaultAddress: true } },
      },
    })

    res.json({
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
    })
  } catch (error) {
    console.error("[routes/positions] Error:", error)
    res.status(500).json({ error: "Failed to fetch positions" })
  }
})

export default router
