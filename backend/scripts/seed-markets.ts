/**
 * seed-markets.ts
 * ---------------
 * Idempotent seed for the Market table.
 * Safe to re-run — uses upsert on vaultAddress (unique).
 *
 * Usage:
 *   cd backend
 *   source ../.env && npx tsx scripts/seed-markets.ts
 */

import "dotenv/config"
import { prisma } from "../src/lib/db"

const ORACLE_ROUTER = "0xf0a440147AAC2FF4349ca623f8bf9BD96EA43843"

const MARKETS = [
  {
    vaultAddress:        "0xE8323c3d293f81C71232023367Bada21137C055E",
    marketAddress:       "0x12f8DA89619C40553d9eA50aAce593cEb2f3eFcE",
    irmAddress:          "0x7Eca31bB8e6C9369b34cacf2dF32E815EbdcAdB2",
    oracleRouterAddress: ORACLE_ROUTER,
    loanAsset:           "0xa23575D09B55c709590F7f5507b246043A8cF49b",
    loanAssetDecimals:   6,
    label:               "USDC Market",
    symbol:              "USDC",
    isActive:            true,
  },
  {
    vaultAddress:        "0xbbc4c7FbCcF0faa27821c4F44C01D3F81C088070",
    marketAddress:       "0x9ef4141b954947800A47F46D11a6B2f366d1673b",
    irmAddress:          "0xD886efbc840024A7758c8fefF115dBd5B1986A04",
    oracleRouterAddress: ORACLE_ROUTER,
    loanAsset:           "0x655Af45748C1116B95339d189B1556c92d73ff77",
    loanAssetDecimals:   18,
    label:               "WETH Market",
    symbol:              "WETH",
    isActive:            true,
  },
  {
    vaultAddress:        "0xBCB5fcA37f87a97eB1C5d6c9a92749e0F41161f0",
    marketAddress:       "0xD1928f50281c65fBC73c8a644D259F1A6633AC56",
    irmAddress:          "0xaDEf01C0aD41b0e5e6AF74e885cD1805dC4FA8E9",
    oracleRouterAddress: ORACLE_ROUTER,
    loanAsset:           "0x3bCFE4F6f3b11c8dB62f8302dc53f5CCdb51F9c3",
    loanAssetDecimals:   8,
    label:               "WBTC Market",
    symbol:              "WBTC",
    isActive:            true,
  },
]

async function main() {
  console.log(`[seed] Upserting ${MARKETS.length} markets...`)

  for (const market of MARKETS) {
    const result = await prisma.market.upsert({
      where:  { vaultAddress: market.vaultAddress },
      update: { ...market },
      create: { ...market },
    })
    console.log(`[seed] ✓ ${result.symbol} — ${result.id}`)
  }

  console.log("[seed] Done.")
  await prisma.$disconnect()
}

main().catch((err) => {
  console.error("[seed] Error:", err)
  prisma.$disconnect()
  process.exit(1)
})
