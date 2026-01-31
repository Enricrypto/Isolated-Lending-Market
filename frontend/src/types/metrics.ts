// Severity levels per MONITORING.md
export type SeverityLevel = 0 | 1 | 2 | 3;

export interface SeverityInfo {
  level: SeverityLevel;
  label: "Normal" | "Elevated" | "Critical" | "Emergency";
  color: string;
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
export interface CurrentMetricsResponse {
  timestamp: string;
  liquidity: {
    available: string;
    totalBorrows: string;
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
    price: string;
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
export type TimeRange = "24h" | "7d" | "30d";
