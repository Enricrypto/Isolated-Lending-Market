import { client, toNumber } from "../rpc";
import { VAULT_ABI, MARKET_ABI, IRM_ABI } from "../contracts";
import type { VaultConfig } from "@/types/metrics";

export interface VaultAgentResult {
  availableLiquidity: bigint;
  totalAssets: bigint;
  totalBorrows: bigint;
  utilizationRate: number;
  borrowRate: number;
  optimalUtilization: number;
}

export async function fetchVaultMetrics(config: VaultConfig): Promise<VaultAgentResult> {
  const results = await client.multicall({
    contracts: [
      { address: config.vaultAddress, abi: VAULT_ABI, functionName: "availableLiquidity" },
      { address: config.vaultAddress, abi: VAULT_ABI, functionName: "totalAssets" },
      { address: config.marketAddress, abi: MARKET_ABI, functionName: "totalBorrows" },
      { address: config.irmAddress, abi: IRM_ABI, functionName: "getUtilizationRate" },
      { address: config.irmAddress, abi: IRM_ABI, functionName: "getDynamicBorrowRate" },
      { address: config.irmAddress, abi: IRM_ABI, functionName: "optimalUtilization" },
    ],
  });

  return {
    availableLiquidity: results[0].status === "success" ? (results[0].result as bigint) : 0n,
    totalAssets: results[1].status === "success" ? (results[1].result as bigint) : 0n,
    totalBorrows: results[2].status === "success" ? (results[2].result as bigint) : 0n,
    utilizationRate: toNumber(results[3].status === "success" ? (results[3].result as bigint) : 0n),
    borrowRate: toNumber(results[4].status === "success" ? (results[4].result as bigint) : 0n),
    optimalUtilization: toNumber(results[5].status === "success" ? (results[5].result as bigint) : 0n),
  };
}
