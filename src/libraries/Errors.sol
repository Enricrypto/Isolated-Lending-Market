// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title Errors
 * @notice Library containing all custom errors for the lending platform
 * @dev Using custom errors saves gas compared to require statements with strings
 */
library Errors {
    // ==================== ACCESS CONTROL ====================
    error Unauthorized();
    error OnlyOwner();
    error OnlyMarket();
    error OnlyMarketOwner();
    error SystemAddressRestricted();

    // ==================== EMERGENCY CONTROLS ====================
    /// @notice Borrowing is paused - deposits, withdrawals, repayments still allowed
    error BorrowingPaused();

    // ==================== MARKET ERRORS ====================
    error TokenNotSupported();
    error TokenAlreadyAdded();
    error DepositsPaused();
    error DepositsNotPaused();
    error InsufficientCollateral();
    error InsufficientBorrowingPower();
    error InsufficientVaultLiquidity();
    error InsufficientProtocolLiquidity();
    error WithdrawalWouldMakePositionUnhealthy();
    error PositionNotLiquidatable();
    error PositionIsHealthy();
    error MustCoverInterest();
    error RepaymentExceedsDebt();
    error CollateralStillInUse();
    error InvalidTokenAddress();
    error InvalidPriceFeedAddress();
    error InvalidMarketAddress();
    error InvalidTreasuryAddress();
    error InvalidBadDebtAddress();
    error TokenDecimalsTooHigh();
    error TransferFailed();
    error BorrowUnderflow();

    // ==================== VAULT ERRORS ====================
    error MarketAlreadySet();
    error InvalidStrategy();
    error StrategyAssetMismatch();
    error InsufficientLiquidity();
    error NoFundsToRedeem();
    error InvalidNewOwner();

    // ==================== ORACLE ERRORS ====================
    error PriceFeedNotSet();
    error InvalidPrice();
    error StalePrice();
    error InvalidDecimals();
    error PriceFeedAlreadyExists();
    error PriceFeedDoesNotExist();

    // ==================== INTEREST RATE MODEL ERRORS ====================
    error MarketNotSet();
    error InvalidBaseRate();
    error InvalidOptimalUtilization();
    error InvalidSlope();
    error ParameterTooHigh();

    // ==================== PARAMETER VALIDATION ====================
    error LiquidationLoanToValueTooHigh();
    error LiquidationPenaltyTooHigh();
    error InvalidAmount();
    error ZeroAddress();

    // ==================== RISK ENGINE ERRORS ====================
    error RiskEngineNotConfigured();
    error InvalidRiskThreshold();
    error TWAPOracleNotSet();
    error LKGPriceExpired();
    error InvalidConfidenceValue();
    error AssetNotRegistered();
    error InvalidSeverityLevel();
    error OracleRouterNotSet();
    error InvalidHalfLife();
    error InvalidMaxAge();
}
