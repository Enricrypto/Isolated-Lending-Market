"use client"

import { useState, useEffect } from "react"
import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt
} from "wagmi"
import { parseUnits, formatUnits, maxUint256 } from "viem"
import { createPublicClient, http } from "viem"
import { sepolia } from "viem/chains"
import { toast } from "sonner"
import { ERC20_ABI, MARKET_ABI } from "@/lib/contracts"
import { useAppStore } from "@/store/useAppStore"
import { usePositions } from "@/hooks/usePositions"
import { useVaults } from "@/hooks/useVaults"
import { getVaultConfig } from "@/lib/vault-registry"
import { TOKENS } from "@/lib/addresses"
import { computeBorrowAPR, formatRate } from "@/lib/irm"
import { Tooltip } from "@/components/Tooltip"
import { TransactionStepper, type TransactionStep } from "./TransactionStepper"
import {
  Wallet,
  ArrowDownToLine,
  ArrowUpFromLine,
  AlertTriangle
} from "lucide-react"
import { TokenIcon } from "@/components/TokenIcon"

const publicClient = createPublicClient({
  chain: sepolia,
  transport: http(
    process.env.NEXT_PUBLIC_RPC_URL ||
      "https://eth-sepolia.g.alchemy.com/v2/demo"
  )
})

// Map store VaultId to vault address
const VAULT_ID_TO_ADDRESS: Record<string, string> = {
  usdc: "0xE8323c3d293f81C71232023367Bada21137C055E",
  weth: "0xbbc4c7FbCcF0faa27821c4F44C01D3F81C088070",
  wbtc: "0xBCB5fcA37f87a97eB1C5d6c9a92749e0F41161f0"
}

type TabMode = "borrow" | "repay"

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

function HealthFactorBadge({ value }: { value: number }) {
  if (value === 0) {
    return <span className='text-slate-500 text-xs'>No debt</span>
  }
  const color =
    value >= 2.0
      ? "text-emerald-400"
      : value >= 1.5
        ? "text-yellow-400"
        : value >= 1.2
          ? "text-orange-400"
          : "text-red-400"
  return (
    <span className={`text-xs font-mono font-semibold ${color}`}>
      {value.toFixed(2)}
    </span>
  )
}

