// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PriceOracle.sol";

contract InterestRateModel {
    uint256 public baseRate; // // Base interest rate (minimum rate applied to all loans)
    uint256 public priceFactor; // Weight for price impact
    uint256 public supplyFactor; // Weight for supply-demand impact

    PriceOracle public priceOracle;
    address public owner;

    // Define mappings for asset classification
    mapping(address => bool) public stablecoins;
    mapping(address => bool) public blueChipAssets;

    mapping(address => uint256) public totalSupply;
    mapping(address => uint256) public totalBorrows;
    mapping(address => int256) public lastPrice;
    mapping(address => uint256) public priceVolatility; // Store volatility values

    event InterestRateUpdated(address indexed asset, uint256 rate);

    constructor(
        address _priceOracle,
        uint256 _baseRate,
        uint256 _priceFactor,
        uint256 _supplyFactor
    ) {
        priceOracle = PriceOracle(_priceOracle);
        baseRate = _baseRate;
        priceFactor = _priceFactor;
        supplyFactor = _supplyFactor;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "Only contract owner can execute this function"
        );
        _;
    }

    function setBaseRate(uint256 _newBaseRate) external onlyOwner {
        baseRate = _newBaseRate;
    }

    function getSlope(address asset) public view returns (uint256) {
        uint256 utilization = getUtilizationRate(asset);
        uint256 optimalUtilization = 80e16; // 80% optimal threshold

        // Assign different slopes for different asset risk profiles
        if (isStablecoin(asset)) {
            return utilization <= optimalUtilization ? 0.05e18 : 0.5e18;
        } else if (isBlueChipCrypto(asset)) {
            return utilization <= optimalUtilization ? 0.1e18 : 1.0e18;
        } else {
            return utilization <= optimalUtilization ? 0.2e18 : 1.5e18;
        }
    }

    function getUtilizationRate(address asset) public view returns (uint256) {
        if (totalSupply[asset] == 0) return 0;
        return (totalBorrows[asset] * 1e18) / totalSupply[asset];
    }

    function getPriceVolatility(address asset) public view returns (uint256) {
        return priceVolatility[asset];
    }

    // Separate function to update volatility (called by the owner or periodically)
    function updatePriceVolatility(address asset) external onlyOwner {
        int256 latestPrice = priceOracle.getLatestPrice(asset);

        // If this is the first time, no volatility to calculate
        if (lastPrice[asset] == 0) {
            lastPrice[asset] = latestPrice;
            return;
        }

        uint256 newVolatility = abs(int256(lastPrice[asset]) - latestPrice);
        priceVolatility[asset] = newVolatility;

        // Update the last price
        lastPrice[asset] = latestPrice;
    }

    function getSupplyDemandRatio(address asset) public view returns (uint256) {
        if (totalSupply[asset] == 0) return 0;
        return
            ((totalSupply[asset] - totalBorrows[asset]) * 1e18) /
            totalSupply[asset];
    }

    function getDynamicBorrowRate(address asset) public view returns (uint256) {
        uint256 utilization = getUtilizationRate(asset);
        uint256 assetPriceVolatility = getPriceVolatility(asset);
        uint256 supplyDemandRatio = getSupplyDemandRatio(asset);
        uint256 slope = getSlope(asset); // Dynamically get slope

        uint256 rate = baseRate +
            ((slope * utilization) / 1e18) +
            ((priceFactor * assetPriceVolatility) / 1e18) +
            ((supplyFactor * supplyDemandRatio) / 1e18);

        return rate;
    }

    function getLendingRate(address asset) public view returns (uint256) {
        uint256 utilization = getUtilizationRate(asset);
        uint256 borrowRate = getDynamicBorrowRate(asset);
        uint256 reserveFactor = 10e16; // Example: 10% protocol fee

        return (borrowRate * utilization * (1e18 - reserveFactor)) / 1e36;
    }

    // ======= HELPER FUNCTIONS ========
    // function to calculate the absolute value, making sure is a positive number
    function abs(int256 x) private pure returns (uint256) {
        return x < 0 ? uint256(-x) : uint256(x);
    }

    // Function to check if an asset is a stablecoin
    function isStablecoin(address asset) public view returns (bool) {
        return stablecoins[asset];
    }

    // Function to check if an asset is a blue-chip crypto
    function isBlueChipCrypto(address asset) public view returns (bool) {
        return blueChipAssets[asset];
    }

    // Admin function to add assets to categories (onlyOwner pattern recommended)
    function addStablecoin(address asset) external onlyOwner {
        stablecoins[asset] = true;
    }

    function addBlueChipAsset(address asset) external onlyOwner {
        blueChipAssets[asset] = true;
    }
}
