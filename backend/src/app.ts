/**
 * LendCore Backend Service
 * ------------------------
 * Standalone Express API + persistent deterministic indexer + cron jobs.
 *
 * Responsibilities:
 *   - Serve market data, metrics, history, positions, liquidations
 *   - Run the block-based deterministic indexer as a persistent process
 *   - Run cron jobs for periodic snapshots and health factor checks
 *   - Expose internal endpoints for operational recovery (secured)
 */

import "dotenv/config"
import express from "express"
import cors from "cors"

import marketsRouter      from "./routes/markets"
import metricsRouter      from "./routes/metrics"
import historyRouter      from "./routes/history"
import positionsRouter    from "./routes/positions"
import liquidationsRouter from "./routes/liquidations"
import indexerRouter      from "./routes/indexer"
import internalRouter     from "./routes/internal"
import adminRouter        from "./routes/admin"

import { startIndexer } from "./indexer/index"
import { startCronJobs } from "./jobs/index"
import { prisma } from "./lib/db"
import { client } from "./lib/rpc"
import { logger } from "./lib/logger"

const app  = express()
const PORT = Number(process.env.PORT ?? 4000)

// --- CORS ---
const allowedOrigins = [
  process.env.FRONTEND_URL,
  "http://localhost:3000",
  "http://localhost:3001",
].filter(Boolean) as string[]

app.use(
  cors({
    origin: (origin, callback) => {
      if (!origin || allowedOrigins.includes(origin)) {
        callback(null, true)
      } else {
        callback(new Error(`CORS blocked: ${origin}`))
      }
    },
    methods: ["GET", "POST"],
    allowedHeaders: ["Content-Type", "Authorization"],
  })
)

app.use(express.json())

// --- Health check ---
app.get("/health", async (_req, res) => {
  const [dbResult, rpcResult, syncResult] = await Promise.allSettled([
    prisma.$queryRaw`SELECT 1`,
    client.getBlockNumber(),
    prisma.syncState.findFirst(),
  ])

  const ok = dbResult.status === "fulfilled" && rpcResult.status === "fulfilled"

  res.status(ok ? 200 : 503).json({
    status:           ok ? "ok" : "degraded",
    db:               dbResult.status  === "fulfilled" ? "connected" : "error",
    rpc:              rpcResult.status === "fulfilled"
                        ? String((rpcResult as PromiseFulfilledResult<bigint>).value)
                        : "error",
    lastIndexedBlock: syncResult.status === "fulfilled"
                        ? syncResult.value?.lastProcessedBlock ?? null
                        : null,
    timestamp: new Date().toISOString(),
  })
})

// --- Routes ---
app.use("/markets",      marketsRouter)
app.use("/metrics",      metricsRouter)
app.use("/history",      historyRouter)
app.use("/positions",    positionsRouter)
app.use("/liquidations", liquidationsRouter)
app.use("/indexer",      indexerRouter)
app.use("/internal",     internalRouter)
app.use("/admin",        adminRouter)

// --- Start ---
app.listen(PORT, async () => {
  logger.info({ port: PORT, origins: allowedOrigins }, "[backend] Server started")

  // Auto-start indexer on boot
  try {
    const result = await startIndexer()
    if ("error" in result) {
      logger.warn({ error: result.error }, "[backend] Indexer could not start")
    }
  } catch (err) {
    logger.error({ err }, "[backend] Indexer startup error")
  }

  // Start cron jobs
  startCronJobs()
})

export default app
