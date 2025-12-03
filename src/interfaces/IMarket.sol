// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../libraries/DataTypes.sol";

/**
 * @title IMarket
 * @notice Interface for the Market contract
 * @dev Defines all external functions for the lending market
 */
interface IMarket {
    // ==================== ADMIN FUNCTIONS ====================

    function setMarketParameters(
        uint256 _lltv,
        uint256 _liquidationPenalty,
        uint256 _protocolFeeRate
    ) external;

    function addCollateralToken(address token, address priceFeed) external;

    function pauseCollateralDeposits(address token) external;

    function resumeCollateralDeposits(address token) external;

    function removeCollateralToken(address token) external;

    function setPaused(bool _paused) external;

    // ==================== USER FUNCTIONS ====================

    function depositCollateral(address token, uint256 amount) external;

    function withdrawCollateral(address token, uint256 rawAmount) external;

    function borrow(uint256 amount) external;

    function repay(uint256 amount) external;

    function liquidate(address borrower) external;

    // ==================== VIEW FUNCTIONS ====================

    function totalBorrowsWithInterest() external view returns (uint256);

    function getMarketParameters()
        external
        view
        returns (uint256 lltv, uint256 liquidationPenalty, uint256 protocolFeeRate);

    function getLendingRate() external view returns (uint256);

    function isHealthy(address user) external view returns (bool);

    function getUserPosition(address user)
        external
        view
        returns (DataTypes.UserPosition memory position);

    function getUserTotalDebt(address user) external view returns (uint256);

    function getBorrowerInterestAccrued(address borrower) external view returns (uint256);

    function getUserTotalCollateralValue(address user) external view returns (uint256);

    function getBadDebt(address user) external view returns (uint256);

    function getLoanAssetDecimals() external view returns (uint8);

    // ==================== STATE VARIABLES ====================

    function owner() external view returns (address);

    function protocolTreasury() external view returns (address);

    function badDebtAddress() external view returns (address);

    function loanAsset() external view returns (IERC20);

    function totalBorrows() external view returns (uint256);

    function globalBorrowIndex() external view returns (uint256);

    function paused() external view returns (bool);

    function supportedCollateralTokens(address token) external view returns (bool);

    function depositsPaused(address token) external view returns (bool);

    function userCollateralBalances(address user, address token) external view returns (uint256);

    function userTotalDebt(address user) external view returns (uint256);

    function lastUpdatedIndex(address user) external view returns (uint256);

    function unrecoveredDebt(address user) external view returns (uint256);
}
