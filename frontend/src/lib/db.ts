import { PrismaClient } from "../../prisma/generated/prisma/client"
import { PrismaPg } from "@prisma/adapter-pg"

// Singleton for dev
const globalForPrisma = globalThis as unknown as {
  prisma: PrismaClient | undefined
}

function createPrismaClient() {
  const adapter = new PrismaPg({
    connectionString: process.env.PG_URL || process.env.DATABASE_URL!,
    ssl: { rejectUnauthorized: false }
  })

  return new PrismaClient({
    adapter, // ← REQUIRED
    log: ["query", "info", "warn", "error"] // optional
  })
}

export const prisma = globalForPrisma.prisma ?? createPrismaClient()

if (process.env.NODE_ENV !== "production") {
  globalForPrisma.prisma = prisma
}

// --- Helpers (unchanged) ---
type Snapshot = Awaited<
  ReturnType<typeof prisma.metricSnapshot.findMany>
>[number]

export async function cleanupOldSnapshots() {
  const ninetyDaysAgo = new Date()
  ninetyDaysAgo.setDate(ninetyDaysAgo.getDate() - 90)
  const result = await prisma.metricSnapshot.deleteMany({
    where: { timestamp: { lt: ninetyDaysAgo } }
  })
  return result.count
}

export async function getLatestSnapshot(vaultAddress?: string) {
  try {
    return await prisma.metricSnapshot.findFirst({
      where: vaultAddress ? { vaultAddress } : undefined,
      orderBy: { timestamp: "desc" }
    })
  } catch (err) {
    console.error("Prisma GET latest snapshot error:", err)
    return null
  }
}

export async function getSnapshotsInRange(
  startTime: Date,
  endTime: Date = new Date(),
  vaultAddress?: string
): Promise<Snapshot[]> {
  try {
    return await prisma.metricSnapshot.findMany({
      where: {
        timestamp: { gte: startTime, lte: endTime },
        ...(vaultAddress ? { vaultAddress } : {})
      },
      orderBy: { timestamp: "asc" }
    })
  } catch (err) {
    console.error("Prisma GET snapshots in range error:", err)
    return []
  }
}

export async function getLatestSnapshotsForAllVaults(
  vaultAddresses: string[]
): Promise<Map<string, Snapshot>> {
  const results = await Promise.all(
    vaultAddresses.map(async (addr) => {
      const snapshot = await prisma.metricSnapshot.findFirst({
        where: { vaultAddress: addr },
        orderBy: { timestamp: "desc" },
      })
      return [addr, snapshot] as const
    })
  )

  const map = new Map<string, Snapshot>()
  for (const [addr, snapshot] of results) {
    if (snapshot) map.set(addr, snapshot)
  }
  return map
}

// --- MarketSnapshot helpers (Phase 5) ---

type MktSnapshot = Awaited<
  ReturnType<typeof prisma.marketSnapshot.findMany>
>[number]

/** Get latest MarketSnapshot for a market, looked up by vaultAddress */
export async function getLatestMarketSnapshot(vaultAddress: string) {
  try {
    const market = await prisma.market.findUnique({
      where: { vaultAddress },
    })
    if (!market) return null
    return await prisma.marketSnapshot.findFirst({
      where: { marketId: market.id },
      orderBy: { timestamp: "desc" },
    })
  } catch (err) {
    console.error("getLatestMarketSnapshot error:", err)
    return null
  }
}

/** Get MarketSnapshot time-series for a market within a time range */
export async function getMarketSnapshotsInRange(
  vaultAddress: string,
  startTime: Date,
  endTime: Date = new Date()
): Promise<MktSnapshot[]> {
  try {
    const market = await prisma.market.findUnique({
      where: { vaultAddress },
    })
    if (!market) return []
    return await prisma.marketSnapshot.findMany({
      where: {
        marketId: market.id,
        timestamp: { gte: startTime, lte: endTime },
      },
      orderBy: { timestamp: "asc" },
    })
  } catch (err) {
    console.error("getMarketSnapshotsInRange error:", err)
    return []
  }
}

/** Get latest MarketSnapshot for every active market */
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
    console.error("getLatestSnapshotsForAllMarkets error:", err)
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
