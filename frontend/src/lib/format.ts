/**
 * Format a normalized number into a human-readable abbreviated string.
 * Input is already human-readable (e.g. 1500000.5 USDC, not raw BigInt).
 * e.g. 1500000.5 -> "1.50M", 1500.5 -> "1.50K", 500 -> "500"
 */
export function formatLargeNumber(value: number): string {
  if (value >= 1_000_000) {
    return `${(value / 1_000_000).toFixed(2)}M`
  }
  if (value >= 1_000) {
    return `${(value / 1_000).toFixed(2)}K`
  }
  return value.toFixed(2)
}

/**
 * Format a normalized price number into USD display.
 * Input is already human-readable (e.g. 1.0002).
 * e.g. 1.0002 -> "1.0002"
 */
export function formatPrice(price: number): string {
  return price.toFixed(4)
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