export function BorrowForm() {
  const { address, isConnected } = useAccount()
  const { selectedVault, triggerRefresh } = useAppStore()
  const [mode, setMode] = useState<TabMode>("borrow")
  const [amount, setAmount] = useState("")
  const [walletBalance, setWalletBalance] = useState<bigint>(0n)
  const [allowance, setAllowance] = useState<bigint>(0n)
  const [steps, setSteps] = useState<TransactionStep[]>([])

  // Resolve vault config from selectedVault id
  const vaultAddress = selectedVault
    ? VAULT_ID_TO_ADDRESS[selectedVault]
    : VAULT_ID_TO_ADDRESS.usdc
  const vaultConfig = getVaultConfig(vaultAddress)

  const token = selectedVault
    ? TOKENS[selectedVault.toUpperCase() as keyof typeof TOKENS]
    : TOKENS.USDC

  // Backend market data for live borrow APR
  const { data: vaultsData } = useVaults()
  const vaultSnapshot = vaultsData?.vaults.find(
    (v) => v.vaultAddress.toLowerCase() === vaultAddress?.toLowerCase()
  )
  const borrowAPR = computeBorrowAPR(vaultSnapshot?.utilization ?? 0)
  const isAboveKink = (vaultSnapshot?.utilization ?? 0) > 0.8

  // Backend position data
  const { positions, refetch: refetchPositions } = usePositions(address)
  const position = positions.find(
    (p) => p.vaultAddress.toLowerCase() === vaultAddress?.toLowerCase()
  )

  const totalDebt = position?.totalDebt ?? 0
  const borrowingPower = position?.borrowingPower ?? 0
  const healthFactor = position?.healthFactor ?? 0

  // Write hooks
  const {
    writeContract: borrow,
    data: borrowTxHash,
    isPending: isBorrowing,
    reset: resetBorrow,
    error: borrowError,
    isError: isBorrowError
  } = useWriteContract()

  const {
    writeContract: approve,
    data: approveTxHash,
    isPending: isApproving,
    reset: resetApprove,
    error: approveError,
    isError: isApproveError
  } = useWriteContract()

  const {
    writeContract: repay,
    data: repayTxHash,
    isPending: isRepaying,
    reset: resetRepay,
    error: repayError,
    isError: isRepayError
  } = useWriteContract()

  const { isSuccess: borrowSuccess } = useWaitForTransactionReceipt({
    hash: borrowTxHash
  })
  const { isSuccess: approveSuccess } = useWaitForTransactionReceipt({
    hash: approveTxHash
  })
  const { isSuccess: repaySuccess } = useWaitForTransactionReceipt({
    hash: repayTxHash
  })

  // Fetch wallet balance + allowance
  useEffect(() => {
    if (!address || !isConnected || !vaultConfig) return

    async function fetchBalances() {
      try {
        const [bal, allow] = await Promise.all([
          publicClient.readContract({
            address: vaultConfig!.loanAsset as `0x${string}`,
            abi: ERC20_ABI,
            functionName: "balanceOf",
            args: [address as `0x${string}`]
          }),
          publicClient.readContract({
            address: vaultConfig!.loanAsset as `0x${string}`,
            abi: ERC20_ABI,
            functionName: "allowance",
            args: [
              address as `0x${string}`,
              vaultConfig!.marketAddress as `0x${string}`
            ]
          })
        ])
        setWalletBalance(bal as bigint)
        setAllowance(allow as bigint)
      } catch (err) {
        console.error("[BorrowForm] Failed to fetch balances:", err)
      }
    }

    fetchBalances()
  }, [address, isConnected, vaultConfig, approveSuccess, repaySuccess])

  // Toast + reset on borrow success
  useEffect(() => {
    if (!borrowSuccess || !borrowTxHash) return
    const hash = borrowTxHash
    toast.success("Borrow confirmed!", {
      description: `${hash.slice(0, 10)}...${hash.slice(-8)}`,
      action: {
        label: "View on Etherscan",
        onClick: () =>
          window.open(`https://sepolia.etherscan.io/tx/${hash}`, "_blank"),
      },
      duration: 6000,
    })
    resetBorrow()
    setAmount("")
    triggerRefresh()
    setTimeout(() => refetchPositions(), 5000)
  }, [borrowSuccess, borrowTxHash, resetBorrow, triggerRefresh, refetchPositions])

  // Toast + reset on repay success
  useEffect(() => {
    if (!repaySuccess || !repayTxHash) return
    const hash = repayTxHash
    toast.success("Repay confirmed!", {
      description: `${hash.slice(0, 10)}...${hash.slice(-8)}`,
      action: {
        label: "View on Etherscan",
        onClick: () =>
          window.open(`https://sepolia.etherscan.io/tx/${hash}`, "_blank"),
      },
      duration: 6000,
    })
    resetApprove()
    resetRepay()
    setAmount("")
    triggerRefresh()
    setTimeout(() => refetchPositions(), 5000)
  }, [repaySuccess, repayTxHash, resetApprove, resetRepay, triggerRefresh, refetchPositions])

  // Toast on any transaction error
  useEffect(() => {
    const err = borrowError ?? approveError ?? repayError
    if (!err) return
    toast.error("Transaction failed", {
      description:
        (err as { shortMessage?: string })?.shortMessage ??
        err.message?.split("\n")[0],
    })
  }, [isBorrowError, isApproveError, isRepayError, borrowError, approveError, repayError])

  // Transaction steps for repay mode
  useEffect(() => {
    if (mode !== "repay" || !amount || !vaultConfig) return

    const parsedAmount = parseUnits(amount || "0", token.decimals)
    const needsApproval = parsedAmount > 0n && allowance < parsedAmount
    const newSteps: TransactionStep[] = []

    if (needsApproval) {
      newSteps.push({
        label: `Approve ${token.symbol}`,
        description: approveSuccess
          ? "Approval granted"
          : isApproving
            ? "Waiting..."
            : "Approve token transfer",
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
        description: "Already approved",
        status: "completed"
      })
    }

    if (parsedAmount > 0n) {
      newSteps.push({
        label: "Repay Debt",
        description: isRepaying ? "Repaying..." : "Repay loan",
        status: isRepaying ? "active" : "pending",
        txHash: repayTxHash
      })
    }

    setSteps(newSteps)
  }, [
    mode,
    amount,
    allowance,
    token,
    isApproving,
    approveSuccess,
    approveTxHash,
    isRepaying,
    repayTxHash,
    vaultConfig
  ])

  const handleBorrow = () => {
    if (!amount || !address || !vaultConfig) return
    const parsedAmount = parseUnits(amount, token.decimals)

    borrow({
      address: vaultConfig.marketAddress as `0x${string}`,
      abi: MARKET_ABI,
      functionName: "borrow",
      args: [parsedAmount]
    })
  }

  const handleRepay = () => {
    if (!amount || !address || !vaultConfig) return
    const parsedAmount = parseUnits(amount, token.decimals)

    // approveSuccess means we just approved this session — go straight to repay
    // even if the allowance refetch hasn't completed yet
    if (allowance >= parsedAmount || approveSuccess) {
      repay({
        address: vaultConfig.marketAddress as `0x${string}`,
        abi: MARKET_ABI,
        functionName: "repay",
        args: [parsedAmount]
      })
    } else {
      approve({
        address: vaultConfig.loanAsset as `0x${string}`,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [vaultConfig.marketAddress as `0x${string}`, maxUint256]
      })
    }
  }

  const handleRepayAll = () => {
    if (totalDebt <= 0) return
    setAmount(totalDebt.toFixed(token.decimals > 6 ? 6 : token.decimals))
  }

  const handleMax = () => {
    if (mode === "borrow") {
      setAmount(borrowingPower.toFixed(token.decimals > 6 ? 6 : token.decimals))
    } else {
      setAmount(formatUnits(walletBalance, token.decimals))
    }
  }

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
          Connect a wallet to borrow from markets and manage your debt.
        </p>
      </div>
    )
  }

  const parsedAmount = amount ? parseUnits(amount, token.decimals) : 0n
  const borrowExceedsLimit =
    mode === "borrow" && parseFloat(amount || "0") > borrowingPower
  const repayExceedsDebt =
    mode === "repay" && parseFloat(amount || "0") > totalDebt * 1.01 // 1% buffer for interest
  const hasError = borrowExceedsLimit || repayExceedsDebt
  const isProcessing = isBorrowing || isApproving || isRepaying

  let buttonText: string
  if (isBorrowing) buttonText = "Borrowing..."
  else if (isApproving) buttonText = "Approving..."
  else if (isRepaying) buttonText = "Repaying..."
  else if (approveSuccess && mode === "repay") buttonText = `Confirm Repay →`
  else if (mode === "borrow")
    buttonText = borrowingPower === 0 ? "Deposit Collateral First" : `Borrow ${token.symbol}`
  else buttonText = totalDebt === 0 ? "No Outstanding Debt" : `Repay ${token.symbol}`

  return (
    <div className='space-y-5'>
      {/* Mode Tabs */}
      <div className='flex bg-midnight-800/50 rounded-lg p-1 border border-midnight-700/50'>
        <button
          onClick={() => {
            setMode("borrow")
            setAmount("")
            setSteps([])
          }}
          className={`flex-1 flex items-center justify-center gap-2 py-2 text-xs font-medium rounded-md transition-all ${
            mode === "borrow"
              ? "bg-indigo-500/20 text-indigo-400 border border-indigo-500/20"
              : "text-slate-500 hover:text-slate-300"
          }`}
        >
          <ArrowDownToLine className='w-3.5 h-3.5' />
          Borrow
        </button>
        <button
          onClick={() => {
            setMode("repay")
            setAmount("")
            setSteps([])
          }}
          className={`flex-1 flex items-center justify-center gap-2 py-2 text-xs font-medium rounded-md transition-all ${
            mode === "repay"
              ? "bg-indigo-500/20 text-indigo-400 border border-indigo-500/20"
              : "text-slate-500 hover:text-slate-300"
          }`}
        >
          <ArrowUpFromLine className='w-3.5 h-3.5' />
          Repay
        </button>
      </div>

      {/* Position Summary from backend */}
      <div className='grid grid-cols-3 gap-2'>
        <div className='bg-midnight-800/40 rounded-lg p-3 border border-midnight-700/30'>
          <Tooltip
            content='Your outstanding debt including accrued interest. Interest compounds continuously based on the current borrow APR. Repay to reduce this and improve your health factor.'
            side='bottom'
            width='w-64'
          >
            <div className='text-[10px] text-slate-500 uppercase tracking-wider mb-1'>
              Debt
            </div>
          </Tooltip>
          <div className='text-sm font-mono text-white'>
            ~{totalDebt.toFixed(2)}
          </div>
          <div className='text-[10px] text-slate-600 mt-0.5'>
            {token.symbol}
          </div>
        </div>
        <div className='bg-midnight-800/40 rounded-lg p-3 border border-midnight-700/30'>
          <Tooltip
            content={
              "Maximum additional amount you can borrow without risking liquidation. " +
              "Formula: (Collateral Value × 85% LLTV) − Current Debt. " +
              "Deposit more collateral to increase this limit."
            }
            side='bottom'
            width='w-64'
          >
            <div className='text-[10px] text-slate-500 uppercase tracking-wider mb-1'>
              Available
            </div>
          </Tooltip>
          <div className='text-sm font-mono text-white'>
            {borrowingPower.toFixed(2)}
          </div>
          <div className='text-[10px] text-slate-600 mt-0.5'>
            {token.symbol}
          </div>
        </div>
        <div className='bg-midnight-800/40 rounded-lg p-3 border border-midnight-700/30'>
          <Tooltip
            content={
              "Health Factor = Collateral Value × 85% LLTV / Total Debt. " +
              "≥ 2.0 Safe · < 1.5 Warning · < 1.2 Danger · < 1.0 Liquidatable. " +
              "Interest accrues continuously, slowly reducing HF over time."
            }
            side='bottom'
            width='w-64'
          >
            <div className='text-[10px] text-slate-500 uppercase tracking-wider mb-1'>
              Health
            </div>
          </Tooltip>
          <div className='flex items-center h-[20px]'>
            <HealthFactorBadge value={healthFactor} />
          </div>
        </div>
      </div>

      {/* Borrow APR */}
      <div className='flex items-center justify-between px-3 py-2 rounded-lg bg-midnight-800/30 border border-midnight-700/30'>
        <Tooltip
          content={
            "Annual interest rate charged to borrowers. Jump Rate Model (same for all markets):\n" +
            "• Below 80% util: 2% + util × 4% (gradual)\n" +
            "• Above 80% util: 5.2% + (util − 80%) × 60% (sharp jump)\n" +
            "The jump incentivises repayment before the market reaches full utilization."
          }
          side='top'
          width='w-72'
        >
          <span className='text-[10px] text-slate-500 uppercase tracking-wider'>
            Borrow APR
          </span>
        </Tooltip>
        <div className='flex items-center gap-1.5'>
          <span
            className={`text-xs font-mono font-semibold ${isAboveKink ? "text-orange-400" : "text-white"}`}
          >
            {formatRate(borrowAPR)}
          </span>
          {isAboveKink && (
            <span className='text-[10px] text-orange-400 font-medium'>
              ↑ above kink
            </span>
          )}
        </div>
      </div>

      {/* Amount Input */}
      <div className='space-y-2'>
        <div className='flex items-center justify-between'>
          <label className='text-xs text-slate-400'>
            {mode === "borrow" ? "Borrow Amount" : "Repay Amount"}
          </label>
          <div className='flex items-center gap-2'>
            {mode === "repay" && totalDebt > 0 && (
              <button
                onClick={handleRepayAll}
                className='text-[10px] text-indigo-400 hover:text-indigo-300 transition-colors font-medium'
              >
                Repay All
              </button>
            )}
            <button
              onClick={handleMax}
              className='text-[10px] text-indigo-400 hover:text-indigo-300 transition-colors font-medium'
            >
              Max
            </button>
          </div>
        </div>

        <div
          className={`flex items-center gap-3 bg-midnight-800/50 border rounded-xl px-4 py-3 transition-colors ${
            hasError
              ? "border-red-500/50"
              : "border-midnight-700/50 focus-within:border-indigo-500/50"
          }`}
        >
          <TokenIcon symbol={token.symbol} size='sm' />
          <input
            type='number'
            placeholder='0.00'
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            className='flex-1 min-w-0 bg-transparent text-white placeholder-slate-600 text-sm outline-none font-mono'
          />
          <span className='shrink-0 text-slate-400 text-xs font-medium'>
            {token.symbol}
          </span>
        </div>

        {borrowExceedsLimit && (
          <div className='flex items-center gap-2 text-red-400 text-xs'>
            <AlertTriangle className='w-3 h-3' />
            Amount exceeds borrow limit ({borrowingPower.toFixed(2)}{" "}
            {token.symbol})
          </div>
        )}
        {repayExceedsDebt && (
          <div className='flex items-center gap-2 text-orange-400 text-xs'>
            <AlertTriangle className='w-3 h-3' />
            Amount exceeds current debt
          </div>
        )}
      </div>

      {/* Transaction Steps (repay mode) */}
      {mode === "repay" && steps.length > 0 && (
        <TransactionStepper steps={steps} />
      )}

      {/* Action Button */}
      <button
        onClick={mode === "borrow" ? handleBorrow : handleRepay}
        disabled={
          !amount ||
          parsedAmount === 0n ||
          hasError ||
          isProcessing ||
          (mode === "borrow" && borrowingPower === 0)
        }
        className='w-full py-3 px-4 rounded-xl text-sm font-semibold transition-all disabled:opacity-40 disabled:cursor-not-allowed bg-indigo-600 hover:bg-indigo-500 text-white shadow-[0_0_20px_rgba(79,70,229,0.2)] hover:shadow-[0_0_30px_rgba(79,70,229,0.4)]'
      >
        {isProcessing && <Spinner />}
        {buttonText}
      </button>

      {(totalDebt > 0 || borrowingPower > 0) && (
        <p className='text-[10px] text-slate-600 text-center'>
          Debt and health factor are approximate. Interest accrues continuously.
        </p>
      )}
    </div>
  )
}
