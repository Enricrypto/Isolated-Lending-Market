/**
 * Market Snapshot Generator
 * -------------------------
 * Reads on-chain market state via multicall and persists a MarketSnapshot.
 */

import { client, normalize, WAD } from "../lib/rpc"
import { VAULT_ABI, MARKET_ABI, IRM_ABI, ORACLE_ROUTER_ABI } from "../lib/contracts"
import { prisma } from "../lib/db"
import {
  computeLiquiditySeverity,
  computeAPRConvexitySeverity,
  computeOracleSeverity,
  computeOverallSeverity,
} from "../lib/severity"

export interface MarketAddresses {
  marketId: string
  vaultAddress: `0x${string}`
  marketAddress: `0x${string}`
  irmAddress: `0x${string}`
  oracleRouterAddress: `0x${string}`
  loanAsset: `0x${string}`
  loanAssetDecimals: number
}

export async function computeAndSaveMarketSnapshot(market: MarketAddresses) {
  const d = market.loanAssetDecimals

  const results = await client.multicall({
    contracts: [
      { address: market.vaultAddress, abi: VAULT_ABI, functionName: "availableLiquidity" },
      { address: market.vaultAddress, abi: VAULT_ABI, functionName: "totalAssets" },
      { address: market.marketAddress, abi: MARKET_ABI, functionName: "totalBorrows" },
      { address: market.irmAddress, abi: IRM_ABI, functionName: "getUtilizationRate" },
      { address: market.irmAddress, abi: IRM_ABI, functionName: "getDynamicBorrowRate" },
      { address: market.irmAddress, abi: IRM_ABI, functionName: "optimalUtilization" },
      { address: market.marketAddress, abi: MARKET_ABI, functionName: "getLendingRate" },
      { address: market.marketAddress, abi: MARKET_ABI, functionName: "globalBorrowIndex" },
      { address: market.oracleRouterAddress, abi: ORACLE_ROUTER_ABI, functionName: "evaluate", args: [market.loanAsset] },
    ],
  })

  const availableLiquidity = normalize(results[0].status === "success" ? (results[0].result as bigint) : 0n, d)
  const totalAssets = normalize(results[1].status === "success" ? (results[1].result as bigint) : 0n, d)
  const totalBorrows = normalize(results[2].status === "success" ? (results[2].result as bigint) : 0n, d)
  const utilizationRate = normalize(results[3].status === "success" ? (results[3].result as bigint) : 0n, WAD)
  const borrowRate = normalize(results[4].status === "success" ? (results[4].result as bigint) : 0n, WAD)
  const optimalUtilization = normalize(results[5].status === "success" ? (results[5].result as bigint) : 0n, WAD)
  const lendingRate = normalize(results[6].status === "success" ? (results[6].result as bigint) : 0n, WAD)
  const globalBorrowIndex = results[7].status === "success" ? normalize(results[7].result as bigint, WAD) : null

  let oraclePrice = 0
  // When oracle call fails, use neutral defaults so a missing/unconfigured
  // feed doesn't trigger Emergency severity (confidence=0 or riskScore=100
  // would falsely alarm for markets like mock-USDC with no Chainlink feed).
  let oracleConfidence = 100
  let oracleIsStale = false
  let oracleRiskScore = 0
  let oracleCallSucceeded = false

  if (results[8].status === "success") {
    oracleCallSucceeded = true
    const oracleEval = results[8].result as {
      resolvedPrice: bigint
      confidence: bigint
      sourceUsed: number
      oracleRiskScore: number
      isStale: boolean
      deviation: bigint
    }
    oraclePrice = normalize(oracleEval.resolvedPrice, WAD)
    oracleConfidence = Math.round(normalize(oracleEval.confidence, WAD) * 100)
    oracleIsStale = oracleEval.isStale
    oracleRiskScore = oracleEval.oracleRiskScore
  }

  const depthRatio = totalBorrows === 0 ? 10.0 : Math.min(availableLiquidity / totalBorrows, 10.0)
  const distanceToKink = optimalUtilization - utilizationRate

  const liquiditySeverity = computeLiquiditySeverity(depthRatio)
  const aprConvexitySeverity = computeAPRConvexitySeverity(utilizationRate, optimalUtilization)
  // Only compute oracle severity from real data; if the call failed (no feed
  // configured for this token), default to 0 so it doesn't show as Emergency.
  const oracleSeverity = oracleCallSucceeded
    ? computeOracleSeverity(oracleConfidence, oracleIsStale, oracleRiskScore)
    : 0
  const overallSeverity = computeOverallSeverity(liquiditySeverity, aprConvexitySeverity, oracleSeverity, null)

  return prisma.marketSnapshot.create({
    data: {
      marketId: market.marketId,
      totalSupply: totalAssets.toFixed(6),
      totalBorrows: totalBorrows.toFixed(6),
      availableLiquidity: availableLiquidity.toFixed(6),
      utilizationRate: utilizationRate.toFixed(6),
      borrowRate: borrowRate.toFixed(6),
      lendingRate: lendingRate.toFixed(6),
      optimalUtilization: optimalUtilization.toFixed(6),
      liquidityDepthRatio: depthRatio.toFixed(6),
      distanceToKink: distanceToKink.toFixed(6),
      oraclePrice: oraclePrice.toFixed(6),
      oracleConfidence,
      oracleRiskScore,
      oracleIsStale,
      globalBorrowIndex: globalBorrowIndex !== null ? globalBorrowIndex.toFixed(18) : null,
      liquiditySeverity,
      aprConvexitySeverity,
      oracleSeverity,
      overallSeverity,
    },
  })
}
