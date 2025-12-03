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
}
