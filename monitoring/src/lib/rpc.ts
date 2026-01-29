import { createPublicClient, http } from "viem";
import { sepolia, mainnet } from "viem/chains";

// Determine chain based on environment
const chain = process.env.CHAIN_ID === "1" ? mainnet : sepolia;

// Create the public client for RPC calls
export const client = createPublicClient({
  chain,
  transport: http(process.env.RPC_URL),
});

// Helper to format bigint values for display
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

// Convert 18-decimal bigint to number (for percentages, ratios)
export function toNumber(value: bigint, decimals: number = 18): number {
  return Number(value) / 10 ** decimals;
}

// Convert number to 18-decimal bigint
export function toBigInt(value: number, decimals: number = 18): bigint {
  return BigInt(Math.floor(value * 10 ** decimals));
}
