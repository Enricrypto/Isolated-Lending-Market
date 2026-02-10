// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IStrategy } from "../interfaces/IStrategy.sol";

interface CErc20 {
    function mint(uint256) external returns (uint256);
    function redeemUnderlying(uint256) external returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function exchangeRateStored() external view returns (uint256);
}

contract CompoundV2Adapter is IStrategy {
    using SafeERC20 for IERC20;

    address public immutable override asset;
    address public immutable vault;
    CErc20 public immutable cToken;

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault");
        _;
    }

    constructor(address _vault, address _asset, address _cToken) {
        require(_vault != address(0), "Invalid vault");
        require(_asset != address(0), "Invalid asset");
        require(_cToken != address(0), "Invalid cToken");

        vault = _vault;
        asset = _asset;
        cToken = CErc20(_cToken);

        IERC20(_asset).approve(_cToken, type(uint256).max);
    }

    function deposit(uint256 amount) external override onlyVault returns (uint256) {
        IERC20(asset).safeTransferFrom(vault, address(this), amount);
        uint256 result = cToken.mint(amount);
        require(result == 0, "Compound mint failed");
        return amount;
    }

    function withdraw(uint256 amount) external override onlyVault returns (uint256) {
        uint256 before = totalAssets();
        uint256 result = cToken.redeemUnderlying(amount);
        require(result == 0, "Compound redeem failed");
        return before - totalAssets();
    }

    function convertToAssets(uint256 shares) external view override returns (uint256) {
        uint256 exchangeRate = cToken.exchangeRateStored();
        return (shares * exchangeRate) / 1e18;
    }

    function balanceOf(address user) public view override returns (uint256) {
        uint256 cBal = cToken.balanceOf(user);
        uint256 exchangeRate = cToken.exchangeRateStored();
        return (cBal * exchangeRate) / 1e18;
    }

    function totalAssets() public view override returns (uint256) {
        return balanceOf(address(this));
    }
}
