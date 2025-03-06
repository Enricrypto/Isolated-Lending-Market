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

    uint256 public constant BLOCKS_PER_YEAR = 2_102_400; // Approx. 12s block time

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

    function setMarketContract(address _marketContract) external onlyOwner {
        marketContract = Market(_marketContract);
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

    // Function to calculate the total supply of the vault excluding interest
    function getTotalSupplyWithoutInterest() public view returns (uint256) {
        // Get total assets from the Vault contract
        uint256 totalAssets = vaultContract.totalAssets(); // Includes both principal and interest

        // Get total interest accrued from the Market contract
        uint256 totalInterestAccrued = marketContract
            ._getTotalInterestAccrued();

        // Subtract interest from total assets to get the total supply excluding interest
        uint256 totalSupplyWithoutInterest = totalAssets - totalInterestAccrued;

        return totalSupplyWithoutInterest;
    }

    // Fetch total borrows from Market Contract
    function getTotalBorrows() public view returns (uint256) {
        return marketContract.totalBorrows();
    }

    // Calculate utilization rate: U = totalBorrows / totalSupply
    function getUtilizationRate() public view returns (uint256) {
        uint256 totalSupply = getTotalSupplyWithoutInterest();
        uint256 totalBorrows = getTotalBorrows();
        if (totalSupply == 0) return 0;
        return (totalBorrows * 1e18) / totalSupply;
    }

    // Calculate the dynamic borrow rate based on Jump-Rate model
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

    // Function to get borrow rate per block
    function getBorrowRatePerBlock() public view returns (uint256) {
        return getDynamicBorrowRate() / BLOCKS_PER_YEAR;
    }
}
