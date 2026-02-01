import { client } from "../rpc";
import { ORACLE_ROUTER_ABI } from "../contracts";
import type { VaultConfig } from "@/types/metrics";

export interface OracleAgentResult {
  price: bigint;
  confidence: number;
  riskScore: number;
  isStale: boolean;
  deviation: bigint;
}

export async function fetchOracleMetrics(config: VaultConfig): Promise<OracleAgentResult> {
  const results = await client.multicall({
    contracts: [
      {
        address: config.oracleRouterAddress,
        abi: ORACLE_ROUTER_ABI,
        functionName: "evaluate",
        args: [config.loanAsset],
      },
    ],
  });

  if (results[0].status === "success") {
    const oracleEval = results[0].result as {
      resolvedPrice: bigint;
      confidence: bigint;
      sourceUsed: number;
      oracleRiskScore: number;
      isStale: boolean;
      deviation: bigint;
    };

    return {
      price: oracleEval.resolvedPrice,
      confidence: Number(oracleEval.confidence * 100n / BigInt(1e18)),
      riskScore: oracleEval.oracleRiskScore,
      isStale: oracleEval.isStale,
      deviation: oracleEval.deviation,
    };
  }

  return { price: 0n, confidence: 0, riskScore: 100, isStale: true, deviation: 0n };
}
