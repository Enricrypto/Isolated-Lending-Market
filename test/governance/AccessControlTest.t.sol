// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../src/core/MarketV1.sol";
import "../../src/core/Vault.sol";
import "../../src/core/OracleRouter.sol";
import "../../src/core/InterestRateModel.sol";
import "../../src/core/RiskEngine.sol";
import "../../src/core/PriceOracle.sol";
import "../../src/governance/GovernanceSetup.sol";
import "../../src/access/ProtocolAccessControl.sol";
import "../../src/libraries/DataTypes.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../Mocks.sol";

/**
 * @title AccessControlTest
 * @notice Tests for role-based access control across all protocol contracts
 */
contract AccessControlTest is Test {
    // Contracts
    MarketV1 public market;
    Vault public vault;
    OracleRouter public oracleRouter;
    InterestRateModel public irm;
    RiskEngine public riskEngine;
    PriceOracle public oracle;
    MarketTimelock public timelock;
    EmergencyGuardian public emergencyGuardian;

    // Mocks
    MockERC20 public usdc;
    MockERC20 public weth;
    MockStrategy public strategy;
    MockPriceFeed public usdcFeed;
    MockPriceFeed public wethFeed;

    // Addresses
    address public admin;
    address public guardian;
    address public oracleManager;
    address public riskManager;
    address public rateManager;
    address public strategyManager;
    address public randomUser;
    address public badDebtAddr;
    address public treasury;

    // Role constants (from ProtocolRoles)
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant MARKET_ADMIN_ROLE = keccak256("MARKET_ADMIN_ROLE");
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");
    bytes32 public constant RISK_MANAGER_ROLE = keccak256("RISK_MANAGER_ROLE");
    bytes32 public constant RATE_MANAGER_ROLE = keccak256("RATE_MANAGER_ROLE");
    bytes32 public constant STRATEGY_MANAGER_ROLE = keccak256("STRATEGY_MANAGER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    function setUp() public {
        // Setup addresses
        admin = makeAddr("admin");
        guardian = makeAddr("guardian");
        oracleManager = makeAddr("oracleManager");
        riskManager = makeAddr("riskManager");
        rateManager = makeAddr("rateManager");
        strategyManager = makeAddr("strategyManager");
        randomUser = makeAddr("randomUser");
        badDebtAddr = makeAddr("badDebt");
        treasury = makeAddr("treasury");

        vm.startPrank(admin);

        // Deploy mocks
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped ETH", "WETH", 18);
        usdcFeed = new MockPriceFeed(1e8); // $1
        wethFeed = new MockPriceFeed(2000e8); // $2000

        // Deploy oracle
        oracle = new PriceOracle(admin);
        oracleRouter = new OracleRouter(address(oracle), admin);

        // Add price feeds
        oracle.addPriceFeed(address(usdc), address(usdcFeed));
        oracle.addPriceFeed(address(weth), address(wethFeed));
        oracle.transferOwnership(address(oracleRouter));

        // Deploy strategy
        strategy = new MockStrategy(usdc, "USDC Strategy", "sUSDC");

        // Deploy vault
        vault = new Vault(usdc, address(0), address(strategy), admin, "Vault USDC", "vUSDC");

        // Deploy IRM
        irm = new InterestRateModel(
            0.02e18, 0.8e18, 0.04e18, 0.6e18, address(vault), address(0), admin
        );

        // Deploy market via proxy
        MarketV1 implementation = new MarketV1();
        bytes memory initData = abi.encodeWithSelector(
            MarketV1.initialize.selector,
            badDebtAddr,
            treasury,
            address(vault),
            address(oracleRouter),
            address(irm),
            address(usdc),
            admin
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        market = MarketV1(address(proxy));

        // Link contracts
        vault.setMarket(address(market));
        irm.setMarketContract(address(market));

        // Configure market
        market.setMarketParameters(0.85e18, 0.05e18, 0.1e18);
        market.addCollateralToken(address(weth), address(wethFeed));

        // Deploy RiskEngine
        DataTypes.RiskEngineConfig memory riskConfig = DataTypes.RiskEngineConfig({
            oracleFreshnessThreshold: 3600,
            oracleDeviationTolerance: 0.02e18,
            oracleCriticalDeviation: 0.05e18,
            lkgDecayHalfLife: 1800,
            lkgMaxAge: 86_400,
            utilizationWarning: 0.85e18,
            utilizationCritical: 0.95e18,
            healthFactorWarning: 1.2e18,
            healthFactorCritical: 1.05e18,
            badDebtThreshold: 0.01e18,
            strategyAllocationCap: 0.9e18
        });
        riskEngine = new RiskEngine(
            address(market), address(vault), address(oracleRouter), address(irm), admin, riskConfig
        );

        // Deploy Timelock (2 day delay)
        address[] memory proposers = new address[](1);
        proposers[0] = admin;
        address[] memory executors = new address[](1);
        executors[0] = admin;
        timelock = new MarketTimelock(2 days, proposers, executors, address(this));

        // Deploy EmergencyGuardian
        emergencyGuardian = new EmergencyGuardian(address(market), guardian);

        // Set EmergencyGuardian as the market's guardian
        market.setGuardian(address(emergencyGuardian));

        vm.stopPrank();
    }

    // ==================== MARKET ACCESS CONTROL TESTS ====================

    function test_Market_OnlyMarketAdminCanSetParameters() public {
        // Admin should succeed
        vm.prank(admin);
        market.setMarketParameters(0.8e18, 0.06e18, 0.15e18);

        // Random user should fail
        vm.expectRevert();
        vm.prank(randomUser);
        market.setMarketParameters(0.8e18, 0.06e18, 0.15e18);
    }

    function test_Market_OnlyMarketAdminCanAddCollateral() public {
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18);
        MockPriceFeed newFeed = new MockPriceFeed(100e8);

        // Add price feed via oracle router first
        vm.prank(admin);
        oracleRouter.addPriceFeed(address(newToken), address(newFeed));

        // Admin should succeed
        vm.prank(admin);
        market.addCollateralToken(address(newToken), address(newFeed));

        // Random user should fail on another token
        MockERC20 anotherToken = new MockERC20("Another", "ANO", 18);
        MockPriceFeed anotherFeed = new MockPriceFeed(50e8);

        vm.prank(admin);
        oracleRouter.addPriceFeed(address(anotherToken), address(anotherFeed));

        vm.expectRevert();
        vm.prank(randomUser);
        market.addCollateralToken(address(anotherToken), address(anotherFeed));
    }

    function test_Market_GuardianCanPauseButNotUnpause() public {
        // Set guardian
        vm.prank(admin);
        market.setGuardian(guardian);

        // Guardian can pause
        vm.prank(guardian);
        market.setBorrowingPaused(true);
        assertTrue(market.paused());

        // Guardian cannot unpause (should revert)
        vm.expectRevert();
        vm.prank(guardian);
        market.setBorrowingPaused(false);

        // Admin can unpause
        vm.prank(admin);
        market.setBorrowingPaused(false);
        assertFalse(market.paused());
    }

    function test_Market_TransferOwnershipGrantsRoles() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        market.transferOwnership(newAdmin);

        // New admin should have all roles
        assertTrue(market.hasRole(DEFAULT_ADMIN_ROLE, newAdmin));
        assertTrue(market.hasRole(MARKET_ADMIN_ROLE, newAdmin));
        assertTrue(market.hasRole(UPGRADER_ROLE, newAdmin));
    }

    // ==================== ORACLE ROUTER ACCESS CONTROL TESTS ====================

    function test_OracleRouter_OnlyOracleManagerCanAddFeed() public {
        MockERC20 newToken = new MockERC20("New", "NEW", 18);
        MockPriceFeed newFeed = new MockPriceFeed(100e8);

        // Admin (who has ORACLE_MANAGER_ROLE) should succeed
        vm.prank(admin);
        oracleRouter.addPriceFeed(address(newToken), address(newFeed));

        // Random user should fail
        MockERC20 anotherToken = new MockERC20("Another", "ANO", 18);
        MockPriceFeed anotherFeed = new MockPriceFeed(50e8);

        vm.expectRevert();
        vm.prank(randomUser);
        oracleRouter.addPriceFeed(address(anotherToken), address(anotherFeed));
    }

    function test_OracleRouter_OnlyOracleManagerCanSetParams() public {
        // Admin should succeed
        vm.prank(admin);
        oracleRouter.setOracleParams(0.03e18, 0.08e18, 3600, 172_800);

        // Random user should fail
        vm.expectRevert();
        vm.prank(randomUser);
        oracleRouter.setOracleParams(0.03e18, 0.08e18, 3600, 172_800);
    }

    // ==================== INTEREST RATE MODEL ACCESS CONTROL TESTS ====================

    function test_IRM_OnlyRateManagerCanSetRates() public {
        // Admin should succeed
        vm.prank(admin);
        irm.setBaseRate(0.03e18);

        // Random user should fail
        vm.expectRevert();
        vm.prank(randomUser);
        irm.setBaseRate(0.04e18);
    }

    function test_IRM_OnlyRateManagerCanSetOptimalUtilization() public {
        vm.prank(admin);
        irm.setOptimalUtilization(0.75e18);

        vm.expectRevert();
        vm.prank(randomUser);
        irm.setOptimalUtilization(0.7e18);
    }

    function test_IRM_OnlyRateManagerCanSetSlopes() public {
        vm.prank(admin);
        irm.setSlope1(0.05e18);

        vm.prank(admin);
        irm.setSlope2(0.8e18);

        vm.expectRevert();
        vm.prank(randomUser);
        irm.setSlope1(0.06e18);

        vm.expectRevert();
        vm.prank(randomUser);
        irm.setSlope2(0.9e18);
    }

    // ==================== RISK ENGINE ACCESS CONTROL TESTS ====================

    function test_RiskEngine_OnlyRiskManagerCanSetConfig() public {
        DataTypes.RiskEngineConfig memory newConfig = DataTypes.RiskEngineConfig({
            oracleFreshnessThreshold: 3600,
            oracleDeviationTolerance: 0.03e18,
            oracleCriticalDeviation: 0.08e18,
            lkgDecayHalfLife: 1800,
            lkgMaxAge: 86_400,
            utilizationWarning: 0.8e18,
            utilizationCritical: 0.9e18,
            healthFactorWarning: 1.2e18,
            healthFactorCritical: 1.05e18,
            badDebtThreshold: 0.02e18,
            strategyAllocationCap: 0.85e18
        });

        // Admin should succeed
        vm.prank(admin);
        riskEngine.setConfig(newConfig);

        // Random user should fail
        vm.expectRevert();
        vm.prank(randomUser);
        riskEngine.setConfig(newConfig);
    }

    function test_RiskEngine_AnyoneCanAssessRisk() public {
        // Risk assessment is public view function
        vm.prank(randomUser);
        DataTypes.RiskAssessment memory assessment = riskEngine.assessRisk();
        assertGe(assessment.severity, 0);
    }

    // ==================== VAULT ACCESS CONTROL TESTS ====================

    function test_Vault_OnlyStrategyManagerCanChangeStrategy() public {
        MockStrategy newStrategy = new MockStrategy(usdc, "New Strategy", "nsUSDC");

        // Admin should succeed
        vm.prank(admin);
        vault.changeStrategy(address(newStrategy));

        // Random user should fail
        MockStrategy anotherStrategy = new MockStrategy(usdc, "Another", "asUSDC");

        vm.expectRevert();
        vm.prank(randomUser);
        vault.changeStrategy(address(anotherStrategy));
    }

    function test_Vault_AnyoneCanDeposit() public {
        // Give user some USDC
        usdc.mint(randomUser, 1000e6);

        vm.startPrank(randomUser);
        usdc.approve(address(vault), 1000e6);
        vault.deposit(1000e6, randomUser);
        vm.stopPrank();

        assertGt(vault.balanceOf(randomUser), 0);
    }

    // ==================== ROLE GRANTING TESTS ====================

    function test_AdminCanGrantRoles() public {
        // Admin grants MARKET_ADMIN_ROLE to another address
        vm.prank(admin);
        market.grantRole(MARKET_ADMIN_ROLE, oracleManager);

        // Now oracleManager can set market params
        vm.prank(oracleManager);
        market.setMarketParameters(0.82e18, 0.04e18, 0.12e18);
    }

    function test_AdminCanRevokeRoles() public {
        // Grant role first
        vm.prank(admin);
        market.grantRole(MARKET_ADMIN_ROLE, oracleManager);

        // Revoke role
        vm.prank(admin);
        market.revokeRole(MARKET_ADMIN_ROLE, oracleManager);

        // Should now fail
        vm.expectRevert();
        vm.prank(oracleManager);
        market.setMarketParameters(0.82e18, 0.04e18, 0.12e18);
    }

    function test_NonAdminCannotGrantRoles() public {
        vm.expectRevert();
        vm.prank(randomUser);
        market.grantRole(MARKET_ADMIN_ROLE, randomUser);
    }

    // ==================== EMERGENCY GUARDIAN TESTS ====================

    function test_EmergencyGuardian_CanPauseMarket() public {
        // Guardian should be able to pause
        vm.prank(guardian);
        emergencyGuardian.emergencyPause();

        assertTrue(market.paused());
    }

    function test_EmergencyGuardian_NonGuardianCannotPause() public {
        vm.expectRevert();
        vm.prank(randomUser);
        emergencyGuardian.emergencyPause();
    }

    function test_EmergencyGuardian_OwnerCanAddGuardian() public {
        address newGuardian = makeAddr("newGuardian");

        vm.prank(admin); // Owner of EmergencyGuardian
        emergencyGuardian.addGuardian(newGuardian);

        assertTrue(emergencyGuardian.guardians(newGuardian));
    }

    function test_EmergencyGuardian_OwnerCanRemoveGuardian() public {
        vm.prank(admin);
        emergencyGuardian.removeGuardian(guardian);

        assertFalse(emergencyGuardian.guardians(guardian));

        // Removed guardian cannot pause
        vm.expectRevert();
        vm.prank(guardian);
        emergencyGuardian.emergencyPause();
    }

    // ==================== TIMELOCK TESTS ====================

    function test_Timelock_ProposalFlow() public {
        // Prepare a proposal to set market parameters
        address[] memory targets = new address[](1);
        targets[0] = address(market);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeWithSelector(
            MarketV1.setMarketParameters.selector, 0.8e18, 0.06e18, 0.12e18
        );

        bytes32 salt = keccak256("test-proposal-1");
        uint256 delay = timelock.getMinDelay();

        // Schedule the proposal
        vm.prank(admin);
        timelock.scheduleBatch(targets, values, payloads, bytes32(0), salt, delay);

        // Get proposal ID
        bytes32 proposalId =
            timelock.hashOperationBatch(targets, values, payloads, bytes32(0), salt);

        // Proposal should be pending
        assertTrue(timelock.isOperationPending(proposalId));

        // Cannot execute before delay
        vm.expectRevert();
        vm.prank(admin);
        timelock.executeBatch(targets, values, payloads, bytes32(0), salt);

        // Wait for delay
        vm.warp(block.timestamp + delay + 1);

        // First transfer market ownership to timelock
        vm.prank(admin);
        market.transferOwnership(address(timelock));

        // Now execute
        vm.prank(admin);
        timelock.executeBatch(targets, values, payloads, bytes32(0), salt);

        // Verify parameters were updated
        (uint256 lltv,,) = market.getMarketParameters();
        assertEq(lltv, 0.8e18);
    }
}
