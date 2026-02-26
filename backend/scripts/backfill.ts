/**
 * backfill.ts
 * -----------
 * CLI script to process a specific block range deterministically.
 * Safe to re-run — all writes are idempotent/upsert.
 *
 * Usage:
 *   cd backend
 *   npx tsx scripts/backfill.ts --from-block 7800000 --to-block 7900000
 *
 * With Railway env:
 *   railway run npx tsx scripts/backfill.ts --from-block 7800000 --to-block 7900000
 */

import "dotenv/config"
import { prisma } from "../src/lib/db"
import { client, CONFIRMATIONS, DEPLOYMENT_BLOCK } from "../src/lib/rpc"
import { processBlockRange } from "../src/indexer/block-processor"
import { logger } from "../src/lib/logger"
import type { MarketConfig } from "../src/indexer/listener"

async function main() {
  // Parse CLI args
  const args = process.argv.slice(2)
  const fromArg = args.indexOf("--from-block")
  const toArg   = args.indexOf("--to-block")

  if (fromArg === -1 || toArg === -1) {
    console.error("Usage: npx tsx scripts/backfill.ts --from-block <N> --to-block <N>")
    process.exit(1)
  }

  const fromBlock = BigInt(args[fromArg + 1])
  const toArgVal  = args[toArg + 1]

  // Support "latest" as to-block
  let toBlock: bigint
  if (toArgVal === "latest") {
    const currentBlock = await client.getBlockNumber()
    toBlock = currentBlock - BigInt(CONFIRMATIONS)
    logger.info({ toBlock: Number(toBlock) }, "[backfill] Resolved 'latest' to confirmed head")
  } else {
    toBlock = BigInt(toArgVal)
  }

  if (fromBlock < DEPLOYMENT_BLOCK) {
    logger.warn(
      { fromBlock: Number(fromBlock), deploymentBlock: Number(DEPLOYMENT_BLOCK) },
      "[backfill] from-block is before deployment block — clamping"
    )
  }

  // Load active markets
  const markets = await prisma.market.findMany({ where: { isActive: true } })
  if (markets.length === 0) {
    logger.error("[backfill] No active markets found. Run seed first.")
    process.exit(1)
  }

  const marketConfigs: MarketConfig[] = markets.map((m) => ({
    marketId:            m.id,
    vaultAddress:        m.vaultAddress        as `0x${string}`,
    marketAddress:       m.marketAddress       as `0x${string}`,
    irmAddress:          m.irmAddress          as `0x${string}`,
    oracleRouterAddress: m.oracleRouterAddress  as `0x${string}`,
    loanAsset:           m.loanAsset           as `0x${string}`,
    loanAssetDecimals:   m.loanAssetDecimals,
  }))

  logger.info(
    { from: Number(fromBlock), to: Number(toBlock), markets: marketConfigs.length },
    "[backfill] Starting"
  )

  await processBlockRange(fromBlock, toBlock, marketConfigs)

  logger.info("[backfill] Done")
  await prisma.$disconnect()
}

main().catch((err) => {
  logger.error({ err }, "[backfill] Fatal error")
  prisma.$disconnect()
  process.exit(1)
})
