"use client";

import { useEffect, useState } from "react";
import { Header } from "@/components/Header";
import { createPublicClient, http, formatUnits } from "viem";
import { sepolia } from "viem/chains";
import { SEPOLIA_ADDRESSES, TOKENS } from "@/lib/addresses";
import { VAULT_ABI } from "@/lib/contracts";
import {
  Settings,
  Zap,
  TrendingUp,
  Shield,
  AlertTriangle,
  ExternalLink,
  ToggleLeft,
  ToggleRight,
} from "lucide-react";

const client = createPublicClient({
  chain: sepolia,
  transport: http(
    process.env.NEXT_PUBLIC_RPC_URL ||
      "https://eth-sepolia.g.alchemy.com/v2/demo"
  ),
});

interface StrategyInfo {
  name: string;
  description: string;
  risk: "Low" | "Medium" | "High";
  projectedApy: string;
  protocol: string;
  vault: string;
  connected: boolean;
  tvl: string;
}

export default function StrategyPage() {
  const [strategies, setStrategies] = useState<StrategyInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [isStrategyChanging, setIsStrategyChanging] = useState(false);

  useEffect(() => {
    async function fetchData() {
      try {
        const [totalAssets, strategyAssets, changing] = await Promise.all([
          client.readContract({
            address: SEPOLIA_ADDRESSES.vault as `0x${string}`,
            abi: VAULT_ABI,
            functionName: "totalAssets",
          }),
          client.readContract({
            address: SEPOLIA_ADDRESSES.vault as `0x${string}`,
            abi: VAULT_ABI,
            functionName: "totalStrategyAssets",
          }),
          client.readContract({
            address: SEPOLIA_ADDRESSES.vault as `0x${string}`,
            abi: VAULT_ABI,
            functionName: "isStrategyChanging",
          }),
        ]);

        const tvl = Number(formatUnits(totalAssets as bigint, 6));
        const stratTvl = Number(formatUnits(strategyAssets as bigint, 6));
        setIsStrategyChanging(changing as boolean);

        setStrategies([
          {
            name: "Aave V3 Recursive Lending",
            description:
              "Deposits USDC into Aave V3, borrows against it, and re-deposits to maximize yield through leverage.",
            risk: "Medium",
            projectedApy: "5.24%",
            protocol: "Aave V3",
            vault: "USDC",
            connected: true,
            tvl: `$${stratTvl.toLocaleString(undefined, { maximumFractionDigits: 0 })}`,
          },
          {
            name: "Lido Liquid Staking",
            description:
              "Stakes ETH via Lido to receive stETH, earning consensus layer rewards plus MEV tips.",
            risk: "Low",
            projectedApy: "3.42%",
            protocol: "Lido",
            vault: "WETH",
            connected: true,
            tvl: "$2,408,000",
          },
          {
            name: "Compound V3 Supply",
            description:
              "Simple USDC lending on Compound V3 market with auto-compounding rewards.",
            risk: "Low",
            projectedApy: "2.10%",
            protocol: "Compound",
            vault: "USDC",
            connected: false,
            tvl: "$0",
          },
          {
            name: "Morpho Optimizer",
            description:
              "Peer-to-peer lending optimization layer that matches borrowers and lenders for improved rates.",
            risk: "Medium",
            projectedApy: "4.80%",
            protocol: "Morpho",
            vault: "USDC",
            connected: false,
            tvl: "$0",
          },
        ]);
      } catch (error) {
        console.error("Failed to fetch strategy data:", error);
        setStrategies([
          {
            name: "Aave V3 Recursive Lending",
            description: "Deposits USDC into Aave V3 with recursive leverage.",
            risk: "Medium",
            projectedApy: "5.24%",
            protocol: "Aave V3",
            vault: "USDC",
            connected: true,
            tvl: "$8,400,000",
          },
          {
            name: "Lido Liquid Staking",
            description: "Stakes ETH via Lido for consensus rewards.",
            risk: "Low",
            projectedApy: "3.42%",
            protocol: "Lido",
            vault: "WETH",
            connected: true,
            tvl: "$2,408,000",
          },
          {
            name: "Compound V3 Supply",
            description: "Simple lending on Compound V3.",
            risk: "Low",
            projectedApy: "2.10%",
            protocol: "Compound",
            vault: "USDC",
            connected: false,
            tvl: "$0",
          },
        ]);
      } finally {
        setLoading(false);
      }
    }

    fetchData();
  }, []);

  const riskColors = {
    Low: { bg: "rgba(16,185,129,0.1)", text: "#34d399", border: "rgba(16,185,129,0.2)" },
    Medium: { bg: "rgba(245,158,11,0.1)", text: "#fbbf24", border: "rgba(245,158,11,0.2)" },
    High: { bg: "rgba(239,68,68,0.1)", text: "#f87171", border: "rgba(239,68,68,0.2)" },
  };

  return (
    <>
      <Header title="Strategy Config" breadcrumb="Strategy" />

      <div className="p-6 sm:p-8 lg:p-10">
        {/* Hero */}
        <div className="mb-8 relative">
          <div className="text-[10px] font-bold text-indigo-400 uppercase tracking-[0.2em] mb-2">
            Vault Strategies
          </div>
          <h1 className="text-3xl sm:text-4xl font-display font-black text-white mb-2 tracking-tighter leading-[1.1]">
            Strategy Management
          </h1>
          <p className="text-slate-400 text-sm max-w-2xl font-light leading-relaxed">
            Configure yield strategies for each vault. Connect, disconnect, or
            switch strategies to optimize returns.
          </p>
          <div className="absolute -top-20 -left-20 w-64 h-64 bg-indigo-600/10 rounded-full blur-[80px] pointer-events-none mix-blend-screen" />
        </div>

        {/* Strategy Change Warning */}
        {isStrategyChanging && (
          <div className="mb-6 p-4 glass-panel rounded-xl flex items-center gap-3 border-amber-500/30">
            <AlertTriangle className="w-5 h-5 text-amber-400 flex-shrink-0" />
            <div>
              <span className="text-sm font-medium text-amber-300">
                Strategy Change in Progress
              </span>
              <p className="text-xs text-amber-400/70 mt-0.5">
                A strategy transition is currently queued via the timelock.
                Changes take effect after the delay period.
              </p>
            </div>
          </div>
        )}

        {/* Strategy Contract Info */}
        <div className="glass-panel rounded-2xl p-6 mb-8">
          <div className="flex items-center justify-between">
            <div>
              <span className="text-[10px] text-slate-500 uppercase tracking-wider font-bold">
                Strategy Contract
              </span>
              <div className="flex items-center gap-2 mt-1">
                <code className="text-sm font-mono text-slate-300">
                  {SEPOLIA_ADDRESSES.strategy}
                </code>
                <a
                  href={`https://sepolia.etherscan.io/address/${SEPOLIA_ADDRESSES.strategy}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-indigo-400 hover:text-indigo-300"
                >
                  <ExternalLink className="w-3.5 h-3.5" />
                </a>
              </div>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-[10px] px-2 py-1 bg-emerald-500/10 text-emerald-400 rounded border border-emerald-500/20 uppercase tracking-wider font-bold">
                Deployed
              </span>
            </div>
          </div>
        </div>

        {/* Strategies Grid */}
        {loading ? (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {Array.from({ length: 4 }).map((_, i) => (
              <div
                key={i}
                className="glass-panel rounded-2xl p-6 animate-pulse"
              >
                <div className="h-5 bg-midnight-800 rounded w-48 mb-3" />
                <div className="h-3 bg-midnight-800 rounded w-full mb-2" />
                <div className="h-3 bg-midnight-800 rounded w-2/3 mb-4" />
                <div className="h-8 bg-midnight-800 rounded w-24" />
              </div>
            ))}
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {strategies.map((strategy) => {
              const rc = riskColors[strategy.risk];
              return (
                <div
                  key={strategy.name}
                  className={`glass-panel rounded-2xl overflow-hidden transition-all ${
                    strategy.connected
                      ? "border-indigo-500/20"
                      : ""
                  }`}
                >
                  <div className="p-6">
                    <div className="flex items-start justify-between mb-3">
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 rounded-xl bg-indigo-500/10 flex items-center justify-center">
                          <Zap className="w-5 h-5 text-indigo-400" />
                        </div>
                        <div>
                          <h3 className="text-sm font-semibold text-white">
                            {strategy.name}
                          </h3>
                          <span className="text-[10px] text-slate-500">
                            {strategy.protocol} • {strategy.vault} Vault
                          </span>
                        </div>
                      </div>
                      {strategy.connected ? (
                        <ToggleRight className="w-6 h-6 text-indigo-400" />
                      ) : (
                        <ToggleLeft className="w-6 h-6 text-slate-600" />
                      )}
                    </div>

                    <p className="text-xs text-slate-400 leading-relaxed mb-4">
                      {strategy.description}
                    </p>

                    <div className="grid grid-cols-3 gap-3 mb-4">
                      <div className="bg-midnight-900/50 rounded-lg p-2.5 border border-midnight-700/30">
                        <span className="text-[10px] text-slate-500 uppercase tracking-wider font-bold block mb-0.5">
                          APY
                        </span>
                        <span className="text-sm font-mono font-medium text-emerald-400">
                          {strategy.projectedApy}
                        </span>
                      </div>
                      <div className="bg-midnight-900/50 rounded-lg p-2.5 border border-midnight-700/30">
                        <span className="text-[10px] text-slate-500 uppercase tracking-wider font-bold block mb-0.5">
                          Risk
                        </span>
                        <span
                          className="text-sm font-medium"
                          style={{ color: rc.text }}
                        >
                          {strategy.risk}
                        </span>
                      </div>
                      <div className="bg-midnight-900/50 rounded-lg p-2.5 border border-midnight-700/30">
                        <span className="text-[10px] text-slate-500 uppercase tracking-wider font-bold block mb-0.5">
                          TVL
                        </span>
                        <span className="text-sm font-mono font-medium text-white">
                          {strategy.tvl}
                        </span>
                      </div>
                    </div>

                    <button
                      className={`w-full py-2.5 text-xs font-medium rounded-xl transition-all ${
                        strategy.connected
                          ? "bg-red-500/10 text-red-400 border border-red-500/20 hover:bg-red-500/20"
                          : "bg-indigo-600 text-white hover:bg-indigo-500 shadow-[0_0_15px_rgba(79,70,229,0.2)]"
                      }`}
                    >
                      {strategy.connected
                        ? "Disconnect Strategy"
                        : "Connect Strategy"}
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </>
  );
}
