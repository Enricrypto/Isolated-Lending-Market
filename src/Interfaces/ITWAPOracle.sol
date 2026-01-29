// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ITWAPOracle
/// @notice Minimal interface for DEX TWAP oracle sources
/// @dev Implementations can wrap Uniswap V3 OracleLibrary, Curve, etc.
interface ITWAPOracle {
    /// @notice Get the TWAP price for an asset
    /// @param asset The asset to price
    /// @param period The TWAP period in seconds
    /// @return price The TWAP price normalized to 18 decimals
    /// @return updatedAt The timestamp of the latest observation
    function getTWAP(address asset, uint32 period) external view returns (uint256 price, uint256 updatedAt);

    /// @notice Check if this oracle supports the given asset
    /// @param asset The asset to check
    /// @return supported True if the asset is supported
    function supportsAsset(address asset) external view returns (bool supported);
}
