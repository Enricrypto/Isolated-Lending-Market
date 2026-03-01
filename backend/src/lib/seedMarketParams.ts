/**
 * Seed Market Parameters
 * ----------------------
 * On indexer startup, reads IRM and risk parameters from each active market's
 * on-chain contracts and upserts them into the MarketParams table.
 *
 * Uses raw SQL to avoid the need for a regenerated Prisma client after the
 * MarketParams model was added to the schema.
 */

import { client, normalize, WAD } from "./rpc"
import { IRM_ABI, MARKET_ABI } from "./contracts"
import { prisma } from "./db"
import { logger } from "./logger"
import type { MarketConfig } from "../indexer/listener"

export async function seedMarketParams(markets: MarketConfig[]): Promise<void> {
  if (markets.length === 0) return

  logger.info({ count: markets.length }, "[seedMarketParams] Seeding market params from chain")

  for (const market of markets) {
    try {
      const results = await client.multicall({
        contracts: [
          {
            address: market.irmAddress,
            abi: IRM_ABI,
            functionName: "getParameters",
          },
          {
            address: market.marketAddress,
            abi: MARKET_ABI,
            functionName: "lltv",
          },
          {
            address: market.marketAddress,
            abi: MARKET_ABI,
            functionName: "liquidationPenalty",
          },
          {
            address: market.marketAddress,
            abi: MARKET_ABI,
            functionName: "protocolFee",
          },
        ],
        allowFailure: true,
      })

      const irmResult     = results[0]
      const lltvResult    = results[1]
      const penaltyResult = results[2]
      const feeResult     = results[3]

      if (irmResult.status !== "success") {
        logger.warn(
          { market: market.marketAddress.slice(0, 10) },
          "[seedMarketParams] getParameters() failed — skipping"
        )
        continue
      }

      const [baseRateRaw, optimalRaw, slope1Raw, slope2Raw] =
        irmResult.result as [bigint, bigint, bigint, bigint]

      const baseRate           = normalize(baseRateRaw, WAD)
      const optimalUtilization = normalize(optimalRaw,  WAD)
      const slope1             = normalize(slope1Raw,   WAD)
      const slope2             = normalize(slope2Raw,   WAD)

      const lltv               = lltvResult.status    === "success"
        ? normalize(lltvResult.result as bigint, WAD) : 0.85
      const liquidationPenalty = penaltyResult.status === "success"
        ? normalize(penaltyResult.result as bigint, WAD) : 0.05
      const protocolFee        = feeResult.status     === "success"
        ? normalize(feeResult.result as bigint, WAD) : 0.10

      // Raw SQL upsert — works before/after prisma generate
      await prisma.$executeRaw`
        INSERT INTO "MarketParams" (
          id, market_id, base_rate, slope1, slope2, optimal_utilization,
          lltv, liquidation_penalty, protocol_fee, updated_at, updated_by
        ) VALUES (
          gen_random_uuid(), ${market.marketId},
          ${baseRate.toFixed(6)}, ${slope1.toFixed(6)}, ${slope2.toFixed(6)},
          ${optimalUtilization.toFixed(6)}, ${lltv.toFixed(6)},
          ${liquidationPenalty.toFixed(6)}, ${protocolFee.toFixed(6)},
          NOW(), 'chain'
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
          updated_by          = 'chain'
      `

      logger.info(
        {
          market:   market.marketAddress.slice(0, 10),
          baseRate: `${(baseRate * 100).toFixed(2)}%`,
          kink:     `${(optimalUtilization * 100).toFixed(0)}%`,
          slope1:   `${(slope1 * 100).toFixed(2)}%`,
          slope2:   `${(slope2 * 100).toFixed(2)}%`,
          lltv:     `${(lltv * 100).toFixed(0)}%`,
        },
        "[seedMarketParams] Upserted"
      )
    } catch (err) {
      logger.error({ market: market.marketAddress.slice(0, 10), err }, "[seedMarketParams] Error")
    }
  }

  logger.info("[seedMarketParams] Done")
}
