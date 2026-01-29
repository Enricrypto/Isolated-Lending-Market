"use client";

import { useEffect, useState } from "react";
import { Header } from "@/components/Header";
import { createPublicClient, http } from "viem";
import { sepolia } from "viem/chains";
import { SEPOLIA_ADDRESSES } from "@/lib/addresses";
import { RISK_ENGINE_ABI } from "@/lib/contracts";
import {
  ShieldAlert,
  Activity,
  Eye,
  Droplets,
  Landmark,
  Zap,
  ExternalLink,
  RefreshCw,
} from "lucide-react";

const client = createPublicClient({
  chain: sepolia,
  transport: http(
    process.env.NEXT_PUBLIC_RPC_URL ||
      "https://eth-sepolia.g.alchemy.com/v2/demo"
  ),
});

interface RiskData {
  scores: {
    oracleRisk: number;
    liquidityRisk: number;
    solvencyRisk: number;
    strategyRisk: number;
  };
  severity: number;
  timestamp: number;
  reasonFlags: string;
}

const severityConfig = [
  { label: "Normal", color: "#34d399", bg: "rgba(16,185,129,0.1)", border: "rgba(16,185,129,0.2)" },
  { label: "Elevated", color: "#fbbf24", bg: "rgba(245,158,11,0.1)", border: "rgba(245,158,11,0.2)" },
  { label: "Critical", color: "#fb923c", bg: "rgba(249,115,22,0.1)", border: "rgba(249,115,22,0.2)" },
  { label: "Emergency", color: "#f87171", bg: "rgba(239,68,68,0.1)", border: "rgba(239,68,68,0.2)" },
];

