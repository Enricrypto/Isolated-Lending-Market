/**
 * MarketV1 Event ABIs
 * -------------------
 * Subset of Events.sol relevant to the indexer.
 * Used by viem's watchContractEvent to decode logs.
 */

export const MARKET_EVENTS_ABI = [
  {
    type: "event",
    name: "CollateralDeposited",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "token", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "CollateralWithdrawn",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "token", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "Borrowed",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
      { name: "newTotalDebt", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "Repaid",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
      { name: "interestPaid", type: "uint256", indexed: false },
      { name: "principalPaid", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "Liquidated",
    inputs: [
      { name: "borrower", type: "address", indexed: true },
      { name: "liquidator", type: "address", indexed: true },
      { name: "debtCovered", type: "uint256", indexed: false },
      { name: "collateralSeized", type: "uint256", indexed: false },
      { name: "badDebt", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "GlobalBorrowIndexUpdated",
    inputs: [
      { name: "oldIndex", type: "uint256", indexed: false },
      { name: "newIndex", type: "uint256", indexed: false },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
] as const
