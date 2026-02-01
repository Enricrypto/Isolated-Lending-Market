/**
 * Format a raw BigInt string (with 6 decimals) into a human-readable number.
 * e.g. "1500000000000" -> "1.50M"
 */
export function formatLargeNumber(value: string): string {
  const num = BigInt(value)
  const divisor = BigInt(1e6)
  const whole = num / divisor

  if (whole >= 1_000_000n) {
    return `${(Number(whole) / 1_000_000).toFixed(2)}M`
  }
  if (whole >= 1_000n) {
    return `${(Number(whole) / 1_000).toFixed(2)}K`
  }
  return whole.toString()
}

/**
 * Format a raw BigInt price string (18 decimals) into USD.
 * e.g. "1000000000000000000" -> "1.00"
 */
export function formatPrice(priceString: string): string {
  const price = BigInt(priceString)
  const usd = Number(price) / 1e18
  return usd.toFixed(4)
}

/**
 * Get a human label for oracle confidence percentage.
 */
export function getConfidenceLabel(confidence: number): string {
  if (confidence >= 95) return "High"
  if (confidence >= 80) return "Good"
  if (confidence >= 50) return "Degraded"
  return "Low"
}
