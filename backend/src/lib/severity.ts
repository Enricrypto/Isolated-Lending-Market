export type SeverityLevel = 0 | 1 | 2 | 3

export function computeLiquiditySeverity(depthRatio: number): SeverityLevel {
  if (depthRatio > 3.0) return 0
  if (depthRatio >= 1.5) return 1
  if (depthRatio >= 1.0) return 1
  return 2
}

export function computeAPRConvexitySeverity(
  utilizationRate: number,
  optimalUtilization: number
): SeverityLevel {
  const distanceToKink = optimalUtilization - utilizationRate
  if (utilizationRate >= optimalUtilization) return 3
  if (distanceToKink < 0.05) return 2
  if (distanceToKink < 0.15) return 1
  return 0
}

export function computeOracleSeverity(
  confidence: number,
  isStale: boolean,
  riskScore: number
): SeverityLevel {
  // riskScore is uint8 (0-100 semantic scale) from OracleEvaluation struct.
  // Emergency only when data is completely unusable (max risk score, no confidence).
  if (confidence === 0 || riskScore >= 100) return 3
  // High risk score on its own → Critical regardless of staleness
  if (riskScore >= 80) return 2
  // Stale feed: severity depends on remaining confidence
  if (isStale) {
    if (confidence >= 80) return 1  // stale but highly confident → Elevated
    if (confidence >= 40) return 2  // stale and shaky confidence → Critical
    return 3                         // stale with near-zero confidence → Emergency
  }
  // Fresh feed: severity from confidence alone
  if (confidence >= 95) return 0
  if (confidence >= 70) return 1
  return 2
}

export function computeOverallSeverity(
  liquiditySeverity: SeverityLevel,
  aprConvexitySeverity: SeverityLevel,
  oracleSeverity: SeverityLevel,
  velocitySeverity: SeverityLevel | null
): SeverityLevel {
  const severities = [liquiditySeverity, aprConvexitySeverity, oracleSeverity]
  if (velocitySeverity !== null) severities.push(velocitySeverity)
  return Math.max(...severities) as SeverityLevel
}

export function computeProtocolSeverity(vaultSeverities: SeverityLevel[]): SeverityLevel {
  if (vaultSeverities.length === 0) return 0
  return Math.max(...vaultSeverities) as SeverityLevel
}
