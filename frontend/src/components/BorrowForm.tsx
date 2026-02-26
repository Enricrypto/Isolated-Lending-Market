"use client";

import { useState, useEffect } from "react";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { parseUnits, formatUnits, maxUint256 } from "viem";
import { createPublicClient, http } from "viem";
import { sepolia } from "viem/chains";
import { ERC20_ABI, MARKET_ABI } from "@/lib/contracts";
import { useAppStore } from "@/store/useAppStore";
import { usePositions } from "@/hooks/usePositions";
import { useVaults } from "@/hooks/useVaults";
import { getVaultConfig } from "@/lib/vault-registry";
import { TOKENS } from "@/lib/addresses";
import { computeBorrowAPR, formatRate } from "@/lib/irm";
import { Tooltip } from "@/components/Tooltip";
import {
  TransactionStepper,
  type TransactionStep,
} from "./TransactionStepper";
import { Wallet, ArrowDownToLine, ArrowUpFromLine, AlertTriangle } from "lucide-react";
import { TokenIcon } from "@/components/TokenIcon";

const publicClient = createPublicClient({
  chain: sepolia,
  transport: http(process.env.NEXT_PUBLIC_RPC_URL || "https://eth-sepolia.g.alchemy.com/v2/demo"),
});

// Map store VaultId to vault address
const VAULT_ID_TO_ADDRESS: Record<string, string> = {
  usdc: "0xE8323c3d293f81C71232023367Bada21137C055E",
  weth: "0xbbc4c7FbCcF0faa27821c4F44C01D3F81C088070",
  wbtc: "0xBCB5fcA37f87a97eB1C5d6c9a92749e0F41161f0",
};

type TabMode = "borrow" | "repay";

function HealthFactorBadge({ value }: { value: number }) {
  if (value === 0) {
    return <span className="text-slate-500 text-xs">No debt</span>;
  }
  const color =
    value >= 2.0
      ? "text-emerald-400"
      : value >= 1.5
      ? "text-yellow-400"
      : value >= 1.2
      ? "text-orange-400"
      : "text-red-400";
  return (
    <span className={`text-xs font-mono font-semibold ${color}`}>
      {value.toFixed(2)}
    </span>
  );
}

