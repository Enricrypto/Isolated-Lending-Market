// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IInterestRateModel
 * @notice Interface for the InterestRateModel contract
 * @dev Defines functions for interest rate calculations and parameter management
 */
interface IInterestRateModel {
    // ==================== ADMIN FUNCTIONS ====================

    function setMarketContract(address _market) external;

    function setBaseRate(uint256 _newBaseRate) external;

    function setOptimalUtilization(uint256 _newOptimalUtilization) external;

    function setSlope1(uint256 _newSlope1) external;

    function setSlope2(uint256 _newSlope2) external;

    // ==================== VIEW FUNCTIONS ====================

    function getTotalBorrows() external view returns (uint256);

    function getTotalAssets() external view returns (uint256);

    function getUtilizationRate() external view returns (uint256);

    function getDynamicBorrowRate() external view returns (uint256);

    function getRateAtOptimal() external view returns (uint256);

    function getMaxRate() external view returns (uint256);

    function getParameters()
        external
        view
        returns (uint256 _baseRate, uint256 _optimalUtilization, uint256 _slope1, uint256 _slope2);

    // ==================== STATE VARIABLES ====================

    function baseRate() external view returns (uint256);

    function optimalUtilization() external view returns (uint256);

    function slope1() external view returns (uint256);

    function slope2() external view returns (uint256);

    function owner() external view returns (address);

    function vaultContract() external view returns (address);

    function marketContract() external view returns (address);
}
