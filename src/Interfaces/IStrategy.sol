// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStrategy {
    function asset() external view returns (address);
    function deposit(
        uint256 amount,
        address receiver
    ) external returns (uint256 shares);
    function withdraw(
        uint256 amount,
        address receiver,
        address owner
    ) external returns (uint256 shares);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}
