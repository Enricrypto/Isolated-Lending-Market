// Contract ABIs - minimal view functions for monitoring
// Addresses loaded from environment variables

export const MARKET_ABI = [
  {
    inputs: [],
    name: "totalBorrows",
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "paused",
    outputs: [{ type: "bool" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "badDebtAddress",
    outputs: [{ type: "address" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "user", type: "address" }],
    name: "userTotalDebt",
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

export const VAULT_ABI = [
  {
    inputs: [],
    name: "totalAssets",
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "availableLiquidity",
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "totalStrategyAssets",
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "isStrategyChanging",
    outputs: [{ type: "bool" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

export const IRM_ABI = [
  {
    inputs: [],
    name: "getUtilizationRate",
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "getDynamicBorrowRate",
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "optimalUtilization",
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "baseRate",
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

// OracleEvaluation struct from DataTypes.sol
// struct OracleEvaluation {
//     uint256 resolvedPrice;
//     uint256 confidence;
//     uint8 sourceUsed;
//     uint8 oracleRiskScore;
//     bool isStale;
//     uint256 deviation;
// }
export const ORACLE_ROUTER_ABI = [
  {
    inputs: [{ name: "asset", type: "address" }],
    name: "evaluate",
    outputs: [
      {
        components: [
          { name: "resolvedPrice", type: "uint256" },
          { name: "confidence", type: "uint256" },
          { name: "sourceUsed", type: "uint8" },
          { name: "oracleRiskScore", type: "uint8" },
          { name: "isStale", type: "bool" },
          { name: "deviation", type: "uint256" },
        ],
        type: "tuple",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "asset", type: "address" }],
    name: "getPrice",
    outputs: [
      { name: "price", type: "uint256" },
      { name: "confidence", type: "uint8" },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "asset", type: "address" }],
    name: "getLatestPrice",
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

// RiskAssessment struct from DataTypes.sol
// struct RiskAssessment {
//     DimensionScore scores;
//     uint8 severity;
//     uint64 timestamp;
//     bytes32 reasonFlags;
// }
// struct DimensionScore {
//     uint8 oracleRisk;
//     uint8 liquidityRisk;
//     uint8 solvencyRisk;
//     uint8 strategyRisk;
// }
export const RISK_ENGINE_ABI = [
  {
    inputs: [],
    name: "assessRisk",
    outputs: [
      {
        components: [
          {
            components: [
              { name: "oracleRisk", type: "uint8" },
              { name: "liquidityRisk", type: "uint8" },
              { name: "solvencyRisk", type: "uint8" },
              { name: "strategyRisk", type: "uint8" },
            ],
            name: "scores",
            type: "tuple",
          },
          { name: "severity", type: "uint8" },
          { name: "timestamp", type: "uint64" },
          { name: "reasonFlags", type: "bytes32" },
        ],
        type: "tuple",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "asset", type: "address" }],
    name: "computeOracleRisk",
    outputs: [{ type: "uint8" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "computeLiquidityRisk",
    outputs: [{ type: "uint8" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

// Contract addresses from environment
export function getContractAddresses() {
  return {
    market: process.env.MARKET_ADDRESS as `0x${string}`,
    vault: process.env.VAULT_ADDRESS as `0x${string}`,
    oracleRouter: process.env.ORACLE_ROUTER_ADDRESS as `0x${string}`,
    irm: process.env.IRM_ADDRESS as `0x${string}`,
    riskEngine: process.env.RISK_ENGINE_ADDRESS as `0x${string}`,
    loanAsset: process.env.LOAN_ASSET_ADDRESS as `0x${string}`,
  };
}
