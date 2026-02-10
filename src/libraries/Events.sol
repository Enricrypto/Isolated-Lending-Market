// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title Events
 * @notice Library containing all events for the lending platform
 * @dev Centralizing events improves maintainability and reduces duplication
 */
library Events {
    // ==================== MARKET EVENTS ====================

    /// @notice Emitted when market parameters are updated
    event MarketParametersUpdated(
        uint256 lltv, uint256 liquidationPenalty, uint256 protocolFeeRate
    );

    /// @notice Emitted when a collateral token is added
    event CollateralTokenAdded(address indexed token, address indexed priceFeed, uint8 decimals);

    /// @notice Emitted when collateral deposits are paused
    event CollateralDepositsPaused(address indexed token);

    /// @notice Emitted when collateral deposits are resumed
    event CollateralDepositsResumed(address indexed token);

    /// @notice Emitted when a collateral token is removed
    event CollateralTokenRemoved(address indexed token);

    /// @notice Emitted when a user deposits collateral
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);

    /// @notice Emitted when a user withdraws collateral
    event CollateralWithdrawn(address indexed user, address indexed token, uint256 amount);

    /// @notice Emitted when a user borrows
    event Borrowed(address indexed user, uint256 amount, uint256 newTotalDebt);

    /// @notice Emitted when a user repays debt
    event Repaid(address indexed user, uint256 amount, uint256 interestPaid, uint256 principalPaid);

    /// @notice Emitted when a position is liquidated
    event Liquidated(
        address indexed borrower,
        address indexed liquidator,
        uint256 debtCovered,
        uint256 collateralSeized,
        uint256 badDebt
    );

    /// @notice Emitted when collateral is seized during liquidation
    event CollateralSeized(
        address indexed borrower, address indexed liquidator, address indexed token, uint256 amount
    );

    /// @notice Emitted when bad debt is transferred
    event BadDebtRecorded(address indexed borrower, uint256 amount);

    /// @notice Emitted when the global borrow index is updated
    event GlobalBorrowIndexUpdated(uint256 oldIndex, uint256 newIndex, uint256 timestamp);

    /// @notice Emitted when borrowing pause state changes
    event BorrowingPausedChanged(bool paused);

    /// @notice Emitted when guardian address is changed
    event GuardianChanged(address indexed oldGuardian, address indexed newGuardian);

    // ==================== VAULT EVENTS ====================

    /// @notice Emitted when market is set on vault
    event MarketSet(address indexed market);

    /// @notice Emitted when the vault's strategy is changed
    event StrategyChanged(
        address indexed oldStrategy, address indexed newStrategy, uint256 amountMigrated
    );

    /// @notice Emitted when market owner is transferred
    event MarketOwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Emitted when market borrows from vault
    event BorrowedByMarket(address indexed market, uint256 amount);

    /// @notice Emitted when market repays to vault
    event RepaidToVault(address indexed market, uint256 amount);

    // ==================== ORACLE EVENTS ====================

    /// @notice Emitted when a price feed is added
    event PriceFeedAdded(address indexed asset, address indexed feed, uint8 decimals);

    /// @notice Emitted when a price feed is updated
    event PriceFeedUpdated(address indexed asset, address indexed oldFeed, address indexed newFeed);

    /// @notice Emitted when a price feed is removed
    event PriceFeedRemoved(address indexed asset);

    /// @notice Emitted when max price age is updated
    event MaxPriceAgeUpdated(uint256 oldMaxAge, uint256 newMaxAge);

    /// @notice Emitted when oracle ownership is transferred
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ==================== INTEREST RATE MODEL EVENTS ====================

    /// @notice Emitted when base rate is updated
    event BaseRateUpdated(uint256 oldRate, uint256 newRate);

    /// @notice Emitted when optimal utilization is updated
    event OptimalUtilizationUpdated(uint256 oldUtilization, uint256 newUtilization);

    /// @notice Emitted when slope1 is updated
    event Slope1Updated(uint256 oldSlope, uint256 newSlope);

    /// @notice Emitted when slope2 is updated
    event Slope2Updated(uint256 oldSlope, uint256 newSlope);

    /// @notice Emitted when market contract is set
    event MarketContractSet(address indexed market);

    // ==================== RISK ENGINE EVENTS ====================

    /// @notice Emitted when a risk assessment is computed (for off-chain indexing)
    event RiskAssessed(
        uint8 severity,
        uint8 oracleRisk,
        uint8 liquidityRisk,
        uint8 solvencyRisk,
        uint8 strategyRisk,
        bytes32 reasonCodes
    );

    /// @notice Emitted when Risk Engine configuration is updated
    event RiskEngineConfigUpdated(address indexed caller);

    /// @notice Emitted when a LKG price is recorded
    event LKGPriceUpdated(address indexed asset, uint256 price, uint64 timestamp);

    /// @notice Emitted when a TWAP oracle is registered
    event TWAPOracleRegistered(address indexed asset, address indexed twapOracle);

    /// @notice Emitted when a TWAP oracle is removed
    event TWAPOracleRemoved(address indexed asset);

    /// @notice Emitted when oracle evaluation uses fallback
    event OracleFallbackUsed(
        address indexed asset, uint8 sourceUsed, uint256 resolvedPrice, uint256 confidence
    );
}
