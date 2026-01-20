// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../src/core/Vault.sol";
import "../../src/core/Market.sol";
import "../../src/core/PriceOracle.sol";
import "../../src/core/InterestRateModel.sol";
import "../Mocks.sol";

/**
 * @title VaultTest
 * @notice Comprehensive test suite for the Vault contract
 * @dev Tests ERC-4626 compliance, strategy integration, and market interactions
 */
contract VaultTest is Test {
    Vault public vault;
    Market public market;
    PriceOracle public oracle;
    InterestRateModel public irm;

    MockERC20 public loanAsset;
    MockERC20 public collateralToken;
    MockPriceFeed public loanAssetFeed;
    MockPriceFeed public collateralFeed;
    MockStrategy public strategy;
    MockStrategy public newStrategy;

    address public owner;
    address public alice;
    address public bob;
    address public charlie;
    address public protocolTreasury;
    address public badDebtAddress;

    uint256 constant INITIAL_LIQUIDITY = 1_000_000e6; // 1M USDC

    function setUp() public {
        owner = address(this);
        alice = address(0x1);
        bob = address(0x2);
        charlie = address(0x3);
        protocolTreasury = address(0x4);
        badDebtAddress = address(0x5);

        // Deploy tokens
        loanAsset = new MockERC20("USD Coin", "USDC", 6);
        collateralToken = new MockERC20("Wrapped Ether", "WETH", 18);

        // Deploy price feeds
        loanAssetFeed = new MockPriceFeed(1e8); // $1.00
        collateralFeed = new MockPriceFeed(2000e8); // $2,000

        // Deploy strategies
        strategy = new MockStrategy(loanAsset, "Strategy Shares", "sUSDC");
        newStrategy = new MockStrategy(loanAsset, "New Strategy", "sUSDC2");

        // Deploy oracle with test contract as owner
        oracle = new PriceOracle(address(this));

        // Only add loan asset price feed initially
        oracle.addPriceFeed(address(loanAsset), address(loanAssetFeed));

        // Deploy vault
        vault = new Vault(
            loanAsset,
            address(0), // Market set later
            address(strategy),
            "Vault Token",
            "vUSDC"
        );

        // Deploy interest rate model
        irm = new InterestRateModel(0.02e18, 0.8e18, 0.04e18, 0.6e18, address(vault), address(0));

        // Deploy market
        market = new Market(
            badDebtAddress,
            protocolTreasury,
            address(vault),
            address(oracle),
            address(irm),
            address(loanAsset)
        );

        // Link contracts
        vault.setMarket(address(market));
        irm.setMarketContract(address(market));

        // Transfer oracle ownership to market
        oracle.transferOwnership(address(market));

        // Set market parameters
        market.setMarketParameters(0.85e18, 0.05e18, 0.1e18);

        // Market adds collateral token (and its price feed)
        market.addCollateralToken(address(collateralToken), address(collateralFeed));

        // Mint tokens to users
        loanAsset.mint(alice, INITIAL_LIQUIDITY);
        loanAsset.mint(bob, INITIAL_LIQUIDITY);
        loanAsset.mint(charlie, INITIAL_LIQUIDITY);
        collateralToken.mint(alice, 100e18);
        collateralToken.mint(bob, 100e18);
    }

    // ========================================
    // ERC4626 BASIC TESTS
    // ========================================

    function testDeposit() public {
        uint256 depositAmount = 1000e6;

        vm.startPrank(alice);
        loanAsset.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, alice);
        vm.stopPrank();

        assertEq(shares, depositAmount, "Shares minted incorrectly");
        assertEq(vault.balanceOf(alice), shares, "Balance incorrect");
        assertEq(vault.totalAssets(), depositAmount, "Total assets incorrect");
    }

    function testMint() public {
        uint256 sharesToMint = 1000e6;

        vm.startPrank(alice);
        loanAsset.approve(address(vault), type(uint256).max);
        uint256 assets = vault.mint(sharesToMint, alice);
        vm.stopPrank();

        assertEq(assets, sharesToMint, "Assets deposited incorrectly");
        assertEq(vault.balanceOf(alice), sharesToMint, "Shares incorrect");
    }

    function testWithdraw() public {
        uint256 depositAmount = 1000e6;

        vm.startPrank(alice);
        loanAsset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);

        uint256 balanceBefore = loanAsset.balanceOf(alice);
        vault.withdraw(depositAmount, alice, alice);
        uint256 balanceAfter = loanAsset.balanceOf(alice);
        vm.stopPrank();

        assertEq(balanceAfter - balanceBefore, depositAmount, "Withdrawal failed");
        assertEq(vault.balanceOf(alice), 0, "Shares not burned");
    }

    function testRedeem() public {
        uint256 depositAmount = 1000e6;

        vm.startPrank(alice);
        loanAsset.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, alice);

        uint256 balanceBefore = loanAsset.balanceOf(alice);
        vault.redeem(shares, alice, alice);
        uint256 balanceAfter = loanAsset.balanceOf(alice);
        vm.stopPrank();

        assertEq(balanceAfter - balanceBefore, depositAmount, "Redemption failed");
        assertEq(vault.balanceOf(alice), 0, "Shares not burned");
    }

    // ========================================
    // STRATEGY INTEGRATION TESTS
    // ========================================

    function testAssetsDeployedToStrategy() public {
        uint256 depositAmount = 1000e6;

        vm.startPrank(alice);
        loanAsset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Check assets were deployed to strategy
        assertTrue(strategy.balanceOf(address(vault)) > 0, "Assets not deployed to strategy");
    }

    function testChangeStrategy() public {
        uint256 depositAmount = 1000e6;

        vm.startPrank(alice);
        loanAsset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Change strategy
        vault.changeStrategy(address(newStrategy));

        assertEq(address(vault.strategy()), address(newStrategy), "Strategy not changed");
        assertTrue(newStrategy.balanceOf(address(vault)) > 0, "Assets not migrated");
        assertEq(strategy.balanceOf(address(vault)), 0, "Old strategy not emptied");
    }

    function testCannotChangeStrategyWithWrongAsset() public {
        MockERC20 wrongAsset = new MockERC20("Wrong", "WRG", 6);
        MockStrategy wrongStrategy = new MockStrategy(wrongAsset, "Wrong Strategy", "sWRG");

        vm.expectRevert();
        vault.changeStrategy(address(wrongStrategy));
    }

    // ========================================
    // MARKET INTEGRATION TESTS
    // ========================================

    function testMarketCanBorrow() public {
        uint256 depositAmount = 10_000e6;
        uint256 borrowAmount = 1000e6;

        // Alice deposits to vault
        vm.startPrank(alice);
        loanAsset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Bob borrows from market
        vm.startPrank(bob);
        collateralToken.approve(address(market), 5e18);
        market.depositCollateral(address(collateralToken), 5e18);
        market.borrow(borrowAmount);
        vm.stopPrank();

        // Check vault accounting
        assertTrue(vault.totalAssets() >= depositAmount, "Total assets incorrect after borrow");
    }

    function testMarketRepayment() public {
        uint256 depositAmount = 10_000e6;
        uint256 borrowAmount = 1000e6;

        // Setup: Alice deposits, Bob borrows
        vm.startPrank(alice);
        loanAsset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        collateralToken.approve(address(market), 5e18);
        market.depositCollateral(address(collateralToken), 5e18);
        market.borrow(borrowAmount);

        // Bob repays
        loanAsset.approve(address(market), type(uint256).max);
        market.repay(borrowAmount);
        vm.stopPrank();

        // Vault should have funds back
        assertGe(vault.totalAssets(), depositAmount, "Funds not returned to vault");
    }

    // ========================================
    // TOTAL ASSETS CALCULATION TESTS
    // ========================================

    function testTotalAssetsWithBorrowing() public {
        uint256 depositAmount = 10_000e6;
        uint256 borrowAmount = 1000e6;

        vm.startPrank(alice);
        loanAsset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 totalAssetsBefore = vault.totalAssets();

        // Bob borrows
        vm.startPrank(bob);
        collateralToken.approve(address(market), 5e18);
        market.depositCollateral(address(collateralToken), 5e18);
        market.borrow(borrowAmount);
        vm.stopPrank();

        uint256 totalAssetsAfter = vault.totalAssets();

        // Total assets should include borrowed amount
        assertGe(totalAssetsAfter, totalAssetsBefore, "Total assets should include borrows");
    }

    function testTotalAssetsWithInterest() public {
        uint256 depositAmount = 10_000e6;
        uint256 borrowAmount = 1000e6;

        vm.startPrank(alice);
        loanAsset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        collateralToken.approve(address(market), 5e18);
        market.depositCollateral(address(collateralToken), 5e18);
        market.borrow(borrowAmount);
        vm.stopPrank();

        uint256 totalAssetsBefore = vault.totalAssets();

        // Time passes, interest accrues
        vm.warp(block.timestamp + 365 days);
        market.updateGlobalBorrowIndex();

        uint256 totalAssetsAfter = vault.totalAssets();

        // Total assets should increase due to interest
        assertGt(totalAssetsAfter, totalAssetsBefore, "Interest not accrued");
    }

    // ========================================
    // LIQUIDITY TESTS
    // ========================================

    function testAvailableLiquidity() public {
        uint256 depositAmount = 10_000e6;
        uint256 borrowAmount = 1000e6;

        vm.startPrank(alice);
        loanAsset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 liquidityBefore = vault.availableLiquidity();

        // Bob borrows
        vm.startPrank(bob);
        collateralToken.approve(address(market), 5e18);
        market.depositCollateral(address(collateralToken), 5e18);
        market.borrow(borrowAmount);
        vm.stopPrank();

        uint256 liquidityAfter = vault.availableLiquidity();

        assertEq(liquidityBefore - liquidityAfter, borrowAmount, "Liquidity not reduced correctly");
    }

    function testCannotWithdrawMoreThanAvailable() public {
        uint256 depositAmount = 10_000e6;
        uint256 borrowAmount = 9000e6;

        vm.startPrank(alice);
        loanAsset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Bob borrows most of the liquidity
        vm.startPrank(bob);
        collateralToken.approve(address(market), 50e18);
        market.depositCollateral(address(collateralToken), 50e18);
        market.borrow(borrowAmount);
        vm.stopPrank();

        // Alice tries to withdraw more than available
        vm.startPrank(alice);
        vm.expectRevert();
        vault.withdraw(depositAmount, alice, alice);
        vm.stopPrank();
    }

    // ========================================
    // SHARE CONVERSION TESTS
    // ========================================

    function testConvertToShares() public {
        uint256 assets = 1000e6;
        uint256 shares = vault.convertToShares(assets);

        // Initially should be 1:1
        assertEq(shares, assets, "Conversion incorrect");
    }

    function testConvertToAssets() public {
        uint256 shares = 1000e6;
        uint256 assets = vault.convertToAssets(shares);

        // Initially should be 1:1
        assertEq(assets, shares, "Conversion incorrect");
    }

    function testPreviewFunctions() public {
        uint256 amount = 1000e6;

        assertEq(vault.previewDeposit(amount), amount, "PreviewDeposit incorrect");
        assertEq(vault.previewMint(amount), amount, "PreviewMint incorrect");
        assertEq(vault.previewWithdraw(amount), amount, "PreviewWithdraw incorrect");
        assertEq(vault.previewRedeem(amount), amount, "PreviewRedeem incorrect");
    }

    // ========================================
    // ACCESS CONTROL TESTS
    // ========================================

    function testOnlyMarketOwnerCanChangeStrategy() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.changeStrategy(address(newStrategy));
    }

    function testOnlyMarketCanBorrow() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.adminBorrow(1000e6);
    }

    function testOnlyMarketCanRepay() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.adminRepay(1000e6);
    }

    function testCannotSetMarketTwice() public {
        vm.expectRevert();
        vault.setMarket(address(market));
    }

    // ========================================
    // EDGE CASE TESTS
    // ========================================

    function testZeroDeposit() public {
        // ERC4626 standard allows 0 deposits (returns 0 shares)
        vm.startPrank(alice);
        loanAsset.approve(address(vault), 0);
        uint256 shares = vault.deposit(0, alice);
        vm.stopPrank();

        assertEq(shares, 0, "Zero deposit should return zero shares");
    }

    function testMultipleUsersIndependentShares() public {
        uint256 depositAmount = 1000e6;

        // Alice deposits
        vm.startPrank(alice);
        loanAsset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Bob deposits
        vm.startPrank(bob);
        loanAsset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, bob);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), vault.balanceOf(bob), "Shares not equal");
    }

    function testMaxFunctions() public {
        uint256 depositAmount = 1000e6;

        vm.startPrank(alice);
        loanAsset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);

        assertGt(vault.maxWithdraw(alice), 0, "MaxWithdraw should be > 0");
        assertGt(vault.maxRedeem(alice), 0, "MaxRedeem should be > 0");
        vm.stopPrank();
    }
}
