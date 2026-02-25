/**
 * LendCore Backend Service
 * ------------------------
 * Standalone Express API + persistent indexer + cron jobs.
 *
 * Responsibilities:
 *   - Serve market data, metrics, history, positions, liquidations
 *   - Run the event-driven indexer as a persistent process
 *   - Run cron jobs for periodic snapshots and health factor checks
 */

import "dotenv/config"
import express from "express"
import cors from "cors"

import marketsRouter from "./routes/markets"
import metricsRouter from "./routes/metrics"
import historyRouter from "./routes/history"
import positionsRouter from "./routes/positions"
import liquidationsRouter from "./routes/liquidations"
import indexerRouter from "./routes/indexer"

import { startIndexer } from "./indexer/index"
import { startCronJobs } from "./jobs/index"

const app = express()
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
      // Allow requests with no origin (curl, Postman, server-to-server)
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
app.get("/health", (_req, res) => {
  res.json({ status: "ok", timestamp: new Date().toISOString() })
})

// --- Routes ---
app.use("/markets", marketsRouter)
app.use("/metrics", metricsRouter)
app.use("/history", historyRouter)
app.use("/positions", positionsRouter)
app.use("/liquidations", liquidationsRouter)
app.use("/indexer", indexerRouter)

// --- Start ---
app.listen(PORT, async () => {
  console.log(`[backend] Server started on :${PORT}`)
  console.log(`[backend] CORS allowed origins: ${allowedOrigins.join(", ")}`)

  // Auto-start indexer on boot
  try {
    const result = await startIndexer()
    if ("error" in result) {
      console.warn(`[backend] Indexer could not start: ${result.error}`)
    }
  } catch (err) {
    console.error("[backend] Indexer startup error:", err)
  }

  // Start cron jobs
  startCronJobs()
})

export default app
