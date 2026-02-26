"use client"

import { useState, useEffect, useCallback, useMemo } from "react"
import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt
} from "wagmi"
import { parseUnits, formatUnits, maxUint256 } from "viem"
import { createPublicClient, http } from "viem"
import { sepolia } from "viem/chains"
import { SEPOLIA_ADDRESSES, TOKENS } from "@/lib/addresses"
import { ERC20_ABI, VAULT_ABI } from "@/lib/contracts"
import { VAULT_REGISTRY } from "@/lib/vault-registry"
import { useAppStore } from "@/store/useAppStore"
import { useVaults } from "@/hooks/useVaults"
import { computeSupplyAPY, formatRate } from "@/lib/irm"
import { Tooltip } from "@/components/Tooltip"
import { TransactionStepper, type TransactionStep } from "./TransactionStepper"
import { Wallet, ArrowDownToLine, ArrowUpFromLine } from "lucide-react"
import { TokenIcon } from "@/components/TokenIcon"

const client = createPublicClient({
  chain: sepolia,
  transport: http(
    process.env.NEXT_PUBLIC_RPC_URL ||
      "https://eth-sepolia.g.alchemy.com/v2/demo"
  )
})

const VAULT_CONFIG_BY_ID = Object.fromEntries(
  VAULT_REGISTRY.map((v) => [v.symbol.toLowerCase(), v])
)

type TabMode = "deposit" | "withdraw"

