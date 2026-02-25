/**
 * Vault Registry (BOOTSTRAP – STATIC)
 * ----------------------------------
 * This file defines the **initial, hardcoded set of vaults** monitored by the protocol.
 *
 * CURRENT ROLE (v1):
 * - Acts as a static bootstrap manifest for known vaults
 * - Provides VaultConfig objects to:
 *   • polling orchestrator (agents/index.ts)
 *   • monitoring & analytics pipeline
 *   • UI routing / labeling
 * - Ensures deterministic, auditable configuration during early development
 *
 * IMPORTANT:
 * - This is NOT a generic or reusable Vault Registry
 * - Vaults, strategies, and addresses are hardcoded
 * - Adding or modifying vaults requires a redeploy
 *
 * WHY THIS EXISTS:
 * - Early-stage safety and auditability
 * - Avoids premature database or on-chain dependency
 * - Stabilizes metrics, severity logic, and UI contracts first
 *
 * FUTURE PLAN (v2+):
 * - Replace this file with a VaultRegistry interface
 * - Back the registry by:
 *   • Database tables (vaults, strategies, networks), or
 *   • On-chain VaultFactory + indexer (permissionless creation)
 * - Polling and agents must depend ONLY on the registry interface,
 *   not on hardcoded configs
 *
 * MIGRATION STRATEGY:
 * - Introduce a VaultRegistry abstraction
 * - Implement StaticVaultRegistry (this file)
 * - Later swap to DbVaultRegistry or OnChainVaultRegistry
 *   with zero changes to pollers or agents
 *
 * Treat this file as a BOOTSTRAP MANIFEST, not a final design.
 */

import type { VaultConfig } from "@/types/metrics"

// Shared across all markets (deployed by DeployAll.s.sol)
const ORACLE_ROUTER = "0xf0a440147AAC2FF4349ca623f8bf9BD96EA43843"

export const VAULT_REGISTRY: VaultConfig[] = [
  // ── USDC Market (deployed Jan 30, 2026) ──────────────────────────────────
  {
    vaultAddress: "0xE8323c3d293f81C71232023367Bada21137C055E",
    marketAddress: "0x12f8DA89619C40553d9eA50aAce593cEb2f3eFcE",
    irmAddress: "0x7Eca31bB8e6C9369b34cacf2dF32E815EbdcAdB2",
    oracleRouterAddress: ORACLE_ROUTER,
    loanAsset: "0xa23575D09B55c709590F7f5507b246043A8cF49b",
    loanAssetDecimals: 6,
    label: "USDC Market",
    symbol: "USDC"
  },
  // ── WETH Market (deployed Feb 25, 2026 — DeployMarkets.s.sol) ───────────
  {
    vaultAddress:        "0xbbc4c7FbCcF0faa27821c4F44C01D3F81C088070",
    marketAddress:       "0x9ef4141b954947800A47F46D11a6B2f366d1673b",
    irmAddress:          "0xD886efbc840024A7758c8fefF115dBd5B1986A04",
    oracleRouterAddress: ORACLE_ROUTER,
    loanAsset:           "0x655Af45748C1116B95339d189B1556c92d73ff77",
    loanAssetDecimals:   18,
    label:               "WETH Market",
    symbol:              "WETH"
  },
  // ── WBTC Market (deployed Feb 25, 2026 — DeployMarkets.s.sol) ───────────
  {
    vaultAddress:        "0xBCB5fcA37f87a97eB1C5d6c9a92749e0F41161f0",
    marketAddress:       "0xD1928f50281c65fBC73c8a644D259F1A6633AC56",
    irmAddress:          "0xaDEf01C0aD41b0e5e6AF74e885cD1805dC4FA8E9",
    oracleRouterAddress: ORACLE_ROUTER,
    loanAsset:           "0x3bCFE4F6f3b11c8dB62f8302dc53f5CCdb51F9c3",
    loanAssetDecimals:   8,
    label:               "WBTC Market",
    symbol:              "WBTC"
  },
]

export const DEFAULT_VAULT = VAULT_REGISTRY[0]

export function getVaultConfig(vaultAddress: string): VaultConfig | undefined {
  return VAULT_REGISTRY.find(
    (v) => v.vaultAddress.toLowerCase() === vaultAddress.toLowerCase()
  )
}

export function getAllVaultAddresses(): string[] {
  return VAULT_REGISTRY.map((v) => v.vaultAddress)
}

