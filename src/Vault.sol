// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "./Market.sol";

contract Vault is ERC4626, ReentrancyGuard {
    using Math for uint256;

    //Events
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event BorrowedByMarket(address indexed market, uint256 amount);
    event RepaidToVault(address indexed market, uint256 amount);
    event Deposit(address indexed user, uint256 amount, uint256 shares);
    event Withdraw(address indexed user, uint256 amount, uint256 shares);

    Market public market; // Store the market

    constructor(
        IERC20 _asset,
        address _marketContract,
        string memory _name, // name of the vault share token
        string memory _symbol // symbol of the vault share token
    ) ERC20(_name, _symbol) ERC4626(IERC20(_asset)) {
        market = Market(_marketContract);
    }

    modifier onlyMarket() {
        require(
            msg.sender == address(market),
            "Only Market contract can execute this function"
        );
        _;
    }

    /// @notice Deposit ERC-20 tokens into the vault
    function deposit(
        uint256 amount,
        address receiver
    ) public override nonReentrant returns (uint256 shares) {
        require(amount > 0, "Deposit amount must be greater than 0");
        shares = super.deposit(amount, receiver);
        emit Deposit(receiver, amount, shares);
        return shares;
    }

    function withdraw(
        uint256 amount,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 shares) {
        require(amount > 0, "Withdraw amount must be greater than 0");
        shares = super.withdraw(amount, receiver, owner);
        emit Withdraw(owner, amount, shares);
        return shares;
    }

    // Admin function to borrow tokens, only callable by the market contract
    function adminBorrow(uint256 amount) external nonReentrant onlyMarket {
        IERC20 token = IERC20(asset());
        require(address(token) != address(0), "Asset token is not set");

        // Transfer tokens directly from vault to market (without burning shares)
        bool success = token.transfer(msg.sender, amount);
        require(success, "Token transfer failed");

        emit BorrowedByMarket(msg.sender, amount);
    }

    // Admin function to repay tokens back to the vault, only callable by the market contract
    function adminRepay(uint256 amount) external onlyMarket {
        IERC20 token = IERC20(asset());
        require(address(token) != address(0), "Asset token is not set");
        // Transfer tokens from market to vault (without burning shares)
        bool success = token.transferFrom(msg.sender, address(this), amount);
        require(success, "Token transfer failed");

        // Emit an event for the repayment action
        emit RepaidToVault(msg.sender, amount);
    }

    function totalAssets() public view override returns (uint256) {
        // Retrieves the idle (not lent) assets in the Vault.
        uint256 idleAssets = totalLiquidity();

        // If there are no idle assets, just return zero to avoid division errors.
        if (idleAssets == 0) {
            return 0;
        }

        // Adds the borrowed assets PLUS interest accrued.
        uint256 totalBorrowedPlusInterest = market._borrowedPlusInterest();
        require(totalBorrowedPlusInterest >= 0, "Invalid borrowedPlusInterest");

        // Return the total assets including borrowed amounts and interest
        return idleAssets + totalBorrowedPlusInterest;
    }

    function totalLiquidity() public view returns (uint256) {
        // Retrieves the idle (not lent) assets in the Vault.
        uint256 idleAssets = IERC20(asset()).balanceOf(address(this));
        return idleAssets;
    }

    function previewDeposit(
        uint256 assets
    ) public view override returns (uint256) {
        uint256 total = totalAssets();

        // If no assets in vault yet, assume assets == totalAssets to prevent division errors
        if (total == 0) {
            return assets; // 1 asset = 1 share on first deposit
        }

        return _convertToShares(assets, Math.Rounding.Floor);
    }

    function previewWithdraw(
        uint256 assets
    ) public view override returns (uint256) {
        uint256 idleAssets = totalLiquidity(); // Only withdrawable assets
        uint256 totalShares = totalSupply();

        if (idleAssets == 0 || totalShares == 0) {
            return 0; // No assets available, so no shares can be redeemed
        }

        // Convert assets to shares using idle assets only
        return assets.mulDiv(totalShares, idleAssets, Math.Rounding.Ceil);
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 idleAssets = totalLiquidity(); // Only available assets in the vault
        if (idleAssets == 0) return 0; // no assets to withdraw

        uint256 userShares = balanceOf(owner); // User's shares
        uint256 totalShares = totalSupply(); // Total shares issued
        // User can withdraw a proportion of the idle assets, based on their share ownership
        return userShares.mulDiv(idleAssets, totalShares, Math.Rounding.Floor);
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        uint256 sharesBalance = balanceOf(owner);
        uint256 idleAssets = totalLiquidity();

        if (idleAssets == 0) return 0; // No assets to redeem

        // Convert idle assets to max redeemable shares
        uint256 maxShares = convertToShares(idleAssets);

        // User can only redeem the lesser of their balance or available shares
        return sharesBalance < maxShares ? sharesBalance : maxShares;
    }
}
