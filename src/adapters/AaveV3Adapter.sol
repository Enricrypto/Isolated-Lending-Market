// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IStrategy } from "../interfaces/IStrategy.sol";
import { IPool } from "@aave/core-v3/interfaces/IPool.sol";
import { IPoolAddressesProvider } from "@aave/core-v3/interfaces/IPoolAddressesProvider.sol";
import { DataTypes } from "@aave/core-v3/protocol/libraries/types/DataTypes.sol";

contract AaveV3Adapter is IStrategy {
    using SafeERC20 for IERC20;

    address public immutable override asset;
    address public immutable vault;
    IPool public immutable pool;

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault");
        _;
    }

    constructor(address _vault, address provider, address _asset) {
        require(_vault != address(0), "Invalid vault");
        require(provider != address(0), "Invalid provider");
        require(_asset != address(0), "Invalid asset");

        vault = _vault;
        asset = _asset;

        IPoolAddressesProvider p = IPoolAddressesProvider(provider);
        pool = IPool(p.getPool());

        // Simple ERC20 approve in constructor
        IERC20(_asset).approve(address(pool), type(uint256).max);
    }

    function deposit(uint256 amount) external override onlyVault returns (uint256) {
        require(amount > 0, "Zero amount");
        IERC20(asset).safeTransferFrom(vault, address(this), amount);
        pool.supply(asset, amount, address(this), 0);
        return amount;
    }

    function withdraw(uint256 amount) external override onlyVault returns (uint256) {
        require(amount > 0, "Zero amount");
        uint256 before = totalAssets();
        pool.withdraw(asset, amount, vault);
        return before - totalAssets();
    }

    function convertToAssets(uint256 shares) external pure override returns (uint256) {
        return shares; // 1:1 since we treat shares as underlying
    }

    function balanceOf(address user) public view override returns (uint256) {
        DataTypes.ReserveData memory reserve = pool.getReserveData(asset);
        return IERC20(reserve.aTokenAddress).balanceOf(user);
    }

    function totalAssets() public view override returns (uint256) {
        return balanceOf(address(this));
    }
}
