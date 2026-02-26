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
import { toast } from "sonner"
import { TOKENS } from "@/lib/addresses"
import { ERC20_ABI, MARKET_ABI } from "@/lib/contracts"
import { useAppStore } from "@/store/useAppStore"
import { TransactionStepper, type TransactionStep } from "./TransactionStepper"
import { TokenIcon } from "@/components/TokenIcon"
import { ArrowDownToLine, ArrowUpFromLine, Wallet } from "lucide-react"

const publicClient = createPublicClient({
  chain: sepolia,
  transport: http(
    process.env.NEXT_PUBLIC_RPC_URL ||
      "https://eth-sepolia.g.alchemy.com/v2/demo"
  )
})

// Which collateral tokens are accepted per market (loan asset is excluded)
const COLLATERAL_TOKENS: Record<string, (keyof typeof TOKENS)[]> = {
  usdc: ["WETH", "WBTC"],
  weth: ["WBTC"],
  wbtc: ["WETH"]
}

type TabMode = "deposit" | "withdraw"

function Spinner() {
  return (
    <svg
      className="animate-spin -ml-1 mr-2 h-4 w-4 text-white inline"
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
    >
      <circle
        className="opacity-25"
        cx="12"
        cy="12"
        r="10"
        stroke="currentColor"
        strokeWidth="4"
      />
      <path
        className="opacity-75"
        fill="currentColor"
        d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
      />
    </svg>
  )
}

interface CollateralFormProps {
  marketAddress: string
  selectedVaultId: string
  onSuccess?: () => void
}

