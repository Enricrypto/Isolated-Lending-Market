// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Vault.sol";
import "./Market.sol";

contract InterestRateModel {
    uint256 public baseRate; // Base interest rate (minimum rate applied to all loans)
    uint256 public optimalUtilization; // Optimal utilization threshold (e.g.: 80%)
    uint256 public slope1; // Slope before reaching optimal utilization
    uint256 public slope2; // Slope after reaching optimal utilization

    address public owner;
    Vault public vaultContract;
    Market public marketContract; // Address of marketContract to fetch supply/borrow data

    event InterestRateUpdated(address indexed asset, uint256 rate);

    constructor(
        uint256 _baseRate,
        uint256 _optimalUtilization,
        uint256 _slope1,
        uint256 _slope2,
        address _vaultContract,
        address _marketContract
    ) {
        baseRate = _baseRate;
        optimalUtilization = _optimalUtilization;
        slope1 = _slope1;
        slope2 = _slope2;
        vaultContract = Vault(_vaultContract);
        marketContract = Market(_marketContract);
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "Only contract owner can execute this function"
        );
        _;
    }

    function setMarketContract(address _market) external onlyOwner {
        require(address(marketContract) == address(0), "Market already set");
        marketContract = Market(_market);
    }

    function setBaseRate(uint256 _newBaseRate) external onlyOwner {
        baseRate = _newBaseRate;
    }

    function setOptimalUtilization(
        uint256 _newOptimalUtilization
    ) external onlyOwner {
        optimalUtilization = _newOptimalUtilization;
    }

    function setSlope1(uint256 _newSlope1) external onlyOwner {
        slope1 = _newSlope1;
    }

    function setSlope2(uint256 _newSlope2) external onlyOwner {
        slope2 = _newSlope2;
    }

    // Fetch total borrows from Market Contract
    function getTotalBorrows() public view returns (uint256) {
        require(
            address(marketContract) != address(0),
            "Market contract not set"
        );
        return marketContract.totalBorrows();
    }

    function getTotalAssets() public view returns (uint256) {
        return vaultContract.totalAssets();
    }

    // Calculate utilization rate: U = totalBorrows / totalAssets
    function getUtilizationRate() public view returns (uint256) {
        uint256 totalAssets = getTotalAssets();
        uint256 totalBorrows = getTotalBorrows();
        if (totalAssets == 0) return 0; // avoid division by zero
        return (totalBorrows * 1e18) / totalAssets;
    }

    // Calculate the dynamic borrow rate per year (based on Jump-Rate model)
    function getDynamicBorrowRate() public view returns (uint256) {
        uint256 utilization = getUtilizationRate();

        if (utilization < optimalUtilization) {
            // Below optimal utilization: use slope1
            return baseRate + (utilization * slope1) / 1e18;
        } else {
            // Above optimal utilization: use slope2 (steep increase)
            uint256 excessUtilization = utilization - optimalUtilization;
            return
                baseRate +
                ((optimalUtilization * slope1) / 1e18) +
                ((excessUtilization * slope2) / 1e18);
        }
    }
}
