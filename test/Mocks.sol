// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

/**
 * @title MockERC20
 * @notice Mock ERC20 token with configurable decimals for testing
 */
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}

/**
 * @title MockPriceFeed
 * @notice Mock Chainlink price feed for testing
 */
contract MockPriceFeed {
    int256 private price;

    constructor(int256 initialPrice) {
        price = initialPrice;
    }

    function setPrice(int256 _price) external {
        price = _price;
    }

    function decimals() external pure returns (uint8) {
        return 8; // Chainlink standard
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (1, price, block.timestamp, block.timestamp, 1);
    }
}

/**
 * @title MockStrategy
 * @notice Mock ERC4626 strategy for testing vault integrations
 * @dev Simple 1:1 share/asset ratio for predictable testing
 */
contract MockStrategy is ERC4626 {
    constructor(IERC20 _asset, string memory name, string memory symbol)
        ERC20(name, symbol)
        ERC4626(_asset)
    { }

    // ==================== ERC4626 OVERRIDES ====================

    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        shares = assets;
        IERC20(address(asset())).transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        assets = shares;
        IERC20(address(asset())).transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        returns (uint256 shares)
    {
        shares = assets;
        _burn(owner, shares);
        IERC20(address(asset())).transfer(receiver, assets);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        returns (uint256 assets)
    {
        assets = shares;
        _burn(owner, shares);
        IERC20(address(asset())).transfer(receiver, assets);
    }

    function totalAssets() public view override returns (uint256) {
        return IERC20(address(asset())).balanceOf(address(this));
    }

    function convertToAssets(uint256 shares) public pure override returns (uint256) {
        return shares;
    }

    function convertToShares(uint256 assets) public pure override returns (uint256) {
        return assets;
    }

    function maxDeposit(address) public pure override returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public pure override returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address) public view override returns (uint256) {
        return IERC20(address(asset())).balanceOf(address(this));
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        return balanceOf(owner);
    }

    function previewDeposit(uint256 assets) public pure override returns (uint256) {
        return assets;
    }

    function previewMint(uint256 shares) public pure override returns (uint256) {
        return shares;
    }

    function previewWithdraw(uint256 assets) public pure override returns (uint256) {
        return assets;
    }

    function previewRedeem(uint256 shares) public pure override returns (uint256) {
        return shares;
    }
}

/**
 * @title MockYieldStrategy
 * @notice Mock ERC4626 strategy that simulates yield generation
 * @dev Allows manual yield injection for testing interest accrual and vault strategy integration
 */
contract MockYieldStrategy is ERC4626 {
    uint256 public yieldAccrued;

    constructor(IERC20 _asset, string memory name, string memory symbol)
        ERC20(name, symbol)
        ERC4626(_asset)
    { }

    /**
     * @notice Add yield to the strategy for testing
     * @param amount Amount of yield to add
     */
    function addYield(uint256 amount) external {
        yieldAccrued += amount;
        IERC20(address(asset())).transferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Remove yield from the strategy (for testing yield loss scenarios)
     * @param amount Amount of yield to remove
     */
    function removeYield(uint256 amount) external {
        require(yieldAccrued >= amount, "Insufficient yield");
        yieldAccrued -= amount;
        IERC20(address(asset())).transfer(msg.sender, amount);
    }

    // ==================== ERC4626 OVERRIDES ====================

    function totalAssets() public view override returns (uint256) {
        return IERC20(address(asset())).balanceOf(address(this));
    }

    function convertToAssets(uint256 shares) public view override returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return shares;
        // Include yield in conversion calculation
        uint256 totalValue = totalAssets() + yieldAccrued;
        return (shares * totalValue) / supply;
    }

    function convertToShares(uint256 assets) public view override returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return assets;
        // Include yield in conversion calculation
        uint256 totalValue = totalAssets() + yieldAccrued;
        return (assets * supply) / totalValue;
    }

    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        shares = convertToShares(assets);
        IERC20(address(asset())).transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        assets = convertToAssets(shares);
        IERC20(address(asset())).transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        returns (uint256 shares)
    {
        shares = convertToShares(assets);
        _burn(owner, shares);
        IERC20(address(asset())).transfer(receiver, assets);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        returns (uint256 assets)
    {
        assets = convertToAssets(shares);
        _burn(owner, shares);
        IERC20(address(asset())).transfer(receiver, assets);
    }

    function maxDeposit(address) public pure override returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public pure override returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address) public view override returns (uint256) {
        return IERC20(address(asset())).balanceOf(address(this));
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        return balanceOf(owner);
    }

    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view override returns (uint256) {
        return convertToAssets(shares);
    }

    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        return convertToShares(assets);
    }

    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return convertToAssets(shares);
    }
}
