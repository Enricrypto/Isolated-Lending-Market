// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "../../src/core/MarketV1.sol";
import "../../src/governance/GovernanceSetup.sol";
import "../../src/core/Vault.sol";
import "../../src/core/PriceOracle.sol";
import "../../src/core/InterestRateModel.sol";
import "../Mocks.sol";

/**
 * @title GovernanceTest
 * @notice Tests for the governance layer (Timelock + Guardian)
 */
contract GovernanceTest is Test {
    // Contracts
    MarketV1 public implementation;
    MarketV1 public market;
    ERC1967Proxy public proxy;
    MarketTimelock public timelock;
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
    address public deployer;
    address public multisig;
    address public guardianSigner;
    address public alice;
    address public treasury;
    address public badDebtAddr;

    // Constants
    uint256 constant MIN_DELAY = 2 days; // 48 hours
    uint256 constant INITIAL_BALANCE = 100_000e6;
    uint256 constant WETH_BALANCE = 100e18;

    function setUp() public {
        deployer = address(this);
        multisig = makeAddr("multisig");
        guardianSigner = makeAddr("guardianSigner");
        alice = makeAddr("alice");
        treasury = makeAddr("treasury");
        badDebtAddr = makeAddr("badDebt");

        // Deploy tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);

        // Deploy price feeds
        usdcFeed = new MockPriceFeed(1e8);
        wethFeed = new MockPriceFeed(2000e8);

        // Deploy oracle
        oracle = new PriceOracle(deployer);

        // Deploy strategy
        strategy = new MockStrategy(usdc, "USDC Strategy", "sUSDC");

        // Deploy vault
        vault = new Vault(usdc, address(0), address(strategy), "Vault USDC", "vUSDC");

        // Deploy IRM
        irm = new InterestRateModel(0.02e18, 0.8e18, 0.04e18, 0.6e18, address(vault), address(0));

        // Deploy MarketV1 implementation
        implementation = new MarketV1();

        // Deploy proxy with deployer as initial owner
        bytes memory initData = abi.encodeWithSelector(
            MarketV1.initialize.selector,
            badDebtAddr,
            treasury,
            address(vault),
            address(oracle),
            address(irm),
            address(usdc),
            deployer
        );
        proxy = new ERC1967Proxy(address(implementation), initData);
        market = MarketV1(address(proxy));

        // Link contracts
        vault.setMarket(address(market));
        irm.setMarketContract(address(market));

        // Add loan asset price feed
        oracle.addPriceFeed(address(usdc), address(usdcFeed));
        oracle.transferOwnership(address(market));

        // Set market parameters
        market.setMarketParameters(0.85e18, 0.05e18, 0.1e18);
        market.addCollateralToken(address(weth), address(wethFeed));

        // Deploy Timelock
        address[] memory proposers = new address[](1);
        proposers[0] = multisig;
        address[] memory executors = new address[](1);
        executors[0] = multisig;

        timelock = new MarketTimelock(MIN_DELAY, proposers, executors);

        // Set guardian directly on market (simpler than separate contract)
        market.setGuardian(guardianSigner);

        // Fund accounts
        usdc.mint(alice, INITIAL_BALANCE);
        weth.mint(alice, WETH_BALANCE);
        usdc.mint(deployer, 1_000_000e6);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(1_000_000e6, deployer);
    }

    // ==================== TIMELOCK TESTS ====================

    function testTimelockDeployment() public view {
        assertEq(timelock.getMinDelay(), MIN_DELAY);
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), multisig));
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), multisig));
    }

    function testTransferOwnershipToTimelock() public {
        // Transfer ownership to timelock
        market.transferOwnership(address(timelock));

        assertEq(market.owner(), address(timelock));
    }

    function testTimelockCanExecuteAfterDelay() public {
        // Transfer ownership to timelock
        market.transferOwnership(address(timelock));

        // Schedule parameter change through timelock
        bytes memory callData =
            abi.encodeWithSelector(MarketV1.setMarketParameters.selector, 0.8e18, 0.06e18, 0.15e18);

        bytes32 salt = keccak256("test");

        vm.prank(multisig);
        timelock.schedule(
            address(market),
            0, // value
            callData,
            bytes32(0), // predecessor
            salt,
            MIN_DELAY
        );

        // Cannot execute immediately
        vm.prank(multisig);
        vm.expectRevert();
        timelock.execute(address(market), 0, callData, bytes32(0), salt);

        // Warp past delay
        vm.warp(block.timestamp + MIN_DELAY + 1);

        // Now can execute
        vm.prank(multisig);
        timelock.execute(address(market), 0, callData, bytes32(0), salt);

        // Verify parameters changed
        (uint256 lltv, uint256 penalty, uint256 fee) = market.getMarketParameters();
        assertEq(lltv, 0.8e18);
        assertEq(penalty, 0.06e18);
        assertEq(fee, 0.15e18);
    }

    function testTimelockUpgrade() public {
        // Transfer ownership to timelock
        market.transferOwnership(address(timelock));

        // Deploy new implementation
        MarketV1 newImpl = new MarketV1();

        // Schedule upgrade
        bytes memory callData =
            abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, address(newImpl), "");

        bytes32 salt = keccak256("upgrade");

        vm.prank(multisig);
        timelock.schedule(address(market), 0, callData, bytes32(0), salt, MIN_DELAY);

        // Warp and execute
        vm.warp(block.timestamp + MIN_DELAY + 1);

        vm.prank(multisig);
        timelock.execute(address(market), 0, callData, bytes32(0), salt);

        // Verify upgrade (implementation slot changed)
        bytes32 implSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address storedImpl = address(uint160(uint256(vm.load(address(proxy), implSlot))));
        assertEq(storedImpl, address(newImpl));
    }

    function testNonProposerCannotSchedule() public {
        market.transferOwnership(address(timelock));

        bytes memory callData =
            abi.encodeWithSelector(MarketV1.setMarketParameters.selector, 0.8e18, 0.06e18, 0.15e18);

        vm.prank(alice);
        vm.expectRevert();
        timelock.schedule(address(market), 0, callData, bytes32(0), keccak256("test"), MIN_DELAY);
    }

    // ==================== GUARDIAN TESTS ====================

    function testGuardianSetup() public view {
        assertEq(market.guardian(), guardianSigner);
    }

    function testGuardianCanPause() public {
        assertFalse(market.paused());

        vm.prank(guardianSigner);
        market.setBorrowingPaused(true);

        assertTrue(market.paused());
    }

    function testNonGuardianCannotPause() public {
        vm.prank(alice);
        vm.expectRevert(Errors.OnlyOwner.selector);
        market.setBorrowingPaused(true);
    }

    function testOwnerCanChangeGuardian() public {
        address newGuardian = makeAddr("newGuardian");

        // Change guardian
        market.setGuardian(newGuardian);
        assertEq(market.guardian(), newGuardian);

        // New guardian can pause
        vm.prank(newGuardian);
        market.setBorrowingPaused(true);
        assertTrue(market.paused());

        // Old guardian cannot pause
        market.setBorrowingPaused(false); // Owner unpauses

        vm.prank(guardianSigner);
        vm.expectRevert(Errors.OnlyOwner.selector);
        market.setBorrowingPaused(true);
    }

    function testOnlyOwnerCanSetGuardian() public {
        vm.prank(alice);
        vm.expectRevert(Errors.OnlyOwner.selector);
        market.setGuardian(alice);
    }

    function testGuardianCanBeRemoved() public {
        // Remove guardian
        market.setGuardian(address(0));
        assertEq(market.guardian(), address(0));

        // Previous guardian cannot pause
        vm.prank(guardianSigner);
        vm.expectRevert(Errors.OnlyOwner.selector);
        market.setBorrowingPaused(true);
    }

    // ==================== FULL GOVERNANCE FLOW TESTS ====================

    function testFullGovernanceFlow() public {
        // 1. Transfer market ownership to timelock
        market.transferOwnership(address(timelock));

        // 2. Verify market still functions
        vm.startPrank(alice);
        weth.approve(address(market), 10e18);
        market.depositCollateral(address(weth), 10e18);
        market.borrow(5000e6);
        vm.stopPrank();

        // 3. Guardian can still pause (guardian was set before ownership transfer)
        vm.prank(guardianSigner);
        market.setBorrowingPaused(true);
        assertTrue(market.paused());

        // 4. Users cannot borrow while paused
        vm.prank(alice);
        vm.expectRevert(Errors.BorrowingPaused.selector);
        market.borrow(1000e6);

        // 5. But can still repay
        vm.startPrank(alice);
        usdc.approve(address(market), 5000e6);
        market.repay(5000e6);
        vm.stopPrank();

        // 6. Unpause through timelock (only owner/timelock can unpause, not guardian)
        bytes memory unpauseData =
            abi.encodeWithSelector(MarketV1.setBorrowingPaused.selector, false);
        bytes32 salt = keccak256("unpause");

        vm.prank(multisig);
        timelock.schedule(address(market), 0, unpauseData, bytes32(0), salt, MIN_DELAY);

        vm.warp(block.timestamp + MIN_DELAY + 1);

        vm.prank(multisig);
        timelock.execute(address(market), 0, unpauseData, bytes32(0), salt);

        assertFalse(market.paused());

        // 7. Borrowing works again
        vm.prank(alice);
        market.borrow(1000e6);
        assertGt(market.getUserTotalDebt(alice), 0);
    }
}
