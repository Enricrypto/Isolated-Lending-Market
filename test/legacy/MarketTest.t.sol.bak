// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../src/core/Market.sol";
import "../../src/core/Vault.sol";
import "../../src/core/PriceOracle.sol";
import "../../src/core/InterestRateModel.sol";
import "../Mocks.sol";

/**
 * @title MarketTest
 * @notice Comprehensive test suite for the Market contract
 * @dev Tests collateral management, borrowing, repayment, liquidations, and health factors
 */
contract MarketTest is Test {
    Market public market;
    Vault public vault;
    PriceOracle public oracle;
    InterestRateModel public irm;

    MockERC20 public loanAsset; // USDC (6 decimals)
    MockERC20 public weth; // WETH (18 decimals)
    MockERC20 public wbtc; // WBTC (8 decimals)

    MockPriceFeed public loanAssetFeed;
    MockPriceFeed public wethFeed;
    MockPriceFeed public wbtcFeed;

    MockStrategy public strategy;

    address public owner;
    address public alice;
    address public bob;
    address public charlie;
    address public liquidator;
    address public protocolTreasury;
    address public badDebtAddress;

    uint256 constant INITIAL_MINT = 1_000_000e18;

    function setUp() public {
        owner = address(this);
        alice = address(0x1);
        bob = address(0x2);
        charlie = address(0x3);
        liquidator = address(0x4);
        protocolTreasury = address(0x5);
        badDebtAddress = address(0x6);

        // Deploy tokens
        loanAsset = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);

        // Deploy price feeds with initial prices
        loanAssetFeed = new MockPriceFeed(1e8); // $1.00
        wethFeed = new MockPriceFeed(2000e8); // $2,000
        wbtcFeed = new MockPriceFeed(50_000e8); // $50,000

        // Deploy strategy
        strategy = new MockStrategy(loanAsset, "USDC Strategy", "sUSDC");

        // Deploy oracle
        oracle = new PriceOracle(address(this));
        oracle.addPriceFeed(address(loanAsset), address(loanAssetFeed));

        // Deploy vault
        vault = new Vault(
            loanAsset,
            address(0), // Market set later
            address(strategy),
            "Vault USDC",
            "vUSDC"
        );

        // Deploy interest rate model
        irm = new InterestRateModel(
            0.02e18, // 2% base rate
            0.8e18, // 80% optimal utilization
            0.04e18, // 4% slope1
            0.6e18, // 60% slope2
            address(vault),
            address(0) // Market set later
        );

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

        // Oracle Transfer Ownership:
        oracle.transferOwnership(address(market));

        // Set market parameters
        market.setMarketParameters(
            0.85e18, // 85% LLTV
            0.05e18, // 5% liquidation penalty
            0.1e18 // 10% protocol fee
        );

        // Add collateral tokens
        market.addCollateralToken(address(weth), address(wethFeed));
        market.addCollateralToken(address(wbtc), address(wbtcFeed));

        // Mint tokens to users
        loanAsset.mint(alice, INITIAL_MINT);
        loanAsset.mint(bob, INITIAL_MINT);
        loanAsset.mint(charlie, INITIAL_MINT);
        loanAsset.mint(liquidator, INITIAL_MINT);

        weth.mint(alice, INITIAL_MINT);
        weth.mint(bob, INITIAL_MINT);
        weth.mint(charlie, INITIAL_MINT);

        wbtc.mint(alice, INITIAL_MINT);
        wbtc.mint(bob, INITIAL_MINT);

        // Fund vault with liquidity
        loanAsset.mint(address(this), 10_000_000e6);
        loanAsset.approve(address(vault), type(uint256).max);
        vault.deposit(10_000_000e6, address(this));
    }

    // ========================================
    // COLLATERAL MANAGEMENT TESTS
    // ========================================

    function testDepositCollateral() public {
        uint256 depositAmount = 1e18;

        vm.startPrank(alice);
        weth.approve(address(market), depositAmount);
        market.depositCollateral(address(weth), depositAmount);
        vm.stopPrank();

        uint256 balance = market.userCollateralBalances(alice, address(weth));
        assertEq(balance, depositAmount, "Collateral not deposited correctly");
    }

    function testDepositMultipleCollaterals() public {
        uint256 wethAmount = 1e18;
        uint256 wbtcAmount = 0.1e8;

        vm.startPrank(alice);

        // Deposit WETH
        weth.approve(address(market), wethAmount);
        market.depositCollateral(address(weth), wethAmount);

        // Deposit WBTC
        wbtc.approve(address(market), wbtcAmount);
        market.depositCollateral(address(wbtc), wbtcAmount);

        vm.stopPrank();

        uint256 wethBalance = market.userCollateralBalances(alice, address(weth));
        uint256 wbtcBalance = market.userCollateralBalances(alice, address(wbtc));

        assertEq(wethBalance, wethAmount, "WETH not deposited correctly");
        // WBTC should be normalized to 18 decimals
        assertEq(wbtcBalance, wbtcAmount * 1e10, "WBTC not normalized correctly");
    }

    function testCannotDepositUnsupportedToken() public {
        MockERC20 unsupported = new MockERC20("Unsupported", "UNS", 18);
        unsupported.mint(alice, 1e18);

        vm.startPrank(alice);
        unsupported.approve(address(market), 1e18);
        vm.expectRevert();
        market.depositCollateral(address(unsupported), 1e18);
        vm.stopPrank();
    }

    function testCannotDepositWhenPaused() public {
        market.pauseCollateralDeposits(address(weth));

        vm.startPrank(alice);
        weth.approve(address(market), 1e18);
        vm.expectRevert();
        market.depositCollateral(address(weth), 1e18);
        vm.stopPrank();
    }

    function testWithdrawCollateral() public {
        uint256 depositAmount = 1e18;

        vm.startPrank(alice);
        weth.approve(address(market), depositAmount);
        market.depositCollateral(address(weth), depositAmount);

        uint256 balanceBefore = weth.balanceOf(alice);
        market.withdrawCollateral(address(weth), depositAmount);
        uint256 balanceAfter = weth.balanceOf(alice);
        vm.stopPrank();

        assertEq(balanceAfter - balanceBefore, depositAmount, "Withdrawal failed");
        assertEq(market.userCollateralBalances(alice, address(weth)), 0, "Balance not updated");
    }

    function testCannotWithdrawMoreThanBalance() public {
        uint256 depositAmount = 1e18;

        vm.startPrank(alice);
        weth.approve(address(market), depositAmount);
        market.depositCollateral(address(weth), depositAmount);

        vm.expectRevert();
        market.withdrawCollateral(address(weth), depositAmount + 1);
        vm.stopPrank();
    }

    // ========================================
    // BORROWING TESTS
    // ========================================

    function testBorrow() public {
        uint256 collateralAmount = 2e18; // 2 WETH = $4,000
        uint256 borrowAmount = 1000e6; // $1,000

        vm.startPrank(alice);
        weth.approve(address(market), collateralAmount);
        market.depositCollateral(address(weth), collateralAmount);

        uint256 balanceBefore = loanAsset.balanceOf(alice);
        market.borrow(borrowAmount);
        uint256 balanceAfter = loanAsset.balanceOf(alice);
        vm.stopPrank();

        assertEq(balanceAfter - balanceBefore, borrowAmount, "Borrow failed");
        assertTrue(market.getUserTotalDebt(alice) > 0, "Debt not recorded");
    }

    function testCannotBorrowWithoutCollateral() public {
        vm.startPrank(alice);
        vm.expectRevert();
        market.borrow(1000e6);
        vm.stopPrank();
    }

    function testCannotBorrowMoreThanAllowed() public {
        uint256 collateralAmount = 1e18; // 1 WETH = $2,000
        // LLTV = 85%, max borrow = $2,000 * 0.85 = $1,700
        uint256 borrowAmount = 2000e6; // Try to borrow $2,000

        vm.startPrank(alice);
        weth.approve(address(market), collateralAmount);
        market.depositCollateral(address(weth), collateralAmount);

        vm.expectRevert();
        market.borrow(borrowAmount);
        vm.stopPrank();
    }

    function testBorrowingPowerCalculation() public {
        uint256 collateralAmount = 1e18; // 1 WETH = $2,000
        // LLTV = 85%, max borrow = $2,000 * 0.85 = $1,700

        vm.startPrank(alice);
        weth.approve(address(market), collateralAmount);
        market.depositCollateral(address(weth), collateralAmount);
        market.borrow(1600e6); // Safely under limit accounting for liquidation penalty buffer
        vm.stopPrank();

        assertTrue(market.isHealthy(alice), "Position should be healthy");
    }

    // ========================================
    // REPAYMENT TESTS
    // ========================================

    function testRepay() public {
        uint256 collateralAmount = 2e18;
        uint256 borrowAmount = 1000e6;

        vm.startPrank(alice);
        weth.approve(address(market), collateralAmount);
        market.depositCollateral(address(weth), collateralAmount);
        market.borrow(borrowAmount);

        // Wait for interest to accrue
        vm.warp(block.timestamp + 365 days);
        market.updateGlobalBorrowIndex();

        uint256 debtBefore = market.getUserTotalDebt(alice);
        loanAsset.approve(address(market), borrowAmount);
        market.repay(borrowAmount);
        uint256 debtAfter = market.getUserTotalDebt(alice);
        vm.stopPrank();

        assertTrue(debtAfter < debtBefore, "Debt not reduced");
    }

    function testCannotRepayMoreThanDebt() public {
        uint256 collateralAmount = 2e18;
        uint256 borrowAmount = 1000e6;

        vm.startPrank(alice);
        weth.approve(address(market), collateralAmount);
        market.depositCollateral(address(weth), collateralAmount);
        market.borrow(borrowAmount);

        loanAsset.approve(address(market), type(uint256).max);
        vm.expectRevert();
        market.repay(borrowAmount * 2);
        vm.stopPrank();
    }

    function testInterestAccrual() public {
        uint256 collateralAmount = 2e18;
        uint256 borrowAmount = 1000e6;

        vm.startPrank(alice);
        weth.approve(address(market), collateralAmount);
        market.depositCollateral(address(weth), collateralAmount);
        market.borrow(borrowAmount);

        uint256 debtBefore = market.getUserTotalDebt(alice);

        // Wait 1 year
        vm.warp(block.timestamp + 365 days);
        market.updateGlobalBorrowIndex();

        uint256 debtAfter = market.getUserTotalDebt(alice);
        vm.stopPrank();

        assertTrue(debtAfter > debtBefore, "Interest did not accrue");
    }

    // ========================================
    // LIQUIDATION TESTS
    // ========================================

    function testLiquidation() public {
        uint256 collateralAmount = 1e18; // 1 WETH = $2,000
        uint256 borrowAmount = 1700e6; // Borrow $1,700 (85% of $2,000)

        // Alice deposits and borrows
        vm.startPrank(alice);
        weth.approve(address(market), collateralAmount);
        market.depositCollateral(address(weth), collateralAmount);
        market.borrow(borrowAmount);
        vm.stopPrank();

        // Price drops, making position unhealthy
        wethFeed.setPrice(1500e8); // WETH drops to $1,500

        assertTrue(!market.isHealthy(alice), "Position should be unhealthy");

        // Liquidator liquidates
        vm.startPrank(liquidator);
        loanAsset.approve(address(market), type(uint256).max);
        market.liquidate(alice);
        vm.stopPrank();

        // Check liquidator received collateral
        assertTrue(weth.balanceOf(liquidator) > 0, "Liquidator should receive collateral");
    }

    function testCannotLiquidateHealthyPosition() public {
        uint256 collateralAmount = 2e18;
        uint256 borrowAmount = 1000e6;

        vm.startPrank(alice);
        weth.approve(address(market), collateralAmount);
        market.depositCollateral(address(weth), collateralAmount);
        market.borrow(borrowAmount);
        vm.stopPrank();

        assertTrue(market.isHealthy(alice), "Position should be healthy");

        vm.startPrank(liquidator);
        loanAsset.approve(address(market), type(uint256).max);
        vm.expectRevert();
        market.liquidate(alice);
        vm.stopPrank();
    }

    function testBadDebtHandling() public {
        uint256 collateralAmount = 1e18; // 1 WETH = $2,000
        uint256 borrowAmount = 1700e6; // Borrow $1,700

        vm.startPrank(alice);
        weth.approve(address(market), collateralAmount);
        market.depositCollateral(address(weth), collateralAmount);
        market.borrow(borrowAmount);
        vm.stopPrank();

        // Price crashes severely
        wethFeed.setPrice(1000e8); // WETH drops to $1,000

        vm.startPrank(liquidator);
        loanAsset.approve(address(market), type(uint256).max);
        market.liquidate(alice);
        vm.stopPrank();

        // Check bad debt was recorded
        uint256 badDebt = market.getBadDebt(alice);
        assertTrue(badDebt > 0, "Bad debt should be recorded");
    }

    // ========================================
    // HEALTH FACTOR TESTS
    // ========================================

    function testHealthFactorCalculation() public {
        uint256 collateralAmount = 2e18; // 2 WETH = $4,000
        uint256 borrowAmount = 1000e6; // $1,000

        vm.startPrank(alice);
        weth.approve(address(market), collateralAmount);
        market.depositCollateral(address(weth), collateralAmount);
        market.borrow(borrowAmount);
        vm.stopPrank();

        assertTrue(market.isHealthy(alice), "Should be healthy");

        // Borrow more
        vm.startPrank(alice);
        market.borrow(2000e6); // Total debt now $3,000
        vm.stopPrank();

        assertTrue(market.isHealthy(alice), "Should still be healthy");
    }

    function testCannotWithdrawIfUnhealthy() public {
        uint256 collateralAmount = 2e18; // 2 WETH = $4,000
        uint256 borrowAmount = 3000e6; // $3,000

        vm.startPrank(alice);
        weth.approve(address(market), collateralAmount);
        market.depositCollateral(address(weth), collateralAmount);
        market.borrow(borrowAmount);

        // Try to withdraw collateral that would make position unhealthy
        vm.expectRevert();
        market.withdrawCollateral(address(weth), 1e18);
        vm.stopPrank();
    }

    // ========================================
    // ADMIN FUNCTION TESTS
    // ========================================

    function testOnlyOwnerCanSetParameters() public {
        vm.prank(alice);
        vm.expectRevert();
        market.setMarketParameters(0.8e18, 0.1e18, 0.15e18);
    }

    function testOnlyOwnerCanAddCollateral() public {
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18);
        MockPriceFeed newFeed = new MockPriceFeed(1e8);

        vm.prank(alice);
        vm.expectRevert();
        market.addCollateralToken(address(newToken), address(newFeed));
    }

    function testPauseAndResumeCollateral() public {
        // Pause
        market.pauseCollateralDeposits(address(weth));

        vm.startPrank(alice);
        weth.approve(address(market), 1e18);
        vm.expectRevert();
        market.depositCollateral(address(weth), 1e18);
        vm.stopPrank();

        // Resume
        market.resumeCollateralDeposits(address(weth));

        vm.startPrank(alice);
        market.depositCollateral(address(weth), 1e18);
        vm.stopPrank();

        assertEq(market.userCollateralBalances(alice, address(weth)), 1e18, "Deposits not resumed");
    }

    // ========================================
    // EDGE CASE TESTS
    // ========================================

    function testZeroDebtUser() public {
        assertTrue(market.isHealthy(alice), "Zero debt should be healthy");
        assertEq(market.getUserTotalDebt(alice), 0, "Debt should be zero");
    }

    function testMultipleUsersIndependence() public {
        uint256 collateralAmount = 2e18;
        uint256 borrowAmount = 1000e6;

        // Alice operations
        vm.startPrank(alice);
        weth.approve(address(market), collateralAmount);
        market.depositCollateral(address(weth), collateralAmount);
        market.borrow(borrowAmount);
        vm.stopPrank();

        // Bob operations
        vm.startPrank(bob);
        weth.approve(address(market), collateralAmount);
        market.depositCollateral(address(weth), collateralAmount);
        market.borrow(borrowAmount);
        vm.stopPrank();

        // Check independence
        uint256 aliceDebt = market.getUserTotalDebt(alice);
        uint256 bobDebt = market.getUserTotalDebt(bob);

        assertTrue(aliceDebt > 0, "Alice should have debt");
        assertTrue(bobDebt > 0, "Bob should have debt");
        assertEq(aliceDebt, bobDebt, "Debts should be equal");
    }

    function testSystemAddressRestrictions() public {
        vm.prank(badDebtAddress);
        vm.expectRevert();
        market.borrow(1000e6);

        vm.prank(protocolTreasury);
        vm.expectRevert();
        market.borrow(1000e6);
    }
}