export function CollateralForm({
  marketAddress,
  selectedVaultId,
  onSuccess
}: CollateralFormProps) {
  const { address, isConnected } = useAccount()
  const { triggerRefresh } = useAppStore()
  const [mode, setMode] = useState<TabMode>("deposit")
  const [amount, setAmount] = useState("")
  const [steps, setSteps] = useState<TransactionStep[]>([])

  // Available collateral tokens for this market
  const collateralKeys = COLLATERAL_TOKENS[selectedVaultId] ?? ["WETH", "WBTC"]
  const [selectedTokenKey, setSelectedTokenKey] = useState<keyof typeof TOKENS>(
    collateralKeys[0]
  )

  // Reset selected token when market changes
  useEffect(() => {
    const keys = COLLATERAL_TOKENS[selectedVaultId] ?? ["WETH", "WBTC"]
    setSelectedTokenKey(keys[0])
    setAmount("")
    setSteps([])
  }, [selectedVaultId])

  const token = TOKENS[selectedTokenKey]

  const parsedAmount = useMemo(
    () => (amount ? parseUnits(amount, token.decimals) : 0n),
    [amount, token.decimals]
  )

  // Wallet balance + allowance for selected collateral token
  const [walletBalance, setWalletBalance] = useState<bigint>(0n)
  const [allowance, setAllowance] = useState<bigint>(0n)

  // Write hooks
  const {
    writeContract: approve,
    data: approveTxHash,
    isPending: isApproving,
    reset: resetApprove,
    error: approveError,
    isError: isApproveError
  } = useWriteContract()

  const {
    writeContract: depositCollateral,
    data: depositTxHash,
    isPending: isDepositing,
    reset: resetDeposit,
    error: depositError,
    isError: isDepositError
  } = useWriteContract()

  const {
    writeContract: withdrawCollateral,
    data: withdrawTxHash,
    isPending: isWithdrawing,
    reset: resetWithdraw,
    error: withdrawError,
    isError: isWithdrawError
  } = useWriteContract()

  const { isSuccess: approveSuccess } = useWaitForTransactionReceipt({
    hash: approveTxHash
  })
  const { isSuccess: depositSuccess } = useWaitForTransactionReceipt({
    hash: depositTxHash
  })
  const { isSuccess: withdrawSuccess } = useWaitForTransactionReceipt({
    hash: withdrawTxHash
  })

  // Fetch balance + allowance
  useEffect(() => {
    if (!address || !isConnected) return

    const fetchBalances = async () => {
      try {
        const [bal, allow] = await Promise.all([
          publicClient.readContract({
            address: token.address as `0x${string}`,
            abi: ERC20_ABI,
            functionName: "balanceOf",
            args: [address as `0x${string}`]
          }),
          publicClient.readContract({
            address: token.address as `0x${string}`,
            abi: ERC20_ABI,
            functionName: "allowance",
            args: [address as `0x${string}`, marketAddress as `0x${string}`]
          })
        ])
        setWalletBalance(bal as bigint)
        setAllowance(allow as bigint)
      } catch (err) {
        console.error("[CollateralForm] Failed to fetch balances:", err)
      }
    }

    fetchBalances()
  }, [address, isConnected, token.address, marketAddress, approveSuccess, depositSuccess, withdrawSuccess])

  // Toast + reset on deposit success
  useEffect(() => {
    if (!depositSuccess || !depositTxHash) return
    const hash = depositTxHash
    toast.success("Collateral deposited!", {
      description: `${hash.slice(0, 10)}...${hash.slice(-8)}`,
      action: {
        label: "View on Etherscan",
        onClick: () =>
          window.open(`https://sepolia.etherscan.io/tx/${hash}`, "_blank"),
      },
      duration: 6000,
    })
    resetApprove()
    resetDeposit()
    setAmount("")
    triggerRefresh()
    onSuccess?.()
  }, [depositSuccess, depositTxHash, resetApprove, resetDeposit, triggerRefresh, onSuccess])

  // Toast + reset on withdraw success
  useEffect(() => {
    if (!withdrawSuccess || !withdrawTxHash) return
    const hash = withdrawTxHash
    toast.success("Collateral withdrawn!", {
      description: `${hash.slice(0, 10)}...${hash.slice(-8)}`,
      action: {
        label: "View on Etherscan",
        onClick: () =>
          window.open(`https://sepolia.etherscan.io/tx/${hash}`, "_blank"),
      },
      duration: 6000,
    })
    resetWithdraw()
    setAmount("")
    triggerRefresh()
    onSuccess?.()
  }, [withdrawSuccess, withdrawTxHash, resetWithdraw, triggerRefresh, onSuccess])

  // Toast on error
  useEffect(() => {
    const err = approveError ?? depositError ?? withdrawError
    if (!err) return
    toast.error("Transaction failed", {
      description:
        (err as { shortMessage?: string })?.shortMessage ??
        err.message?.split("\n")[0],
    })
  }, [isApproveError, isDepositError, isWithdrawError, approveError, depositError, withdrawError])

  // Build transaction steps for deposit mode
  useEffect(() => {
    if (mode !== "deposit" || parsedAmount === 0n) {
      setSteps([])
      return
    }

    const needsApproval = allowance < parsedAmount
    const newSteps: TransactionStep[] = []

    if (needsApproval) {
      newSteps.push({
        label: `Approve ${token.symbol}`,
        description: approveSuccess
          ? "Infinite approval granted"
          : isApproving
            ? "Waiting for approval..."
            : "Token approval required",
        status: approveSuccess ? "completed" : isApproving ? "active" : "pending",
        txHash: approveTxHash
      })
    } else {
      newSteps.push({
        label: `Approve ${token.symbol}`,
        description: "Infinite approval granted",
        status: "completed"
      })
    }

    newSteps.push({
      label: "Deposit Collateral",
      description: isDepositing ? "Depositing collateral..." : "Send collateral to market",
      status: isDepositing ? "active" : "pending",
      txHash: depositTxHash
    })

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
    depositTxHash
  ])

  const handleDeposit = useCallback(() => {
    if (!amount || !address || parsedAmount <= 0n) return

    if (allowance >= parsedAmount || approveSuccess) {
      depositCollateral({
        address: marketAddress as `0x${string}`,
        abi: MARKET_ABI,
        functionName: "depositCollateral",
        args: [token.address as `0x${string}`, parsedAmount]
      })
    } else {
      approve({
        address: token.address as `0x${string}`,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [marketAddress as `0x${string}`, maxUint256]
      })
    }
  }, [amount, address, parsedAmount, allowance, approveSuccess, depositCollateral, approve, token.address, marketAddress])

  const handleWithdraw = useCallback(() => {
    if (!amount || !address || parsedAmount <= 0n) return

    withdrawCollateral({
      address: marketAddress as `0x${string}`,
      abi: MARKET_ABI,
      functionName: "withdrawCollateral",
      args: [token.address as `0x${string}`, parsedAmount]
    })
  }, [amount, address, parsedAmount, withdrawCollateral, token.address, marketAddress])

  const handleMax = useCallback(() => {
    setAmount(formatUnits(walletBalance, token.decimals))
  }, [walletBalance, token.decimals])

  if (!isConnected) {
    return (
      <div className='flex flex-col items-center justify-center py-8 px-6 text-center'>
        <div className='w-10 h-10 rounded-full bg-indigo-500/10 flex items-center justify-center mb-3'>
          <Wallet className='w-5 h-5 text-indigo-400' />
        </div>
        <p className='text-xs text-slate-500'>
          Connect a wallet to manage collateral.
        </p>
      </div>
    )
  }

  const isProcessing = isApproving || isDepositing || isWithdrawing

  let buttonText: string
  if (isApproving) buttonText = "Approving..."
  else if (isDepositing) buttonText = "Depositing..."
  else if (isWithdrawing) buttonText = "Withdrawing..."
  else if (approveSuccess && mode === "deposit") buttonText = "Confirm Deposit →"
  else if (mode === "deposit") buttonText = "Deposit Collateral"
  else buttonText = "Withdraw Collateral"

  return (
    <div className='space-y-4'>
      {/* Mode Tabs */}
      <div className='flex bg-midnight-800/50 rounded-lg p-1 border border-midnight-700/50'>
        {(["deposit", "withdraw"] as TabMode[]).map((tab) => (
          <button
            key={tab}
            onClick={() => {
              setMode(tab)
              setAmount("")
              setSteps([])
            }}
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

      {/* Collateral Token Selector */}
      <div className='flex gap-2'>
        {collateralKeys.map((key) => {
          const t = TOKENS[key]
          const isSelected = selectedTokenKey === key
          return (
            <button
              key={key}
              onClick={() => {
                setSelectedTokenKey(key)
                setAmount("")
              }}
              className={`flex items-center gap-2 px-3 py-1.5 rounded-xl border text-xs font-medium transition-all ${
                isSelected
                  ? "border-indigo-500/40 bg-indigo-500/10 text-indigo-300"
                  : "border-midnight-700/50 text-slate-500 hover:text-slate-300 hover:border-midnight-600/50"
              }`}
            >
              <TokenIcon symbol={t.symbol} size='sm' />
              {t.symbol}
            </button>
          )
        })}
      </div>

      {/* Wallet Balance */}
      <div className='flex items-center justify-between text-xs'>
        <span className='text-slate-500'>Wallet Balance</span>
        <span className='text-slate-300 font-mono'>
          {formatUnits(walletBalance, token.decimals)} {token.symbol}
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
            className='flex-1 min-w-0 bg-transparent text-2xl font-mono font-medium text-white placeholder-slate-700 outline-none'
          />
          <div
            className='shrink-0 flex items-center gap-2 px-3 py-1.5 rounded-xl border border-midnight-700/50'
            style={{ backgroundColor: `${token.color}10` }}
          >
            <TokenIcon symbol={token.symbol} size='sm' />
            <span className='text-sm font-medium text-slate-300'>
              {token.symbol}
            </span>
          </div>
        </div>
      </div>

      {/* Transaction Steps (deposit mode) */}
      {mode === "deposit" && steps.length > 0 && (
        <TransactionStepper steps={steps} />
      )}

      {/* Action Button */}
      <button
        onClick={mode === "deposit" ? handleDeposit : handleWithdraw}
        disabled={!amount || parseFloat(amount) <= 0 || isProcessing}
        className='w-full py-3 bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-medium rounded-xl transition-all disabled:opacity-50 disabled:cursor-not-allowed shadow-[0_0_20px_rgba(79,70,229,0.2)] hover:shadow-[0_0_30px_rgba(79,70,229,0.4)]'
      >
        {isProcessing && <Spinner />}
        {buttonText}
      </button>
    </div>
  )
}
