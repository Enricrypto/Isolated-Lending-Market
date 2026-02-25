"use client";

import Link from "next/link";
import { ArrowRight, TrendingUp, Shield } from "lucide-react";
import { TokenIcon } from "@/components/TokenIcon";
import { useVaults } from "@/hooks/useVaults";
import type { VaultSummary, SeverityLevel } from "@/types/metrics";

function severityToHealthStatus(
  severity: SeverityLevel,
  hasData: boolean
): "low-risk" | "stable" | "elevated" | "idle" {
  if (!hasData) return "idle";
  if (severity === 0) return "low-risk";
  if (severity === 1) return "stable";
  return "elevated";
}

function formatTVL(totalSupply: number, symbol: string) {
  const isStablecoin =
    symbol.toLowerCase().includes("usdc") || symbol.toLowerCase().includes("usd");
  const usdValue = isStablecoin ? totalSupply : totalSupply;
  return {
    raw: totalSupply.toLocaleString(undefined, { maximumFractionDigits: 2 }),
    usd: `$${usdValue.toLocaleString(undefined, { maximumFractionDigits: 0 })}`,
  };
}

function simulatedAPY(utilization: number): string {
  if (utilization === 0) return "0.00%";
  return `${(utilization * 8 * 100).toFixed(2)}%`;
}

export function VaultTable() {
  const { data, loading, error } = useVaults();

  if (loading) {
    return (
      <div className="glass-panel rounded-2xl overflow-hidden shadow-2xl">
        <div className="px-8 py-6 border-b border-midnight-700/50 bg-white/5">
          <h3 className="text-lg font-semibold text-white">Market Overview</h3>
        </div>
        <div className="p-12 flex items-center justify-center">
          <div className="flex items-center gap-3 text-slate-400">
            <div className="w-5 h-5 border-2 border-indigo-500/50 border-t-indigo-400 rounded-full animate-spin" />
            <span className="text-sm">Loading market data...</span>
          </div>
        </div>
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="glass-panel rounded-2xl overflow-hidden shadow-2xl">
        <div className="px-8 py-6 border-b border-midnight-700/50 bg-white/5">
          <h3 className="text-lg font-semibold text-white">Market Overview</h3>
        </div>
        <div className="p-12 flex items-center justify-center text-slate-500 text-sm">
          Unable to load market data
        </div>
      </div>
    );
  }

  const vaults: VaultSummary[] = data.vaults;

  return (
    <div className="glass-panel rounded-2xl overflow-hidden shadow-2xl">
      <div className="px-8 py-6 border-b border-midnight-700/50 flex items-center justify-between bg-white/5">
        <div>
          <h3 className="text-lg font-semibold tracking-wide text-white">
            Market Overview
          </h3>
          <p className="text-xs text-slate-500 mt-1">
            {vaults.length} active market{vaults.length !== 1 ? "s" : ""} on Sepolia
          </p>
        </div>
        <Link
          href="/monitoring"
          className="text-xs font-semibold text-indigo-400 hover:text-indigo-300 flex items-center gap-1.5 uppercase tracking-wider transition-colors"
        >
          View All <ArrowRight className="w-3.5 h-3.5" />
        </Link>
      </div>

      <div className="overflow-x-auto">
        <table className="w-full text-left text-sm">
          <thead>
            <tr className="border-b border-midnight-700/50 text-[10px] font-bold text-slate-500 uppercase tracking-[0.1em]">
              <th className="px-8 py-5">Asset</th>
              <th className="px-6 py-5">TVL</th>
              <th className="px-6 py-5">APY (Sim)</th>
              <th className="px-6 py-5">Utilization</th>
              <th className="px-6 py-5">Status</th>
              <th className="px-6 py-5 text-right">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-midnight-700/50">
            {vaults.map((vault) => {
              const hasData = !!vault.lastUpdated;
              const healthStatus = severityToHealthStatus(vault.overallSeverity, hasData);
              const tvl = formatTVL(vault.totalSupply, vault.symbol);
              const apy = hasData ? simulatedAPY(vault.utilization) : "--";
              const utilPct = hasData ? `${(vault.utilization * 100).toFixed(1)}%` : "--";

              return (
                <tr key={vault.vaultAddress} className="hover:bg-white/5 transition-all">
                  <td className="px-8 py-5">
                    <div className="flex items-center gap-4">
                      <div className="w-10 h-10 rounded-xl bg-indigo-500/10 border border-indigo-500/20 flex items-center justify-center shadow-lg">
                        <TokenIcon symbol={vault.symbol} size={22} />
                      </div>
                      <div>
                        <span className="font-medium text-white text-base block">
                          {vault.symbol}
                        </span>
                        <span className="text-xs text-slate-500">{vault.label}</span>
                      </div>
                    </div>
                  </td>
                  <td className="px-6 py-5">
                    {hasData ? (
                      <div>
                        <span className="text-white font-mono font-medium">{tvl.usd}</span>
                        <span className="block text-xs text-slate-500 font-mono">
                          {tvl.raw} {vault.symbol}
                        </span>
                      </div>
                    ) : (
                      <span className="text-slate-500 font-mono">--</span>
                    )}
                  </td>
                  <td className="px-6 py-5">
                    {hasData && vault.utilization > 0 ? (
                      <div className="flex items-center gap-2">
                        <TrendingUp className="w-3.5 h-3.5 text-emerald-400" />
                        <span className="text-emerald-400 font-mono font-medium">{apy}</span>
                      </div>
                    ) : (
                      <span className="text-slate-500 font-mono">{apy}</span>
                    )}
                  </td>
                  <td className="px-6 py-5">
                    <span className="text-white font-mono">{utilPct}</span>
                  </td>
                  <td className="px-6 py-5">
                    <HealthBadge status={healthStatus} />
                  </td>
                  <td className="px-6 py-5 text-right">
                    <Link
                      href="/deposit"
                      className="px-4 py-1.5 text-xs font-medium rounded-lg transition-all bg-midnight-800 text-slate-300 border border-midnight-700/50 hover:bg-midnight-700 hover:text-white inline-block"
                    >
                      Manage
                    </Link>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function HealthBadge({
  status,
}: {
  status: "low-risk" | "stable" | "elevated" | "idle";
}) {
  const config = {
    "low-risk": {
      label: "Low Risk",
      bgColor: "rgba(16,185,129,0.1)",
      textColor: "#34d399",
      borderColor: "rgba(16,185,129,0.2)",
    },
    stable: {
      label: "Stable",
      bgColor: "rgba(59,130,246,0.1)",
      textColor: "#60a5fa",
      borderColor: "rgba(59,130,246,0.2)",
    },
    elevated: {
      label: "Elevated",
      bgColor: "rgba(245,158,11,0.1)",
      textColor: "#fbbf24",
      borderColor: "rgba(245,158,11,0.2)",
    },
    idle: {
      label: "No Data",
      bgColor: "rgba(100,116,139,0.1)",
      textColor: "#94a3b8",
      borderColor: "rgba(100,116,139,0.2)",
    },
  };

  const c = config[status];

  return (
    <span
      className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold"
      style={{
        backgroundColor: c.bgColor,
        color: c.textColor,
        borderWidth: 1,
        borderColor: c.borderColor,
      }}
    >
      <Shield className="w-2.5 h-2.5" />
      {c.label}
    </span>
  );
}
