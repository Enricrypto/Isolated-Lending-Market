// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/core/MarketV1.sol";
import "../../src/core/Vault.sol";
import "../../src/core/PriceOracle.sol";
import "../../src/core/InterestRateModel.sol";
import "../Mocks.sol";

/**
 * @title MarketV1Test
 * @notice Tests for the upgradeable MarketV1 contract
 * @dev Tests proxy deployment, initialization, and upgrade mechanics
 */
contract MarketV1Test is Test {
    // Contracts
    MarketV1 public implementation;
    MarketV1 public market; // Proxy cast to MarketV1
    ERC1967Proxy public proxy;
    Vault public vault;
    PriceOracle public oracle;
    InterestRateModel public irm;
    MockStrategy public strategy;

    // Tokens
    MockERC20 public usdc;
    MockERC20 public weth;

    // Price feeds
    MockPriceFeed public usdcFeed;
    MockPriceFeed public wethFeed;

    // Addresses
    address public owner;
    address public treasury;
    address public badDebtAddr;
    address public alice;
    address public bob;

    // Constants
    uint256 constant INITIAL_BALANCE = 100_000e6; // 100k USDC (6 decimals)
    uint256 constant WETH_BALANCE = 100e18; // 100 WETH

    function setUp() public {
        // Setup accounts
        owner = address(this);
        treasury = makeAddr("treasury");
        badDebtAddr = makeAddr("badDebt");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Deploy tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);

        // Deploy price feeds
        usdcFeed = new MockPriceFeed(1e8); // $1.00
        wethFeed = new MockPriceFeed(2000e8); // $2000

        // Deploy oracle (price feeds added later via market.addCollateralToken)
        oracle = new PriceOracle(address(this));

        // Deploy strategy (mock ERC4626)
        strategy = new MockStrategy(usdc, "USDC Strategy", "sUSDC");

        // Deploy vault
        vault = new Vault(
            usdc,
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

        // Deploy MarketV1 implementation
        implementation = new MarketV1();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            MarketV1.initialize.selector,
            badDebtAddr,
            treasury,
            address(vault),
            address(oracle),
            address(irm),
            address(usdc),
            owner
        );

        // Deploy proxy
        proxy = new ERC1967Proxy(address(implementation), initData);

        // Cast proxy to MarketV1
        market = MarketV1(address(proxy));

        // Setup vault and IRM to point to market
        vault.setMarket(address(market));
        irm.setMarketContract(address(market));

        // Add loan asset price feed (needed for debt calculations)
        oracle.addPriceFeed(address(usdc), address(usdcFeed));

        // Transfer oracle ownership to market
        oracle.transferOwnership(address(market));

        // Set market parameters
        market.setMarketParameters(
            0.85e18, // 85% LLTV
            0.05e18, // 5% liquidation penalty
            0.1e18 // 10% protocol fee
        );

        // Add WETH as collateral
        market.addCollateralToken(address(weth), address(wethFeed));

        // Fund test accounts
        usdc.mint(alice, INITIAL_BALANCE);
        usdc.mint(bob, INITIAL_BALANCE);
        weth.mint(alice, WETH_BALANCE);
        weth.mint(bob, WETH_BALANCE);

        // Fund vault with liquidity
        usdc.mint(address(this), 1_000_000e6);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(1_000_000e6, address(this));
    }

    // ==================== INITIALIZATION TESTS ====================

    function testInitialization() public view {
        assertEq(market.owner(), owner);
        assertEq(market.protocolTreasury(), treasury);
        assertEq(market.badDebtAddress(), badDebtAddr);
        assertEq(address(market.vaultContract()), address(vault));
        assertEq(address(market.priceOracle()), address(oracle));
        assertEq(address(market.interestRateModel()), address(irm));
        assertEq(address(market.loanAsset()), address(usdc));
        assertEq(market.globalBorrowIndex(), 1e18);
    }

    function testCannotInitializeTwice() public {
        vm.expectRevert();
        market.initialize(
            badDebtAddr,
            treasury,
            address(vault),
            address(oracle),
            address(irm),
            address(usdc),
            owner
        );
    }

    function testImplementationCannotBeInitialized() public {
        vm.expectRevert();
        implementation.initialize(
            badDebtAddr,
            treasury,
            address(vault),
            address(oracle),
            address(irm),
            address(usdc),
            owner
        );
    }

    // ==================== CORE FUNCTIONALITY TESTS ====================

    function testDepositCollateralThroughProxy() public {
        uint256 depositAmount = 10e18; // 10 WETH

        vm.startPrank(alice);
        weth.approve(address(market), depositAmount);
        market.depositCollateral(address(weth), depositAmount);
        vm.stopPrank();

        assertEq(market.userCollateralBalances(alice, address(weth)), depositAmount);
    }

    function testBorrowThroughProxy() public {
        // Deposit collateral
        uint256 collateralAmount = 10e18; // 10 WETH = $20,000
        vm.startPrank(alice);
        weth.approve(address(market), collateralAmount);
        market.depositCollateral(address(weth), collateralAmount);

        // Borrow
        uint256 borrowAmount = 5000e6; // $5,000
        market.borrow(borrowAmount);
        vm.stopPrank();

        assertEq(usdc.balanceOf(alice), INITIAL_BALANCE + borrowAmount);
        assertGt(market.getUserTotalDebt(alice), 0);
    }

    // ==================== OWNERSHIP TESTS ====================

    function testTransferOwnership() public {
        address newOwner = makeAddr("newOwner");

        market.transferOwnership(newOwner);

        assertEq(market.owner(), newOwner);
    }

    function testOnlyOwnerCanTransferOwnership() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(alice);
        vm.expectRevert(Errors.OnlyOwner.selector);
        market.transferOwnership(newOwner);
    }

    function testCannotTransferOwnershipToZero() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        market.transferOwnership(address(0));
    }

    // ==================== UPGRADE TESTS ====================

    function testOnlyOwnerCanUpgrade() public {
        // Deploy a new implementation
        MarketV1 newImplementation = new MarketV1();

        vm.prank(alice);
        vm.expectRevert(Errors.OnlyOwner.selector);
        market.upgradeToAndCall(address(newImplementation), "");
    }

    function testUpgradePreservesState() public {
        // First, create some state
        uint256 collateralAmount = 10e18;
        uint256 borrowAmount = 5000e6;

        vm.startPrank(alice);
        weth.approve(address(market), collateralAmount);
        market.depositCollateral(address(weth), collateralAmount);
        market.borrow(borrowAmount);
        vm.stopPrank();

        // Record state before upgrade
        uint256 aliceCollateralBefore = market.userCollateralBalances(alice, address(weth));
        uint256 aliceDebtBefore = market.userTotalDebt(alice);
        uint256 totalBorrowsBefore = market.totalBorrows();
        address ownerBefore = market.owner();

        // Deploy new implementation
        MarketV1 newImplementation = new MarketV1();

        // Upgrade
        market.upgradeToAndCall(address(newImplementation), "");

        // Verify state is preserved
        assertEq(market.userCollateralBalances(alice, address(weth)), aliceCollateralBefore);
        assertEq(market.userTotalDebt(alice), aliceDebtBefore);
        assertEq(market.totalBorrows(), totalBorrowsBefore);
        assertEq(market.owner(), ownerBefore);
    }

    function testUpgradeToNewImplementationVersion() public {
        // Deploy MarketV2Mock for testing upgrade
        MarketV2Mock newImplementation = new MarketV2Mock();

        // Upgrade
        market.upgradeToAndCall(address(newImplementation), "");

        // Cast to V2 and verify new functionality
        MarketV2Mock marketV2 = MarketV2Mock(address(proxy));
        assertEq(marketV2.version(), 2);
    }

    // ==================== PROXY SPECIFIC TESTS ====================

    function testProxyDelegatesToImplementation() public view {
        // The proxy should delegate calls to the implementation
        // This is verified by the fact that all our other tests work
        // Here we just verify the implementation address is set correctly
        bytes32 implSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address storedImpl = address(uint160(uint256(vm.load(address(proxy), implSlot))));
        assertEq(storedImpl, address(implementation));
    }

    function testDirectCallToImplementationFails() public {
        // Calling the implementation directly should fail for state-changing functions
        // because the implementation is not initialized
        vm.expectRevert();
        implementation.setMarketParameters(0.8e18, 0.05e18, 0.1e18);
    }

    // ==================== EMERGENCY PAUSE TESTS ====================

    function testBorrowingPausedBlocksBorrow() public {
        // Deposit collateral first
        uint256 collateralAmount = 10e18;
        vm.startPrank(alice);
        weth.approve(address(market), collateralAmount);
        market.depositCollateral(address(weth), collateralAmount);
        vm.stopPrank();

        // Pause borrowing
        market.setBorrowingPaused(true);

        // Attempt to borrow should fail
        vm.prank(alice);
        vm.expectRevert(Errors.BorrowingPaused.selector);
        market.borrow(1000e6);
    }

    function testPauseAllowsDeposits() public {
        // Pause borrowing
        market.setBorrowingPaused(true);

        // Deposits should still work
        uint256 depositAmount = 10e18;
        vm.startPrank(alice);
        weth.approve(address(market), depositAmount);
        market.depositCollateral(address(weth), depositAmount);
        vm.stopPrank();

        assertEq(market.userCollateralBalances(alice, address(weth)), depositAmount);
    }

    function testPauseAllowsWithdrawals() public {
        // First deposit
        uint256 depositAmount = 10e18;
        vm.startPrank(alice);
        weth.approve(address(market), depositAmount);
        market.depositCollateral(address(weth), depositAmount);
        vm.stopPrank();

        // Pause borrowing
        market.setBorrowingPaused(true);

        // Withdrawals should still work
        vm.prank(alice);
        market.withdrawCollateral(address(weth), depositAmount);

        assertEq(market.userCollateralBalances(alice, address(weth)), 0);
    }

    function testPauseAllowsRepayments() public {
        // Setup: deposit and borrow
        uint256 collateralAmount = 10e18;
        uint256 borrowAmount = 5000e6;

        vm.startPrank(alice);
        weth.approve(address(market), collateralAmount);
        market.depositCollateral(address(weth), collateralAmount);
        market.borrow(borrowAmount);
        vm.stopPrank();

        // Pause borrowing
        market.setBorrowingPaused(true);

        // Repayments should still work
        vm.startPrank(alice);
        usdc.approve(address(market), borrowAmount);
        market.repay(borrowAmount);
        vm.stopPrank();

        assertEq(market.getUserTotalDebt(alice), 0);
    }

    function testPauseAllowsLiquidations() public {
        // Setup: deposit and borrow at max
        uint256 collateralAmount = 10e18; // $20,000 worth
        uint256 borrowAmount = 16_000e6; // Close to max borrow

        vm.startPrank(alice);
        weth.approve(address(market), collateralAmount);
        market.depositCollateral(address(weth), collateralAmount);
        market.borrow(borrowAmount);
        vm.stopPrank();

        // Crash the price to make position unhealthy
        wethFeed.setPrice(1000e8); // $1000 (50% drop)

        // Pause borrowing
        market.setBorrowingPaused(true);

        // Liquidations should still work
        vm.startPrank(bob);
        usdc.approve(address(market), 20_000e6);
        market.liquidate(alice);
        vm.stopPrank();

        // Alice's debt should be cleared
        assertEq(market.getUserTotalDebt(alice), 0);
    }

    function testOnlyOwnerCanPause() public {
        vm.prank(alice);
        vm.expectRevert(Errors.OnlyOwner.selector);
        market.setBorrowingPaused(true);
    }

    function testUnpauseAllowsBorrowing() public {
        // Deposit collateral
        uint256 collateralAmount = 10e18;
        vm.startPrank(alice);
        weth.approve(address(market), collateralAmount);
        market.depositCollateral(address(weth), collateralAmount);
        vm.stopPrank();

        // Pause then unpause
        market.setBorrowingPaused(true);
        market.setBorrowingPaused(false);

        // Borrowing should work again
        vm.prank(alice);
        market.borrow(1000e6);

        assertGt(market.getUserTotalDebt(alice), 0);
    }
}

/**
 * @title MarketV2Mock
 * @notice Mock V2 implementation for testing upgrades
 */
contract MarketV2Mock is MarketV1 {
    function version() public pure returns (uint256) {
        return 2;
    }
}
