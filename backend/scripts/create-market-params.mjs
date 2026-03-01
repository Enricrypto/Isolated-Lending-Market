/**
 * create-market-params.mjs
 * -------------------------
 * Creates the MarketParams table in Postgres (if it doesn't exist).
 * Run once after adding the model to the Prisma schema:
 *   node scripts/create-market-params.mjs
 */

import pg from "pg"
import { readFileSync } from "fs"
import { resolve, dirname } from "path"
import { fileURLToPath } from "url"

const __dir = dirname(fileURLToPath(import.meta.url))

// Load DATABASE_URL from ../.env if present
const envPath = resolve(__dir, "../.env")
try {
  const raw = readFileSync(envPath, "utf8")
  for (const line of raw.split("\n")) {
    const m = line.match(/^([A-Z_]+)\s*=\s*"?([^"]*)"?$/)
    if (m) process.env[m[1]] ??= m[2]
  }
} catch { /* .env not found — use env vars already in process */ }

const url = process.env.DATABASE_URL
if (!url) {
  console.error("DATABASE_URL is not set")
  process.exit(1)
}

const { Client } = pg
const client = new Client({ connectionString: url })
await client.connect()

try {
  // Create the table
  await client.query(`
    CREATE TABLE IF NOT EXISTS "MarketParams" (
      id                  UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
      market_id           TEXT    NOT NULL UNIQUE,
      base_rate           NUMERIC(18, 6) NOT NULL,
      slope1              NUMERIC(18, 6) NOT NULL,
      slope2              NUMERIC(18, 6) NOT NULL,
      optimal_utilization NUMERIC(18, 6) NOT NULL,
      lltv                NUMERIC(18, 6) NOT NULL,
      liquidation_penalty NUMERIC(18, 6) NOT NULL,
      protocol_fee        NUMERIC(18, 6) NOT NULL,
      updated_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
      updated_by          TEXT           NOT NULL DEFAULT 'chain',
      CONSTRAINT "MarketParams_market_id_fkey"
        FOREIGN KEY (market_id) REFERENCES "Market"(id) ON DELETE CASCADE
    )
  `)
  console.log('✓ "MarketParams" table created (or already existed)')

  // Verify
  const r = await client.query(`
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_name = 'MarketParams'
  `)
  console.log("  Rows in information_schema:", r.rows[0].count)
} catch (err) {
  console.error("Error:", err.message)
  process.exit(1)
} finally {
  await client.end()
}
