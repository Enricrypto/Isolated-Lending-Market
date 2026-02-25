import { createPublicClient, http } from "viem"
import { sepolia, mainnet } from "viem/chains"

const chain = process.env.CHAIN_ID === "1" ? mainnet : sepolia

export const client = createPublicClient({
  chain,
  transport: http(process.env.RPC_URL),
})

export const WAD = 18

export function normalize(raw: bigint, decimals: number): number {
  return Number(raw) / 10 ** decimals
}

export function denormalize(value: number, decimals: number): bigint {
  return BigInt(Math.round(value * 10 ** decimals))
}

export function formatUnits(value: bigint, decimals: number): string {
  const divisor = BigInt(10 ** decimals)
  const integerPart = value / divisor
  const fractionalPart = value % divisor

  if (fractionalPart === 0n) {
    return integerPart.toString()
  }

  const fractionalStr = fractionalPart.toString().padStart(decimals, "0")
  const trimmed = fractionalStr.replace(/0+$/, "")
  return `${integerPart}.${trimmed}`
}
