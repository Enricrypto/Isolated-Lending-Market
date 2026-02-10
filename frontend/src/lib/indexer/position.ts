/**
 * User Position Tracker
 * ---------------------
 * Reads getUserPosition() from MarketV1 and persists a UserPositionSnapshot.
 * Called on each user-facing event (deposit, withdraw, borrow, repay, liquidation).
 */

import { client, normalize, WAD } from "../rpc"
import { MARKET_ABI } from "../contracts"
import { prisma } from "../db"

export async function updateUserPosition(
  userAddress: `0x${string}`,
  marketId: string,
  marketAddress: `0x${string}`
) {
  const result = await client.readContract({
    address: marketAddress,
    abi: MARKET_ABI,
    functionName: "getUserPosition",
    args: [userAddress],
  })

  const pos = result as {
    collateralValue: bigint
    totalDebt: bigint
    healthFactor: bigint
    borrowingPower: bigint
  }

  return prisma.userPositionSnapshot.create({
    data: {
      userAddress,
      marketId,
      collateralValue: normalize(pos.collateralValue, WAD).toFixed(6),
      totalDebt: normalize(pos.totalDebt, WAD).toFixed(6),
      healthFactor: normalize(pos.healthFactor, WAD).toFixed(6),
      borrowingPower: normalize(pos.borrowingPower, WAD).toFixed(6),
    },
  })
}
