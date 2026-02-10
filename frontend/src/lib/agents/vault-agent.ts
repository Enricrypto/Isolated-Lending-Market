/**
 * Vault Agent
 * -----------
 * This file is responsible for **fetching the fundamental on-chain state of a vault**
 * required to assess liquidity, utilization, and interest rate behavior.
 *
 * Role in the system:
 * - Canonical source of truth for vault-level financial primitives
 * - Reads directly from Vault, Market, and IRM contracts via RPC
 * - Outputs normalized, unit-safe values for downstream processing
 *
 * What this agent DOES:
 * - Reads vault liquidity and asset balances
 * - Reads total borrows from the associated market
 * - Reads utilization and borrow rate parameters from the IRM
 * - Normalizes all token amounts and rates into human-readable numbers
 *
 * What this agent does NOT do:
 * - Does NOT compute risk or severity classifications
 * - Does NOT apply protocol policy or thresholds
 * - Does NOT persist data or handle historical comparisons
 * - Does NOT contain UI or presentation logic
 *
 * Downstream consumers:
 * - pollAndStore() combines this with oracle & strategy agents
 * - Severity functions derive liquidity, APR convexity, and velocity risk
 * - Normalized values are stored as metric snapshots in the database
 * - Monitoring UI renders these values via read-only API endpoints
 *
 * Normalization rules:
 * - Token amounts are normalized using the loan asset decimals
 * - Rates from the IRM are always WAD-based (18 decimals, 0–1 range)
 *
 * IMPORTANT:
 * - This agent must remain deterministic and side-effect free
 * - Any change here directly impacts risk calculations system-wide
 */

import { client, normalize, WAD } from "../rpc"
import { VAULT_ABI, MARKET_ABI, IRM_ABI } from "../contracts"
import type { VaultConfig } from "@/types/metrics"

export interface VaultAgentResult {
  availableLiquidity: number // normalized (e.g. 1500.5 USDC)
  totalAssets: number // normalized
  totalBorrows: number // normalized
  utilizationRate: number // 0-1 (WAD-normalized)
  borrowRate: number // 0-1 (WAD-normalized)
  optimalUtilization: number // 0-1 (WAD-normalized)
}

export async function fetchVaultMetrics(
  config: VaultConfig
): Promise<VaultAgentResult> {
  const results = await client.multicall({
    contracts: [
      {
        address: config.vaultAddress,
        abi: VAULT_ABI,
        functionName: "availableLiquidity"
      },
      {
        address: config.vaultAddress,
        abi: VAULT_ABI,
        functionName: "totalAssets"
      },
      {
        address: config.marketAddress,
        abi: MARKET_ABI,
        functionName: "totalBorrows"
      },
      {
        address: config.irmAddress,
        abi: IRM_ABI,
        functionName: "getUtilizationRate"
      },
      {
        address: config.irmAddress,
        abi: IRM_ABI,
        functionName: "getDynamicBorrowRate"
      },
      {
        address: config.irmAddress,
        abi: IRM_ABI,
        functionName: "optimalUtilization"
      }
    ]
  })

  const d = config.loanAssetDecimals

  return {
    // Token amounts: normalize by loan asset decimals
    availableLiquidity: normalize(
      results[0].status === "success" ? (results[0].result as bigint) : 0n,
      d
    ),
    totalAssets: normalize(
      results[1].status === "success" ? (results[1].result as bigint) : 0n,
      d
    ),
    totalBorrows: normalize(
      results[2].status === "success" ? (results[2].result as bigint) : 0n,
      d
    ),
    // IRM rates: always WAD (18 decimals)
    utilizationRate: normalize(
      results[3].status === "success" ? (results[3].result as bigint) : 0n,
      WAD
    ),
    borrowRate: normalize(
      results[4].status === "success" ? (results[4].result as bigint) : 0n,
      WAD
    ),
    optimalUtilization: normalize(
      results[5].status === "success" ? (results[5].result as bigint) : 0n,
      WAD
    )
  }
}
