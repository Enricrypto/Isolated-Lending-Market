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
  if (confidence === 0 || riskScore >= 90) return 3
  if (isStale) {
    if (confidence >= 80) return 1
    if (confidence >= 50) return 2
    return 3
  }
  if (confidence >= 95) return 0
  if (confidence >= 80) return 1
  if (confidence >= 50) return 2
  return 3
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
