import { PrismaClient } from "@prisma/client";
import { PrismaPg } from "@prisma/adapter-pg";

// Prevent multiple instances of Prisma Client in development
const globalForPrisma = globalThis as unknown as {
  prisma: PrismaClient | undefined;
};

function createPrismaClient() {
  const adapter = new PrismaPg({
    connectionString: process.env.DATABASE_URL,
  });

  return new PrismaClient({
    adapter,
    log: process.env.NODE_ENV === "development" ? ["query", "error", "warn"] : ["error"],
  });
}

export const prisma = globalForPrisma.prisma ?? createPrismaClient();

if (process.env.NODE_ENV !== "production") {
  globalForPrisma.prisma = prisma;
}

// Helper to clean up old snapshots (keep last 30 days)
export async function cleanupOldSnapshots() {
  const thirtyDaysAgo = new Date();
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

  const result = await prisma.metricSnapshot.deleteMany({
    where: {
      timestamp: {
        lt: thirtyDaysAgo,
      },
    },
  });

  return result.count;
}

// Get the most recent snapshot
export async function getLatestSnapshot() {
  return prisma.metricSnapshot.findFirst({
    orderBy: { timestamp: "desc" },
  });
}

// Get snapshots for a time range
export async function getSnapshotsInRange(startTime: Date, endTime: Date = new Date()) {
  return prisma.metricSnapshot.findMany({
    where: {
      timestamp: {
        gte: startTime,
        lte: endTime,
      },
    },
    orderBy: { timestamp: "asc" },
  });
}

// Get time range based on string
export function getTimeRangeStart(range: string): Date {
  const now = new Date();
  switch (range) {
    case "24h":
      return new Date(now.getTime() - 24 * 60 * 60 * 1000);
    case "7d":
      return new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    case "30d":
      return new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
    default:
      return new Date(now.getTime() - 24 * 60 * 60 * 1000);
  }
}
