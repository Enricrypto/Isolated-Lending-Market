"use client"

import { Header } from "@/components/Header"
import { VaultTable } from "@/components/VaultTable"
import { DepositForm } from "@/components/DepositForm"
import { Tooltip } from "@/components/Tooltip"
import { useAppStore } from "@/store/useAppStore"
import { useVaults } from "@/hooks/useVaults"
import { TOKENS } from "@/lib/addresses"
import { formatRate } from "@/lib/irm"
import { DollarSign, Activity, TrendingUp, X } from "lucide-react"
import { TokenIcon } from "@/components/TokenIcon"
import { MarketUtilizationGraph } from "@/components/MarketUtilizationGraph"

// ── Tooltip copy ─────────────────────────────────────────────────────────────

const TIPS = {
  tvl:
    "Total USD value of assets deposited across all three lending vaults, " +
    "calculated using live Chainlink oracle prices. Higher TVL = deeper " +
    "market liquidity and lower liquidation risk.",
  utilization:
    "Average utilization across all markets: Total Borrows / Total Assets. " +
    "The protocol targets 80% (kink point). Above 80%, borrow rates spike " +
    "sharply to attract repayment and protect lender liquidity.",
  supplyApy:
    "Average annual yield for depositors across all active markets. " +
    "Formula: Borrow APR × Utilization × (1 − 10% fee). " +
    "At 0% utilization this is 0%; at 80% utilization it is ~3.74%.",
  currentApy:
    "Supply APY for this market using the Jump Rate Model. " +
    "Formula: Borrow APR × Utilization × 90%. " +
    "The borrow rate is " +
    `2% + util × 4% (below 80% kink) or 5.2% + (util − 80%) × 60% above it.`,
  borrowApr:
    "Annual interest rate borrowers pay in this market. " +
    "Uses the Jump Rate Model — gradual below 80% utilization, " +
    "then a sharp jump above it to incentivise repayment."
} as const

// ── Component ─────────────────────────────────────────────────────────────────

