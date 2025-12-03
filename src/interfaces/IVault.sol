// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title IVault
 * @notice Interface for the Vault contract
 * @dev Extends IERC4626 with custom vault functionality
 */
interface IVault is IERC4626 {
    // ==================== ADMIN FUNCTIONS ====================

    function setMarket(address _market) external;

    function changeStrategy(address _newStrategy) external;

    function transferMarketOwnership(address newOwner) external;

    // ==================== MARKET FUNCTIONS ====================

    function adminBorrow(uint256 amount) external;

    function adminRepay(uint256 amount) external;

    // ==================== VIEW FUNCTIONS ====================

    function totalStrategyAssets() external view returns (uint256);

    function availableLiquidity() external view returns (uint256);

    function getStrategy() external view returns (address);

    function isStrategyChanging() external view returns (bool);

    // ==================== STATE VARIABLES ====================

    function market() external view returns (address);

    function strategy() external view returns (address);

    function marketOwner() external view returns (address);
}
