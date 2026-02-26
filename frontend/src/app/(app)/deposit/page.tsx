"use client"

import { useState, useEffect } from "react"
import { Header } from "@/components/Header"
import { DepositForm } from "@/components/DepositForm"
import { useAccount } from "wagmi"
import { useAppStore } from "@/store/useAppStore"
import { TOKENS } from "@/lib/addresses"
import { Wallet, ArrowRightLeft, Shield } from "lucide-react"
import { TokenIcon } from "@/components/TokenIcon"

export default function DepositPage() {
  const { address, isConnected } = useAccount()
  const { selectedVault, setSelectedVault } = useAppStore()

  // Default to USDC if no vault selected
  useEffect(() => {
    if (!selectedVault) {
      setSelectedVault("usdc")
    }
  }, [selectedVault, setSelectedVault])

  const vaults = [
    { id: "usdc" as const, ...TOKENS.USDC, apy: "5.24%" },
    { id: "weth" as const, ...TOKENS.WETH, apy: "3.42%" },
    { id: "wbtc" as const, ...TOKENS.WBTC, apy: "0.00%" }
  ]

  return (
    <>
      <Header
        title='Token Management'
        breadcrumb='Deposit'
        showModeToggle={false}
      />

      <div className='p-6 sm:p-8 lg:p-10'>
        {/* Hero */}
        <div className='mb-8 relative'>
          <div className='text-[10px] font-bold text-indigo-400 uppercase tracking-[0.2em] mb-2'>
            Token Management
          </div>
          <h1 className='text-3xl sm:text-4xl font-display font-black text-white mb-2 tracking-tighter leading-[1.1]'>
            Deposit & Withdraw
          </h1>
          <p className='text-slate-400 text-sm max-w-2xl font-light leading-relaxed'>
            Manage your positions across LendCore markets. Deposit tokens to
            earn yield or withdraw to your wallet.
          </p>
          <div className='absolute -top-20 -left-20 w-64 h-64 bg-indigo-600/10 rounded-full blur-[80px] pointer-events-none mix-blend-screen' />
        </div>

        <div className='grid grid-cols-1 lg:grid-cols-3 gap-8'>
          {/* Vault Selector */}
          <div className='lg:col-span-1'>
            <div className='glass-panel rounded-2xl overflow-hidden'>
              <div className='px-6 py-5 border-b border-midnight-700/50 bg-white/5'>
                <h3 className='text-sm font-semibold text-white'>
                  Select Market
                </h3>
              </div>
              <div className='p-4 space-y-2'>
                {vaults.map((vault) => (
                  <button
                    key={vault.id}
                    onClick={() => setSelectedVault(vault.id)}
                    className={`w-full flex items-center gap-4 p-4 rounded-xl border transition-all ${
                      selectedVault === vault.id
                        ? "bg-indigo-500/5 border-indigo-500/20"
                        : "bg-midnight-900/30 border-midnight-700/30 hover:border-midnight-600/50"
                    }`}
                  >
                    <div
                      className='w-10 h-10 rounded-xl flex items-center justify-center border border-white/10'
                      style={{ backgroundColor: `${vault.color}15` }}
                    >
                      <TokenIcon symbol={vault.symbol} size='sm' />
                    </div>
                    <div className='flex-1 text-left'>
                      <span className='text-sm font-medium text-white block'>
                        {vault.symbol}
                      </span>
                      <span className='text-xs text-slate-500'>
                        {vault.name}
                      </span>
                    </div>
                    <span className='text-xs font-mono text-emerald-400'>
                      {vault.apy}
                    </span>
                  </button>
                ))}
              </div>
            </div>

            {/* Info Card */}
            <div className='mt-6 glass-panel rounded-2xl p-6'>
              <h4 className='text-xs font-bold text-indigo-400 uppercase tracking-wider mb-3'>
                How it works
              </h4>
              <div className='space-y-4'>
                <InfoStep
                  icon={<Wallet className='w-4 h-4' />}
                  title='1. Approve Token'
                  description='Grant the market contract permission to transfer your tokens.'
                />
                <InfoStep
                  icon={<ArrowRightLeft className='w-4 h-4' />}
                  title='2. Deposit'
                  description='Your tokens are deposited into the lending market and you receive shares.'
                />
                <InfoStep
                  icon={<Shield className='w-4 h-4' />}
                  title='3. Earn Yield'
                  description='Your shares accumulate yield from lending interest.'
                />
              </div>
            </div>
          </div>

          {/* Deposit Form */}
          <div className='lg:col-span-2'>
            <div className='glass-panel rounded-2xl overflow-hidden'>
              <div className='px-6 py-5 border-b border-midnight-700/50 bg-white/5'>
                <h3 className='text-sm font-semibold text-white'>
                  {selectedVault
                    ? `${TOKENS[selectedVault.toUpperCase() as keyof typeof TOKENS].symbol} Market`
                    : "Select a Market"}
                </h3>
                <p className='text-xs text-slate-500 mt-1'>
                  Manage your market position
                </p>
              </div>
              <div className='p-6'>
                <DepositForm />
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