export function BorrowForm() {
  const { address, isConnected } = useAccount();
  const { selectedVault } = useAppStore();
  const [mode, setMode] = useState<TabMode>("borrow");
  const [amount, setAmount] = useState("");
  const [walletBalance, setWalletBalance] = useState<bigint>(0n);
  const [allowance, setAllowance] = useState<bigint>(0n);
  const [steps, setSteps] = useState<TransactionStep[]>([]);

  // Resolve vault config from selectedVault id
  const vaultAddress = selectedVault ? VAULT_ID_TO_ADDRESS[selectedVault] : VAULT_ID_TO_ADDRESS.usdc;
  const vaultConfig = getVaultConfig(vaultAddress);

  const token = selectedVault
    ? TOKENS[selectedVault.toUpperCase() as keyof typeof TOKENS]
    : TOKENS.USDC;

  // Backend market data for live borrow APR
  const { data: vaultsData } = useVaults();
  const vaultSnapshot = vaultsData?.vaults.find(
    (v) => v.vaultAddress.toLowerCase() === vaultAddress?.toLowerCase()
  );
  const borrowAPR = computeBorrowAPR(vaultSnapshot?.utilization ?? 0);
  const isAboveKink = (vaultSnapshot?.utilization ?? 0) > 0.80;

  // Backend position data
  const { positions, refetch: refetchPositions } = usePositions(address);
  const position = positions.find(
    (p) => p.vaultAddress.toLowerCase() === vaultAddress?.toLowerCase()
  );

  const totalDebt = position?.totalDebt ?? 0;
  const borrowingPower = position?.borrowingPower ?? 0;
  const healthFactor = position?.healthFactor ?? 0;

  // Write hooks
  const {
    writeContract: borrow,
    data: borrowTxHash,
    isPending: isBorrowing,
  } = useWriteContract();

  const {
    writeContract: approve,
    data: approveTxHash,
    isPending: isApproving,
  } = useWriteContract();

  const {
    writeContract: repay,
    data: repayTxHash,
    isPending: isRepaying,
  } = useWriteContract();

  const { isSuccess: borrowSuccess } = useWaitForTransactionReceipt({ hash: borrowTxHash });
  const { isSuccess: approveSuccess } = useWaitForTransactionReceipt({ hash: approveTxHash });
  const { isSuccess: repaySuccess } = useWaitForTransactionReceipt({ hash: repayTxHash });

  // Fetch wallet balance + allowance (chain reads — wallet state only)
  useEffect(() => {
    if (!address || !isConnected || !vaultConfig) return;

    async function fetchBalances() {
      try {
        const [bal, allow] = await Promise.all([
          publicClient.readContract({
            address: vaultConfig!.loanAsset as `0x${string}`,
            abi: ERC20_ABI,
            functionName: "balanceOf",
            args: [address as `0x${string}`],
          }),
          publicClient.readContract({
            address: vaultConfig!.loanAsset as `0x${string}`,
            abi: ERC20_ABI,
            functionName: "allowance",
            args: [address as `0x${string}`, vaultConfig!.marketAddress as `0x${string}`],
          }),
        ]);
        setWalletBalance(bal as bigint);
        setAllowance(allow as bigint);
      } catch (err) {
        console.error("[BorrowForm] Failed to fetch balances:", err);
      }
    }

    fetchBalances();
  }, [address, isConnected, vaultConfig, approveSuccess, repaySuccess]);

  // Auto-repay after approval
  useEffect(() => {
    if (approveSuccess && amount && address && vaultConfig) {
      const parsedAmount = parseUnits(amount, token.decimals);
      repay({
        address: vaultConfig.marketAddress as `0x${string}`,
        abi: MARKET_ABI,
        functionName: "repay",
        args: [parsedAmount],
      });
    }
  }, [approveSuccess]);

  // Refresh backend position after borrow/repay confirmed
  useEffect(() => {
    if (borrowSuccess || repaySuccess) {
      setAmount("");
      // Backend will update within 12 blocks (~2min on Sepolia)
      // Trigger an optimistic refresh after a short delay
      setTimeout(() => refetchPositions(), 5000);
    }
  }, [borrowSuccess, repaySuccess]);

  // Transaction steps for repay mode
  useEffect(() => {
    if (mode !== "repay" || !amount || !vaultConfig) return;

    const parsedAmount = parseUnits(amount || "0", token.decimals);
    const needsApproval = parsedAmount > 0n && allowance < parsedAmount;
    const newSteps: TransactionStep[] = [];

    if (needsApproval) {
      newSteps.push({
        label: `Approve ${token.symbol}`,
        description: approveSuccess ? "Approval granted" : isApproving ? "Waiting..." : "Approve token transfer",
        status: approveSuccess ? "completed" : isApproving ? "active" : "pending",
        txHash: approveTxHash,
      });
    } else if (parsedAmount > 0n) {
      newSteps.push({
        label: `Approve ${token.symbol}`,
        description: "Already approved",
        status: "completed",
      });
    }

    if (parsedAmount > 0n) {
      newSteps.push({
        label: "Repay Debt",
        description: repaySuccess ? "Repay confirmed" : isRepaying ? "Repaying..." : "Repay loan",
        status: repaySuccess ? "completed" : isRepaying ? "active" : "pending",
        txHash: repayTxHash,
      });
    }

    setSteps(newSteps);
  }, [mode, amount, allowance, token, isApproving, approveSuccess, approveTxHash, isRepaying, repaySuccess, repayTxHash, vaultConfig]);

  const handleBorrow = () => {
    if (!amount || !address || !vaultConfig) return;
    const parsedAmount = parseUnits(amount, token.decimals);

    borrow({
      address: vaultConfig.marketAddress as `0x${string}`,
      abi: MARKET_ABI,
      functionName: "borrow",
      args: [parsedAmount],
    });
  };

  const handleRepay = () => {
    if (!amount || !address || !vaultConfig) return;
    const parsedAmount = parseUnits(amount, token.decimals);

    if (allowance < parsedAmount) {
      approve({
        address: vaultConfig.loanAsset as `0x${string}`,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [vaultConfig.marketAddress as `0x${string}`, maxUint256],
      });
    } else {
      repay({
        address: vaultConfig.marketAddress as `0x${string}`,
        abi: MARKET_ABI,
        functionName: "repay",
        args: [parsedAmount],
      });
    }
  };

  const handleRepayAll = () => {
    if (totalDebt <= 0) return;
    setAmount(totalDebt.toFixed(token.decimals > 6 ? 6 : token.decimals));
  };

  const handleMax = () => {
    if (mode === "borrow") {
      setAmount(borrowingPower.toFixed(token.decimals > 6 ? 6 : token.decimals));
    } else {
      setAmount(formatUnits(walletBalance, token.decimals));
    }
  };

  if (!isConnected) {
    return (
      <div className="flex flex-col items-center justify-center py-12 px-6 text-center">
        <div className="w-12 h-12 rounded-full bg-indigo-500/10 flex items-center justify-center mb-4">
          <Wallet className="w-6 h-6 text-indigo-400" />
        </div>
        <h4 className="text-sm font-medium text-white mb-2">Connect Your Wallet</h4>
        <p className="text-xs text-slate-500 max-w-[200px]">
          Connect a wallet to borrow from markets and manage your debt.
        </p>
      </div>
    );
  }

  const parsedAmount = amount ? parseUnits(amount, token.decimals) : 0n;
  const borrowExceedsLimit = mode === "borrow" && parseFloat(amount || "0") > borrowingPower;
  const repayExceedsDebt = mode === "repay" && parseFloat(amount || "0") > totalDebt * 1.01; // 1% buffer for interest
  const hasError = borrowExceedsLimit || repayExceedsDebt;

  return (
    <div className="space-y-5">
      {/* Mode Tabs */}
      <div className="flex bg-midnight-800/50 rounded-lg p-1 border border-midnight-700/50">
        <button
          onClick={() => { setMode("borrow"); setAmount(""); setSteps([]); }}
          className={`flex-1 flex items-center justify-center gap-2 py-2 text-xs font-medium rounded-md transition-all ${
            mode === "borrow"
              ? "bg-indigo-500/20 text-indigo-400 border border-indigo-500/20"
              : "text-slate-500 hover:text-slate-300"
          }`}
        >
          <ArrowDownToLine className="w-3.5 h-3.5" />
          Borrow
        </button>
        <button
          onClick={() => { setMode("repay"); setAmount(""); setSteps([]); }}
          className={`flex-1 flex items-center justify-center gap-2 py-2 text-xs font-medium rounded-md transition-all ${
            mode === "repay"
              ? "bg-indigo-500/20 text-indigo-400 border border-indigo-500/20"
              : "text-slate-500 hover:text-slate-300"
          }`}
        >
          <ArrowUpFromLine className="w-3.5 h-3.5" />
          Repay
        </button>
      </div>

      {/* Position Summary from backend */}
      <div className="grid grid-cols-3 gap-2">
        <div className="bg-midnight-800/40 rounded-lg p-3 border border-midnight-700/30">
          <Tooltip
            content="Your outstanding debt including accrued interest. Interest compounds continuously based on the current borrow APR. Repay to reduce this and improve your health factor."
            side="bottom"
            width="w-64"
          >
            <div className="text-[10px] text-slate-500 uppercase tracking-wider mb-1">Debt</div>
          </Tooltip>
          <div className="text-sm font-mono text-white">
            ~{totalDebt.toFixed(2)}
          </div>
          <div className="text-[10px] text-slate-600 mt-0.5">{token.symbol}</div>
        </div>
        <div className="bg-midnight-800/40 rounded-lg p-3 border border-midnight-700/30">
          <Tooltip
            content={
              "Maximum additional amount you can borrow without risking liquidation. " +
              "Formula: (Collateral Value × 85% LLTV) − Current Debt. " +
              "Deposit more collateral to increase this limit."
            }
            side="bottom"
            width="w-64"
          >
            <div className="text-[10px] text-slate-500 uppercase tracking-wider mb-1">Available</div>
          </Tooltip>
          <div className="text-sm font-mono text-white">
            {borrowingPower.toFixed(2)}
          </div>
          <div className="text-[10px] text-slate-600 mt-0.5">{token.symbol}</div>
        </div>
        <div className="bg-midnight-800/40 rounded-lg p-3 border border-midnight-700/30">
          <Tooltip
            content={
              "Health Factor = Collateral Value × 85% LLTV / Total Debt. " +
              "≥ 2.0 Safe · < 1.5 Warning · < 1.2 Danger · < 1.0 Liquidatable. " +
              "Interest accrues continuously, slowly reducing HF over time."
            }
            side="bottom"
            width="w-64"
          >
            <div className="text-[10px] text-slate-500 uppercase tracking-wider mb-1">Health</div>
          </Tooltip>
          <div className="flex items-center h-[20px]">
            <HealthFactorBadge value={healthFactor} />
          </div>
        </div>
      </div>

      {/* Borrow APR */}
      <div className="flex items-center justify-between px-3 py-2 rounded-lg bg-midnight-800/30 border border-midnight-700/30">
        <Tooltip
          content={
            "Annual interest rate charged to borrowers. Jump Rate Model (same for all markets):\n" +
            "• Below 80% util: 2% + util × 4% (gradual)\n" +
            "• Above 80% util: 5.2% + (util − 80%) × 60% (sharp jump)\n" +
            "The jump incentivises repayment before the market reaches full utilization."
          }
          side="top"
          width="w-72"
        >
          <span className="text-[10px] text-slate-500 uppercase tracking-wider">Borrow APR</span>
        </Tooltip>
        <div className="flex items-center gap-1.5">
          <span className={`text-xs font-mono font-semibold ${isAboveKink ? "text-orange-400" : "text-white"}`}>
            {formatRate(borrowAPR)}
          </span>
          {isAboveKink && (
            <span className="text-[10px] text-orange-400 font-medium">↑ above kink</span>
          )}
        </div>
      </div>

      {/* Amount Input */}
      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <label className="text-xs text-slate-400">
            {mode === "borrow" ? "Borrow Amount" : "Repay Amount"}
          </label>
          <div className="flex items-center gap-2">
            {mode === "repay" && totalDebt > 0 && (
              <button
                onClick={handleRepayAll}
                className="text-[10px] text-indigo-400 hover:text-indigo-300 transition-colors font-medium"
              >
                Repay All
              </button>
            )}
            <button
              onClick={handleMax}
              className="text-[10px] text-indigo-400 hover:text-indigo-300 transition-colors font-medium"
            >
              Max
            </button>
          </div>
        </div>

        <div className={`flex items-center gap-3 bg-midnight-800/50 border rounded-xl px-4 py-3 transition-colors ${
          hasError ? "border-red-500/50" : "border-midnight-700/50 focus-within:border-indigo-500/50"
        }`}>
          <TokenIcon symbol={token.symbol} size="sm" />
          <input
            type="number"
            placeholder="0.00"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            className="flex-1 bg-transparent text-white placeholder-slate-600 text-sm outline-none font-mono"
          />
          <span className="text-slate-400 text-xs font-medium">{token.symbol}</span>
        </div>

        {borrowExceedsLimit && (
          <div className="flex items-center gap-2 text-red-400 text-xs">
            <AlertTriangle className="w-3 h-3" />
            Amount exceeds borrow limit ({borrowingPower.toFixed(2)} {token.symbol})
          </div>
        )}
        {repayExceedsDebt && (
          <div className="flex items-center gap-2 text-orange-400 text-xs">
            <AlertTriangle className="w-3 h-3" />
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
          isBorrowing ||
          isApproving ||
          isRepaying ||
          (mode === "borrow" && borrowingPower === 0)
        }
        className="w-full py-3 px-4 rounded-xl text-sm font-semibold transition-all disabled:opacity-40 disabled:cursor-not-allowed bg-indigo-600 hover:bg-indigo-500 text-white"
      >
        {mode === "borrow"
          ? isBorrowing
            ? "Borrowing..."
            : borrowSuccess
            ? "Borrowed ✓"
            : borrowingPower === 0
            ? "Deposit Collateral First"
            : `Borrow ${token.symbol}`
          : isApproving
          ? "Approving..."
          : isRepaying
          ? "Repaying..."
          : repaySuccess
          ? "Repaid ✓"
          : totalDebt === 0
          ? "No Outstanding Debt"
          : `Repay ${token.symbol}`}
      </button>

      {/* Staleness notice */}
      {(borrowSuccess || repaySuccess) && (
        <p className="text-[10px] text-slate-500 text-center">
          Position updating... reflects on-chain in ~2 min (12 block confirmations).
        </p>
      )}

      {(totalDebt > 0 || borrowingPower > 0) && (
        <p className="text-[10px] text-slate-600 text-center">
          Debt and health factor are approximate. Interest accrues continuously.
        </p>
      )}
    </div>
  );
}
