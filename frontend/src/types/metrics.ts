// Severity levels per MONITORING.md
export type SeverityLevel = 0 | 1 | 2 | 3;

export interface SeverityInfo {
  level: SeverityLevel;
  label: "Normal" | "Elevated" | "Critical" | "Emergency";
  color: string;
}

// Market configuration for multi-market polling
export interface VaultConfig {
  vaultAddress: `0x${string}`;
  marketAddress: `0x${string}`;
  irmAddress: `0x${string}`;
  oracleRouterAddress: `0x${string}`;
  loanAsset: `0x${string}`;
  loanAssetDecimals: number;
  label: string;
  symbol: string;
}

// Liquidity Depth signal
export interface LiquidityMetrics {
  availableLiquidity: bigint;
  totalBorrows: bigint;
  depthRatio: number; // availableLiquidity / liquidatableNotional (approximated)
  severity: SeverityLevel;
}

// Borrow Cost / APR Convexity signal
export interface APRConvexityMetrics {
  utilizationRate: number; // 0-1
  borrowRate: number; // Annual rate (0.05 = 5%)
  optimalUtilization: number; // Kink point
  distanceToKink: number; // How far from the kink
  severity: SeverityLevel;
}

// Oracle Deviations signal
export interface OracleMetrics {
  price: bigint;
  confidence: number; // 0-100
  riskScore: number; // 0-100
  isStale: boolean;
  deviation: number; // 0-1
  severity: SeverityLevel;
}

// Utilization Velocity signal
export interface VelocityMetrics {
  currentUtilization: number;
  previousUtilization: number;
  delta: number; // Change per hour
  severity: SeverityLevel;
}

// Combined snapshot for storage
export interface MetricSnapshot {
  id?: number;
  timestamp: Date;
  vaultAddress: string;

  // Liquidity
  availableLiquidity: bigint;
  totalBorrows: bigint;
  liquidityDepthRatio: number;
  liquiditySeverity: SeverityLevel;

  // APR Convexity
  utilizationRate: number;
  borrowRate: number;
  optimalUtilization: number;
  distanceToKink: number;
  aprConvexitySeverity: SeverityLevel;

  // Oracle
  oraclePrice: bigint;
  oracleConfidence: number;
  oracleRiskScore: number;
  oracleIsStale: boolean;
  oracleSeverity: SeverityLevel;

  // Velocity
  utilizationDelta: number | null;
  velocitySeverity: SeverityLevel | null;

  // Overall
  overallSeverity: SeverityLevel;
}

// API response types
// All amounts are normalized (human-readable floats, e.g. 1500.5 USDC not raw 1500500000)
export interface CurrentMetricsResponse {
  vaultAddress: string;
  timestamp: string;
  liquidity: {
    available: number;
    totalBorrows: number;
    depthRatio: number;
    severity: SeverityLevel;
  };
  aprConvexity: {
    utilization: number;
    borrowRate: number;
    distanceToKink: number;
    severity: SeverityLevel;
  };
  oracle: {
    price: number;
    confidence: number;
    riskScore: number;
    isStale: boolean;
    severity: SeverityLevel;
  };
  velocity: {
    delta: number | null;
    severity: SeverityLevel | null;
  };
  overall: SeverityLevel;
}

export interface HistoryDataPoint {
  timestamp: string;
  value: number;
  severity: SeverityLevel;
}

export interface HistoryResponse {
  signal: string;
  range: string;
  data: HistoryDataPoint[];
}

// Time range for queries
export type TimeRange = "24h" | "7d" | "30d" | "90d";

// Per-vault summary for protocol overview
export interface VaultSummary {
  vaultAddress: string;
  label: string;
  symbol: string;
  overallSeverity: SeverityLevel;
  utilization: number;
  totalSupply: number;
  totalBorrows: number;
  oraclePrice: number;
  lastUpdated: string;
}

// Protocol-level overview (aggregated across all vaults)
export interface ProtocolOverviewResponse {
  vaults: VaultSummary[];
  protocolSeverity: SeverityLevel;
  totalTVL: number;
  totalBorrows: number;
  timestamp: string;
}
