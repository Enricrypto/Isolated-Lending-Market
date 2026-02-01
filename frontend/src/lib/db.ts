import { PrismaClient } from "@prisma/client"
import { PrismaPg } from "@prisma/adapter-pg"
import { Pool } from "pg"

// Prevent multiple instances of Prisma Client in development (Next.js hot reloads)
const globalForPrisma = globalThis as unknown as {
  prisma: PrismaClient | undefined
}

function createPrismaClient() {
  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false }, // Required for Supabase
    max: 5 // Keep low for free-tier / shared DB
  })
  console.log("DATABASE_URL =", process.env.DATABASE_URL)

  const adapter = new PrismaPg(pool)

  return new PrismaClient({
    adapter,
    log:
      process.env.NODE_ENV === "development"
        ? ["query", "warn", "error"]
        : ["error"]
  })
}

// Use singleton in development to prevent multiple connections
export const prisma = globalForPrisma.prisma ?? createPrismaClient()

if (process.env.NODE_ENV !== "production") {
  globalForPrisma.prisma = prisma
}

// --- Helpers ---

// Delete snapshots older than 90 days
export async function cleanupOldSnapshots() {
  const ninetyDaysAgo = new Date()
  ninetyDaysAgo.setDate(ninetyDaysAgo.getDate() - 90)

  const result = await prisma.metricSnapshot.deleteMany({
    where: { timestamp: { lt: ninetyDaysAgo } }
  })

  return result.count
}

// Get the most recent snapshot, optionally filtered by vault
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

// Get snapshots in a given range, optionally filtered by vault
export async function getSnapshotsInRange(
  startTime: Date,
  endTime: Date = new Date(),
  vaultAddress?: string
) {
  try {
    return await prisma.metricSnapshot.findMany({
      where: {
        timestamp: { gte: startTime, lte: endTime },
        ...(vaultAddress ? { vaultAddress } : {}),
      },
      orderBy: { timestamp: "asc" }
    })
  } catch (err) {
    console.error("Prisma GET snapshots in range error:", err)
    return []
  }
}

// Convert string range to Date
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
