// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IPriceOracle
 * @notice Interface for the PriceOracle contract
 * @dev Defines functions for managing and querying Chainlink price feeds
 */
interface IPriceOracle {
    // ==================== ADMIN FUNCTIONS ====================

    function addPriceFeed(address asset, address feed) external;

    function updatePriceFeed(address asset, address newFeed) external;

    function removePriceFeed(address asset) external;

    function setMaxPriceAge(uint256 newMaxAge) external;

    // ==================== VIEW FUNCTIONS ====================

    function getLatestPrice(address asset) external view returns (uint256 price);

    function getLatestPriceUnsafe(address asset) external view returns (uint256 price);

    function hasPriceFeed(address asset) external view returns (bool exists);

    function getPriceFeedInfo(address asset) external view returns (address feed, uint8 decimals);

    // ==================== STATE VARIABLES ====================

    function owner() external view returns (address);

    function maxPriceAge() external view returns (uint256);

    function priceFeeds(address asset) external view returns (address);

    function priceFeedDecimals(address asset) external view returns (uint8);
}
