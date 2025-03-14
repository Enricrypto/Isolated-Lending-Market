// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/chainlink-local/src/data-feeds/interfaces/AggregatorV3Interface.sol";

contract PriceOracle {
    mapping(address => AggregatorV3Interface) public priceFeeds;

    // Interest Rate Model Constants
    address public owner;

    event PriceFeedAdded(address indexed asset, address indexed feed);
    event PriceFeedUpdated(address indexed asset, address indexed newFeed);
    event PriceFeedRemoved(address indexed asset);

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    // Function to add a new price feed (onlyOwner)
    function addPriceFeed(address asset, address feed) external {
        require(asset != address(0) && feed != address(0), "Invalid addresses");
        priceFeeds[asset] = AggregatorV3Interface(feed);
        emit PriceFeedAdded(asset, feed);
    }

    // Update an existing price feed
    function updatePriceFeed(
        address asset,
        address newFeed
    ) external onlyOwner {
        require(
            asset != address(0) && newFeed != address(0),
            "Invalid addresses"
        );
        require(
            address(priceFeeds[asset]) != address(0),
            "Feed does not exist"
        );
        priceFeeds[asset] = AggregatorV3Interface(newFeed);
        emit PriceFeedUpdated(asset, newFeed);
    }

    // Remove a price feed
    function removePriceFeed(address asset) external onlyOwner {
        require(
            address(priceFeeds[asset]) != address(0),
            "Feed does not exist"
        );
        delete priceFeeds[asset];
        emit PriceFeedRemoved(asset);
    }

    function getLatestPrice(address asset) public view returns (int256) {
        require(address(priceFeeds[asset]) != address(0), "Price feed not set");

        (, int256 price, , , ) = priceFeeds[asset].latestRoundData();
        // Ensure the price is non-negative
        require(price > 0, "Invalid price from Chainlink");

        return price;
    }
}
