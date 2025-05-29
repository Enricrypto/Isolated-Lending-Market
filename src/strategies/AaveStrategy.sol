// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IPool} from "lib/aave-v3-origin/src/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "lib/aave-v3-origin/src/contracts/interfaces/IPoolAddressesProvider.sol";
import {DataTypes} from "lib/aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol";

contract AaveStrategy is IStrategy {
    address public immutable override asset;
    IPool public immutable pool;

    // The Aave Pool Addresses Provider address on your network (e.g., on Ethereum mainnet)
    constructor(address _provider, address _asset) {
        require(_provider != address(0), "Invalid data provider");
        require(_asset != address(0), "Invalid asset");

        IPoolAddressesProvider provider = IPoolAddressesProvider(_provider);
        pool = IPool(provider.getPool());
        asset = _asset;

        // Confirm that the asset is supported
        DataTypes.ReserveDataLegacy memory reserve = pool.getReserveData(asset);
        require(reserve.aTokenAddress != address(0), "Asset not supported");
    }

    // Deposit funds into Aave
    function deposit(uint256 amount) external override {
        require(amount > 0, "Zero amount");
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        IERC20(asset).approve(address(pool), amount);
        pool.supply(asset, amount, msg.sender, 0); // deposits on behalf of msg.sender
    }

    // Withdraw amount of the underlying asset from Aave to the caller
    function withdraw(uint256 amount) external override {
        require(amount > 0, "Zero amount");
        pool.withdraw(asset, amount, msg.sender); // sends to caller
    }

    // Withdraws all and returns the total amount withdrawn
    function withdrawAll() external override returns (uint256) {
        uint256 balance = balanceOf(msg.sender);
        if (balance == 0) return 0;

        uint256 withdrawn = pool.withdraw(asset, balance, msg.sender);
        return withdrawn;
    }

    // Returns the total assets held in Aave for the given address
    function balanceOf(address vaultAddress) public view returns (uint256) {
        DataTypes.ReserveDataLegacy memory reserve = pool.getReserveData(asset);
        return IERC20(reserve.aTokenAddress).balanceOf(vaultAddress);
    }

    // Total Aave balance held by this strategy contract (can be used by external views)
    function totalAssets() external view override returns (uint256) {
        return balanceOf(address(this));
    }
}