export function DepositForm() {
  const { address, isConnected } = useAccount()
  const { selectedVault } = useAppStore()
  const { data: vaultsData } = useVaults()
  const [mode, setMode] = useState<TabMode>("deposit")
  const [amount, setAmount] = useState("")
  const [balance, setBalance] = useState<bigint>(0n)
  const [vaultBalance, setVaultBalance] = useState<bigint>(0n)
  const [allowance, setAllowance] = useState<bigint>(0n)
  const [steps, setSteps] = useState<TransactionStep[]>([])

  // Token & vault info
  const token = selectedVault
    ? TOKENS[selectedVault.toUpperCase() as keyof typeof TOKENS]
    : TOKENS.USDC

  const vaultAddress =
    (selectedVault
      ? VAULT_CONFIG_BY_ID[selectedVault]?.vaultAddress
      : undefined) ?? SEPOLIA_ADDRESSES.vault

  // Parse amount once
  const parsedAmount = useMemo(
    () => (amount ? parseUnits(amount, token.decimals) : 0n),
    [amount, token.decimals]
  )

  // Compute APY & yield
  const vaultSnapshot = vaultsData?.vaults.find(
    (v) => v.vaultAddress.toLowerCase() === vaultAddress.toLowerCase()
  )
  const utilization = vaultSnapshot?.utilization ?? 0
  const supplyAPY = computeSupplyAPY(utilization)
  const weeklyYield =
    parsedAmount > 0n && supplyAPY > 0
      ? (Number(formatUnits(parsedAmount, token.decimals)) * supplyAPY) / 52
      : 0

  // Write contracts
  const {
    writeContract: approve,
    data: approveTxHash,
    isPending: isApproving
  } = useWriteContract()
  const {
    writeContract: deposit,
    data: depositTxHash,
    isPending: isDepositing
  } = useWriteContract()
  const {
    writeContract: withdraw,
    data: withdrawTxHash,
    isPending: isWithdrawing
  } = useWriteContract()

  // Transaction receipts
  const { isSuccess: approveSuccess } = useWaitForTransactionReceipt({
    hash: approveTxHash
  })
  const { isSuccess: depositSuccess } = useWaitForTransactionReceipt({
    hash: depositTxHash
  })
  const { isSuccess: withdrawSuccess } = useWaitForTransactionReceipt({
    hash: withdrawTxHash
  })

  // Reset form on vault change
  useEffect(() => {
    setAmount("")
    setBalance(0n)
    setVaultBalance(0n)
    setAllowance(0n)
    setSteps([])
  }, [vaultAddress])

  // Fetch balances & allowance
  useEffect(() => {
    if (!address || !isConnected) return

    const fetchBalances = async () => {
      try {
        const [bal, vBal, allow] = await Promise.all([
          client.readContract({
            address: token.address as `0x${string}`,
            abi: ERC20_ABI,
            functionName: "balanceOf",
            args: [address as `0x${string}`]
          }),
          client.readContract({
            address: vaultAddress as `0x${string}`,
            abi: VAULT_ABI,
            functionName: "balanceOf",
            args: [address as `0x${string}`]
          }),
          client.readContract({
            address: token.address as `0x${string}`,
            abi: ERC20_ABI,
            functionName: "allowance",
            args: [address as `0x${string}`, vaultAddress as `0x${string}`]
          })
        ])

        setBalance(bal as bigint)
        setVaultBalance(vBal as bigint)
        setAllowance(allow as bigint)
      } catch (err) {
        console.error("Failed to fetch balances:", err)
      }
    }

    fetchBalances()
  }, [
    address,
    isConnected,
    token.address,
    vaultAddress,
    approveSuccess,
    depositSuccess,
    withdrawSuccess
  ])

  // Update transaction steps
  useEffect(() => {
    const newSteps: TransactionStep[] = []

    const needsApproval = parsedAmount > 0n && allowance < parsedAmount

    if (mode === "deposit") {
      if (needsApproval) {
        newSteps.push({
          label: `Approve ${token.symbol}`,
          description: approveSuccess
            ? "Infinite approval granted"
            : isApproving
              ? "Waiting for approval..."
              : "Token approval required",
          status: approveSuccess
            ? "completed"
            : isApproving
              ? "active"
              : "pending",
          txHash: approveTxHash
        })
      } else if (parsedAmount > 0n) {
        newSteps.push({
          label: `Approve ${token.symbol}`,
          description: "Infinite approval granted",
          status: "completed"
        })
      }

      if (parsedAmount > 0n) {
        newSteps.push({
          label: "Deposit to Vault",
          description: depositSuccess
            ? "Deposit confirmed"
            : isDepositing
              ? "Minting vault shares..."
              : "ERC4626 Mint Shares",
          status: depositSuccess
            ? "completed"
            : isDepositing
              ? "active"
              : "pending",
          txHash: depositTxHash
        })
      }
    }

    setSteps(newSteps)
  }, [
    mode,
    parsedAmount,
    allowance,
    token.symbol,
    isApproving,
    approveSuccess,
    approveTxHash,
    isDepositing,
    depositSuccess,
    depositTxHash
  ])

  // Handlers
  const handleDeposit = useCallback(() => {
    if (!amount || !address || parsedAmount <= 0n) return

    // approveSuccess means we just approved this session — go straight to deposit
    // even if the allowance refetch hasn't completed yet
    if (allowance >= parsedAmount || approveSuccess) {
      deposit({
        address: vaultAddress as `0x${string}`,
        abi: VAULT_ABI,
        functionName: "deposit",
        args: [parsedAmount, address as `0x${string}`]
      })
    } else {
      approve({
        address: token.address as `0x${string}`,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [vaultAddress as `0x${string}`, maxUint256]
      })
    }
  }, [
    amount,
    address,
    parsedAmount,
    allowance,
    approveSuccess,
    approve,
    deposit,
    token.address,
    vaultAddress
  ])

  const handleWithdraw = useCallback(() => {
    if (!amount || !address || parsedAmount <= 0n) return

    withdraw({
      address: vaultAddress as `0x${string}`,
      abi: VAULT_ABI,
      functionName: "withdraw",
      args: [parsedAmount, address as `0x${string}`, address as `0x${string}`]
    })
  }, [amount, address, parsedAmount, withdraw, vaultAddress])

  const handleMax = useCallback(() => {
    if (mode === "deposit") {
      setAmount(formatUnits(balance, token.decimals))
    } else {
      setAmount(formatUnits(vaultBalance, token.decimals))
    }
  }, [mode, balance, vaultBalance, token.decimals])

  if (!isConnected) {
    return (
      <div className='flex flex-col items-center justify-center py-12 px-6 text-center'>
        <div className='w-12 h-12 rounded-full bg-indigo-500/10 flex items-center justify-center mb-4'>
          <Wallet className='w-6 h-6 text-indigo-400' />
        </div>
        <h4 className='text-sm font-medium text-white mb-2'>
          Connect Your Wallet
        </h4>
        <p className='text-xs text-slate-500 max-w-[200px]'>
          Connect a wallet to deposit into vaults and manage your positions.
        </p>
      </div>
    )
  }

  return (
    <div className='space-y-5'>
      {/* Mode Tabs */}
      <div className='flex bg-midnight-800/50 rounded-lg p-1 border border-midnight-700/50'>
        {(["deposit", "withdraw"] as TabMode[]).map((tab) => (
          <button
            key={tab}
            onClick={() => setMode(tab)}
            className={`flex-1 flex items-center justify-center gap-2 py-2 text-xs font-medium rounded-md transition-all ${
              mode === tab
                ? "bg-indigo-500/20 text-indigo-400 border border-indigo-500/20"
                : "text-slate-500 hover:text-slate-300"
            }`}
          >
            {tab === "deposit" ? (
              <ArrowDownToLine className='w-3.5 h-3.5' />
            ) : (
              <ArrowUpFromLine className='w-3.5 h-3.5' />
            )}
            {tab.charAt(0).toUpperCase() + tab.slice(1)}
          </button>
        ))}
      </div>

      {/* Balance Display */}
      <div className='flex items-center justify-between text-xs'>
        <span className='text-slate-500'>
          {mode === "deposit" ? "Wallet Balance" : "Vault Balance"}
        </span>
        <span className='text-slate-300 font-mono'>
          {mode === "deposit"
            ? formatUnits(balance, token.decimals)
            : formatUnits(vaultBalance, token.decimals)}{" "}
          {token.symbol}
        </span>
      </div>

      {/* Amount Input */}
      <div className='bg-midnight-900 border border-midnight-700/50 rounded-xl p-4'>
        <div className='flex items-center justify-between mb-2'>
          <span className='text-[10px] text-slate-500 uppercase tracking-wider font-bold'>
            Amount
          </span>
          <button
            onClick={handleMax}
            className='text-[10px] text-indigo-400 hover:text-indigo-300 font-bold uppercase tracking-wider'
          >
            MAX
          </button>
        </div>
        <div className='flex items-center gap-3'>
          <input
            type='number'
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder='0.00'
            className='flex-1 bg-transparent text-2xl font-mono font-medium text-white placeholder-slate-700 outline-none'
          />
          <div
            className='flex items-center gap-2 px-3 py-1.5 rounded-xl border border-midnight-700/50'
            style={{ backgroundColor: `${token.color}10` }}
          >
            <TokenIcon symbol={token.symbol} size='sm' />
            <span className='text-sm font-medium text-slate-300'>
              {token.symbol}
            </span>
          </div>
        </div>
      </div>

      {/* Supply APY + Weekly Yield */}
      {mode === "deposit" && (
        <div className='px-4 py-3 bg-emerald-500/5 border border-emerald-500/10 rounded-lg space-y-1.5'>
          <div className='flex items-center justify-between'>
            <Tooltip
              content={
                "Annual yield earned by depositors. Computed as: Borrow APR × Utilization × 90%. " +
                "Jump Rate Model: below 80% util the rate rises gradually; above 80% jumps steeply."
              }
              side='top'
              width='w-72'
            >
              <span className='text-xs text-emerald-400'>Supply APY</span>
            </Tooltip>
            <span className='text-xs font-mono font-medium text-emerald-300'>
              {utilization > 0 ? formatRate(supplyAPY) : "--"}
            </span>
          </div>
          {weeklyYield > 0 ? (
            <div className='flex items-center justify-between'>
              <span className='text-[10px] text-slate-500'>
                Est. weekly yield
              </span>
              <span className='text-[10px] font-mono text-slate-400'>
                +{weeklyYield.toFixed(4)} {token.symbol}
              </span>
            </div>
          ) : (
            <p className='text-[10px] text-slate-500'>
              No borrows yet — yield starts once borrowers draw liquidity.
            </p>
          )}
        </div>
      )}

      {/* Transaction Steps */}
      {steps.length > 0 && <TransactionStepper steps={steps} />}

      {/* Action Button */}
      <button
        onClick={mode === "deposit" ? handleDeposit : handleWithdraw}
        disabled={
          !amount ||
          parseFloat(amount) <= 0 ||
          isApproving ||
          isDepositing ||
          isWithdrawing
        }
        className='w-full py-3 bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-medium rounded-xl transition-all disabled:opacity-50 disabled:cursor-not-allowed shadow-[0_0_20px_rgba(79,70,229,0.2)] hover:shadow-[0_0_30px_rgba(79,70,229,0.4)]'
      >
        {isApproving
          ? "Approving..."
          : isDepositing
            ? "Depositing..."
            : isWithdrawing
              ? "Withdrawing..."
              : depositSuccess
                ? "Deposit Complete ✓"
                : withdrawSuccess
                  ? "Withdrawal Complete ✓"
                  : approveSuccess && mode === "deposit"
                    ? "Confirm Deposit →"
                    : mode === "deposit"
                      ? "Confirm Deposit"
                      : "Confirm Withdrawal"}
      </button>

      {/* Gas Estimate */}
      <div className='flex items-center justify-center gap-1 text-[10px] text-slate-600'>
        <span>Est. gas: ~0.002 ETH</span>
        <span>•</span>
        <span>Sepolia Testnet</span>
      </div>
    </div>
  )
}
