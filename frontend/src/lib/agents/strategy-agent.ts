import { client } from "../rpc";
import { VAULT_ABI } from "../contracts";
import type { VaultConfig } from "@/types/metrics";

export interface StrategyAgentResult {
  strategyTotalAssets: bigint;
  strategyAllocPct: number;
  isStrategyChanging: boolean;
}

export async function fetchStrategyMetrics(config: VaultConfig): Promise<StrategyAgentResult> {
  const results = await client.multicall({
    contracts: [
      { address: config.vaultAddress, abi: VAULT_ABI, functionName: "totalStrategyAssets" },
      { address: config.vaultAddress, abi: VAULT_ABI, functionName: "totalAssets" },
      { address: config.vaultAddress, abi: VAULT_ABI, functionName: "isStrategyChanging" },
    ],
  });

  const strategyAssets = results[0].status === "success" ? (results[0].result as bigint) : 0n;
  const totalAssets = results[1].status === "success" ? (results[1].result as bigint) : 0n;
  const isChanging = results[2].status === "success" ? (results[2].result as boolean) : false;

  const allocPct = totalAssets > 0n ? Number(strategyAssets) / Number(totalAssets) : 0;

  return {
    strategyTotalAssets: strategyAssets,
    strategyAllocPct: allocPct,
    isStrategyChanging: isChanging,
  };
}
