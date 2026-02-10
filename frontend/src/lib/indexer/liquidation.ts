/**
 * Liquidation Recorder
 * --------------------
 * Stores a LiquidationEvent from the Liquidated event emitted by MarketV1.
 */

import { normalize, WAD } from "../rpc"
import { prisma } from "../db"

interface LiquidationLog {
  borrower: `0x${string}`
  liquidator: `0x${string}`
  debtCovered: bigint
  collateralSeized: bigint
  badDebt: bigint
  txHash: `0x${string}`
  blockNumber: bigint
  logIndex: number
  loanAssetDecimals: number
}

export async function storeLiquidation(marketId: string, log: LiquidationLog) {
  const d = log.loanAssetDecimals

  return prisma.liquidationEvent.upsert({
    where: {
      txHash_logIndex: {
        txHash: log.txHash,
        logIndex: log.logIndex,
      },
    },
    update: {},
    create: {
      marketId,
      txHash: log.txHash,
      blockNumber: Number(log.blockNumber),
      logIndex: log.logIndex,
      borrower: log.borrower,
      liquidator: log.liquidator,
      debtCovered: normalize(log.debtCovered, d).toFixed(6),
      collateralSeized: normalize(log.collateralSeized, WAD).toFixed(6),
      badDebt: normalize(log.badDebt, d).toFixed(6),
    },
  })
}
