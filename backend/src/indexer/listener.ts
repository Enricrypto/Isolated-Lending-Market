/**
 * Event Log Processor
 * -------------------
 * Processes a single decoded MarketV1 event log.
 * Called by block-processor.ts after deterministic getLogs fetching.
 *
 * This replaces the previous watchContractEvent callback approach.
 * No polling, no raw WebSocket callbacks — purely driven by block-processor.
 */

import { computeAndSaveMarketSnapshot } from "./snapshot"
import { updateUserPosition } from "./position"
import { storeLiquidation } from "./liquidation"
import { logger } from "../lib/logger"

export interface MarketConfig {
  marketId: string
  vaultAddress: `0x${string}`
  marketAddress: `0x${string}`
  irmAddress: `0x${string}`
  oracleRouterAddress: `0x${string}`
  loanAsset: `0x${string}`
  loanAssetDecimals: number
}

export interface DecodedLog {
  eventName: string
  args: Record<string, unknown>
  transactionHash: `0x${string}`
  blockNumber: bigint
  logIndex: number
}

/**
 * Process a single decoded event log for a given market.
 * All operations are idempotent — safe to call multiple times for the same log.
 */
export async function processEventLog(log: DecodedLog, market: MarketConfig): Promise<void> {
  const { eventName, args } = log

  switch (eventName) {
    case "CollateralDeposited":
    case "CollateralWithdrawn": {
      const user = args.user as `0x${string}`
      logger.info(
        { event: eventName, user: user.slice(0, 10), block: Number(log.blockNumber) },
        "[listener] User collateral event"
      )
      await updateUserPosition(user, market.marketId, market.marketAddress)
      await computeAndSaveMarketSnapshot(market)
      break
    }

    case "Borrowed":
    case "Repaid": {
      const user = args.user as `0x${string}`
      logger.info(
        { event: eventName, user: user.slice(0, 10), block: Number(log.blockNumber) },
        "[listener] User borrow/repay event"
      )
      await updateUserPosition(user, market.marketId, market.marketAddress)
      await computeAndSaveMarketSnapshot(market)
      break
    }

    case "Liquidated": {
      const borrower   = args.borrower   as `0x${string}`
      const liquidator = args.liquidator as `0x${string}`
      logger.info(
        { borrower: borrower.slice(0, 10), liquidator: liquidator.slice(0, 10), block: Number(log.blockNumber) },
        "[listener] Liquidated event"
      )
      await storeLiquidation(market.marketId, {
        borrower,
        liquidator,
        debtCovered:       args.debtCovered      as bigint,
        collateralSeized:  args.collateralSeized  as bigint,
        badDebt:           args.badDebt           as bigint,
        txHash:            log.transactionHash,
        blockNumber:       log.blockNumber,
        logIndex:          log.logIndex,
        loanAssetDecimals: market.loanAssetDecimals,
      })
      await updateUserPosition(borrower, market.marketId, market.marketAddress)
      await computeAndSaveMarketSnapshot(market)
      break
    }

    case "GlobalBorrowIndexUpdated": {
      logger.info(
        { block: Number(log.blockNumber) },
        "[listener] GlobalBorrowIndexUpdated — snapshotting market"
      )
      await computeAndSaveMarketSnapshot(market)
      break
    }

    default:
      break
  }
}
