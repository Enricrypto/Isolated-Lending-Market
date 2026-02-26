"use client"

import { useEffect } from "react"
import { Header } from "@/components/Header"
import { BorrowForm } from "@/components/BorrowForm"
import { useAccount } from "wagmi"
import { useAppStore } from "@/store/useAppStore"
import { usePositions } from "@/hooks/usePositions"
import { TOKENS } from "@/lib/addresses"
import { TokenIcon } from "@/components/TokenIcon"
import { TrendingDown, TrendingUp, Shield } from "lucide-react"

function HealthBar({ value }: { value: number }) {
  if (value === 0) return null
  const pct = Math.min((value / 3) * 100, 100)
  const color =
    value >= 2.0
      ? "bg-emerald-500"
      : value >= 1.5
        ? "bg-yellow-500"
        : value >= 1.2
          ? "bg-orange-500"
          : "bg-red-500"
  return (
    <div className='w-full bg-midnight-800 rounded-full h-1.5 mt-1'>
      <div
        className={`h-1.5 rounded-full transition-all ${color}`}
        style={{ width: `${pct}%` }}
      />
    </div>
  )
}

export default function BorrowPage() {
  const { address, isConnected } = useAccount()
  const { selectedVault, setSelectedVault } = useAppStore()
  const { positions } = usePositions(address)

  useEffect(() => {
    if (!selectedVault) setSelectedVault("usdc")
  }, [selectedVault, setSelectedVault])

  const markets = [
    { id: "usdc" as const, ...TOKENS.USDC },
    { id: "weth" as const, ...TOKENS.WETH },
    { id: "wbtc" as const, ...TOKENS.WBTC }
  ]

  const VAULT_ID_TO_ADDRESS: Record<string, string> = {
    usdc: "0xE8323c3d293f81C71232023367Bada21137C055E",
    weth: "0xbbc4c7FbCcF0faa27821c4F44C01D3F81C088070",
    wbtc: "0xBCB5fcA37f87a97eB1C5d6c9a92749e0F41161f0"
  }

  return (
    <>
      <Header title='Borrow' breadcrumb='Borrow' showModeToggle={false} />

      <div className='p-6 sm:p-8 lg:p-10'>
        {/* Hero */}
        <div className='mb-8 relative'>
          <div className='text-[10px] font-bold text-indigo-400 uppercase tracking-[0.2em] mb-2'>
            Lending Markets
          </div>
          <h1 className='text-3xl sm:text-4xl font-display font-black text-white mb-2 tracking-tighter leading-[1.1]'>
            Borrow & Repay
          </h1>
          <p className='text-slate-400 text-sm max-w-2xl font-light leading-relaxed'>
            Borrow against your collateral. Debt and health factor are served
            from the indexer — no direct chain reads for protocol state.
          </p>
          <div className='absolute -top-20 -left-20 w-64 h-64 bg-indigo-600/10 rounded-full blur-[80px] pointer-events-none mix-blend-screen' />
        </div>

        <div className='grid grid-cols-1 lg:grid-cols-3 gap-8'>
          {/* Left: Market Selector + Position Summary */}
          <div className='lg:col-span-1 space-y-6'>
            {/* Market Selector */}
            <div className='glass-panel rounded-2xl overflow-hidden'>
              <div className='px-6 py-5 border-b border-midnight-700/50 bg-white/5'>
                <h3 className='text-sm font-semibold text-white'>
                  Select Market
                </h3>
              </div>
              <div className='p-4 space-y-2'>
                {markets.map((market) => {
                  const pos = positions.find(
                    (p) =>
                      p.vaultAddress.toLowerCase() ===
                      VAULT_ID_TO_ADDRESS[market.id]?.toLowerCase()
                  )
                  return (
                    <button
                      key={market.id}
                      onClick={() => setSelectedVault(market.id)}
                      className={`w-full flex items-center gap-4 p-4 rounded-xl border transition-all ${
                        selectedVault === market.id
                          ? "bg-indigo-500/5 border-indigo-500/20"
                          : "bg-midnight-900/30 border-midnight-700/30 hover:border-midnight-600/50"
                      }`}
                    >
                      <div
                        className='w-10 h-10 rounded-xl flex items-center justify-center border border-white/10'
                        style={{ backgroundColor: `${market.color}15` }}
                      >
                        <TokenIcon symbol={market.symbol} size='sm' />
                      </div>
                      <div className='flex-1 text-left'>
                        <span className='text-sm font-medium text-white block'>
                          {market.symbol}
                        </span>
                        {pos && pos.totalDebt > 0 ? (
                          <span className='text-xs text-slate-500'>
                            ~{pos.totalDebt.toFixed(2)} debt
                          </span>
                        ) : (
                          <span className='text-xs text-slate-500'>
                            No debt
                          </span>
                        )}
                      </div>
                      {pos && pos.healthFactor > 0 && (
                        <span
                          className={`text-xs font-mono font-semibold ${
                            pos.healthFactor >= 2.0
                              ? "text-emerald-400"
                              : pos.healthFactor >= 1.5
                                ? "text-yellow-400"
                                : pos.healthFactor >= 1.2
                                  ? "text-orange-400"
                                  : "text-red-400"
                          }`}
                        >
                          {pos.healthFactor.toFixed(2)}
                        </span>
                      )}
                    </button>
                  )
                })}
              </div>
            </div>

            {/* How it works */}
            <div className='glass-panel rounded-2xl p-6'>
              <h4 className='text-xs font-bold text-indigo-400 uppercase tracking-wider mb-3'>
                How it works
              </h4>
              <div className='space-y-4'>
                <InfoStep
                  icon={<Shield className='w-4 h-4' />}
                  title='1. Deposit Collateral'
                  description='Deposit tokens into the vault to receive collateral shares.'
                />
                <InfoStep
                  icon={<TrendingDown className='w-4 h-4' />}
                  title='2. Borrow'
                  description='Borrow up to your available limit. Interest accrues continuously.'
                />
                <InfoStep
                  icon={<TrendingUp className='w-4 h-4' />}
                  title='3. Repay'
                  description='Repay debt to restore your health factor and release collateral.'
                />
              </div>
            </div>
          </div>

          {/* Right: Borrow Form */}
          <div className='lg:col-span-2'>
            <div className='glass-panel rounded-2xl overflow-hidden'>
              <div className='px-6 py-5 border-b border-midnight-700/50 bg-white/5'>
                <h3 className='text-sm font-semibold text-white'>
                  {selectedVault
                    ? `${TOKENS[selectedVault.toUpperCase() as keyof typeof TOKENS].symbol} Market`
                    : "Select a Market"}
                </h3>
                <p className='text-xs text-slate-500 mt-1'>
                  Borrow and repay against your collateral
                </p>
              </div>
              <div className='p-6'>
                <BorrowForm />
              </div>
            </div>
          </div>
        </div>
      </div>
    </>
  )
}

function InfoStep({
  icon,
  title,
  description
}: {
  icon: React.ReactNode
  title: string
  description: string
}) {
  return (
    <div className='flex gap-3'>
      <div className='w-8 h-8 rounded-lg bg-indigo-500/10 flex items-center justify-center text-indigo-400 flex-shrink-0'>
        {icon}
      </div>
      <div>
        <span className='text-xs font-medium text-white block'>{title}</span>
        <p className='text-[11px] text-slate-500 mt-0.5 leading-relaxed'>
          {description}
        </p>
      </div>
    </div>
  )
}
