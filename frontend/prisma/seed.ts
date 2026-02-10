/**
 * Seed script — Populates the Market table from VAULT_REGISTRY.
 *
 * Usage:
 *   npx tsx prisma/seed.ts
 *
 * Idempotent: uses upsert keyed on vaultAddress, safe to re-run.
 */

import { PrismaClient } from "./generated/prisma/client"
import { PrismaPg } from "@prisma/adapter-pg"

const MARKETS = [
  {
    vaultAddress: "0xE8323c3d293f81C71232023367Bada21137C055E",
    marketAddress: "0x12f8DA89619C40553d9eA50aAce593cEb2f3eFcE",
    irmAddress: "0x7Eca31bB8e6C9369b34cacf2dF32E815EbdcAdB2",
    oracleRouterAddress: "0xf0a440147AAC2FF4349ca623f8bf9BD96EA43843",
    loanAsset: "0xa23575D09B55c709590F7f5507b246043A8cF49b",
    loanAssetDecimals: 6,
    label: "USDC Market",
    symbol: "USDC",
  },
] as const

async function main() {
  const adapter = new PrismaPg({
    connectionString: process.env.PG_URL || process.env.DATABASE_URL!,
    ssl: { rejectUnauthorized: false },
  })

  const prisma = new PrismaClient({ adapter })

  console.log(`Seeding ${MARKETS.length} market(s)...`)

  for (const m of MARKETS) {
    const result = await prisma.market.upsert({
      where: { vaultAddress: m.vaultAddress },
      update: {
        marketAddress: m.marketAddress,
        irmAddress: m.irmAddress,
        oracleRouterAddress: m.oracleRouterAddress,
        loanAsset: m.loanAsset,
        loanAssetDecimals: m.loanAssetDecimals,
        label: m.label,
        symbol: m.symbol,
      },
      create: {
        vaultAddress: m.vaultAddress,
        marketAddress: m.marketAddress,
        irmAddress: m.irmAddress,
        oracleRouterAddress: m.oracleRouterAddress,
        loanAsset: m.loanAsset,
        loanAssetDecimals: m.loanAssetDecimals,
        label: m.label,
        symbol: m.symbol,
      },
    })
    console.log(`  ✓ ${result.label} (${result.id})`)
  }

  console.log("Done.")
  await prisma.$disconnect()
}

main().catch((e) => {
  console.error("Seed failed:", e)
  process.exit(1)
})
