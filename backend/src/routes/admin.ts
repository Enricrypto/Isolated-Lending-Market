/**
 * Admin Routes
 * ------------
 * Secured endpoints for updating market parameters in the DB.
 * All routes require: Authorization: Bearer <ADMIN_SECRET>
 *
 * GET  /admin/market-params     — list all markets with their current params
 * POST /admin/market-params     — update params for one market (by marketAddress)
 * POST /admin/trigger-snapshot  — force a snapshot recompute
 *
 * Uses raw SQL for MarketParams to work before/after prisma generate.
 */

import { Router, Request, Response } from "express"
import { prisma } from "../lib/db"
import { computeAndSaveMarketSnapshot } from "../indexer/snapshot"
import { activeMarkets } from "../indexer/index"
import { logger } from "../lib/logger"

const router = Router()

// ─── Auth middleware ──────────────────────────────────────────────────────────

function requireAdmin(req: Request, res: Response, next: () => void) {
  const secret = process.env.ADMIN_SECRET
  if (!secret) {
    res.status(503).json({ error: "ADMIN_SECRET not configured on server" })
    return
  }
  const auth = req.headers.authorization ?? ""
  if (auth !== `Bearer ${secret}`) {
    res.status(401).json({ error: "Unauthorized" })
    return
  }
  next()
}

type ParamsRow = {
  market_id: string; base_rate: string; slope1: string; slope2: string;
  optimal_utilization: string; lltv: string; liquidation_penalty: string;
  protocol_fee: string; updated_at: Date; updated_by: string;
}

// ─── GET /admin/market-params ─────────────────────────────────────────────────

router.get("/market-params", requireAdmin, async (_req: Request, res: Response) => {
  try {
    const markets = await prisma.market.findMany({
      where:   { isActive: true },
      orderBy: { createdAt: "asc" },
    })

    let paramRows: ParamsRow[] = []
    try {
      paramRows = await prisma.$queryRaw<ParamsRow[]>`
        SELECT market_id, base_rate, slope1, slope2, optimal_utilization,
               lltv, liquidation_penalty, protocol_fee, updated_at, updated_by
        FROM "MarketParams"
      `
    } catch {
      // Table may not exist before first db push
    }

    const paramsByMarketId = Object.fromEntries(
      paramRows.map((r) => [r.market_id, r])
    )

    const result = markets.map((m) => {
      const p = paramsByMarketId[m.id] ?? null
      return {
        marketId:      m.id,
        marketAddress: m.marketAddress,
        vaultAddress:  m.vaultAddress,
        label:         m.label,
        symbol:        m.symbol,
        params: p
          ? {
              baseRate:           Number(p.base_rate),
              slope1:             Number(p.slope1),
              slope2:             Number(p.slope2),
              optimalUtilization: Number(p.optimal_utilization),
              lltv:               Number(p.lltv),
              liquidationPenalty: Number(p.liquidation_penalty),
              protocolFee:        Number(p.protocol_fee),
              updatedAt:          p.updated_at.toISOString(),
              updatedBy:          p.updated_by,
            }
          : null,
      }
    })

    res.json({ markets: result, timestamp: new Date().toISOString() })
  } catch (err) {
    logger.error({ err }, "[admin/market-params GET] Error")
    res.status(500).json({ error: "Failed to fetch market params" })
  }
})

// ─── POST /admin/market-params ────────────────────────────────────────────────

/**
 * Body (all fields optional except marketAddress):
 * {
 *   marketAddress: string,       // identify which market to update
 *   baseRate?: number,           // 0.02 = 2%
 *   slope1?: number,
 *   slope2?: number,
 *   optimalUtilization?: number, // 0.80 = 80%
 *   lltv?: number,               // 0.85 = 85%
 *   liquidationPenalty?: number,
 *   protocolFee?: number,
 * }
 */
