import type { SeverityLevel, SeverityInfo } from "@/types/metrics";

// Severity level mapping per MONITORING.md
export const SEVERITY_INFO: Record<SeverityLevel, SeverityInfo> = {
  0: { level: 0, label: "Normal", color: "severity-normal" },
  1: { level: 1, label: "Elevated", color: "severity-elevated" },
  2: { level: 2, label: "Critical", color: "severity-critical" },
  3: { level: 3, label: "Emergency", color: "severity-emergency" },
};

// =============================================================================
// LIQUIDITY DEPTH SEVERITY
// =============================================================================
// depthCoverageRatio = availableLiquidity / liquidatableNotional
// > 3.0 → Severity 0
// 1.5 - 3.0 → Severity 1
// < 1.0 → Severity 2

export function computeLiquiditySeverity(depthRatio: number): SeverityLevel {
  if (depthRatio > 3.0) return 0;
  if (depthRatio >= 1.5) return 1;
  if (depthRatio >= 1.0) return 1; // Between 1.0-1.5 is also elevated
  return 2; // < 1.0 is critical
}

// =============================================================================
// APR CONVEXITY SEVERITY
// =============================================================================
// Based on distance to kink (optimal utilization)
// Far below kink (>20% away) → Severity 0
// Near kink (10-20% away) → Severity 1
// Very near kink (<10% away) → Severity 2
// Above kink → Severity 3

export function computeAPRConvexitySeverity(
  utilizationRate: number,
  optimalUtilization: number
): SeverityLevel {
  const distanceToKink = optimalUtilization - utilizationRate;

  if (utilizationRate >= optimalUtilization) {
    return 3; // Above kink - emergency
  }
  if (distanceToKink < 0.05) {
    return 2; // Within 5% of kink - critical
  }
  if (distanceToKink < 0.15) {
    return 1; // Within 15% of kink - elevated
  }
  return 0; // Far from kink - normal
}

// =============================================================================
// ORACLE DEVIATION SEVERITY
// =============================================================================
// Based on oracle confidence and staleness
// Confidence 100, fresh → Severity 0
// Minor deviation (confidence 80-99) → Severity 1
// Moderate deviation or stale (confidence 50-79) → Severity 2
// Unavailable or confidence < 50 → Severity 3

export function computeOracleSeverity(
  confidence: number,
  isStale: boolean,
  riskScore: number
): SeverityLevel {
  // If oracle is completely unavailable
  if (confidence === 0 || riskScore >= 90) {
    return 3;
  }

  // If stale, increase severity
  if (isStale) {
    if (confidence >= 80) return 1;
    if (confidence >= 50) return 2;
    return 3;
  }

  // Based on confidence level
  if (confidence >= 95) return 0;
  if (confidence >= 80) return 1;
  if (confidence >= 50) return 2;
  return 3;
}

// =============================================================================
// UTILIZATION VELOCITY SEVERITY
// =============================================================================
// Based on rate of change of utilization per hour
// < 1%/hour → Severity 0
// 1-5%/hour → Severity 1
// 5-10%/hour → Severity 2
// > 10%/hour → Severity 3

export function computeVelocitySeverity(deltaPerHour: number): SeverityLevel {
  const absDelta = Math.abs(deltaPerHour);

  if (absDelta < 0.01) return 0; // < 1%/hour
  if (absDelta < 0.05) return 1; // 1-5%/hour
  if (absDelta < 0.10) return 2; // 5-10%/hour
  return 3; // > 10%/hour
}

// =============================================================================
// OVERALL SEVERITY
// =============================================================================
// Maximum severity across all dimensions

export function computeOverallSeverity(
  liquiditySeverity: SeverityLevel,
  aprConvexitySeverity: SeverityLevel,
  oracleSeverity: SeverityLevel,
  velocitySeverity: SeverityLevel | null
): SeverityLevel {
  const severities = [liquiditySeverity, aprConvexitySeverity, oracleSeverity];
  if (velocitySeverity !== null) {
    severities.push(velocitySeverity);
  }
  return Math.max(...severities) as SeverityLevel;
}

// =============================================================================
// PROTOCOL-LEVEL SEVERITY (aggregated across vaults)
// =============================================================================

export function computeProtocolSeverity(
  vaultSeverities: SeverityLevel[]
): SeverityLevel {
  if (vaultSeverities.length === 0) return 0;
  return Math.max(...vaultSeverities) as SeverityLevel;
}

// =============================================================================
// SEVERITY STYLING HELPERS
// =============================================================================

export function getSeverityColor(severity: SeverityLevel): string {
  switch (severity) {
    case 0:
      return "bg-green-500";
    case 1:
      return "bg-yellow-500";
    case 2:
      return "bg-orange-500";
    case 3:
      return "bg-red-500";
  }
}

export function getSeverityTextColor(severity: SeverityLevel): string {
  switch (severity) {
    case 0:
      return "text-green-500";
    case 1:
      return "text-yellow-500";
    case 2:
      return "text-orange-500";
    case 3:
      return "text-red-500";
  }
}

export function getSeverityBorderColor(severity: SeverityLevel): string {
  switch (severity) {
    case 0:
      return "border-green-500";
    case 1:
      return "border-yellow-500";
    case 2:
      return "border-orange-500";
    case 3:
      return "border-red-500";
  }
}

export function getSeverityLabel(severity: SeverityLevel): string {
  return SEVERITY_INFO[severity].label;
}
