/**
 * reindex.ts
 * ----------
 * Full reindex: drops all derived tables, resets SyncState, replays from DEPLOYMENT_BLOCK.
 * After this, DB state is a pure function of chain state.
 *
 * ⚠️  DESTRUCTIVE — deletes all MarketSnapshot, UserPositionSnapshot, LiquidationEvent,
 *     IndexedBlock records. Markets table is preserved.
 *
 * Usage:
 *   cd backend
 *   railway run npx tsx scripts/reindex.ts
 *
 * Pass --yes to skip the confirmation prompt (for CI use):
 *   railway run npx tsx scripts/reindex.ts --yes
 */

import "dotenv/config"
import * as readline from "readline"
import { prisma } from "../src/lib/db"
import { client, CONFIRMATIONS, DEPLOYMENT_BLOCK } from "../src/lib/rpc"
import { processBlockRange } from "../src/indexer/block-processor"
import { logger } from "../src/lib/logger"
import type { MarketConfig } from "../src/indexer/listener"

async function confirm(prompt: string): Promise<boolean> {
  if (process.argv.includes("--yes")) return true

  const rl = readline.createInterface({ input: process.stdin, output: process.stdout })
  return new Promise((resolve) => {
    rl.question(`${prompt} (yes/no): `, (answer) => {
      rl.close()
      resolve(answer.trim().toLowerCase() === "yes")
    })
  })
}

async function main() {
  console.log("\n⚠️  FULL REINDEX")
  console.log("This will DELETE all MarketSnapshot, UserPositionSnapshot, LiquidationEvent,")
  console.log(`and IndexedBlock records, then replay from block ${DEPLOYMENT_BLOCK}.\n`)

  const ok = await confirm("Are you sure?")
  if (!ok) {
    console.log("Aborted.")
    process.exit(0)
  }

  // 1. Load active markets (preserved)
  const markets = await prisma.market.findMany({ where: { isActive: true } })
  if (markets.length === 0) {
    logger.error("[reindex] No active markets found. Run seed first.")
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

  // 2. Truncate derived tables
  logger.info("[reindex] Truncating derived tables...")
  await prisma.$transaction([
    prisma.marketSnapshot.deleteMany(),
    prisma.userPositionSnapshot.deleteMany(),
    prisma.liquidationEvent.deleteMany(),
    prisma.indexedBlock.deleteMany(),
    prisma.syncState.deleteMany(),
  ])
  logger.info("[reindex] Tables cleared")

  // 3. Determine safe head
  const currentBlock = await client.getBlockNumber()
  const safeHead     = currentBlock - BigInt(CONFIRMATIONS)

  logger.info(
    { from: Number(DEPLOYMENT_BLOCK), to: Number(safeHead) },
    "[reindex] Replaying blocks"
  )

  // 4. Full replay
  await processBlockRange(DEPLOYMENT_BLOCK, safeHead, marketConfigs)

  logger.info("[reindex] Done — DB is now a pure function of chain state")
  await prisma.$disconnect()
}

main().catch((err) => {
  logger.error({ err }, "[reindex] Fatal error")
  prisma.$disconnect()
  process.exit(1)
})