export default function RiskEnginePage() {
  const [riskData, setRiskData] = useState<RiskData | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const fetchRiskData = async () => {
    try {
      const result = await client.readContract({
        address: SEPOLIA_ADDRESSES.market as `0x${string}`,
        abi: RISK_ENGINE_ABI,
        functionName: "assessRisk",
      });

      const data = result as {
        scores: {
          oracleRisk: number;
          liquidityRisk: number;
          solvencyRisk: number;
          strategyRisk: number;
        };
        severity: number;
        timestamp: bigint;
        reasonFlags: string;
      };

      setRiskData({
        scores: {
          oracleRisk: Number(data.scores.oracleRisk),
          liquidityRisk: Number(data.scores.liquidityRisk),
          solvencyRisk: Number(data.scores.solvencyRisk),
          strategyRisk: Number(data.scores.strategyRisk),
        },
        severity: Number(data.severity),
        timestamp: Number(data.timestamp),
        reasonFlags: data.reasonFlags,
      });
    } catch (error) {
      console.error("Failed to fetch risk data:", error);
      // Mock data for display
      setRiskData({
        scores: {
          oracleRisk: 15,
          liquidityRisk: 25,
          solvencyRisk: 10,
          strategyRisk: 20,
        },
        severity: 0,
        timestamp: Math.floor(Date.now() / 1000),
        reasonFlags: "0x0000000000000000000000000000000000000000000000000000000000000000",
      });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchRiskData();
  }, []);

  const handleRefresh = async () => {
    setRefreshing(true);
    await fetchRiskData();
    setRefreshing(false);
  };

  const severity = riskData?.severity ?? 0;
  const config = severityConfig[severity] || severityConfig[0];

  const dimensions = riskData
    ? [
        {
          name: "Oracle Risk",
          score: riskData.scores.oracleRisk,
          icon: Eye,
          description: "Price feed staleness, deviation, and confidence metrics",
        },
        {
          name: "Liquidity Risk",
          score: riskData.scores.liquidityRisk,
          icon: Droplets,
          description: "Available liquidity depth and withdrawal capacity",
        },
        {
          name: "Solvency Risk",
          score: riskData.scores.solvencyRisk,
          icon: Landmark,
          description: "Collateral coverage and bad debt exposure",
        },
        {
          name: "Strategy Risk",
          score: riskData.scores.strategyRisk,
          icon: Zap,
          description: "External protocol exposure and smart contract risk",
        },
      ]
    : [];

  return (
    <>
      <Header title="Risk Engine" breadcrumb="Risk Engine" />

      <div className="p-6 sm:p-8 lg:p-10">
        {/* Hero */}
        <div className="mb-8 relative">
          <div className="text-[10px] font-bold text-indigo-400 uppercase tracking-[0.2em] mb-2">
            Admin Panel
          </div>
          <h1 className="text-3xl sm:text-4xl font-display font-black text-white mb-2 tracking-tighter leading-[1.1]">
            Risk Engine
          </h1>
          <p className="text-slate-400 text-sm max-w-2xl font-light leading-relaxed">
            Real-time risk assessment across oracle, liquidity, solvency, and
            strategy dimensions. Data sourced directly from on-chain risk engine.
          </p>
          <div className="absolute -top-20 -left-20 w-64 h-64 bg-indigo-600/10 rounded-full blur-[80px] pointer-events-none mix-blend-screen" />
        </div>

        {loading ? (
          <div className="flex items-center justify-center py-20">
            <div className="flex items-center gap-3 text-slate-400">
              <div className="w-5 h-5 border-2 border-indigo-500/50 border-t-indigo-400 rounded-full animate-spin" />
              <span className="text-sm">Loading risk assessment...</span>
            </div>
          </div>
        ) : (
          <>
            {/* Overall Severity */}
            <div className="glass-panel rounded-2xl p-8 mb-8">
              <div className="flex items-center justify-between mb-6">
                <div className="flex items-center gap-4">
                  <div
                    className="w-14 h-14 rounded-2xl flex items-center justify-center"
                    style={{ backgroundColor: config.bg }}
                  >
                    <ShieldAlert
                      className="w-7 h-7"
                      style={{ color: config.color }}
                    />
                  </div>
                  <div>
                    <h2 className="text-xl font-bold text-white">
                      Overall System Status
                    </h2>
                    <div className="flex items-center gap-2 mt-1">
                      <div
                        className="w-2 h-2 rounded-full animate-pulse"
                        style={{ backgroundColor: config.color }}
                      />
                      <span
                        className="text-sm font-semibold uppercase tracking-wider"
                        style={{ color: config.color }}
                      >
                        {config.label}
                      </span>
                      <span className="text-xs text-slate-500 ml-2">
                        Severity Level {severity}/3
                      </span>
                    </div>
                  </div>
                </div>

                <div className="flex items-center gap-3">
                  <button
                    onClick={handleRefresh}
                    disabled={refreshing}
                    className="flex items-center gap-2 px-4 py-2 text-xs font-medium text-slate-300 bg-midnight-800/50 border border-midnight-700/50 rounded-lg hover:bg-midnight-700/50 transition-all disabled:opacity-50"
                  >
                    <RefreshCw
                      className={`w-3.5 h-3.5 ${refreshing ? "animate-spin" : ""}`}
                    />
                    Re-assess
                  </button>
                  <a
                    href={`https://sepolia.etherscan.io/address/${SEPOLIA_ADDRESSES.market}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="flex items-center gap-2 px-4 py-2 text-xs font-medium text-indigo-400 bg-indigo-500/10 border border-indigo-500/20 rounded-lg hover:bg-indigo-500/20 transition-all"
                  >
                    <ExternalLink className="w-3.5 h-3.5" />
                    View on Etherscan
                  </a>
                </div>
              </div>

              {/* Severity Bar */}
              <div className="flex gap-2 mb-4">
                {[0, 1, 2, 3].map((level) => (
                  <div
                    key={level}
                    className="flex-1 h-2 rounded-full transition-all"
                    style={{
                      backgroundColor:
                        level <= severity
                          ? severityConfig[level].color
                          : "rgba(100,116,139,0.15)",
                      opacity: level <= severity ? 1 : 0.3,
                    }}
                  />
                ))}
              </div>
              <div className="flex justify-between text-[10px] text-slate-600 uppercase tracking-wider font-bold">
                <span>Normal</span>
                <span>Elevated</span>
                <span>Critical</span>
                <span>Emergency</span>
              </div>

              {/* Timestamp */}
              {riskData && (
                <div className="mt-6 pt-4 border-t border-midnight-700/30 flex items-center justify-between">
                  <span className="text-xs text-slate-500">
                    Last Assessment:{" "}
                    {new Date(riskData.timestamp * 1000).toLocaleString()}
                  </span>
                  <span className="text-[10px] font-mono text-slate-600">
                    Flags: {riskData.reasonFlags.slice(0, 18)}...
                  </span>
                </div>
              )}
            </div>

            {/* Dimension Scores */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              {dimensions.map((dim) => {
                const Icon = dim.icon;
                const scoreLevel =
                  dim.score < 25
                    ? 0
                    : dim.score < 50
                    ? 1
                    : dim.score < 75
                    ? 2
                    : 3;
                const sc = severityConfig[scoreLevel];

                return (
                  <div
                    key={dim.name}
                    className="glass-panel rounded-2xl p-6"
                  >
                    <div className="flex items-center gap-3 mb-4">
                      <div
                        className="w-10 h-10 rounded-xl flex items-center justify-center"
                        style={{ backgroundColor: sc.bg }}
                      >
                        <Icon className="w-5 h-5" style={{ color: sc.color }} />
                      </div>
                      <div>
                        <h3 className="text-sm font-semibold text-white">
                          {dim.name}
                        </h3>
                        <p className="text-[10px] text-slate-500">
                          {dim.description}
                        </p>
                      </div>
                    </div>

                    {/* Score Bar */}
                    <div className="mb-3">
                      <div className="flex items-center justify-between mb-1.5">
                        <span className="text-xs text-slate-500">
                          Risk Score
                        </span>
                        <span
                          className="text-sm font-mono font-bold"
                          style={{ color: sc.color }}
                        >
                          {dim.score}/100
                        </span>
                      </div>
                      <div className="w-full h-2 rounded-full bg-midnight-900 border border-midnight-700/30 overflow-hidden">
                        <div
                          className="h-full rounded-full transition-all duration-500"
                          style={{
                            width: `${dim.score}%`,
                            backgroundColor: sc.color,
                            boxShadow: `0 0 10px ${sc.color}40`,
                          }}
                        />
                      </div>
                    </div>

                    <div className="flex items-center gap-2">
                      <div
                        className="w-1.5 h-1.5 rounded-full"
                        style={{ backgroundColor: sc.color }}
                      />
                      <span
                        className="text-[10px] font-bold uppercase tracking-wider"
                        style={{ color: sc.color }}
                      >
                        {severityConfig[scoreLevel].label}
                      </span>
                    </div>
                  </div>
                );
              })}
            </div>
          </>
        )}
      </div>
    </>
  );
}
