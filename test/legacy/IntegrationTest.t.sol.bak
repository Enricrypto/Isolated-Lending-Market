// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../src/core/Market.sol";
import "../../src/core/Vault.sol";
import "../../src/core/PriceOracle.sol";
import "../../src/core/InterestRateModel.sol";
import "../Mocks.sol";

/**
 * @title IntegrationTest
 * @notice End-to-end integration tests for the complete DeFi lending protocol
 * @dev Tests realistic user workflows and system interactions
 */
contract IntegrationTest is Test {
    Market public market;
    Vault public vault;
    PriceOracle public oracle;
    InterestRateModel public irm;

    MockERC20 public usdc;
    MockERC20 public weth;
    MockERC20 public wbtc;

    MockPriceFeed public usdcFeed;
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

    function setUp() public {
        owner = address(this);
        alice = address(0x1);
        bob = address(0x2);
        charlie = address(0x3);
        liquidator = address(0x4);
        protocolTreasury = address(0x5);
        badDebtAddress = address(0x6);

        // Deploy tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);

        // Deploy price feeds
        usdcFeed = new MockPriceFeed(1e8); // $1
        wethFeed = new MockPriceFeed(2000e8); // $2,000
        wbtcFeed = new MockPriceFeed(50_000e8); // $50,000

        // Deploy strategy
        strategy = new MockStrategy(usdc, "USDC Strategy", "sUSDC");

        // Deploy oracle
        oracle = new PriceOracle(address(this));
        oracle.addPriceFeed(address(usdc), address(usdcFeed));

        // Deploy vault
        vault = new Vault(usdc, address(0), address(strategy), "Vault USDC", "vUSDC");

        // Deploy interest rate model
        irm = new InterestRateModel(
            0.02e18, // 2% base
            0.8e18, // 80% optimal
            0.04e18, // 4% slope1
            0.6e18, // 60% slope2
            address(vault),
            address(0)
        );

        // Deploy market
        market = new Market(
            badDebtAddress,
            protocolTreasury,
            address(vault),
            address(oracle),
            address(irm),
            address(usdc)
        );

        // Link contracts
        vault.setMarket(address(market));
        irm.setMarketContract(address(market));

        oracle.transferOwnership(address(market));

        // Configure market
        market.setMarketParameters(0.85e18, 0.05e18, 0.1e18);

        // Market adds collateral tokens
        market.addCollateralToken(address(weth), address(wethFeed));
        market.addCollateralToken(address(wbtc), address(wbtcFeed));

        // Mint tokens
        usdc.mint(alice, 10_000e6);
        usdc.mint(bob, 10_000e6);
        usdc.mint(charlie, 100_000e6);
        usdc.mint(liquidator, 100_000e6);

        weth.mint(alice, 100e18);
        weth.mint(bob, 100e18);

        wbtc.mint(alice, 10e8);
        wbtc.mint(bob, 10e8);
    }

    // ========================================
    // SCENARIO 1: BASIC LENDING CYCLE
    // ========================================

    function testScenario1_BasicLendingCycle() public {
        console.log("\n=== SCENARIO 1: Basic Lending Cycle ===");

        // Step 1: Charlie provides liquidity
        console.log("Step 1: Charlie provides liquidity to vault");
        vm.startPrank(charlie);
        usdc.approve(address(vault), 50_000e6);
        uint256 charlieShares = vault.deposit(50_000e6, charlie);
        vm.stopPrank();
        console.log("Charlie deposited: 50,000 USDC");
        console.log("Charlie received shares:", charlieShares);

        // Step 2: Alice deposits collateral
        console.log("\nStep 2: Alice deposits 5 WETH as collateral");
        vm.startPrank(alice);
        weth.approve(address(market), 5e18);
        market.depositCollateral(address(weth), 5e18);
        vm.stopPrank();
        console.log(
            "Alice collateral value:", market.getUserPosition(alice).collateralValue / 1e18, "USD"
        );

        // Step 3: Alice borrows
        console.log("\nStep 3: Alice borrows 5,000 USDC");
        vm.startPrank(alice);
        market.borrow(5000e6);
        vm.stopPrank();
        console.log("Alice debt:", market.getUserTotalDebt(alice) / 1e18, "USD");
        console.log("Alice health factor:", market.getUserPosition(alice).healthFactor / 1e18);

        // Step 4: Time passes, interest accrues
        console.log("\nStep 4: 1 year passes, interest accrues");
        vm.warp(block.timestamp + 365 days);
        market.updateGlobalBorrowIndex();
        uint256 aliceDebtAfter = market.getUserTotalDebt(alice);
        console.log("Alice debt with interest:", aliceDebtAfter / 1e18, "USD");

        // Step 5: Alice repays
        console.log("\nStep 5: Alice repays her debt");
        vm.startPrank(alice);
        usdc.approve(address(market), type(uint256).max);
        // Use helper function to get exact repay amount (handles rounding)
        uint256 repayAmount = market.getRepayAmount(alice);
        market.repay(repayAmount);

        vm.stopPrank();
        console.log("Alice debt after repayment:", market.getUserTotalDebt(alice) / 1e18, "USD");

        // Step 6: Alice withdraws collateral
        console.log("\nStep 6: Alice withdraws collateral");
        vm.startPrank(alice);
        market.withdrawCollateral(address(weth), 5e18);
        vm.stopPrank();
        console.log("Alice final WETH balance:", weth.balanceOf(alice) / 1e18);

        // Step 7: Charlie withdraws with profit
        console.log("\nStep 7: Charlie withdraws his liquidity plus interest");
        uint256 charlieAssets = vault.convertToAssets(charlieShares);
        console.log("Charlie can withdraw:", charlieAssets / 1e6, "USDC");

        assertTrue(charlieAssets > 50_000e6, "Charlie should have earned interest");
    }

    // ========================================
    // SCENARIO 2: MULTIPLE COLLATERALS
    // ========================================

    function testScenario2_MultipleCollaterals() public {
        console.log("\n=== SCENARIO 2: Multiple Collaterals ===");

        // Setup liquidity
        vm.startPrank(charlie);
        usdc.approve(address(vault), 50_000e6);
        vault.deposit(50_000e6, charlie);
        vm.stopPrank();

        // Bob deposits both WETH and WBTC
        console.log("Bob deposits mixed collateral");
        vm.startPrank(bob);

        weth.approve(address(market), 2e18);
        market.depositCollateral(address(weth), 2e18);
        console.log("Deposited 2 WETH");

        wbtc.approve(address(market), 0.1e8);
        market.depositCollateral(address(wbtc), 0.1e8);
        console.log("Deposited 0.1 WBTC");

        uint256 totalCollateral = market.getUserPosition(bob).collateralValue;
        console.log("Total collateral value:", totalCollateral / 1e18, "USD");

        // Bob borrows against mixed collateral
        uint256 borrowAmount = 7000e6;
        market.borrow(borrowAmount);
        console.log("Borrowed:", borrowAmount / 1e6, "USDC");
        console.log("Health factor:", market.getUserPosition(bob).healthFactor / 1e18);

        vm.stopPrank();

        assertTrue(market.isHealthy(bob), "Position should be healthy");
    }

    // ========================================
    // SCENARIO 3: LIQUIDATION EVENT
    // ========================================

    function testScenario3_LiquidationEvent() public {
        console.log("\n=== SCENARIO 3: Liquidation Event ===");

        // Setup
        vm.startPrank(charlie);
        usdc.approve(address(vault), 50_000e6);
        vault.deposit(50_000e6, charlie);
        vm.stopPrank();

        // Alice borrows at maximum capacity
        console.log("Alice opens leveraged position");
        vm.startPrank(alice);
        weth.approve(address(market), 5e18);
        market.depositCollateral(address(weth), 5e18);
        market.borrow(8500e6); // 85% of $10,000
        console.log("Collateral: 5 WETH ($10,000)");
        console.log("Borrowed: $8,500");
        console.log("Health factor:", market.getUserPosition(alice).healthFactor / 1e18);
        vm.stopPrank();

        // Market crashes
        console.log("\nMarket crash: WETH drops 30%");
        wethFeed.setPrice(1400e8); // $2000 -> $1400
        console.log(
            "New collateral value:", market.getUserPosition(alice).collateralValue / 1e18, "USD"
        );
        console.log("Health factor:", market.getUserPosition(alice).healthFactor / 1e18);

        bool healthy = market.isHealthy(alice);
        console.log("Position healthy?", healthy);

        assertTrue(!healthy, "Position should be liquidatable");

        // Liquidation
        console.log("\nLiquidator steps in");
        uint256 liquidatorBalanceBefore = weth.balanceOf(liquidator);
        vm.startPrank(liquidator);
        usdc.approve(address(market), type(uint256).max);
        market.liquidate(alice);
        vm.stopPrank();
        uint256 liquidatorBalanceAfter = weth.balanceOf(liquidator);

        console.log(
            "Liquidator received WETH:", (liquidatorBalanceAfter - liquidatorBalanceBefore) / 1e18
        );
        console.log("Alice remaining debt:", market.getUserTotalDebt(alice) / 1e18, "USD");

        assertTrue(
            liquidatorBalanceAfter > liquidatorBalanceBefore, "Liquidator should receive collateral"
        );
    }

    // ========================================
    // SCENARIO 4: INTEREST RATE DYNAMICS
    // ========================================

    function testScenario4_InterestRateDynamics() public {
        console.log("\n=== SCENARIO 4: Interest Rate Dynamics ===");

        // Setup large liquidity pool
        vm.startPrank(charlie);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, charlie);
        vm.stopPrank();

        // Test at low utilization
        console.log("\nLow utilization (10%):");
        vm.startPrank(alice);
        weth.approve(address(market), 10e18);
        market.depositCollateral(address(weth), 10e18);
        market.borrow(10_000e6);
        vm.stopPrank();

        uint256 rateLow = irm.getDynamicBorrowRate();
        console.log("Borrow rate:", rateLow * 100 / 1e18, "%");

        // Increase utilization
        console.log("\nHigh utilization (90%):");
        vm.startPrank(bob);
        weth.approve(address(market), 100e18);
        market.depositCollateral(address(weth), 100e18);
        market.borrow(80_000e6);
        vm.stopPrank();

        uint256 rateHigh = irm.getDynamicBorrowRate();
        console.log("Borrow rate:", rateHigh * 100 / 1e18, "%");

        assertTrue(rateHigh > rateLow, "Rate should increase with utilization");
    }

    // ========================================
    // SCENARIO 5: VAULT OPERATIONS
    // ========================================

    function testScenario5_VaultOperations() public {
        console.log("\n=== SCENARIO 5: Vault Operations ===");

        // Multiple depositors
        console.log("Multiple users deposit to vault");

        weth.mint(charlie, 100e18); // Charlie needs WETH for borrowing
        vm.startPrank(alice);
        usdc.approve(address(vault), 10_000e6);
        uint256 aliceShares = vault.deposit(10_000e6, alice);
        vm.stopPrank();
        console.log("Alice deposited 10,000 USDC");

        vm.startPrank(bob);
        usdc.approve(address(vault), 10_000e6);
        uint256 bobShares = vault.deposit(10_000e6, bob);
        vm.stopPrank();
        console.log("Bob deposited 10,000 USDC");

        // Charlie borrows, generating yield
        console.log("\nCharlie borrows, generating interest");
        vm.startPrank(charlie);
        weth.approve(address(market), 20e18);
        market.depositCollateral(address(weth), 20e18);
        market.borrow(15_000e6);
        vm.stopPrank();

        // Time passes
        vm.warp(block.timestamp + 365 days);
        market.updateGlobalBorrowIndex();
        console.log("1 year passes...");

        // Check vault appreciation
        uint256 aliceValue = vault.convertToAssets(aliceShares);
        uint256 bobValue = vault.convertToAssets(bobShares);
        console.log("Alice shares now worth:", aliceValue / 1e6, "USDC");
        console.log("Bob shares now worth:", bobValue / 1e6, "USDC");

        assertTrue(aliceValue > 10_000e6, "Alice should have earned yield");
        assertTrue(bobValue > 10_000e6, "Bob should have earned yield");
    }

    // ========================================
    // SCENARIO 6: BAD DEBT SCENARIO
    // ========================================

    function testScenario6_BadDebtScenario() public {
        console.log("\n=== SCENARIO 6: Bad Debt Scenario ===");

        // Setup
        vm.startPrank(charlie);
        usdc.approve(address(vault), 50_000e6);
        vault.deposit(50_000e6, charlie);
        vm.stopPrank();

        // Alice borrows at limit
        console.log("Alice borrows at maximum");
        vm.startPrank(alice);
        weth.approve(address(market), 5e18);
        market.depositCollateral(address(weth), 5e18);
        market.borrow(8500e6);
        vm.stopPrank();
        console.log("Borrowed: $8,500 against $10,000 collateral");

        // Catastrophic price drop
        console.log("\nCatastrophic event: WETH drops 70%");
        wethFeed.setPrice(600e8); // $2000 -> $600
        console.log(
            "New collateral value:", market.getUserPosition(alice).collateralValue / 1e18, "USD"
        );

        // Liquidation with bad debt
        console.log("\nLiquidation occurs");
        uint256 debtBefore = market.getUserTotalDebt(alice);

        vm.startPrank(liquidator);
        usdc.approve(address(market), type(uint256).max);
        market.liquidate(alice);
        vm.stopPrank();

        uint256 badDebt = market.getBadDebt(alice);
        console.log("Bad debt recorded:", badDebt / 1e18, "USD");
        console.log("Unrecovered amount sent to bad debt address");

        assertTrue(badDebt > 0, "Bad debt should be recorded");
    }

    // ========================================
    // SCENARIO 7: STRATEGY MIGRATION
    // ========================================

    function testScenario7_StrategyMigration() public {
        console.log("\n=== SCENARIO 7: Strategy Migration ===");

        // Initial setup with deposits
        vm.startPrank(charlie);
        usdc.approve(address(vault), 50_000e6);
        vault.deposit(50_000e6, charlie);
        vm.stopPrank();
        console.log("Vault has 50,000 USDC");

        // Active borrowing
        vm.startPrank(alice);
        weth.approve(address(market), 10e18);
        market.depositCollateral(address(weth), 10e18);
        market.borrow(10_000e6);
        vm.stopPrank();
        console.log("10,000 USDC borrowed");

        uint256 totalAssetsBefore = vault.totalAssets();
        console.log("Total assets before migration:", totalAssetsBefore / 1e6, "USDC");

        // Migrate to new strategy
        console.log("\nMigrating to new strategy");
        MockStrategy newStrategy = new MockStrategy(usdc, "New Strategy V2", "sUSDC-v2");
        vault.changeStrategy(address(newStrategy));

        uint256 totalAssetsAfter = vault.totalAssets();
        console.log("Total assets after migration:", totalAssetsAfter / 1e6, "USDC");

        // Verify continuity
        assertEq(totalAssetsBefore, totalAssetsAfter, "Assets should be preserved");
        console.log("Migration successful - no funds lost");
    }
}
