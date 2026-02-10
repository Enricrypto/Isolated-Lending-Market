// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./MarketV1.sol";
import "../libraries/Errors.sol";
import "../libraries/Events.sol";
import "../access/ProtocolAccessControl.sol";

/**
 * @title Vault
 * @notice ERC-4626 compliant vault for lending protocol liquidity management
 * @dev Integrates with external yield strategies while serving market borrow demands.
 *      Uses AccessControl for role-based permissions (STRATEGY_MANAGER_ROLE).
 * @author Your Team
 *
 * Key Features:
 * - Full ERC-4626 compliance for standard vault operations
 * - Strategy integration for yield generation
 * - Hot-swappable strategies with safety checks
 * - Market integration for lending operations
 * - Liquidity management across strategy and borrows
 *
 * Architecture:
 * - Depositors receive vault shares representing their claim on assets
 * - Assets are deployed to yield-generating strategies (ERC-4626)
 * - Market can borrow from vault for lending operations
 * - Total assets = strategy assets + market borrows (with interest)
 */
contract Vault is ERC4626, ReentrancyGuard, ProtocolAccessControl {
    using Math for uint256;

    // ==================== STATE VARIABLES ====================

    /// @notice Linked market contract for borrowing operations
    MarketV1 public market;

    /// @notice Current yield strategy (ERC-4626 vault)
    IERC4626 public strategy;

    /// @notice Legacy marketOwner variable (deprecated, use AccessControl roles)
    address public marketOwner;

    /// @notice Strategy change in progress flag
    bool private _strategyChanging;

    // ==================== CONSTANTS ====================

    uint256 private constant PRECISION = 1e18;

    // ==================== CONSTRUCTOR ====================

    /**
     * @notice Initialize the vault
     * @param _asset Underlying asset (e.g., USDC)
     * @param _marketContract Market contract address (can be set later)
     * @param _strategy Initial yield strategy address
     * @param _owner Initial owner address
     * @param _name Vault token name
     * @param _symbol Vault token symbol
     */
    constructor(
        IERC20 _asset,
        address _marketContract,
        address _strategy,
        address _owner,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) ERC4626(IERC20(_asset)) {
        if (address(_asset) == address(0)) {
            revert Errors.InvalidTokenAddress();
        }
        if (_strategy == address(0)) revert Errors.InvalidStrategy();
        if (_owner == address(0)) revert Errors.ZeroAddress();

        // Verify strategy asset matches vault asset
        if (ERC4626(_strategy).asset() != address(_asset)) {
            revert Errors.StrategyAssetMismatch();
        }

        strategy = ERC4626(_strategy);
        marketOwner = _owner;

        // Initialize AccessControl
        _initializeAccessControl(_owner);
        _grantRole(ProtocolRoles.STRATEGY_MANAGER_ROLE, _owner);

        // Pre-approve strategy for deposits
        IERC20(_asset).approve(address(strategy), type(uint256).max);

        // Market can be set later if not available at deployment
        if (_marketContract != address(0)) {
            _setMarket(_marketContract);
        }
    }

    // ==================== MODIFIERS ====================

    // Note: Role-based modifiers inherited from ProtocolAccessControl (onlyStrategyManager)

    modifier onlyMarket() {
        if (msg.sender != address(market)) revert Errors.OnlyMarket();
        _;
    }

    modifier whenNotChangingStrategy() {
        if (_strategyChanging) revert Errors.InvalidStrategy();
        _;
    }

    // ==================== ADMIN FUNCTIONS ====================

    /**
     * @notice Set the market contract (one-time operation)
     * @param _market Market contract address
     * @dev Can only be called once, validates the market contract
     */
    function setMarket(address _market) external onlyStrategyManager {
        if (address(market) != address(0)) revert Errors.MarketAlreadySet();
        _setMarket(_market);
    }

    /**
     * @notice Change the yield strategy
     * @param _newStrategy New strategy address
     * @dev Migrates all funds from old strategy to new strategy atomically
     */
    function changeStrategy(address _newStrategy) external onlyStrategyManager nonReentrant {
        if (_newStrategy == address(0)) revert Errors.InvalidStrategy();
        if (_newStrategy == address(strategy)) revert Errors.InvalidStrategy();

        // Verify new strategy asset matches
        if (ERC4626(_newStrategy).asset() != asset()) {
            revert Errors.StrategyAssetMismatch();
        }

        // Set flag to prevent operations during migration
        _strategyChanging = true;

        address oldStrategy = address(strategy);
        uint256 oldStrategyShares = strategy.balanceOf(address(this));

        // Redeem all from old strategy
        uint256 amountRedeemed = 0;
        if (oldStrategyShares > 0) {
            amountRedeemed = strategy.redeem(oldStrategyShares, address(this), address(this));
        }

        // Update strategy reference
        strategy = ERC4626(_newStrategy);

        // Approve new strategy
        IERC20(asset()).approve(_newStrategy, type(uint256).max);

        // Deposit all idle assets into new strategy
        uint256 idleBalance = IERC20(asset()).balanceOf(address(this));
        if (idleBalance > 0) {
            strategy.deposit(idleBalance, address(this));
        }

        // Clear flag
        _strategyChanging = false;

        emit Events.StrategyChanged(oldStrategy, _newStrategy, amountRedeemed);
    }

    /**
     * @notice Transfer ownership of the vault (grants all admin roles to new owner)
     * @param newOwner New owner address
     */
    function transferMarketOwnership(address newOwner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newOwner == address(0)) revert Errors.InvalidNewOwner();

        // Grant roles to new owner
        _grantRole(DEFAULT_ADMIN_ROLE, newOwner);
        _grantRole(ProtocolRoles.STRATEGY_MANAGER_ROLE, newOwner);

        address oldOwner = marketOwner;
        marketOwner = newOwner;

        emit Events.MarketOwnershipTransferred(oldOwner, newOwner);
    }

    // ==================== ERC-4626 OVERRIDES ====================

    /**
     * @notice Deposit assets into vault
     * @param assets Amount of assets to deposit
     * @param receiver Address to receive vault shares
     * @return shares Amount of shares minted
     * @dev Automatically deploys assets to strategy
     */
    function deposit(uint256 assets, address receiver)
        public
        override
        nonReentrant
        whenNotChangingStrategy
        returns (uint256 shares)
    {
        // Perform standard ERC4626 deposit
        shares = super.deposit(assets, receiver);

        // Deploy to strategy
        _deployToStrategy(assets);

        return shares;
    }

    /**
     * @notice Mint exact amount of shares
     * @param shares Amount of shares to mint
     * @param receiver Address to receive shares
     * @return assets Amount of assets deposited
     */
    function mint(uint256 shares, address receiver)
        public
        override
        nonReentrant
        whenNotChangingStrategy
        returns (uint256 assets)
    {
        // Call parent mint
        assets = super.mint(shares, receiver);

        // Deploy to strategy
        _deployToStrategy(assets);

        return assets;
    }

    /**
     * @notice Withdraw assets from vault
     * @param assets Amount of assets to withdraw
     * @param receiver Address to receive assets
     * @param owner Address of share owner
     * @return shares Amount of shares burned
     */
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        whenNotChangingStrategy
        returns (uint256 shares)
    {
        if (assets > availableLiquidity()) revert Errors.InsufficientLiquidity();

        // Calculate shares before pulling from strategy
        shares = previewWithdraw(assets);

        // Pull assets from strategy
        _withdrawFromStrategy(assets);

        // Burn shares and transfer assets
        _withdraw(msg.sender, receiver, owner, assets, shares);

        return shares;
    }

    /**
     * @notice Redeem shares for assets
     * @param shares Amount of shares to redeem
     * @param receiver Address to receive assets
     * @param owner Address of share owner
     * @return assets Amount of assets withdrawn
     */
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        whenNotChangingStrategy
        returns (uint256 assets)
    {
        // Calculate assets before state changes
        assets = previewRedeem(shares);

        if (assets > availableLiquidity()) revert Errors.InsufficientLiquidity();

        // Pull assets from strategy
        _withdrawFromStrategy(assets);

        // Burn shares and transfer assets
        _withdraw(msg.sender, receiver, owner, assets, shares);

        return assets;
    }

    // ==================== MARKET INTEGRATION ====================

    /**
     * @notice Borrow assets (only callable by market)
     * @param amount Amount to borrow
     * @dev Pulls from strategy and transfers to market
     */
    function adminBorrow(uint256 amount) external nonReentrant onlyMarket whenNotChangingStrategy {
        // Pull from strategy
        _withdrawFromStrategy(amount);

        // Transfer to market
        bool success = IERC20(asset()).transfer(msg.sender, amount);
        if (!success) revert Errors.TransferFailed();

        emit Events.BorrowedByMarket(msg.sender, amount);
    }

    /**
     * @notice Repay borrowed assets (only callable by market)
     * @param amount Amount to repay
     * @dev Receives from market and deploys to strategy
     */
    function adminRepay(uint256 amount) external nonReentrant onlyMarket whenNotChangingStrategy {
        // Transfer from market to vault
        bool success = IERC20(asset()).transferFrom(msg.sender, address(this), amount);
        if (!success) revert Errors.TransferFailed();

        // Deploy to strategy
        _deployToStrategy(amount);

        emit Events.RepaidToVault(msg.sender, amount);
    }

    // ==================== VIEW FUNCTIONS ====================

    /**
     * @notice Calculate total assets under management
     * @return Total assets (strategy + market borrows with interest)
     * @dev Includes accrued interest from market borrows
     */
    function totalAssets() public view override returns (uint256) {
        uint256 strategyAssets = totalStrategyAssets();
        uint256 marketBorrows =
            address(market) != address(0) ? market.totalBorrowsWithInterest() : 0;

        return strategyAssets + marketBorrows;
    }

    /**
     * @notice Get total assets deployed in strategy
     * @return Assets in strategy
     */
    function totalStrategyAssets() public view returns (uint256) {
        uint256 strategyShares = strategy.balanceOf(address(this));
        return strategy.convertToAssets(strategyShares);
    }

    /**
     * @notice Get immediately available liquidity
     * @return Available liquidity that can be withdrawn
     */
    function availableLiquidity() public view returns (uint256) {
        return strategy.maxWithdraw(address(this));
    }

    /**
     * @notice Calculate maximum withdrawable assets for a user
     * @param user User address
     * @return Maximum assets user can withdraw
     */
    function maxWithdraw(address user) public view override returns (uint256) {
        uint256 strategyAssets = totalStrategyAssets();
        if (strategyAssets == 0) return 0;

        uint256 userShares = balanceOf(user);
        uint256 totalShares = totalSupply();
        if (totalShares == 0) return 0;

        // User's proportional share of strategy assets
        uint256 userProportionalAssets =
            userShares.mulDiv(strategyAssets, totalShares, Math.Rounding.Floor);

        // Cap at available liquidity
        uint256 liquidity = availableLiquidity();
        return Math.min(userProportionalAssets, liquidity);
    }

    /**
     * @notice Calculate maximum redeemable shares for a user
     * @param user User address
     * @return Maximum shares user can redeem
     */
    function maxRedeem(address user) public view override returns (uint256) {
        uint256 userShares = balanceOf(user);
        uint256 totalShares = totalSupply();
        uint256 liquidity = availableLiquidity();
        uint256 strategyAssets = totalStrategyAssets();

        if (totalShares == 0 || strategyAssets == 0) return 0;

        // Calculate max shares based on available liquidity
        uint256 maxSharesFromLiquidity =
            liquidity.mulDiv(totalShares, strategyAssets, Math.Rounding.Floor);

        return Math.min(userShares, maxSharesFromLiquidity);
    }

    /**
     * @notice Get current strategy address
     * @return Strategy address
     */
    function getStrategy() external view returns (address) {
        return address(strategy);
    }

    /**
     * @notice Check if strategy is being changed
     * @return True if strategy change in progress
     */
    function isStrategyChanging() external view returns (bool) {
        return _strategyChanging;
    }

    // ==================== INTERNAL FUNCTIONS ====================

    /**
     * @notice Set market contract with validation
     * @param _market Market address
     */
    function _setMarket(address _market) private {
        if (_market == address(0)) revert Errors.InvalidMarketAddress();

        MarketV1 newMarket = MarketV1(_market);

        // Verify market's loan asset matches vault asset
        if (address(newMarket.loanAsset()) != asset()) {
            revert Errors.StrategyAssetMismatch();
        }

        market = newMarket;
        emit Events.MarketSet(_market);
    }

    /**
     * @notice Deploy assets to strategy
     * @param amount Amount to deploy
     */
    function _deployToStrategy(uint256 amount) private {
        if (amount == 0) return;
        strategy.deposit(amount, address(this));
    }

    /**
     * @notice Withdraw assets from strategy
     * @param amount Amount to withdraw
     */
    function _withdrawFromStrategy(uint256 amount) private {
        if (amount == 0) return;
        strategy.withdraw(amount, address(this), address(this));
    }
}
