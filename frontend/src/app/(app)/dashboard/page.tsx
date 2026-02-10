"use client";

import { useEffect, useState } from "react";
import { Header } from "@/components/Header";
import { VaultTable } from "@/components/VaultTable";
import { DepositForm } from "@/components/DepositForm";
import { useAppStore } from "@/store/useAppStore";
import { TOKENS } from "@/lib/addresses";
import { VAULT_ABI, IRM_ABI } from "@/lib/contracts";
import { SEPOLIA_ADDRESSES } from "@/lib/addresses";
import { createPublicClient, http, formatUnits } from "viem";
import { sepolia } from "viem/chains";
import {
  DollarSign,
  Activity,
  TrendingUp,
  X,
} from "lucide-react";
import { TokenIcon } from "@/components/TokenIcon";

const client = createPublicClient({
  chain: sepolia,
  transport: http(
    process.env.NEXT_PUBLIC_RPC_URL ||
      "https://eth-sepolia.g.alchemy.com/v2/demo"
  ),
});

interface MetricCardData {
  label: string;
  value: string;
  change?: string;
  changePositive?: boolean;
  icon: React.ReactNode;
  color: string;
  subLabel?: string;
}

export default function VaultDashboard() {
  const { selectedVault, setSelectedVault } =
    useAppStore();
  const [metrics, setMetrics] = useState<MetricCardData[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function fetchMetrics() {
      try {
        const [totalAssets, utilRate] = await Promise.all([
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
        ]);

        const tvl = Number(formatUnits(totalAssets as bigint, 6));
        const util = Number(formatUnits(utilRate as bigint, 18));
        const simulatedYield = util * 8 * 0.08;

        setMetrics([
          {
            label: "Total Value Locked",
            value: `$${tvl.toLocaleString(undefined, { maximumFractionDigits: 0 })}`,
            change: "+4.2%",
            changePositive: true,
            icon: <DollarSign className="w-4 h-4" />,
            color: "#6366f1",
            subLabel: "Across all markets",
          },
          {
            label: "Avg. Utilization Rate",
            value: `${(util * 100).toFixed(1)}%`,
            change: util > 0.8 ? "High" : util > 0.5 ? "Moderate" : "Low",
            changePositive: util <= 0.8,
            icon: <Activity className="w-4 h-4" />,
            color: "#f59e0b",
            subLabel: "IRM Curve Position",
          },
          {
            label: "Simulated Yield (30d)",
            value: `${simulatedYield.toFixed(2)}%`,
            change: "+0.3%",
            changePositive: true,
            icon: <TrendingUp className="w-4 h-4" />,
            color: "#10b981",
            subLabel: "Projected returns",
          },
        ]);
      } catch (error) {
        console.error("Failed to fetch dashboard metrics:", error);
        setMetrics([
          {
            label: "Total Value Locked",
            value: "$8,400,000",
            change: "+4.2%",
            changePositive: true,
            icon: <DollarSign className="w-4 h-4" />,
            color: "#6366f1",
            subLabel: "Across all markets",
          },
          {
            label: "Avg. Utilization Rate",
            value: "65.2%",
            change: "Moderate",
            changePositive: true,
            icon: <Activity className="w-4 h-4" />,
            color: "#f59e0b",
            subLabel: "IRM Curve Position",
          },
          {
            label: "Simulated Yield (30d)",
            value: "5.24%",
            change: "+0.3%",
            changePositive: true,
            icon: <TrendingUp className="w-4 h-4" />,
            color: "#10b981",
            subLabel: "Projected returns",
          },
        ]);
      } finally {
        setLoading(false);
      }
    }

    fetchMetrics();
  }, []);

  const selectedToken = selectedVault
    ? TOKENS[selectedVault.toUpperCase() as keyof typeof TOKENS]
    : null;

  return (
    <>
      <Header title="Market Dashboard" breadcrumb="Dashboard" />

      <div className="flex flex-col xl:flex-row w-full">
        {/* Main Content */}
        <div className="flex-1 p-6 sm:p-8 lg:p-10">
          {/* Hero Section */}
          <div className="mb-8 relative">
            <div className="text-[10px] font-bold text-indigo-400 uppercase tracking-[0.2em] mb-2">
              Protocol Overview
            </div>
            <h1 className="text-3xl sm:text-4xl font-display font-black text-white mb-2 tracking-tighter leading-[1.1]">
              Dashboard Overview
            </h1>
            <p className="text-slate-400 text-sm max-w-2xl font-light leading-relaxed">
              Monitor aggregate risk and interact with protocol positions on
              Sepolia testnet.
            </p>
            <div className="absolute -top-20 -left-20 w-64 h-64 bg-indigo-600/10 rounded-full blur-[80px] pointer-events-none mix-blend-screen" />
          </div>

          {/* Metrics Cards */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-5 mb-8">
            {loading
              ? Array.from({ length: 3 }).map((_, i) => (
                  <div
                    key={i}
                    className="glass-panel rounded-xl p-6 animate-pulse"
                  >
                    <div className="h-4 bg-midnight-800 rounded w-24 mb-3" />
                    <div className="h-8 bg-midnight-800 rounded w-32 mb-2" />
                    <div className="h-3 bg-midnight-800 rounded w-16" />
                  </div>
                ))
              : metrics.map((metric, i) => (
                  <div
                    key={i}
                    className="glass-panel rounded-xl p-6 group hover:border-indigo-500/20 transition-all"
                  >
                    <div className="flex items-center justify-between mb-4">
                      <span className="text-xs font-medium text-slate-500 uppercase tracking-wider">
                        {metric.label}
                      </span>
                      <div
                        className="w-8 h-8 rounded-lg flex items-center justify-center"
                        style={{
                          backgroundColor: `${metric.color}15`,
                          color: metric.color,
                        }}
                      >
                        {metric.icon}
                      </div>
                    </div>
                    <div className="flex items-end gap-3">
                      <span className="text-2xl font-display font-bold text-white">
                        {metric.value}
                      </span>
                      {metric.change && (
                        <span
                          className={`text-xs font-medium mb-1 ${
                            metric.changePositive
                              ? "text-emerald-400"
                              : "text-red-400"
                          }`}
                        >
                          {metric.change}
                        </span>
                      )}
                    </div>
                    {metric.subLabel && (
                      <span className="text-[10px] text-slate-600 mt-1 block">
                        {metric.subLabel}
                      </span>
                    )}
                  </div>
                ))}
          </div>

          {/* Vault Table */}
          <VaultTable />
        </div>

        {/* Right Sidebar Panel */}
        {selectedVault && selectedToken && (
          <aside className="w-full xl:w-[380px] border-l border-midnight-700/50 bg-midnight-950/40 backdrop-blur-md flex flex-col shrink-0">
            {/* Vault Header */}
            <div className="p-6 border-b border-midnight-700/50">
              <div className="flex items-center justify-between mb-4">
                <div className="flex items-center gap-3">
                  <div
                    className="w-10 h-10 rounded-xl flex items-center justify-center border border-white/10"
                    style={{ backgroundColor: `${selectedToken.color}15` }}
                  >
                    <TokenIcon symbol={selectedToken.symbol} size={22} />
                  </div>
                  <div>
                    <h3 className="text-base font-semibold text-white">
                      {selectedToken.symbol} Market
                    </h3>
                    <span className="text-[10px] px-1.5 py-0.5 bg-emerald-500/10 text-emerald-400 rounded border border-emerald-500/20 uppercase tracking-wider font-bold">
                      Active
                    </span>
                  </div>
                </div>
                <button
                  onClick={() => setSelectedVault(null)}
                  className="p-1.5 text-slate-500 hover:text-white hover:bg-midnight-800 rounded-lg transition-all"
                >
                  <X className="w-4 h-4" />
                </button>
              </div>

              {/* Stats Grid */}
              <div className="grid grid-cols-2 gap-3">
                <div className="bg-midnight-900/50 rounded-lg p-3 border border-midnight-700/30">
                  <span className="text-[10px] text-slate-500 uppercase tracking-wider font-bold block mb-1">
                    Your Balance
                  </span>
                  <span className="text-sm font-mono font-medium text-white">
                    0.00 {selectedToken.symbol}
                  </span>
                </div>
                <div className="bg-midnight-900/50 rounded-lg p-3 border border-midnight-700/30">
                  <span className="text-[10px] text-slate-500 uppercase tracking-wider font-bold block mb-1">
                    Current APY
                  </span>
                  <span className="text-sm font-mono font-medium text-emerald-400">
                    5.24%
                  </span>
                </div>
              </div>
            </div>

            {/* Deposit Form */}
            <div className="p-6 flex-1 overflow-y-auto">
              <DepositForm />
            </div>
          </aside>
        )}
      </div>
    </>
  );
}

