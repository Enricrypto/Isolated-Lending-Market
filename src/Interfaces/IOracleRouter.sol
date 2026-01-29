// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../libraries/DataTypes.sol";

/// @title IOracleRouter
/// @notice Interface for the hierarchical oracle evaluation system
/// @dev Wraps the existing PriceOracle with DEX TWAP cross-validation and LKG fallback.
///      Provides backward-compatible methods for Market integration.
interface IOracleRouter {
    // ==================== MARKET-COMPATIBLE INTERFACE ====================

    /// @notice Get the latest price for an asset using hierarchical evaluation
    /// @param asset The asset to price
    /// @return price Price in USD with 18 decimals
    /// @dev Uses Chainlink → TWAP cross-validation → LKG fallback
    ///      Reverts if no valid price available (confidence = 0)
    function getLatestPrice(address asset) external view returns (uint256 price);

    /// @notice Add a price feed for an asset (delegates to underlying PriceOracle)
    /// @param asset The asset address
    /// @param feed The Chainlink price feed address
    function addPriceFeed(address asset, address feed) external;

    /// @notice Check if an asset has a price feed configured
    /// @param asset The asset address
    /// @return exists True if price feed exists
    function hasPriceFeed(address asset) external view returns (bool exists);

    // ==================== ADVANCED EVALUATION ====================

    /// @notice Evaluate oracle for an asset using the full hierarchy
    /// @param asset The asset to evaluate
    /// @return evaluation Full evaluation result with confidence and risk scores
    function evaluate(address asset) external view returns (DataTypes.OracleEvaluation memory evaluation);

    /// @notice Returns price and confidence level for an asset
    /// @param asset Address of the asset
    /// @return price Current price in USD with 18 decimals
    /// @return confidence 0-100, where 100 = fully confident
    function getPrice(address asset) external view returns (uint256 price, uint8 confidence);

    // ==================== LKG MANAGEMENT ====================

    /// @notice Update the LKG price for an asset (call when Chainlink is fresh)
    /// @param asset The asset to update
    function updateLKG(address asset) external;

    /// @notice Register a TWAP oracle for an asset
    /// @param asset The asset address
    /// @param twapOracle The TWAP oracle address
    function setTWAPOracle(address asset, address twapOracle) external;

    /// @notice Remove a TWAP oracle for an asset
    /// @param asset The asset address
    function removeTWAPOracle(address asset) external;

    /// @notice Set oracle evaluation parameters
    /// @param deviationTolerance Max acceptable Chainlink-vs-TWAP deviation (18 decimals)
    /// @param criticalDeviation Deviation that triggers critical (18 decimals)
    /// @param lkgDecayHalfLife Half-life for LKG confidence decay in seconds
    /// @param lkgMaxAge Maximum age before LKG is considered fully decayed
    function setOracleParams(
        uint256 deviationTolerance,
        uint256 criticalDeviation,
        uint256 lkgDecayHalfLife,
        uint256 lkgMaxAge
    ) external;

    /// @notice Get the LKG price for an asset
    /// @param asset The asset address
    /// @return lkg The LKG price entry
    function getLKGPrice(address asset) external view returns (DataTypes.LKGPrice memory lkg);

    /// @notice Get the TWAP oracle for an asset
    /// @param asset The asset address
    /// @return oracle The TWAP oracle address
    function twapOracles(address asset) external view returns (address oracle);

    /// @notice Returns timestamp of last valid update for an asset
    /// @param asset Address of the asset
    /// @return timestamp The last LKG update timestamp
    function lastUpdate(address asset) external view returns (uint256 timestamp);

    // ==================== STATE ACCESSORS ====================

    /// @notice Get the underlying price oracle
    /// @return The PriceOracle address
    function priceOracle() external view returns (address);

    /// @notice Get the contract owner
    /// @return The owner address
    function owner() external view returns (address);

    /// @notice Transfer ownership
    /// @param newOwner The new owner address
    function transferOwnership(address newOwner) external;

    /// @notice Get the deviation tolerance parameter
    function deviationTolerance() external view returns (uint256);

    /// @notice Get the critical deviation parameter
    function criticalDeviation() external view returns (uint256);

    /// @notice Get the LKG decay half-life parameter
    function lkgDecayHalfLife() external view returns (uint256);

    /// @notice Get the LKG max age parameter
    function lkgMaxAge() external view returns (uint256);
}
