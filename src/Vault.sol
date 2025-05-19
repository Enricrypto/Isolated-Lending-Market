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
    event BorrowedByMarket(address indexed market, uint256 amount);
    event RepaidToVault(address indexed market, uint256 amount);

    Market public market; // Store the market
    address public owner;

    constructor(
        IERC20 _asset,
        address _marketContract,
        string memory _name, // name of the vault share token
        string memory _symbol // symbol of the vault share token
    ) ERC20(_name, _symbol) ERC4626(IERC20(_asset)) {
        owner = msg.sender;
        require(address(_asset) != address(0), "Invalid asset address");
        if (_marketContract != address(0)) {
            market = Market(_marketContract);
        }
    }

    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "Only contract owner can execute this function"
        );
        _;
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
        return super.deposit(amount, receiver);
    }

    function withdraw(
        uint256 amount,
        address receiver,
        address user
    ) public override nonReentrant returns (uint256 shares) {
        return super.withdraw(amount, receiver, user);
    }

    // Admin function to borrow tokens, only callable by the market contract
    function adminBorrow(uint256 amount) external nonReentrant onlyMarket {
        // Transfer tokens directly from vault to market (without burning shares)
        bool success = IERC20(asset()).transfer(msg.sender, amount);
        require(success, "Token transfer failed");

        emit BorrowedByMarket(msg.sender, amount);
    }

    // Admin function to repay tokens back to the vault, only callable by the market contract
    function adminRepay(uint256 amount) external nonReentrant onlyMarket {
        // Transfer tokens from market to vault (without burning shares)
        bool success = IERC20(asset()).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        require(success, "Token transfer failed");

        // Emit an event for the repayment action
        emit RepaidToVault(msg.sender, amount);
    }

    function totalAssets() public view override returns (uint256) {
        // Retrieves the idle (not lent) assets in the Vault.
        uint256 idleAssets = totalIdle();

        // Adds the borrowed assets, including interests owed to the platform
        uint256 borrowedAssets = market._lentAssets();

        // Return the total assets including borrowed amounts
        return idleAssets + borrowedAssets;
    }

    function totalIdle() public view returns (uint256) {
        // Retrieves the idle (not lent) assets in the Vault.
        return IERC20(asset()).balanceOf(address(this));
    }

    function maxWithdraw(address user) public view override returns (uint256) {
        uint256 idleAssets = totalIdle(); // Only available assets in the vault
        if (idleAssets == 0) return 0; // no assets to withdraw

        uint256 userShares = balanceOf(user); // User's shares
        uint256 totalShares = totalSupply(); // Total shares issued
        // User can withdraw a proportion of the idle assets, based on their share ownership
        return userShares.mulDiv(idleAssets, totalShares, Math.Rounding.Floor);
    }

    function maxRedeem(address user) public view override returns (uint256) {
        uint256 sharesBalance = balanceOf(user);
        uint256 idleAssets = totalIdle();

        if (idleAssets == 0) return 0; // No assets to redeem

        // Convert idle assets to max redeemable shares
        uint256 maxShares = convertToShares(idleAssets);

        // User can only redeem the lesser of their balance or available shares
        return sharesBalance < maxShares ? sharesBalance : maxShares;
    }

    function mint(
        uint256 shares,
        address receiver
    ) public override nonReentrant returns (uint256 assets) {
        return super.mint(shares, receiver);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 assets) {
        return super.redeem(shares, receiver, owner);
    }

    function setMarket(address _market) external onlyOwner {
        require(address(market) == address(0), "Market already set");
        require(_market != address(0), "Invalid market address");
        Market newMarket = Market(_market);
        // Vault can only receive valid market asset
        require(market.loanAsset() == asset(), "Mismatched loan asset");

        market = newMarket;
    }
}
