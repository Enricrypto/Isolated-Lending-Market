// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IStrategy {
    /// Returns the underlying asset this strategy operates on
    function asset() external view returns (address);

    /// Returns the total value managed by this strategy
    function totalAssets() external view returns (uint256);

    /// Returns how much of the strategy is attributed to the given vault/manager
    function balanceOf(address owner) external view returns (uint256);

    /// Deposits `amount` into the strategy
    function deposit(uint256 amount) external;

    /// Withdraws `amount` from the strategy, returning funds to the caller
    function withdraw(uint256 amount) external;

    /// Withdraws all funds to the caller and returns how much was withdrawn
    function withdrawAll() external returns (uint256);
}
