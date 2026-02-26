/**
 * Interest Rate Model (IRM) — Jump Rate Model
 *
 * All three deployed markets (USDC, WETH, WBTC) use identical parameters.
 * Source: script/DeployAll.s.sol + script/DeployMarkets.s.sol
 * Mirrors: src/core/InterestRateModel.sol — getDynamicBorrowRate()
 *
 * Formula:
 *   utilization ≤ OPTIMAL: borrowAPR = BASE_RATE + utilization × SLOPE1
 *   utilization >  OPTIMAL: borrowAPR = BASE_RATE + OPTIMAL × SLOPE1 + (utilization − OPTIMAL) × SLOPE2
 *
 * Kink values:
 *   util=0%  → borrowAPR=2.00%, supplyAPY=0.00%
 *   util=40% → borrowAPR=3.60%, supplyAPY=1.30%
 *   util=80% → borrowAPR=5.20%, supplyAPY=3.74%  ← kink
 *   util=90% → borrowAPR=11.2%, supplyAPY=9.07%
 *   util=100%→ borrowAPR=17.2%, supplyAPY=15.48%
 */

export const IRM = {
  BASE_RATE:    0.02,  // 2%  — minimum borrow rate at 0% utilization
  OPTIMAL:      0.80,  // 80% — kink point; above this, rate jumps sharply
  SLOPE1:       0.04,  // 4%  — gradual slope below kink
  SLOPE2:       0.60,  // 60% — steep slope above kink
  PROTOCOL_FEE: 0.10,  // 10% — share of interest taken by protocol treasury
} as const;

/**
 * Annual borrow rate charged to borrowers.
 * Mirrors InterestRateModel.getDynamicBorrowRate()
 */
export function computeBorrowAPR(utilization: number): number {
  if (utilization <= IRM.OPTIMAL) {
    return IRM.BASE_RATE + utilization * IRM.SLOPE1;
  }
  const optimalRate = IRM.BASE_RATE + IRM.OPTIMAL * IRM.SLOPE1;
  return optimalRate + (utilization - IRM.OPTIMAL) * IRM.SLOPE2;
}

/**
 * Annual yield earned by lenders (depositors).
 * = borrowAPR × utilization × (1 − protocolFee)
 */
export function computeSupplyAPY(utilization: number): number {
  return computeBorrowAPR(utilization) * utilization * (1 - IRM.PROTOCOL_FEE);
}

/** Format a decimal rate to a percentage string (0.052 → "5.20%") */
export function formatRate(rate: number): string {
  return `${(rate * 100).toFixed(2)}%`;
}
