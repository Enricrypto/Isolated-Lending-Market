// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Unified strategy interface for all adapters
interface IStrategy {
    /// @notice The underlying asset (e.g., USDC, DAI, etc.)
    function asset() external view returns (address);

    /// @notice Deposit underlying into the strategy
    /// @param amount The amount of underlying to deposit
    /// @return shares The “shares” minted (optional semantics)
    function deposit(uint256 amount) external returns (uint256 shares);

    /// @notice Withdraw underlying from the strategy
    /// @param amount The amount of underlying to withdraw
    /// @return shares The “shares” burned (optional semantics)
    function withdraw(uint256 amount) external returns (uint256 shares);

    /// @notice Preview how much underlying is represented by shares
    function convertToAssets(uint256 shares) external view returns (uint256);

    /// @notice Balance of assets for a particular owner
    function balanceOf(address owner) external view returns (uint256);

    /// @notice Total assets held by this strategy contract
    function totalAssets() external view returns (uint256);
}
