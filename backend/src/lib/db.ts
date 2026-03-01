import { PrismaClient } from "../generated/prisma/client"
import { PrismaPg } from "@prisma/adapter-pg"
import { Pool } from "pg"

function createPrismaClient(): PrismaClient {
  const connectionString = process.env.PG_URL || process.env.DATABASE_URL
  if (!connectionString) {
    throw new Error("PG_URL or DATABASE_URL environment variable is required")
  }

  const pool = new Pool({ connectionString, ssl: { rejectUnauthorized: false } })
  const adapter = new PrismaPg(pool)

  return new PrismaClient({
    adapter,
    log: process.env.NODE_ENV === "development" ? ["warn", "error"] : ["error"],
  })
}

export const prisma = createPrismaClient()

// --- MarketSnapshot helpers ---

type MktSnapshot = Awaited<
  ReturnType<typeof prisma.marketSnapshot.findMany>
>[number]

export async function getLatestMarketSnapshot(vaultAddress: string) {
  try {
    const market = await prisma.market.findUnique({ where: { vaultAddress } })
    if (!market) return null
    return await prisma.marketSnapshot.findFirst({
      where: { marketId: market.id },
      orderBy: { timestamp: "desc" },
    })
  } catch (err) {
    console.error("[db] getLatestMarketSnapshot error:", err)
    return null
  }
}

export async function getMarketSnapshotsInRange(
  vaultAddress: string,
  startTime: Date,
  endTime: Date = new Date()
): Promise<MktSnapshot[]> {
  try {
    const market = await prisma.market.findUnique({ where: { vaultAddress } })
    if (!market) return []
    return await prisma.marketSnapshot.findMany({
      where: {
        marketId: market.id,
        timestamp: { gte: startTime, lte: endTime },
      },
      orderBy: { timestamp: "asc" },
    })
  } catch (err) {
    console.error("[db] getMarketSnapshotsInRange error:", err)
    return []
  }
}

export async function getLatestSnapshotsForAllMarkets() {
  try {
    const markets = await prisma.market.findMany({ where: { isActive: true } })
    const results = await Promise.all(
      markets.map(async (m) => {
        const snapshot = await prisma.marketSnapshot.findFirst({
          where: { marketId: m.id },
          orderBy: { timestamp: "desc" },
        })
        return { market: m, snapshot }
      })
    )
    return results
  } catch (err) {
    console.error("[db] getLatestSnapshotsForAllMarkets error:", err)
    return []
  }
}

export function getTimeRangeStart(range: string): Date {
  const now = new Date()
  switch (range) {
    case "24h":
      return new Date(now.getTime() - 24 * 60 * 60 * 1000)
    case "7d":
      return new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000)
    case "30d":
      return new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000)
    case "90d":
      return new Date(now.getTime() - 90 * 24 * 60 * 60 * 1000)
    default:
      return new Date(now.getTime() - 24 * 60 * 60 * 1000)
  }
}
