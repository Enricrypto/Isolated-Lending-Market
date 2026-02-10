"use client";

import { useEffect, useState } from "react";
import { createPublicClient, http, formatUnits } from "viem";
import { sepolia } from "viem/chains";
import { SEPOLIA_ADDRESSES, TOKENS } from "@/lib/addresses";
import { VAULT_ABI, IRM_ABI, ORACLE_ROUTER_ABI } from "@/lib/contracts";
import { useAppStore } from "@/store/useAppStore";
import { ArrowRight, TrendingUp, Shield } from "lucide-react";
import { TokenIcon } from "@/components/TokenIcon";

const client = createPublicClient({
  chain: sepolia,
  transport: http(process.env.NEXT_PUBLIC_RPC_URL || "https://eth-sepolia.g.alchemy.com/v2/demo"),
});

interface VaultData {
  id: "usdc" | "weth" | "wbtc";
  asset: string;
  symbol: string;
  icon: string;
  color: string;
  tvl: string;
  tvlUsd: string;
  apy: string;
  healthFactor: string;
  healthStatus: "low-risk" | "stable" | "idle" | "loading";
  utilization: number;
}

export function VaultTable() {
  const [vaults, setVaults] = useState<VaultData[]>([]);
  const [loading, setLoading] = useState(true);
  const { selectedVault, setSelectedVault } = useAppStore();
  const { refreshKey } = useAppStore();

  useEffect(() => {
    async function fetchVaultData() {
      try {
        // Fetch vault TVL
        const [totalAssets, utilRate, usdcPrice, wethPrice, wbtcPrice] =
          await Promise.all([
            client.readContract({
              address: SEPOLIA_ADDRESSES.vault as `0x${string}`,
              abi: VAULT_ABI,
              functionName: "totalAssets",
            }),
            client.readContract({
              address: SEPOLIA_ADDRESSES.irm as `0x${string}`,
              abi: IRM_ABI,
              functionName: "getUtilizationRate",
            }),
            client
              .readContract({
                address: SEPOLIA_ADDRESSES.oracleRouter as `0x${string}`,
                abi: ORACLE_ROUTER_ABI,
                functionName: "getLatestPrice",
                args: [SEPOLIA_ADDRESSES.usdc as `0x${string}`],
              })
              .catch(() => BigInt(1e18)),
            client
              .readContract({
                address: SEPOLIA_ADDRESSES.oracleRouter as `0x${string}`,
                abi: ORACLE_ROUTER_ABI,
                functionName: "getLatestPrice",
                args: [SEPOLIA_ADDRESSES.weth as `0x${string}`],
              })
              .catch(() => BigInt(2000n * BigInt(1e18))),
            client
              .readContract({
                address: SEPOLIA_ADDRESSES.oracleRouter as `0x${string}`,
                abi: ORACLE_ROUTER_ABI,
                functionName: "getLatestPrice",
                args: [SEPOLIA_ADDRESSES.wbtc as `0x${string}`],
              })
              .catch(() => BigInt(40000n * BigInt(1e18))),
          ]);

        const totalAssetsNum = Number(formatUnits(totalAssets as bigint, 6));
        const utilization = Number(formatUnits(utilRate as bigint, 18));
        const usdcPriceNum = Number(formatUnits(usdcPrice as bigint, 18));
        const wethPriceNum = Number(formatUnits(wethPrice as bigint, 18));
        const wbtcPriceNum = Number(formatUnits(wbtcPrice as bigint, 18));

        // Simulated APY based on utilization
        const baseApy = utilization * 8;

        const vaultData: VaultData[] = [
          {
            id: "usdc",
            asset: TOKENS.USDC.name,
            symbol: TOKENS.USDC.symbol,
            icon: TOKENS.USDC.icon,
            color: TOKENS.USDC.color,
            tvl: `${totalAssetsNum.toLocaleString(undefined, { maximumFractionDigits: 0 })}`,
            tvlUsd: `$${(totalAssetsNum * usdcPriceNum).toLocaleString(undefined, { maximumFractionDigits: 0 })}`,
            apy: `${baseApy.toFixed(2)}%`,
            healthFactor: "1.82",
            healthStatus: "low-risk",
            utilization,
          },
          {
            id: "weth",
            asset: TOKENS.WETH.name,
            symbol: TOKENS.WETH.symbol,
            icon: TOKENS.WETH.icon,
            color: TOKENS.WETH.color,
            tvl: "1,204",
            tvlUsd: `$${(1204 * wethPriceNum).toLocaleString(undefined, { maximumFractionDigits: 0 })}`,
            apy: "3.42%",
            healthFactor: "--",
            healthStatus: "stable",
            utilization: 0,
          },
          {
            id: "wbtc",
            asset: TOKENS.WBTC.name,
            symbol: TOKENS.WBTC.symbol,
            icon: TOKENS.WBTC.icon,
            color: TOKENS.WBTC.color,
            tvl: "12.5",
            tvlUsd: `$${(12.5 * wbtcPriceNum).toLocaleString(undefined, { maximumFractionDigits: 0 })}`,
            apy: "0.00%",
            healthFactor: "--",
            healthStatus: "idle",
            utilization: 0,
          },
        ];

        setVaults(vaultData);
      } catch (error) {
        console.error("Failed to fetch vault data:", error);
        // Set mock data on error
        setVaults([
          {
            id: "usdc",
            asset: "USD Coin",
            symbol: "USDC",
            icon: "$",
            color: "#2775CA",
            tvl: "8,400,000",
            tvlUsd: "$8,400,000",
            apy: "5.24%",
            healthFactor: "1.82",
            healthStatus: "low-risk",
            utilization: 0.65,
          },
          {
            id: "weth",
            asset: "Wrapped Ether",
            symbol: "WETH",
            icon: "Ξ",
            color: "#627EEA",
            tvl: "1,204",
            tvlUsd: "$2,408,000",
            apy: "3.42%",
            healthFactor: "--",
            healthStatus: "stable",
            utilization: 0,
          },
          {
            id: "wbtc",
            asset: "Wrapped Bitcoin",
            symbol: "WBTC",
            icon: "₿",
            color: "#F7931A",
            tvl: "12.5",
            tvlUsd: "$500,000",
            apy: "0.00%",
            healthFactor: "--",
            healthStatus: "idle",
            utilization: 0,
          },
        ]);
      } finally {
        setLoading(false);
      }
    }

    fetchVaultData();
  }, [refreshKey]);

  if (loading) {
    return (
      <div className="glass-panel rounded-2xl overflow-hidden shadow-2xl">
        <div className="px-8 py-6 border-b border-midnight-700/50 bg-white/5">
          <h3 className="text-lg font-semibold text-white">Market Overview</h3>
        </div>
        <div className="p-12 flex items-center justify-center">
          <div className="flex items-center gap-3 text-slate-400">
            <div className="w-5 h-5 border-2 border-indigo-500/50 border-t-indigo-400 rounded-full animate-spin" />
            <span className="text-sm">Loading vault data...</span>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="glass-panel rounded-2xl overflow-hidden shadow-2xl">
      <div className="px-8 py-6 border-b border-midnight-700/50 flex items-center justify-between bg-white/5">
        <div>
          <h3 className="text-lg font-semibold tracking-wide text-white">
            Market Overview
          </h3>
          <p className="text-xs text-slate-500 mt-1">
            {vaults.length} active markets on Sepolia
          </p>
        </div>
        <button className="text-xs font-semibold text-indigo-400 hover:text-indigo-300 flex items-center gap-1.5 uppercase tracking-wider transition-colors">
          View All <ArrowRight className="w-3.5 h-3.5" />
        </button>
      </div>

      <div className="overflow-x-auto">
        <table className="w-full text-left text-sm">
          <thead>
            <tr className="border-b border-midnight-700/50 text-[10px] font-bold text-slate-500 uppercase tracking-[0.1em]">
              <th className="px-8 py-5">Asset</th>
              <th className="px-6 py-5">TVL</th>
              <th className="px-6 py-5">Net APY (Sim)</th>
              <th className="px-6 py-5">Health Factor</th>
              <th className="px-6 py-5 text-right">Quick Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-midnight-700/50">
            {vaults.map((vault) => (
              <tr
                key={vault.id}
                onClick={() => setSelectedVault(vault.id)}
                className={`group cursor-pointer transition-all ${
                  selectedVault === vault.id
                    ? "bg-indigo-500/5 border-l-2 border-l-indigo-500"
                    : "hover:bg-white/5"
                }`}
              >
                <td className="px-8 py-5">
                  <div className="flex items-center gap-4">
                    <div
                      className="w-10 h-10 rounded-xl flex items-center justify-center shadow-lg border border-white/10"
                      style={{ backgroundColor: `${vault.color}15` }}
                    >
                      <TokenIcon symbol={vault.symbol} size={22} />
                    </div>
                    <div>
                      <span className="font-medium text-white text-base block">
                        {vault.symbol}
                      </span>
                      <span className="text-xs text-slate-500">
                        {vault.asset}
                      </span>
                    </div>
                  </div>
                </td>
                <td className="px-6 py-5">
                  <div>
                    <span className="text-white font-mono font-medium">
                      {vault.tvlUsd}
                    </span>
                    <span className="block text-xs text-slate-500 font-mono">
                      {vault.tvl} {vault.symbol}
                    </span>
                  </div>
                </td>
                <td className="px-6 py-5">
                  <div className="flex items-center gap-2">
                    {parseFloat(vault.apy) > 0 ? (
                      <>
                        <TrendingUp className="w-3.5 h-3.5 text-emerald-400" />
                        <span className="text-emerald-400 font-mono font-medium">
                          {vault.apy}
                        </span>
                      </>
                    ) : (
                      <span className="text-slate-500 font-mono">
                        {vault.apy}
                      </span>
                    )}
                  </div>
                </td>
                <td className="px-6 py-5">
                  <HealthBadge
                    factor={vault.healthFactor}
                    status={vault.healthStatus}
                  />
                </td>
                <td className="px-6 py-5 text-right">
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      setSelectedVault(vault.id);
                    }}
                    className="px-4 py-1.5 text-xs font-medium rounded-lg transition-all bg-midnight-800 text-slate-300 border border-midnight-700/50 hover:bg-midnight-700 hover:text-white"
                  >
                    Manage
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function HealthBadge({
  factor,
  status,
}: {
  factor: string;
  status: "low-risk" | "stable" | "idle" | "loading";
}) {
  const config = {
    "low-risk": {
      label: "Low Risk",
      bgColor: "rgba(16,185,129,0.1)",
      textColor: "#34d399",
      borderColor: "rgba(16,185,129,0.2)",
      icon: Shield,
    },
    stable: {
      label: "Stable",
      bgColor: "rgba(59,130,246,0.1)",
      textColor: "#60a5fa",
      borderColor: "rgba(59,130,246,0.2)",
      icon: Shield,
    },
    idle: {
      label: "Idle",
      bgColor: "rgba(100,116,139,0.1)",
      textColor: "#94a3b8",
      borderColor: "rgba(100,116,139,0.2)",
      icon: Shield,
    },
    loading: {
      label: "...",
      bgColor: "rgba(100,116,139,0.1)",
      textColor: "#94a3b8",
      borderColor: "rgba(100,116,139,0.2)",
      icon: Shield,
    },
  };

  const c = config[status];
  const Icon = c.icon;

  return (
    <span className="inline-flex items-center gap-1.5 whitespace-nowrap">
      {factor !== "--" && (
        <span className="font-mono font-medium text-white text-sm">{factor}</span>
      )}
      <span
        className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold"
        style={{
          backgroundColor: c.bgColor,
          color: c.textColor,
          borderWidth: 1,
          borderColor: c.borderColor,
        }}
      >
        <Icon className="w-2.5 h-2.5" />
        {c.label}
      </span>
    </span>
  );
}
