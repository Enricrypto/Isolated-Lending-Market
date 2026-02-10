"use client";

import { useState, useEffect } from "react";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { parseUnits, formatUnits, maxUint256 } from "viem";
import { createPublicClient, http } from "viem";
import { sepolia } from "viem/chains";
import { SEPOLIA_ADDRESSES, TOKENS } from "@/lib/addresses";
import { ERC20_ABI, VAULT_ABI } from "@/lib/contracts";
import { useAppStore } from "@/store/useAppStore";
import {
  TransactionStepper,
  type TransactionStep,
} from "./TransactionStepper";
import { Wallet, ArrowDownToLine, ArrowUpFromLine, Info } from "lucide-react";
import { TokenIcon } from "@/components/TokenIcon";

const client = createPublicClient({
  chain: sepolia,
  transport: http(process.env.NEXT_PUBLIC_RPC_URL || "https://eth-sepolia.g.alchemy.com/v2/demo"),
});

type TabMode = "deposit" | "withdraw";

export function DepositForm() {
  const { address, isConnected } = useAccount();
  const { selectedVault } = useAppStore();
  const [mode, setMode] = useState<TabMode>("deposit");
  const [amount, setAmount] = useState("");
  const [balance, setBalance] = useState<bigint>(0n);
  const [vaultBalance, setVaultBalance] = useState<bigint>(0n);
  const [allowance, setAllowance] = useState<bigint>(0n);
  const [steps, setSteps] = useState<TransactionStep[]>([]);

  // Get token info based on selected vault
  const token = selectedVault
    ? TOKENS[selectedVault.toUpperCase() as keyof typeof TOKENS]
    : TOKENS.USDC;

  // Write hooks
  const {
    writeContract: approve,
    data: approveTxHash,
    isPending: isApproving,
  } = useWriteContract();

  const {
    writeContract: deposit,
    data: depositTxHash,
    isPending: isDepositing,
  } = useWriteContract();

  const {
    writeContract: withdraw,
    data: withdrawTxHash,
    isPending: isWithdrawing,
  } = useWriteContract();

  // Wait for tx receipts
  const { isSuccess: approveSuccess } = useWaitForTransactionReceipt({
    hash: approveTxHash,
  });
  const { isSuccess: depositSuccess } = useWaitForTransactionReceipt({
    hash: depositTxHash,
  });
  const { isSuccess: withdrawSuccess } = useWaitForTransactionReceipt({
    hash: withdrawTxHash,
  });

  // Fetch balances
  useEffect(() => {
    if (!address || !isConnected) return;

    async function fetchBalances() {
      try {
        const [bal, vBal, allow] = await Promise.all([
          client.readContract({
            address: token.address as `0x${string}`,
            abi: ERC20_ABI,
            functionName: "balanceOf",
            args: [address as `0x${string}`],
          }),
          client.readContract({
            address: SEPOLIA_ADDRESSES.vault as `0x${string}`,
            abi: VAULT_ABI,
            functionName: "balanceOf",
            args: [address as `0x${string}`],
          }),
          client.readContract({
            address: token.address as `0x${string}`,
            abi: ERC20_ABI,
            functionName: "allowance",
            args: [
              address as `0x${string}`,
              SEPOLIA_ADDRESSES.vault as `0x${string}`,
            ],
          }),
        ]);

        setBalance(bal as bigint);
        setVaultBalance(vBal as bigint);
        setAllowance(allow as bigint);
      } catch (err) {
        console.error("Failed to fetch balances:", err);
      }
    }

    fetchBalances();
  }, [address, isConnected, token.address, approveSuccess, depositSuccess, withdrawSuccess]);

  // Update steps based on transaction state
  useEffect(() => {
    if (mode === "deposit") {
      const parsedAmount = amount
        ? parseUnits(amount, token.decimals)
        : 0n;
      const needsApproval = parsedAmount > 0n && allowance < parsedAmount;

      const newSteps: TransactionStep[] = [];

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
          txHash: approveTxHash,
        });
      } else if (parsedAmount > 0n) {
        newSteps.push({
          label: `Approve ${token.symbol}`,
          description: "Infinite approval granted",
          status: "completed",
        });
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
            : approveSuccess || allowance >= parsedAmount
            ? "pending"
            : "pending",
          txHash: depositTxHash,
        });
      }

      setSteps(newSteps);
    }
  }, [
    mode,
    amount,
    allowance,
    token,
    isApproving,
    approveSuccess,
    approveTxHash,
    isDepositing,
    depositSuccess,
    depositTxHash,
  ]);

  const handleDeposit = () => {
    if (!amount || !address) return;
    const parsedAmount = parseUnits(amount, token.decimals);

    if (allowance < parsedAmount) {
      // Need approval first
      approve({
        address: token.address as `0x${string}`,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [SEPOLIA_ADDRESSES.vault as `0x${string}`, maxUint256],
      });
    } else {
      // Deposit directly
      deposit({
        address: SEPOLIA_ADDRESSES.vault as `0x${string}`,
        abi: VAULT_ABI,
        functionName: "deposit",
        args: [parsedAmount, address as `0x${string}`],
      });
    }
  };

  // Auto-deposit after approval
  useEffect(() => {
    if (approveSuccess && amount && address) {
      const parsedAmount = parseUnits(amount, token.decimals);
      deposit({
        address: SEPOLIA_ADDRESSES.vault as `0x${string}`,
        abi: VAULT_ABI,
        functionName: "deposit",
        args: [parsedAmount, address as `0x${string}`],
      });
    }
  }, [approveSuccess]);

  const handleWithdraw = () => {
    if (!amount || !address) return;
    const parsedAmount = parseUnits(amount, token.decimals);

    withdraw({
      address: SEPOLIA_ADDRESSES.vault as `0x${string}`,
      abi: VAULT_ABI,
      functionName: "withdraw",
      args: [
        parsedAmount,
        address as `0x${string}`,
        address as `0x${string}`,
      ],
    });
  };

  const handleMax = () => {
    if (mode === "deposit") {
      setAmount(formatUnits(balance, token.decimals));
    } else {
      setAmount(formatUnits(vaultBalance, token.decimals));
    }
  };

  // Projected weekly yield (simple calculation)
  const projectedWeeklyYield = amount
    ? (parseFloat(amount) * 0.0524 * 7) / 365
    : 0;

  if (!isConnected) {
    return (
      <div className="flex flex-col items-center justify-center py-12 px-6 text-center">
        <div className="w-12 h-12 rounded-full bg-indigo-500/10 flex items-center justify-center mb-4">
          <Wallet className="w-6 h-6 text-indigo-400" />
        </div>
        <h4 className="text-sm font-medium text-white mb-2">
          Connect Your Wallet
        </h4>
        <p className="text-xs text-slate-500 max-w-[200px]">
          Connect a wallet to deposit into vaults and manage your positions.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-5">
      {/* Mode Tabs */}
      <div className="flex bg-midnight-800/50 rounded-lg p-1 border border-midnight-700/50">
        <button
          onClick={() => setMode("deposit")}
          className={`flex-1 flex items-center justify-center gap-2 py-2 text-xs font-medium rounded-md transition-all ${
            mode === "deposit"
              ? "bg-indigo-500/20 text-indigo-400 border border-indigo-500/20"
              : "text-slate-500 hover:text-slate-300"
          }`}
        >
          <ArrowDownToLine className="w-3.5 h-3.5" />
          Deposit
        </button>
        <button
          onClick={() => setMode("withdraw")}
          className={`flex-1 flex items-center justify-center gap-2 py-2 text-xs font-medium rounded-md transition-all ${
            mode === "withdraw"
              ? "bg-indigo-500/20 text-indigo-400 border border-indigo-500/20"
              : "text-slate-500 hover:text-slate-300"
          }`}
        >
          <ArrowUpFromLine className="w-3.5 h-3.5" />
          Withdraw
        </button>
      </div>

      {/* Balance display */}
      <div className="flex items-center justify-between text-xs">
        <span className="text-slate-500">
          {mode === "deposit" ? "Wallet Balance" : "Vault Balance"}
        </span>
        <span className="text-slate-300 font-mono">
          {mode === "deposit"
            ? formatUnits(balance, token.decimals)
            : formatUnits(vaultBalance, token.decimals)}{" "}
          {token.symbol}
        </span>
      </div>

      {/* Amount Input */}
      <div className="bg-midnight-900 border border-midnight-700/50 rounded-xl p-4">
        <div className="flex items-center justify-between mb-2">
          <span className="text-[10px] text-slate-500 uppercase tracking-wider font-bold">
            Amount
          </span>
          <button
            onClick={handleMax}
            className="text-[10px] text-indigo-400 hover:text-indigo-300 font-bold uppercase tracking-wider"
          >
            MAX
          </button>
        </div>
        <div className="flex items-center gap-3">
          <input
            type="number"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0.00"
            className="flex-1 bg-transparent text-2xl font-mono font-medium text-white placeholder-slate-700 outline-none"
          />
          <div
            className="flex items-center gap-2 px-3 py-1.5 rounded-xl border border-midnight-700/50"
            style={{ backgroundColor: `${token.color}10` }}
          >
            <TokenIcon symbol={token.symbol} size={18} />
            <span className="text-sm font-medium text-slate-300">
              {token.symbol}
            </span>
          </div>
        </div>
      </div>

      {/* Projected Yield */}
      {mode === "deposit" && amount && parseFloat(amount) > 0 && (
        <div className="flex items-center justify-between px-4 py-3 bg-emerald-500/5 border border-emerald-500/10 rounded-lg">
          <div className="flex items-center gap-2">
            <Info className="w-3.5 h-3.5 text-emerald-400" />
            <span className="text-xs text-emerald-400">
              Projected Weekly Yield
            </span>
          </div>
          <span className="text-xs font-mono font-medium text-emerald-300">
            +{projectedWeeklyYield.toFixed(4)} {token.symbol}
          </span>
        </div>
      )}

      {/* Transaction Steps */}
      {steps.length > 0 && (
        <div className="px-1">
          <TransactionStepper steps={steps} />
        </div>
      )}

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
        className="w-full py-3 bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-medium rounded-xl transition-all disabled:opacity-50 disabled:cursor-not-allowed shadow-[0_0_20px_rgba(79,70,229,0.2)] hover:shadow-[0_0_30px_rgba(79,70,229,0.4)]"
      >
        {isApproving
          ? "Approving..."
          : isDepositing
          ? "Depositing..."
          : isWithdrawing
          ? "Withdrawing..."
          : depositSuccess || withdrawSuccess
          ? "Transaction Complete"
          : mode === "deposit"
          ? "Confirm Deposit"
          : "Confirm Withdrawal"}
      </button>

      {/* Gas Estimate */}
      <div className="flex items-center justify-center gap-1 text-[10px] text-slate-600">
        <span>Est. gas: ~0.002 ETH</span>
        <span>•</span>
        <span>Sepolia Testnet</span>
      </div>
    </div>
  );
}
