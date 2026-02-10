// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "../../src/core/MarketV1.sol";
import "../../src/core/Vault.sol";
import "../../src/core/PriceOracle.sol";
import "../../src/core/OracleRouter.sol";
import "../../src/core/InterestRateModel.sol";
import "../../src/governance/GovernanceSetup.sol";
import "../Mocks.sol";

/**
 * @title UpgradeSimulationTest
 * @notice Comprehensive tests simulating real-world upgrade scenarios
 * @dev Tests state preservation, storage layout, and upgrade mechanics
 */
contract UpgradeSimulationTest is Test {
    // Contracts
    MarketV1 public implementation;
    MarketV1 public market;
    ERC1967Proxy public proxy;
    MarketTimelock public timelock;
    Vault public vault;
    PriceOracle public oracle;
    OracleRouter public oracleRouter;
    InterestRateModel public irm;
    MockStrategy public strategy;

    // Tokens
    MockERC20 public usdc;
    MockERC20 public weth;
    MockERC20 public wbtc;

    // Price feeds
    MockPriceFeed public usdcFeed;
    MockPriceFeed public wethFeed;
    MockPriceFeed public wbtcFeed;

    // Addresses
    address public deployer;
    address public multisig;
    address public guardian;
    address public alice;
    address public bob;
    address public charlie;
    address public treasury;
    address public badDebtAddr;

    // Constants
    uint256 constant MIN_DELAY = 2 days;

    function setUp() public {
        deployer = address(this);
        multisig = makeAddr("multisig");
        guardian = makeAddr("guardian");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
        treasury = makeAddr("treasury");
        badDebtAddr = makeAddr("badDebt");

        // Deploy full protocol stack
        _deployProtocol();
        _setupGovernance();
        _fundUsers();
    }

    function _deployProtocol() internal {
        // Deploy tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);

        // Deploy price feeds
        usdcFeed = new MockPriceFeed(1e8); // $1.00
        wethFeed = new MockPriceFeed(2000e8); // $2000
        wbtcFeed = new MockPriceFeed(50_000e8); // $50000

        // Deploy oracle and OracleRouter
        oracle = new PriceOracle(deployer);
        oracleRouter = new OracleRouter(address(oracle), deployer);

        // Deploy strategy
        strategy = new MockStrategy(usdc, "USDC Strategy", "sUSDC");

        // Deploy vault (with deployer for AccessControl)
        vault = new Vault(usdc, address(0), address(strategy), deployer, "Vault USDC", "vUSDC");

        // Deploy IRM (with deployer for AccessControl)
        irm = new InterestRateModel(
            0.02e18, 0.8e18, 0.04e18, 0.6e18, address(vault), address(0), deployer
        );

        // Add ALL price feeds before transferring ownership to OracleRouter
        oracle.addPriceFeed(address(usdc), address(usdcFeed));
        oracle.addPriceFeed(address(weth), address(wethFeed));
        oracle.addPriceFeed(address(wbtc), address(wbtcFeed));
        oracle.transferOwnership(address(oracleRouter));

        // Deploy MarketV1 with proxy (using OracleRouter)
        implementation = new MarketV1();
        bytes memory initData = abi.encodeWithSelector(
            MarketV1.initialize.selector,
            badDebtAddr,
            treasury,
            address(vault),
            address(oracleRouter),
            address(irm),
            address(usdc),
            deployer
        );
        proxy = new ERC1967Proxy(address(implementation), initData);
        market = MarketV1(address(proxy));

        // Link contracts
        vault.setMarket(address(market));
        irm.setMarketContract(address(market));

        // Set market parameters
        market.setMarketParameters(0.85e18, 0.05e18, 0.1e18);
        market.addCollateralToken(address(weth), address(wethFeed));
        market.addCollateralToken(address(wbtc), address(wbtcFeed));
    }

    function _setupGovernance() internal {
        // Deploy timelock
        address[] memory proposers = new address[](1);
        proposers[0] = multisig;
        address[] memory executors = new address[](1);
        executors[0] = multisig;
        timelock = new MarketTimelock(MIN_DELAY, proposers, executors, address(this));

        // Set guardian
        market.setGuardian(guardian);

        // Transfer ownership to timelock
        market.transferOwnership(address(timelock));
    }

    function _fundUsers() internal {
        // Fund vault with liquidity
        usdc.mint(deployer, 10_000_000e6);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(10_000_000e6, deployer);

        // Fund users
        usdc.mint(alice, 1_000_000e6);
        usdc.mint(bob, 1_000_000e6);
        usdc.mint(charlie, 1_000_000e6);
        weth.mint(alice, 1000e18);
        weth.mint(bob, 1000e18);
        wbtc.mint(alice, 10e8);
        wbtc.mint(bob, 10e8);
    }

    // ==================== UPGRADE SIMULATION TESTS ====================

    /**
     * @notice Test full upgrade flow with active positions
     * @dev Simulates: active loans → upgrade → verify state preserved
     */
    function testUpgradeWithActivePositions() public {
        // === SETUP: Create active positions ===

        // Alice: deposits 10 WETH, borrows 10,000 USDC
        vm.startPrank(alice);
        weth.approve(address(market), 10e18);
        market.depositCollateral(address(weth), 10e18);
        market.borrow(10_000e6);
        vm.stopPrank();

        // Bob: deposits 1 WBTC, borrows 25,000 USDC
        vm.startPrank(bob);
        wbtc.approve(address(market), 1e8);
        market.depositCollateral(address(wbtc), 1e8);
        market.borrow(25_000e6);
        vm.stopPrank();

        // Let some time pass for interest accrual
        vm.warp(block.timestamp + 30 days);

        // Record state before upgrade
        uint256 aliceCollateralBefore = market.userCollateralBalances(alice, address(weth));
        uint256 aliceDebtBefore = market.getUserTotalDebt(alice);
        uint256 bobCollateralBefore = market.userCollateralBalances(bob, address(wbtc));
        uint256 bobDebtBefore = market.getUserTotalDebt(bob);
        uint256 totalBorrowsBefore = market.totalBorrows();
        uint256 globalIndexBefore = market.globalBorrowIndex();
        (uint256 lltvBefore, uint256 penaltyBefore, uint256 feeBefore) =
            market.getMarketParameters();

        // === UPGRADE ===

        // Deploy new implementation
        MarketV1 newImplementation = new MarketV1();

        // Schedule upgrade through timelock
        bytes memory upgradeData = abi.encodeWithSelector(
            UUPSUpgradeable.upgradeToAndCall.selector, address(newImplementation), ""
        );
        bytes32 salt = keccak256("upgrade-v1.1");

        vm.prank(multisig);
        timelock.schedule(address(market), 0, upgradeData, bytes32(0), salt, MIN_DELAY);

        // Warp past delay
        vm.warp(block.timestamp + MIN_DELAY + 1);

        // Execute upgrade
        vm.prank(multisig);
        timelock.execute(address(market), 0, upgradeData, bytes32(0), salt);

        // === VERIFY STATE PRESERVED ===

        // Verify implementation changed
        bytes32 implSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address storedImpl = address(uint160(uint256(vm.load(address(proxy), implSlot))));
        assertEq(storedImpl, address(newImplementation), "Implementation not updated");

        // Verify user state preserved
        assertEq(
            market.userCollateralBalances(alice, address(weth)),
            aliceCollateralBefore,
            "Alice collateral changed"
        );
        assertEq(market.getUserTotalDebt(alice), aliceDebtBefore, "Alice debt changed");
        assertEq(
            market.userCollateralBalances(bob, address(wbtc)),
            bobCollateralBefore,
            "Bob collateral changed"
        );
        assertEq(market.getUserTotalDebt(bob), bobDebtBefore, "Bob debt changed");

        // Verify global state preserved
        assertEq(market.totalBorrows(), totalBorrowsBefore, "Total borrows changed");
        assertEq(market.globalBorrowIndex(), globalIndexBefore, "Global index changed");

        // Verify parameters preserved
        (uint256 lltvAfter, uint256 penaltyAfter, uint256 feeAfter) = market.getMarketParameters();
        assertEq(lltvAfter, lltvBefore, "LLTV changed");
        assertEq(penaltyAfter, penaltyBefore, "Penalty changed");
        assertEq(feeAfter, feeBefore, "Fee changed");

        // === VERIFY OPERATIONS STILL WORK ===

        // Trigger interest accrual by having charlie do a small operation (updates globalBorrowIndex)
        vm.startPrank(charlie);
        weth.mint(charlie, 1e18);
        weth.approve(address(market), 1e18);
        market.depositCollateral(address(weth), 1e18);
        market.borrow(100e6); // Small borrow triggers index update
        vm.stopPrank();

        // Now Alice can repay with accurate debt amount
        vm.startPrank(alice);
        usdc.approve(address(market), type(uint256).max);
        uint256 aliceRepayAmount = market.getRepayAmount(alice);
        market.repay(aliceRepayAmount);
        vm.stopPrank();
        assertEq(market.getUserTotalDebt(alice), 0, "Alice repay failed");

        // Alice can withdraw
        vm.prank(alice);
        market.withdrawCollateral(address(weth), 10e18);
        assertEq(market.userCollateralBalances(alice, address(weth)), 0, "Alice withdraw failed");

        // Charlie can deposit and borrow (new user post-upgrade)
        vm.startPrank(charlie);
        weth.mint(charlie, 5e18);
        weth.approve(address(market), 5e18);
        market.depositCollateral(address(weth), 5e18);
        market.borrow(5000e6);
        vm.stopPrank();
        assertGt(market.getUserTotalDebt(charlie), 0, "Charlie borrow failed");
    }

    /**
     * @notice Test upgrade during emergency pause
     */
    function testUpgradeDuringPause() public {
        // Create some positions
        vm.startPrank(alice);
        weth.approve(address(market), 10e18);
        market.depositCollateral(address(weth), 10e18);
        market.borrow(5000e6);
        vm.stopPrank();

        // Guardian pauses market
        vm.prank(guardian);
        market.setBorrowingPaused(true);
        assertTrue(market.paused(), "Market not paused");

        // Deploy and schedule upgrade
        MarketV1 newImplementation = new MarketV1();
        bytes memory upgradeData = abi.encodeWithSelector(
            UUPSUpgradeable.upgradeToAndCall.selector, address(newImplementation), ""
        );
        bytes32 salt = keccak256("upgrade-during-pause");

        vm.prank(multisig);
        timelock.schedule(address(market), 0, upgradeData, bytes32(0), salt, MIN_DELAY);

        vm.warp(block.timestamp + MIN_DELAY + 1);

        vm.prank(multisig);
        timelock.execute(address(market), 0, upgradeData, bytes32(0), salt);

        // Verify upgrade succeeded and pause state preserved
        assertTrue(market.paused(), "Pause state not preserved");

        // Users still cannot borrow
        vm.prank(alice);
        vm.expectRevert(Errors.BorrowingPaused.selector);
        market.borrow(1000e6);

        // But can repay
        vm.startPrank(alice);
        usdc.approve(address(market), 5000e6);
        market.repay(5000e6);
        vm.stopPrank();

        // Unpause through timelock
        bytes memory unpauseData =
            abi.encodeWithSelector(MarketV1.setBorrowingPaused.selector, false);
        bytes32 unpauseSalt = keccak256("unpause");

        vm.prank(multisig);
        timelock.schedule(address(market), 0, unpauseData, bytes32(0), unpauseSalt, MIN_DELAY);

        vm.warp(block.timestamp + MIN_DELAY + 1);

        vm.prank(multisig);
        timelock.execute(address(market), 0, unpauseData, bytes32(0), unpauseSalt);

        assertFalse(market.paused(), "Market still paused");
    }

    /**
     * @notice Test that liquidations work after upgrade
     */
    function testLiquidationAfterUpgrade() public {
        // Alice deposits and borrows at high utilization
        vm.startPrank(alice);
        weth.approve(address(market), 10e18);
        market.depositCollateral(address(weth), 10e18);
        market.borrow(15_000e6); // $15k against $20k collateral = 75% LTV
        vm.stopPrank();

        // Perform upgrade
        MarketV1 newImplementation = new MarketV1();
        bytes memory upgradeData = abi.encodeWithSelector(
            UUPSUpgradeable.upgradeToAndCall.selector, address(newImplementation), ""
        );
        bytes32 salt = keccak256("upgrade-before-liquidation");

        vm.prank(multisig);
        timelock.schedule(address(market), 0, upgradeData, bytes32(0), salt, MIN_DELAY);
        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.prank(multisig);
        timelock.execute(address(market), 0, upgradeData, bytes32(0), salt);

        // Price crash makes position unhealthy
        wethFeed.setPrice(1000e8); // $2000 → $1000 (50% drop)

        // Verify position is unhealthy
        assertFalse(market.isHealthy(alice), "Position should be unhealthy");

        // Bob liquidates
        vm.startPrank(bob);
        usdc.approve(address(market), type(uint256).max);
        market.liquidate(alice);
        vm.stopPrank();

        // Verify liquidation succeeded
        assertEq(market.getUserTotalDebt(alice), 0, "Liquidation failed");
    }

    /**
     * @notice Test multiple sequential upgrades
     */
    function testMultipleSequentialUpgrades() public {
        // Create position
        vm.startPrank(alice);
        weth.approve(address(market), 10e18);
        market.depositCollateral(address(weth), 10e18);
        market.borrow(5000e6);
        vm.stopPrank();

        uint256 aliceDebtStart = market.getUserTotalDebt(alice);

        // First upgrade
        MarketV1 impl2 = new MarketV1();
        _executeUpgrade(address(impl2), keccak256("upgrade-1"));

        // Time passes, interest accrues
        vm.warp(block.timestamp + 90 days);

        // Second upgrade
        MarketV1 impl3 = new MarketV1();
        _executeUpgrade(address(impl3), keccak256("upgrade-2"));

        // More time passes
        vm.warp(block.timestamp + 90 days);

        // Third upgrade
        MarketV1 impl4 = new MarketV1();
        _executeUpgrade(address(impl4), keccak256("upgrade-3"));

        // Trigger interest accrual by having charlie do a small borrow (updates globalBorrowIndex)
        vm.startPrank(charlie);
        weth.mint(charlie, 1e18);
        weth.approve(address(market), 1e18);
        market.depositCollateral(address(weth), 1e18);
        market.borrow(100e6); // Small borrow triggers index update
        vm.stopPrank();

        // Now verify interest has accrued for alice
        assertGt(market.getUserTotalDebt(alice), aliceDebtStart, "Interest not accruing");
        assertEq(market.userCollateralBalances(alice, address(weth)), 10e18, "Collateral changed");

        // Operations still work
        vm.startPrank(alice);
        usdc.approve(address(market), type(uint256).max);
        market.repay(market.getRepayAmount(alice));
        market.withdrawCollateral(address(weth), 10e18);
        vm.stopPrank();

        assertEq(market.getUserTotalDebt(alice), 0, "Final repay failed");
        assertEq(market.userCollateralBalances(alice, address(weth)), 0, "Final withdraw failed");
    }

    // ==================== STORAGE LAYOUT TESTS ====================

    /**
     * @notice Verify storage slots are correctly assigned
     * @dev Storage layout:
     *   Slot 0: owner
     *   Slot 1: protocolTreasury
     *   Slot 2: badDebtAddress
     *   Slot 3: vaultContract
     *   Slot 4: priceOracle
     *   Slot 5: interestRateModel
     *   Slot 6: loanAsset
     *   Slot 7-9: marketParams (3 uint256s)
     *   Slot 10: totalBorrows
     *   Slot 11: globalBorrowIndex
     *   Slot 12: lastAccrualTimestamp
     *   Slot 13: paused (bool, 1 byte) + guardian (address, 20 bytes) - PACKED
     */
    function testStorageLayout() public view {
        // Slot 0: owner
        bytes32 ownerSlot = vm.load(address(proxy), bytes32(uint256(0)));
        assertEq(address(uint160(uint256(ownerSlot))), address(timelock), "Owner slot mismatch");

        // Slot 3: vaultContract
        bytes32 vaultSlot = vm.load(address(proxy), bytes32(uint256(3)));
        assertEq(address(uint160(uint256(vaultSlot))), address(vault), "Vault slot mismatch");

        // Slot 11: globalBorrowIndex (should be 1e18 = PRECISION)
        bytes32 indexSlot = vm.load(address(proxy), bytes32(uint256(11)));
        assertEq(uint256(indexSlot), 1e18, "GlobalBorrowIndex slot mismatch");

        // Slot 13: paused (bool) + guardian (address) are PACKED in same slot
        // Layout: | 11 bytes unused | guardian (20 bytes) | paused (1 byte) |
        bytes32 packedSlot = vm.load(address(proxy), bytes32(uint256(13)));
        // Extract paused (lowest byte)
        bool pausedValue = uint8(uint256(packedSlot)) == 1;
        assertFalse(pausedValue, "Paused should be false");
        // Extract guardian (next 20 bytes after lowest byte)
        address guardianValue = address(uint160(uint256(packedSlot) >> 8));
        assertEq(guardianValue, guardian, "Guardian slot mismatch");
    }

    // ==================== HELPER FUNCTIONS ====================

    function _executeUpgrade(address newImpl, bytes32 salt) internal {
        bytes memory upgradeData =
            abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, newImpl, "");

        vm.prank(multisig);
        timelock.schedule(address(market), 0, upgradeData, bytes32(0), salt, MIN_DELAY);

        vm.warp(block.timestamp + MIN_DELAY + 1);

        vm.prank(multisig);
        timelock.execute(address(market), 0, upgradeData, bytes32(0), salt);
    }
}