router.post("/market-params", requireAdmin, async (req: Request, res: Response) => {
  const {
    marketAddress,
    baseRate,
    slope1,
    slope2,
    optimalUtilization,
    lltv,
    liquidationPenalty,
    protocolFee,
  } = req.body as Record<string, unknown>

  if (!marketAddress || typeof marketAddress !== "string") {
    res.status(400).json({ error: "marketAddress is required" })
    return
  }

  const fields: Record<string, number | undefined> = {
    baseRate:           typeof baseRate           === "number" ? baseRate           : undefined,
    slope1:             typeof slope1             === "number" ? slope1             : undefined,
    slope2:             typeof slope2             === "number" ? slope2             : undefined,
    optimalUtilization: typeof optimalUtilization === "number" ? optimalUtilization : undefined,
    lltv:               typeof lltv               === "number" ? lltv               : undefined,
    liquidationPenalty: typeof liquidationPenalty === "number" ? liquidationPenalty : undefined,
    protocolFee:        typeof protocolFee        === "number" ? protocolFee        : undefined,
  }

  const provided = Object.entries(fields).filter(([, v]) => v !== undefined)
  if (provided.length === 0) {
    res.status(400).json({ error: "At least one parameter field must be provided" })
    return
  }

  for (const [key, val] of provided) {
    if (val! < 0 || val! > 10) {
      res.status(400).json({ error: `${key} must be between 0 and 10 (= 0–1000%)` })
      return
    }
  }

  try {
    const market = await prisma.market.findFirst({
      where: { marketAddress: { equals: marketAddress, mode: "insensitive" } },
    })

    if (!market) {
      res.status(404).json({ error: `Market not found: ${marketAddress}` })
      return
    }

    // Fetch existing row (if any) to fill in unchanged fields
    let existing: ParamsRow | null = null
    try {
      const rows = await prisma.$queryRaw<ParamsRow[]>`
        SELECT * FROM "MarketParams" WHERE market_id = ${market.id} LIMIT 1
      `
      existing = rows[0] ?? null
    } catch { /* table may not exist */ }

    const merged = {
      baseRate:           (fields.baseRate           ?? (existing ? Number(existing.base_rate)           : 0.02)).toFixed(6),
      slope1:             (fields.slope1             ?? (existing ? Number(existing.slope1)             : 0.04)).toFixed(6),
      slope2:             (fields.slope2             ?? (existing ? Number(existing.slope2)             : 0.60)).toFixed(6),
      optimalUtilization: (fields.optimalUtilization ?? (existing ? Number(existing.optimal_utilization) : 0.80)).toFixed(6),
      lltv:               (fields.lltv               ?? (existing ? Number(existing.lltv)               : 0.85)).toFixed(6),
      liquidationPenalty: (fields.liquidationPenalty ?? (existing ? Number(existing.liquidation_penalty) : 0.05)).toFixed(6),
      protocolFee:        (fields.protocolFee        ?? (existing ? Number(existing.protocol_fee)        : 0.10)).toFixed(6),
    }

    await prisma.$executeRaw`
      INSERT INTO "MarketParams" (
        id, market_id, base_rate, slope1, slope2, optimal_utilization,
        lltv, liquidation_penalty, protocol_fee, updated_at, updated_by
      ) VALUES (
        gen_random_uuid(), ${market.id},
        ${merged.baseRate}, ${merged.slope1}, ${merged.slope2},
        ${merged.optimalUtilization}, ${merged.lltv},
        ${merged.liquidationPenalty}, ${merged.protocolFee},
        NOW(), 'admin'
      )
      ON CONFLICT (market_id) DO UPDATE SET
        base_rate           = EXCLUDED.base_rate,
        slope1              = EXCLUDED.slope1,
        slope2              = EXCLUDED.slope2,
        optimal_utilization = EXCLUDED.optimal_utilization,
        lltv                = EXCLUDED.lltv,
        liquidation_penalty = EXCLUDED.liquidation_penalty,
        protocol_fee        = EXCLUDED.protocol_fee,
        updated_at          = NOW(),
        updated_by          = 'admin'
    `

    logger.info(
      { market: marketAddress.slice(0, 10), fields: provided.map(([k]) => k) },
      "[admin/market-params POST] Updated"
    )

    res.json({
      ok:        true,
      marketId:  market.id,
      symbol:    market.symbol,
      updatedAt: new Date().toISOString(),
      params:    {
        baseRate:           Number(merged.baseRate),
        slope1:             Number(merged.slope1),
        slope2:             Number(merged.slope2),
        optimalUtilization: Number(merged.optimalUtilization),
        lltv:               Number(merged.lltv),
        liquidationPenalty: Number(merged.liquidationPenalty),
        protocolFee:        Number(merged.protocolFee),
      },
    })
  } catch (err) {
    logger.error({ err }, "[admin/market-params POST] Error")
    res.status(500).json({ error: "Failed to update market params" })
  }
})

// ─── POST /admin/trigger-snapshot ────────────────────────────────────────────

router.post("/trigger-snapshot", requireAdmin, async (req: Request, res: Response) => {
  const { marketAddress } = req.body as { marketAddress?: string }

  const targets = marketAddress
    ? activeMarkets.filter(
        (m) => m.marketAddress.toLowerCase() === marketAddress.toLowerCase()
      )
    : activeMarkets

  if (targets.length === 0) {
    res.status(404).json({ error: "No matching active markets" })
    return
  }

  const results: Array<{ symbol: string; ok: boolean; error?: string }> = []

  for (const market of targets) {
    try {
      await computeAndSaveMarketSnapshot(market)
      results.push({ symbol: market.marketId, ok: true })
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Unknown"
      results.push({ symbol: market.marketId, ok: false, error: msg })
    }
  }

  res.json({ ok: true, recomputed: results.length, results })
})

export default router
