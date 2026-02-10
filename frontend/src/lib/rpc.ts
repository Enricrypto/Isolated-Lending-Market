import { createPublicClient, http } from "viem";
import { sepolia, mainnet } from "viem/chains";

// Determine chain based on environment
const chain = process.env.CHAIN_ID === "1" ? mainnet : sepolia;

// Create the public client for RPC calls
export const client = createPublicClient({
  chain,
  transport: http(process.env.RPC_URL),
});

// --- Decimal Normalization Helpers ---

// WAD constant (18 decimals) — used by IRM rates, oracle confidence/deviation
export const WAD = 18;

// Convert raw BigInt to human-readable number.
// e.g. normalize(1500000000n, 6) → 1500.0  (USDC with 6 decimals)
// e.g. normalize(800000000000000000n, WAD) → 0.8  (80% utilization)
export function normalize(raw: bigint, decimals: number): number {
  return Number(raw) / 10 ** decimals;
}

// Convert human-readable number back to raw BigInt.
// e.g. denormalize(1500.0, 6) → 1500000000n
export function denormalize(value: number, decimals: number): bigint {
  return BigInt(Math.round(value * 10 ** decimals));
}

// Helper to format bigint values for display (string output with full precision)
export function formatUnits(value: bigint, decimals: number): string {
  const divisor = BigInt(10 ** decimals);
  const integerPart = value / divisor;
  const fractionalPart = value % divisor;

  if (fractionalPart === 0n) {
    return integerPart.toString();
  }

  const fractionalStr = fractionalPart.toString().padStart(decimals, "0");
  // Trim trailing zeros
  const trimmed = fractionalStr.replace(/0+$/, "");
  return `${integerPart}.${trimmed}`;
}
