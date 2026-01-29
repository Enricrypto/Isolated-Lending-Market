// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title DataTypes
 * @notice Library containing shared data structures for the lending platform
 * @dev Centralizing structs improves type consistency across contracts
 */
library DataTypes {
    /**
     * @notice Market configuration parameters
     * @param lltv Liquidation Loan-to-Value ratio (e.g., 0.85e18 for 85%)
     * @param liquidationPenalty Bonus for liquidators (e.g., 0.05e18 for 5%)
     * @param protocolFeeRate Protocol's share of interest (e.g., 0.10e18 for 10%)
     */
    struct MarketParameters {
        uint256 lltv;
        uint256 liquidationPenalty;
        uint256 protocolFeeRate;
    }

    /**
     * @notice User's position data
     * @param collateralValue Total USD value of collateral
     * @param totalDebt Total debt including interest
     * @param healthFactor Position health (1e18 = healthy threshold)
     * @param borrowingPower Available borrowing capacity
     */
    struct UserPosition {
        uint256 collateralValue;
        uint256 totalDebt;
        uint256 healthFactor;
        uint256 borrowingPower;
    }

    /**
     * @notice Liquidation calculation results
     * @param debtToCover Amount of debt to repay (USD)
     * @param collateralToSeize Amount of collateral to seize (USD)
     * @param badDebt Amount of unrecoverable debt (USD)
     */
    struct LiquidationData {
        uint256 debtToCover;
        uint256 collateralToSeize;
        uint256 badDebt;
    }

    /**
     * @notice Interest accrual data
     * @param borrowIndex Global borrow index
     * @param lastUpdateTimestamp Last time index was updated
     * @param totalBorrows Total borrowed amount (normalized)
     */
    struct InterestData {
        uint256 borrowIndex;
        uint256 lastUpdateTimestamp;
        uint256 totalBorrows;
    }

    // ==================== RISK ENGINE DATA TYPES ====================

    /// @notice Configuration for the Risk Engine's scoring thresholds
    /// @dev All thresholds are in 18-decimal precision unless stated otherwise
    struct RiskEngineConfig {
        // Oracle risk thresholds
        uint256 oracleFreshnessThreshold; // seconds before price is "stale" (e.g., 3600)
        uint256 oracleDeviationTolerance; // max Chainlink-vs-TWAP deviation (e.g., 0.02e18 = 2%)
        uint256 oracleCriticalDeviation; // deviation triggering critical (e.g., 0.05e18 = 5%)
        uint256 lkgDecayHalfLife; // seconds for LKG confidence to halve (e.g., 1800)
        uint256 lkgMaxAge; // seconds before LKG is considered fully decayed
        // Liquidity risk thresholds
        uint256 utilizationWarning; // utilization triggering elevated (e.g., 0.85e18)
        uint256 utilizationCritical; // utilization triggering critical (e.g., 0.95e18)
        // Solvency risk thresholds
        uint256 healthFactorWarning; // aggregate HF below this = elevated (e.g., 1.2e18)
        uint256 healthFactorCritical; // aggregate HF below this = critical (e.g., 1.05e18)
        uint256 badDebtThreshold; // bad debt ratio triggering concern (e.g., 0.01e18 = 1%)
        // Strategy risk thresholds
        uint256 strategyAllocationCap; // max % of vault in strategy (e.g., 0.95e18)
    }

    /// @notice Per-dimension risk score (0-100)
    struct DimensionScore {
        uint8 oracleRisk;
        uint8 liquidityRisk;
        uint8 solvencyRisk;
        uint8 strategyRisk;
    }

    /// @notice Full risk assessment output
    struct RiskAssessment {
        DimensionScore scores;
        uint8 severity; // 0=Normal, 1=Elevated, 2=Critical, 3=Emergency
        uint64 timestamp; // when assessment was computed
        bytes32 reasonCodes; // packed reason flags (32 possible reasons)
    }

    /// @notice Oracle evaluation result from hierarchical resolution
    struct OracleEvaluation {
        uint256 resolvedPrice; // final price used (18 decimals)
        uint256 confidence; // 0-1e18, how confident we are in this price
        uint8 sourceUsed; // 0=Chainlink fresh, 1=Chainlink+TWAP consensus, 2=LKG fallback
        uint8 oracleRiskScore; // 0-100 risk score from oracle evaluation
        bool isStale; // whether primary source was stale
        uint256 deviation; // deviation between sources (18 decimals)
    }

    /// @notice Last Known Good price entry
    struct LKGPrice {
        uint256 price; // normalized to 18 decimals
        uint64 timestamp; // when this LKG was recorded
        uint64 updatedAt; // Chainlink updatedAt when LKG was set
    }
}
