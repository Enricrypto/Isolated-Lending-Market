// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "../libraries/Errors.sol";
import "../libraries/Events.sol";

/**
 * @title PriceOracle
 * @notice Manages Chainlink price feeds with staleness checks and decimal handling
 * @dev Ensures price freshness and validates all price feed operations
 * @author Your Team
 */
contract PriceOracle {
    // ==================== STATE VARIABLES ====================

    /// @notice Owner address with admin privileges
    address public owner;

    /// @notice Maximum age for a price to be considered valid (default: 1 hour)
    uint256 public maxPriceAge;

    /// @notice Mapping of asset addresses to their Chainlink price feeds
    mapping(address => AggregatorV3Interface) public priceFeeds;

    /// @notice Mapping of asset addresses to their price feed decimals
    mapping(address => uint8) public priceFeedDecimals;

    // ==================== CONSTANTS ====================

    uint256 private constant DEFAULT_MAX_PRICE_AGE = 1 hours;
    uint8 private constant TARGET_DECIMALS = 18;

    // ==================== CONSTRUCTOR ====================

    /**
     * @notice Initialize the price oracle
     * @param _owner Address that will own the oracle (typically the Market contract)
     */
    constructor(address _owner) {
        if (_owner == address(0)) revert Errors.ZeroAddress();
        owner = _owner;
        maxPriceAge = DEFAULT_MAX_PRICE_AGE;
    }

    // ==================== MODIFIERS ====================

    modifier onlyOwner() {
        if (msg.sender != owner) revert Errors.OnlyOwner();
        _;
    }

    // ==================== ADMIN FUNCTIONS ====================

    /**
     * @notice Add a new price feed for an asset
     * @param asset The asset address
     * @param feed The Chainlink price feed address
     * @dev Validates feed exists and stores decimals for future normalization
     */
    function addPriceFeed(address asset, address feed) external onlyOwner {
        if (asset == address(0)) revert Errors.InvalidTokenAddress();
        if (feed == address(0)) revert Errors.InvalidPriceFeedAddress();
        if (address(priceFeeds[asset]) != address(0)) revert Errors.PriceFeedAlreadyExists();

        AggregatorV3Interface priceFeed = AggregatorV3Interface(feed);

        // Validate the price feed by attempting to get decimals and latest price
        uint8 decimals = priceFeed.decimals();
        if (decimals == 0 || decimals > 18) revert Errors.InvalidDecimals();

        // Validate we can get a price
        try priceFeed.latestRoundData() returns (
            uint80, int256 price, uint256, uint256 updatedAt, uint80
        ) {
            if (price <= 0) revert Errors.InvalidPrice();
            if (updatedAt == 0) revert Errors.StalePrice();
        } catch {
            revert Errors.InvalidPriceFeedAddress();
        }

        priceFeeds[asset] = priceFeed;
        priceFeedDecimals[asset] = decimals;

        emit Events.PriceFeedAdded(asset, feed, decimals);
    }

    /**
     * @notice Update an existing price feed
     * @param asset The asset address
     * @param newFeed The new Chainlink price feed address
     */
    function updatePriceFeed(address asset, address newFeed) external onlyOwner {
        if (asset == address(0)) revert Errors.InvalidTokenAddress();
        if (newFeed == address(0)) revert Errors.InvalidPriceFeedAddress();
        if (address(priceFeeds[asset]) == address(0)) revert Errors.PriceFeedDoesNotExist();

        address oldFeed = address(priceFeeds[asset]);
        AggregatorV3Interface priceFeed = AggregatorV3Interface(newFeed);

        // Validate new feed
        uint8 decimals = priceFeed.decimals();
        if (decimals == 0 || decimals > 18) revert Errors.InvalidDecimals();

        try priceFeed.latestRoundData() returns (
            uint80, int256 price, uint256, uint256 updatedAt, uint80
        ) {
            if (price <= 0) revert Errors.InvalidPrice();
            if (updatedAt == 0) revert Errors.StalePrice();
        } catch {
            revert Errors.InvalidPriceFeedAddress();
        }

        priceFeeds[asset] = priceFeed;
        priceFeedDecimals[asset] = decimals;

        emit Events.PriceFeedUpdated(asset, oldFeed, newFeed);
    }

    /**
     * @notice Remove a price feed
     * @param asset The asset address
     */
    function removePriceFeed(address asset) external onlyOwner {
        if (address(priceFeeds[asset]) == address(0)) revert Errors.PriceFeedDoesNotExist();

        delete priceFeeds[asset];
        delete priceFeedDecimals[asset];

        emit Events.PriceFeedRemoved(asset);
    }

    /**
     * @notice Update the maximum allowed price age
     * @param newMaxAge New maximum age in seconds
     */
    function setMaxPriceAge(uint256 newMaxAge) external onlyOwner {
        if (newMaxAge == 0 || newMaxAge > 1 days) revert Errors.ParameterTooHigh();

        uint256 oldMaxAge = maxPriceAge;
        maxPriceAge = newMaxAge;

        emit Events.MaxPriceAgeUpdated(oldMaxAge, newMaxAge);
    }

    /**
     * @notice Transfer ownership to a new address
     * @param newOwner The address of the new owner
     * @dev Can only be called by current owner
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert Errors.ZeroAddress();

        address oldOwner = owner;
        owner = newOwner;

        emit Events.OwnershipTransferred(oldOwner, newOwner);
    }

    // ==================== VIEW FUNCTIONS ====================

    /**
     * @notice Get the latest price for an asset with staleness check
     * @param asset The asset address
     * @return price The price normalized to 18 decimals
     * @dev Reverts if price is stale or invalid
     */
    function getLatestPrice(address asset) external view returns (uint256 price) {
        if (address(priceFeeds[asset]) == address(0)) revert Errors.PriceFeedNotSet();

        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeeds[asset].latestRoundData();

        // Validate price data
        if (answer <= 0) revert Errors.InvalidPrice();
        if (updatedAt == 0) revert Errors.StalePrice();
        if (answeredInRound < roundId) revert Errors.StalePrice();

        // Check price freshness
        if (block.timestamp - updatedAt > maxPriceAge) revert Errors.StalePrice();

        // Normalize price to 18 decimals
        uint8 feedDecimals = priceFeedDecimals[asset];
        price = _normalizePrice(uint256(answer), feedDecimals);
    }

    /**
     * @notice Get the latest price without staleness check (use with caution)
     * @param asset The asset address
     * @return price The price normalized to 18 decimals
     * @dev Only validates that price > 0, doesn't check timestamp
     */
    function getLatestPriceUnsafe(address asset) external view returns (uint256 price) {
        if (address(priceFeeds[asset]) == address(0)) revert Errors.PriceFeedNotSet();

        (, int256 answer,,,) = priceFeeds[asset].latestRoundData();

        if (answer <= 0) revert Errors.InvalidPrice();

        uint8 feedDecimals = priceFeedDecimals[asset];
        price = _normalizePrice(uint256(answer), feedDecimals);
    }

    /**
     * @notice Check if a price feed exists for an asset
     * @param asset The asset address
     * @return exists True if price feed is configured
     */
    function hasPriceFeed(address asset) external view returns (bool exists) {
        return address(priceFeeds[asset]) != address(0);
    }

    /**
     * @notice Get price feed information
     * @param asset The asset address
     * @return feed The price feed address
     * @return decimals The price feed decimals
     */
    function getPriceFeedInfo(address asset) external view returns (address feed, uint8 decimals) {
        feed = address(priceFeeds[asset]);
        decimals = priceFeedDecimals[asset];
    }

    // ==================== INTERNAL FUNCTIONS ====================

    /**
     * @notice Normalize price from feed decimals to 18 decimals
     * @param price The price in feed decimals
     * @param feedDecimals The number of decimals in the price feed
     * @return normalized The price in 18 decimals
     */
    function _normalizePrice(uint256 price, uint8 feedDecimals)
        internal
        pure
        returns (uint256 normalized)
    {
        if (feedDecimals == TARGET_DECIMALS) {
            return price;
        } else if (feedDecimals < TARGET_DECIMALS) {
            // Scale up
            return price * (10 ** (TARGET_DECIMALS - feedDecimals));
        } else {
            // Scale down (shouldn't happen as we check decimals <= 18)
            return price / (10 ** (feedDecimals - TARGET_DECIMALS));
        }
    }
}
