// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IWETH {
    // Deposit ETH to mint WETH (users send ETH to the contract)
    function deposit() external payable;

    // Withdraw WETH to get ETH (users burn WETH to get ETH)
    function withdraw(uint256 amount) external;

    // ERC20 functionality
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}
