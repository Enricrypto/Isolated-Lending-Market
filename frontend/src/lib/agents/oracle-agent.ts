/**
 * Oracle Agent
 * ------------
 * This file is responsible for **reading oracle-related data from the blockchain**
 * via the OracleRouter and returning **normalized, UI-agnostic metrics**.
 *
 * Role in the system:
 * - Acts as a pure on-chain data ingestion layer
 * - Talks directly to RPC / contracts (no DB, no API, no UI concerns)
 * - Returns clean, normalized numerical values suitable for downstream analytics
 *
 * What this agent DOES:
 * - Calls OracleRouter.evaluate() for a given loan asset
 * - Normalizes WAD-based values into human-readable numbers
 * - Exposes oracle health signals (price, confidence, risk score, staleness, deviation)
 *
 * What this agent does NOT do:
 * - Does NOT compute severity levels
 * - Does NOT store anything in the database
 * - Does NOT apply protocol-specific risk logic
 * - Does NOT know about UI, monitoring pages, or alerts
 *
 * Downstream consumers:
 * - pollAndStore() aggregates this data with vault & strategy agents
 * - Severity logic derives risk classifications
 * - Snapshots are persisted and later read by API routes and the Monitoring UI
 *
 * IMPORTANT:
 * All values returned here are normalized and deterministic.
 * This file is part of the protocol's single source of truth for oracle observations.
 */

import { client, normalize, WAD } from "../rpc"
import { ORACLE_ROUTER_ABI } from "../contracts"
import type { VaultConfig } from "@/types/metrics"

export interface OracleAgentResult {
  price: number // normalized (e.g. 1.0002 for USDC)
  confidence: number // 0-100 percentage
  riskScore: number // 0-100
  isStale: boolean
  deviation: number // normalized 0-1 (WAD)
}

export async function fetchOracleMetrics(
  config: VaultConfig
): Promise<OracleAgentResult> {
  const results = await client.multicall({
    contracts: [
      {
        address: config.oracleRouterAddress,
        abi: ORACLE_ROUTER_ABI,
        functionName: "evaluate",
        args: [config.loanAsset]
      }
    ]
  })

  if (results[0].status === "success") {
    const oracleEval = results[0].result as {
      resolvedPrice: bigint
      confidence: bigint
      sourceUsed: number
      oracleRiskScore: number
      isStale: boolean
      deviation: bigint
    }

    return {
      // Price is WAD (18 decimals) → normalized to human-readable (e.g. 1.0002)
      price: normalize(oracleEval.resolvedPrice, WAD),
      // Confidence is WAD (0-1e18) → convert to 0-100 percentage
      confidence: Math.round(normalize(oracleEval.confidence, WAD) * 100),
      riskScore: oracleEval.oracleRiskScore,
      isStale: oracleEval.isStale,
      // Deviation is WAD → normalize to 0-1
      deviation: normalize(oracleEval.deviation, WAD)
    }
  }

  return {
    price: 0,
    confidence: 0,
    riskScore: 100,
    isStale: true,
    deviation: 0
  }
}
