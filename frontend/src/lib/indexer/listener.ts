/**
 * Event Listener
 * --------------
 * Subscribes to MarketV1 contract events using viem's watchContractEvent.
 * Works over HTTP (polling-based) — no websocket URL required.
 *
 * On each event:
 *  - Updates the affected user's position snapshot
 *  - Triggers a market snapshot recomputation
 *  - On Liquidated events, also stores a LiquidationEvent record
 */

import { client } from "../rpc"
import { MARKET_EVENTS_ABI } from "./events"
import { computeAndSaveMarketSnapshot } from "./snapshot"
import { updateUserPosition } from "./position"
import { storeLiquidation } from "./liquidation"
import type { WatchContractEventReturnType, Log } from "viem"

interface MarketConfig {
  marketId: string
  vaultAddress: `0x${string}`
  marketAddress: `0x${string}`
  irmAddress: `0x${string}`
  oracleRouterAddress: `0x${string}`
  loanAsset: `0x${string}`
  loanAssetDecimals: number
}

type EventHandler = (logs: Log[]) => void

export function watchMarketEvents(
  market: MarketConfig,
  pollingInterval = 15_000
): WatchContractEventReturnType {
  const marketAddresses = {
    marketId: market.marketId,
    vaultAddress: market.vaultAddress,
    marketAddress: market.marketAddress,
    irmAddress: market.irmAddress,
    oracleRouterAddress: market.oracleRouterAddress,
    loanAsset: market.loanAsset,
    loanAssetDecimals: market.loanAssetDecimals,
  }

  async function handleUserEvent(user: `0x${string}`, eventName: string) {
    console.log(`[indexer] ${eventName} from ${user.slice(0, 8)}...`)
    try {
      await updateUserPosition(user, market.marketId, market.marketAddress)
      await computeAndSaveMarketSnapshot(marketAddresses)
    } catch (err) {
      console.error(`[indexer] Error handling ${eventName}:`, err)
    }
  }

  const unwatch = client.watchContractEvent({
    address: market.marketAddress,
    abi: MARKET_EVENTS_ABI,
    pollingInterval,
    onLogs: ((logs: Log[]) => {
      for (const log of logs) {
        const args = (log as unknown as { args: Record<string, unknown> }).args
        const eventName = (log as unknown as { eventName: string }).eventName

        switch (eventName) {
          case "CollateralDeposited":
          case "CollateralWithdrawn":
            handleUserEvent(args.user as `0x${string}`, eventName)
            break

          case "Borrowed":
          case "Repaid":
            handleUserEvent(args.user as `0x${string}`, eventName)
            break

          case "Liquidated":
            handleLiquidation(
              marketAddresses,
              args as {
                borrower: `0x${string}`
                liquidator: `0x${string}`
                debtCovered: bigint
                collateralSeized: bigint
                badDebt: bigint
              },
              log as unknown as { transactionHash: `0x${string}`; blockNumber: bigint; logIndex: number }
            )
            break

          case "GlobalBorrowIndexUpdated":
            // Snapshot already captures globalBorrowIndex via multicall
            computeAndSaveMarketSnapshot(marketAddresses).catch((err) =>
              console.error("[indexer] Error on index update snapshot:", err)
            )
            break
        }
      }
    }) as EventHandler,
  })

  return unwatch
}

async function handleLiquidation(
  market: MarketConfig & { marketId: string },
  args: {
    borrower: `0x${string}`
    liquidator: `0x${string}`
    debtCovered: bigint
    collateralSeized: bigint
    badDebt: bigint
  },
  log: { transactionHash: `0x${string}`; blockNumber: bigint; logIndex: number }
) {
  console.log(`[indexer] Liquidated borrower=${args.borrower.slice(0, 8)}...`)
  try {
    await storeLiquidation(market.marketId, {
      borrower: args.borrower,
      liquidator: args.liquidator,
      debtCovered: args.debtCovered,
      collateralSeized: args.collateralSeized,
      badDebt: args.badDebt,
      txHash: log.transactionHash,
      blockNumber: log.blockNumber,
      logIndex: log.logIndex,
      loanAssetDecimals: market.loanAssetDecimals,
    })
    await updateUserPosition(args.borrower, market.marketId, market.marketAddress)
    await computeAndSaveMarketSnapshot(market)
  } catch (err) {
    console.error("[indexer] Error handling Liquidated:", err)
  }
}