export default function VaultDashboard() {
  const { selectedVault, setSelectedVault } = useAppStore()
  const { data, loading } = useVaults()

  // ── Protocol-level aggregates (from backend, oracle-priced) ─────────────
  const usdTVL = data
    ? data.vaults.reduce((acc, v) => acc + v.totalSupply * v.oraclePrice, 0)
    : null

  const hasAnyData = data ? data.vaults.some((v) => !!v.lastUpdated) : false

  const avgUtil =
    hasAnyData && data
      ? data.vaults
          .filter((v) => !!v.lastUpdated)
          .reduce((acc, v, _, arr) => acc + v.utilization / arr.length, 0)
      : null

  // Average supply APY — average of backend-provided lendingRate across active markets
  const avgSupplyAPY =
    hasAnyData && data
      ? data.vaults
          .filter((v) => !!v.lastUpdated)
          .reduce((acc, v, _, arr) => acc + (v.lendingRate ?? 0) / arr.length, 0)
      : null

  // ── Per-vault data for the selected market sidebar ───────────────────────
  const selectedToken = selectedVault
    ? TOKENS[selectedVault.toUpperCase() as keyof typeof TOKENS]
    : null

  const selectedVaultData =
    data?.vaults.find(
      (v) => selectedToken && v.symbol === selectedToken.symbol
    ) ?? null

  // Use live rates from backend snapshot — never compute from hardcoded IRM constants
  const selectedSupplyAPY = selectedVaultData?.lendingRate ?? 0
  const selectedBorrowAPR = selectedVaultData?.borrowRate ?? selectedVaultData?.baseRate ?? 0.02

  // ── Metric cards ─────────────────────────────────────────────────────────
  const metrics = [
    {
      label: "Total Value Locked",
      tooltip: TIPS.tvl,
      value: loading
        ? null
        : usdTVL !== null && usdTVL > 0
          ? `$${usdTVL.toLocaleString(undefined, { maximumFractionDigits: 0 })}`
          : "--",
      sub: "Across all markets · Oracle-priced",
      icon: <DollarSign className='w-4 h-4' />,
      color: "#6366f1"
    },
    {
      label: "Avg. Utilization",
      tooltip: TIPS.utilization,
      value: loading
        ? null
        : avgUtil !== null
          ? `${(avgUtil * 100).toFixed(1)}%`
          : "--",
      sub:
        avgUtil !== null
          ? avgUtil > 0.8
            ? "Above kink — borrow rate elevated"
            : avgUtil > 0.5
              ? "Moderate — healthy range"
              : "Low — ample liquidity"
          : "No data yet",
      icon: <Activity className='w-4 h-4' />,
      color: "#f59e0b"
    },
    {
      label: "Avg. Supply APY",
      tooltip: TIPS.supplyApy,
      value: loading
        ? null
        : avgSupplyAPY !== null && avgSupplyAPY > 0
          ? formatRate(avgSupplyAPY)
          : "--",
      sub: "Lender yield after 10% protocol fee",
      icon: <TrendingUp className='w-4 h-4' />,
      color: "#10b981"
    }
  ]

  return (
    <>
      <Header title='Market Dashboard' breadcrumb='Dashboard' />

      <div className='flex flex-col xl:flex-row w-full'>
        {/* Main Content */}
        <div className='flex-1 p-6 sm:p-8 lg:p-10'>
          {/* Hero */}
          <div className='mb-8 relative'>
            <div className='text-[10px] font-bold text-indigo-400 uppercase tracking-[0.2em] mb-2'>
              Protocol Overview
            </div>
            <h1 className='text-3xl sm:text-4xl font-display font-black text-white mb-2 tracking-tighter leading-[1.1]'>
              Dashboard Overview
            </h1>
            <p className='text-slate-400 text-sm max-w-2xl font-light leading-relaxed'>
              Monitor aggregate risk and interact with protocol positions on
              Sepolia testnet.
            </p>
            <div className='absolute -top-20 -left-20 w-64 h-64 bg-indigo-600/10 rounded-full blur-[80px] pointer-events-none mix-blend-screen' />
          </div>

          {/* Metric Cards */}
          <div className='grid grid-cols-1 md:grid-cols-3 gap-5 mb-8'>
            {metrics.map((metric, i) => (
              <div
                key={i}
                className='glass-panel rounded-xl p-6 group hover:border-indigo-500/20 transition-all'
              >
                <div className='flex items-center justify-between mb-4'>
                  <Tooltip content={metric.tooltip} side='bottom' width='w-72'>
                    <span className='text-xs font-medium text-slate-500 uppercase tracking-wider'>
                      {metric.label}
                    </span>
                  </Tooltip>
                  <div
                    className='w-8 h-8 rounded-lg flex items-center justify-center'
                    style={{
                      backgroundColor: `${metric.color}15`,
                      color: metric.color
                    }}
                  >
                    {metric.icon}
                  </div>
                </div>
                <div className='flex items-end gap-3'>
                  {metric.value === null ? (
                    <div className='h-8 w-24 bg-midnight-800 rounded animate-pulse' />
                  ) : (
                    <span className='text-2xl font-display font-bold text-white'>
                      {metric.value}
                    </span>
                  )}
                </div>
                <span className='text-[10px] text-slate-600 mt-1 block'>
                  {metric.sub}
                </span>
              </div>
            ))}
          </div>

          {/* Market Table */}
          <VaultTable />
        </div>

        {/* Right Sidebar — shown when a market is selected */}
        {selectedVault && selectedToken && (
          <aside className='w-full xl:w-[380px] xl:sticky xl:top-16 xl:h-[calc(100vh-4rem)] border-l border-midnight-700/50 bg-midnight-950/40 backdrop-blur-md flex flex-col shrink-0'>
            {/* Market Header */}
            <div className='p-6 border-b border-midnight-700/50'>
              <div className='flex items-center justify-between mb-4'>
                <div className='flex items-center gap-3'>
                  <div
                    className='w-10 h-10 rounded-xl flex items-center justify-center border border-white/10'
                    style={{ backgroundColor: `${selectedToken.color}15` }}
                  >
                    <TokenIcon symbol={selectedToken.symbol} size='sm' />
                  </div>
                  <div>
                    <h3 className='text-base font-semibold text-white'>
                      {selectedToken.symbol} Market
                    </h3>
                    <span className='text-[10px] px-1.5 py-0.5 bg-emerald-500/10 text-emerald-400 rounded border border-emerald-500/20 uppercase tracking-wider font-bold'>
                      Active
                    </span>
                  </div>
                </div>
                <button
                  onClick={() => setSelectedVault(null)}
                  className='p-1.5 text-slate-500 hover:text-white hover:bg-midnight-800 rounded-lg transition-all'
                >
                  <X className='w-4 h-4' />
                </button>
              </div>

              {/* Market Stats */}
              <div className='grid grid-cols-2 gap-3'>
                <div className='bg-midnight-900/50 rounded-lg p-3 border border-midnight-700/30'>
                  <Tooltip content={TIPS.currentApy} side='bottom' width='w-72' align='start'>
                    <span className='text-[10px] text-slate-500 uppercase tracking-wider font-bold block mb-1'>
                      Supply APY
                    </span>
                  </Tooltip>
                  <span className='text-sm font-mono font-medium text-emerald-400'>
                    {selectedVaultData && selectedVaultData.utilization > 0
                      ? formatRate(selectedSupplyAPY)
                      : "--"}
                  </span>
                  <span className='text-[10px] text-slate-600 block mt-0.5'>
                    {selectedVaultData
                      ? `${(selectedVaultData.utilization * 100).toFixed(1)}% utilized`
                      : "No data"}
                  </span>
                </div>
                <div className='bg-midnight-900/50 rounded-lg p-3 border border-midnight-700/30'>
                  <Tooltip content={TIPS.borrowApr} side='bottom' width='w-72' align='end'>
                    <span className='text-[10px] text-slate-500 uppercase tracking-wider font-bold block mb-1'>
                      Borrow APR
                    </span>
                  </Tooltip>
                  <span
                    className={`text-sm font-mono font-medium ${
                      selectedVaultData && selectedVaultData.utilization > 0.8
                        ? "text-orange-400"
                        : "text-white"
                    }`}
                  >
                    {formatRate(selectedBorrowAPR)}
                  </span>
                  {selectedVaultData && selectedVaultData.utilization > 0.8 && (
                    <span className='text-[10px] text-orange-400 block mt-0.5'>
                      ↑ above kink
                    </span>
                  )}
                </div>
              </div>

              {/* Interest Rate Curve */}
              <div className='mt-4'>
                <div className='flex items-center justify-between mb-2'>
                  <span className='text-[10px] font-bold text-slate-500 uppercase tracking-[0.1em]'>
                    Interest Rate Curve
                  </span>
                  <span className='text-[10px] text-slate-600'>
                    Borrow APR vs utilization
                  </span>
                </div>
                <MarketUtilizationGraph
                  utilization={selectedVaultData?.utilization ?? 0}
                  height={110}
                />
                <div className='flex items-center gap-4 mt-2'>
                  <span className='flex items-center gap-1 text-[10px] text-slate-600'>
                    <span className='inline-block w-2.5 h-0.5 rounded bg-emerald-500' />
                    Below kink
                  </span>
                  <span className='flex items-center gap-1 text-[10px] text-slate-600'>
                    <span className='inline-block w-2.5 h-0.5 rounded bg-amber-500' />
                    Above kink
                  </span>
                  <span className='flex items-center gap-1 text-[10px] text-slate-600'>
                    <span className='inline-block w-2.5 border-t border-dashed border-indigo-400' />
                    Kink (80%)
                  </span>
                </div>
              </div>
            </div>

            {/* Deposit Form */}
            <div className='p-6 flex-1 overflow-y-auto'>
              <DepositForm />
            </div>
          </aside>
        )}
      </div>
    </>
  )
}
