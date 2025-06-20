// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "./Market.sol";

contract Vault is ERC4626, ReentrancyGuard {
    using Math for uint256;

    Market public market; // Store the market
    IERC4626 public strategy;
    address public marketOwner;

    //Events
    event BorrowedByMarket(address indexed market, uint256 amount);
    event RepaidToVault(address indexed market, uint256 amount);
    event StrategyChanged(address oldStrategy, address newStrategy);
    event StrategyFundsRedeemed(uint256 amount);
    event MarketOwnerChanged(address oldOwner, address newOwner);

    constructor(
        IERC20 _asset,
        address _marketContract,
        address _strategy, // The initial strategy vault to deposit into
        string memory _name, // Vault token name
        string memory _symbol // Vault token symbol
    ) ERC20(_name, _symbol) ERC4626(IERC20(_asset)) {
        require(address(_asset) != address(0), "Invalid asset address");
        require(_strategy != address(0), "Invalid strategy");
        // Check that the strategy vault's underlying asset matches this vault's asset
        require(
            ERC4626(_strategy).asset() == address(_asset),
            "Strategy asset mismatch"
        );

        market = Market(_marketContract);
        strategy = ERC4626(_strategy);
        marketOwner = msg.sender;

        // Approve strategy to pull tokens from this vault
        IERC20(_asset).approve(address(strategy), type(uint256).max);
    }

    modifier onlyMarketOwner() {
        require(msg.sender == marketOwner, "Not market owner");
        _;
    }

    modifier onlyMarket() {
        require(msg.sender == address(market), "Not market");
        _;
    }

    // ========== Admin Functions ==========

    function setMarket(address _market) external onlyMarketOwner {
        require(address(market) == address(0), "Market already set");
        require(_market != address(0), "Invalid market address");
        Market newMarket = Market(_market);
        // Vault can only receive valid market asset
        require(
            address(newMarket.loanAsset()) == asset(),
            "Mismatched loan asset"
        );

        market = newMarket;
    }

    /// Marked as nonReentrant to prevent inconsistent state during strategy transition.
    /// This ensures that no other sensitive functions (e.g., withdraw or adminBorrow)
    /// can execute while funds are temporarily idle between redemption from the old
    /// strategy and deposit into the new one, preventing potential misuse or loss of funds.
    function changeStrategy(
        address _newStrategy
    ) external onlyMarketOwner nonReentrant {
        require(_newStrategy != address(0), "Invalid strategy");

        require(
            ERC4626(_newStrategy).asset() == address(asset()),
            "Strategy asset mismatch"
        );

        // Withdraw from the old strategy
        uint256 amountRedeemed = strategy.redeem(
            strategy.balanceOf(address(this)),
            address(this),
            address(this)
        );
        require(amountRedeemed > 0, "No funds in strategy to redeem");

        emit StrategyChanged(address(strategy), _newStrategy);
        emit StrategyFundsRedeemed(amountRedeemed);

        strategy = ERC4626(_newStrategy);
        IERC20(asset()).approve(_newStrategy, type(uint256).max);

        // Immediately deposit idle assets into the new strategy
        uint256 idleBalance = IERC20(asset()).balanceOf(address(this));
        if (idleBalance > 0) {
            strategy.deposit(idleBalance, address(this));
        }
    }

    function transferMarketOwnership(
        address newOwner
    ) external onlyMarketOwner {
        require(newOwner != address(0), "Invalid new owner");
        emit MarketOwnerChanged(marketOwner, newOwner);
        marketOwner = newOwner;
    }

    // Deposit ERC-20 tokens into the vault
    function deposit(
        uint256 amount,
        address receiver
    ) public override nonReentrant returns (uint256 shares) {
        // Perform standard ERC4626 deposit (transfers tokens from sender, mints shares)
        shares = super.deposit(amount, receiver);

        // After deposit, if a strategy is set, forward the assets to it
        if (address(strategy) != address(0)) {
            // Vault receives shares from strategy that represent a claim on the assets.
            strategy.deposit(amount, address(this));
        }
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 shares) {
        require(
            assets <= availableLiquidity(),
            "Vault: Insufficient liquidity"
        );

        shares = previewWithdraw(assets); // Lock in required shares before strategy state changes

        // Always pull required assets back from the strategy
        strategy.withdraw(assets, address(this), address(this));

        _withdraw(msg.sender, receiver, owner, assets, shares); // Burn shares and transfer assets

        return shares;
    }

    // Admin function to borrow tokens, only callable by the market contract
    function adminBorrow(uint256 amount) external nonReentrant onlyMarket {
        // Pull the full amount from the strategy into the vault
        strategy.withdraw(amount, address(this), address(this));

        // Transfer the borrowed funds to the market (without burning shares)
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

        // If a strategy is set, forward the funds to it
        if (address(strategy) != address(0)) {
            strategy.deposit(amount, address(this));
        }

        // Emit an event for the repayment action
        emit RepaidToVault(msg.sender, amount);
    }

    function totalAssets() public view override returns (uint256) {
        return totalStrategyAssets() + market.totalBorrowsWithInterest();
    }

    function totalStrategyAssets() public view returns (uint256) {
        // Retrieves the deployed assets in the strategy.
        return strategy.convertToAssets(strategy.balanceOf(address(this)));
    }

    // Covers what the strategy can immediately redeem
    function availableLiquidity() public view returns (uint256) {
        return strategy.maxWithdraw(address(this));
    }

    function maxWithdraw(address user) public view override returns (uint256) {
        uint256 strategyAssets = totalStrategyAssets(); // Total assets available (fully deployed)
        if (strategyAssets == 0) return 0; // no assets to withdraw

        uint256 userShares = balanceOf(user);
        uint256 totalShares = totalSupply();
        if (totalShares == 0) return 0; // avoid div-by-zero
        // User can withdraw a proportion of the strategy assets, based on their share ownership
        // (userShares * strategyAssets) / totalShares
        uint256 userProportionalAssets = userShares.mulDiv(
            strategyAssets,
            totalShares,
            Math.Rounding.Floor
        );

        // If user's withdrawable amount is more than liquidity, cap it to liquidity
        return Math.min(userProportionalAssets, availableLiquidity());
    }

    function maxRedeem(address user) public view override returns (uint256) {
        uint256 userShares = balanceOf(user);
        uint256 totalShares = totalSupply();
        uint256 liquidity = availableLiquidity();
        uint256 strategyAssets = totalStrategyAssets();

        if (totalShares == 0 || strategyAssets == 0) return 0;

        // Max shares user can redeem, based on how much liquidity is available
        uint256 maxSharesFromLiquidity = liquidity.mulDiv(
            totalShares,
            strategyAssets,
            Math.Rounding.Floor
        );

        return Math.min(userShares, maxSharesFromLiquidity);
    }

    // add to deposit into strategy
    function mint(
        uint256 shares,
        address receiver
    ) public override nonReentrant returns (uint256 assets) {
        // Call the parent function which handles pulling in tokens and minting shares
        assets = super.mint(shares, receiver);

        // After mint, if a strategy is set, forward the assets to it
        if (address(strategy) != address(0)) {
            strategy.deposit(assets, address(this));
        }

        return assets;
    }

    // add to withdraw from strategy
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 assets) {
        // Determine the amount of assets equivalent to the shares
        assets = previewRedeem(shares);

        // Ensure there's enough liquidity
        require(
            assets <= availableLiquidity(),
            "Vault: Insufficient liquidity"
        );

        // Pull assets from strategy before redeeming shares
        strategy.withdraw(assets, address(this), address(this));

        // Burn the shares and transfer assets to receiver
        _withdraw(msg.sender, receiver, owner, assets, shares);

        return assets;
    }

    function getStrategy() external view returns (address) {
        return address(strategy);
    }
}
