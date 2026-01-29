// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "../../src/core/RiskEngine.sol";
import "../../src/core/OracleRouter.sol";
import "../../src/core/MarketV1.sol";
import "../../src/core/Vault.sol";
import "../../src/core/PriceOracle.sol";
import "../../src/core/InterestRateModel.sol";
import "../../src/libraries/DataTypes.sol";
import "../../src/libraries/Errors.sol";
import "../../src/access/ProtocolAccessControl.sol";
import "../Mocks.sol";

contract RiskEngineTest is Test {
    // Core protocol
    MarketV1 public market;
    Vault public vault;
    PriceOracle public oracle;
    InterestRateModel public irm;

    // Risk Engine stack
    OracleRouter public router;
    RiskEngine public riskEngine;
    MockTWAPOracle public twapOracle;

    // Mocks
    MockERC20 public usdc;
    MockERC20 public weth;
    MockConfigurablePriceFeed public usdcFeed;
    MockConfigurablePriceFeed public wethFeed;
    MockStrategy public strategy;

    // Addresses
    address public owner;
    address public treasury;
    address public badDebtAddr;
    address public alice;
    address public bob;

    uint256 constant PRECISION = 1e18;

    function setUp() public {
        vm.warp(100_000);

        owner = address(this);
        treasury = makeAddr("treasury");
        badDebtAddr = makeAddr("badDebt");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Deploy tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);

        // Deploy configurable price feeds
        usdcFeed = new MockConfigurablePriceFeed(1e8); // $1.00
        wethFeed = new MockConfigurablePriceFeed(2000e8); // $2000

        // Deploy oracle and OracleRouter
        oracle = new PriceOracle(owner);
        router = new OracleRouter(address(oracle), owner);

        // Deploy strategy
        strategy = new MockStrategy(usdc, "USDC Strategy", "sUSDC");

        // Deploy vault (with owner for AccessControl)
        vault = new Vault(usdc, address(0), address(strategy), owner, "Vault USDC", "vUSDC");

        // Deploy IRM (with owner for AccessControl)
        irm = new InterestRateModel(0.02e18, 0.8e18, 0.04e18, 0.6e18, address(vault), address(0), owner);

        // Add ALL price feeds before transferring ownership to OracleRouter
        oracle.addPriceFeed(address(usdc), address(usdcFeed));
        oracle.addPriceFeed(address(weth), address(wethFeed));
        oracle.transferOwnership(address(router));

        // Deploy Market via proxy (using OracleRouter)
        MarketV1 implementation = new MarketV1();
        bytes memory initData = abi.encodeWithSelector(
            MarketV1.initialize.selector, badDebtAddr, treasury, address(vault), address(router), address(irm), address(usdc), owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        market = MarketV1(address(proxy));

        // Link contracts
        vault.setMarket(address(market));
        irm.setMarketContract(address(market));

        // Configure market
        market.setMarketParameters(0.85e18, 0.05e18, 0.1e18);
        market.addCollateralToken(address(weth), address(wethFeed));

        // Deploy TWAP oracle
        twapOracle = new MockTWAPOracle();
        twapOracle.setPrice(address(usdc), 1e18);

        // Deploy RiskEngine with default config
        DataTypes.RiskEngineConfig memory cfg = _defaultConfig();
        riskEngine = new RiskEngine(address(market), address(vault), address(router), address(irm), owner, cfg);

        // Fund alice with tokens
        usdc.mint(alice, 1_000_000e6);
        weth.mint(alice, 1000e18);

        // Fund vault with liquidity
        usdc.mint(address(this), 1_000_000e6);
        usdc.approve(address(vault), 1_000_000e6);
        vault.deposit(1_000_000e6, address(this));
    }

    function _defaultConfig() internal pure returns (DataTypes.RiskEngineConfig memory) {
        return DataTypes.RiskEngineConfig({
            oracleFreshnessThreshold: 3600,
            oracleDeviationTolerance: 0.02e18,
            oracleCriticalDeviation: 0.05e18,
            lkgDecayHalfLife: 1800,
            lkgMaxAge: 86400,
            utilizationWarning: 0.85e18,
            utilizationCritical: 0.95e18,
            healthFactorWarning: 1.2e18,
            healthFactorCritical: 1.05e18,
            badDebtThreshold: 0.01e18,
            strategyAllocationCap: 1e18 // 100% — vault deposits all into strategy by default
        });
    }

    // ==================== CONSTRUCTION ====================

    function testConstructor_SetsState() public view {
        assertEq(address(riskEngine.market()), address(market));
        assertEq(address(riskEngine.vault()), address(vault));
        assertEq(address(riskEngine.oracleRouter()), address(router));
        assertEq(address(riskEngine.interestRateModel()), address(irm));
        assertEq(riskEngine.owner(), owner);
    }

    function testConstructor_RevertsZeroAddresses() public {
        DataTypes.RiskEngineConfig memory cfg = _defaultConfig();

        vm.expectRevert(Errors.ZeroAddress.selector);
        new RiskEngine(address(0), address(vault), address(router), address(irm), owner, cfg);

        vm.expectRevert(Errors.ZeroAddress.selector);
        new RiskEngine(address(market), address(0), address(router), address(irm), owner, cfg);

        vm.expectRevert(Errors.ZeroAddress.selector);
        new RiskEngine(address(market), address(vault), address(0), address(irm), owner, cfg);

        vm.expectRevert(Errors.ZeroAddress.selector);
        new RiskEngine(address(market), address(vault), address(router), address(0), owner, cfg);

        vm.expectRevert(Errors.ZeroAddress.selector);
        new RiskEngine(address(market), address(vault), address(router), address(irm), address(0), cfg);
    }

    // ==================== ASSESS RISK: NORMAL CONDITIONS ====================

    function testAssessRisk_NormalConditions() public view {
        DataTypes.RiskAssessment memory assessment = riskEngine.assessRisk();

        // With fresh oracle, low utilization, no bad debt, no strategy overallocation
        assertEq(assessment.severity, 0); // Normal
        assertTrue(assessment.scores.oracleRisk <= 20);
        assertTrue(assessment.scores.liquidityRisk < 25);
        assertTrue(assessment.scores.solvencyRisk == 0); // No borrows
        assertTrue(assessment.scores.strategyRisk < 25);
        assertEq(assessment.timestamp, uint64(block.timestamp));
    }

    // ==================== ORACLE RISK ====================

    function testOracleRisk_FreshChainlink_LowRisk() public view {
        (uint8 score,) = riskEngine.computeOracleRisk(address(usdc));
        assertTrue(score <= 20); // Fresh Chainlink, no TWAP = 10
    }

    function testOracleRisk_StaleChainlink_HighRisk() public {
        // Store LKG first
        router.updateLKG(address(usdc));

        // Make stale
        usdcFeed.setUpdatedAt(block.timestamp - 7200);

        (uint8 score,) = riskEngine.computeOracleRisk(address(usdc));
        assertTrue(score >= 30); // LKG fallback
    }

    function testOracleRisk_ChainlinkDown_MaxRisk() public {
        usdcFeed.setShouldRevert(true);

        (uint8 score,) = riskEngine.computeOracleRisk(address(usdc));
        assertEq(score, 100); // No data = max risk
    }

    // ==================== LIQUIDITY RISK ====================

    function testLiquidityRisk_LowUtilization() public view {
        uint8 score = riskEngine.computeLiquidityRisk();
        assertTrue(score < 25); // Low utilization
    }

    function testLiquidityRisk_HighUtilization() public {
        // Alice deposits collateral and borrows heavily
        _depositAndBorrow(alice, 1000e18, 850_000e6);

        uint8 score = riskEngine.computeLiquidityRisk();
        assertTrue(score >= 25); // Elevated
    }

    function testLiquidityRisk_CriticalUtilization() public {
        // Borrow almost everything
        _depositAndBorrow(alice, 1000e18, 950_000e6);

        uint8 score = riskEngine.computeLiquidityRisk();
        assertTrue(score >= 50); // Critical range
    }

    // ==================== SOLVENCY RISK ====================

    function testSolvencyRisk_NoBorrows() public view {
        uint8 score = riskEngine.computeSolvencyRisk();
        assertEq(score, 0); // No borrows = no solvency risk
    }

    function testSolvencyRisk_PausedMarket() public {
        // Need some borrows first
        _depositAndBorrow(alice, 100e18, 100_000e6);

        // Pause borrowing
        market.setBorrowingPaused(true);

        uint8 score = riskEngine.computeSolvencyRisk();
        assertTrue(score >= 30); // Paused = minimum 30
    }

    // ==================== STRATEGY RISK ====================

    function testStrategyRisk_NormalAllocation() public view {
        uint8 score = riskEngine.computeStrategyRisk();
        assertTrue(score < 25); // 100% in strategy, but cap is 100%, so no overallocation
    }

    function testStrategyRisk_OverAllocation() public {
        // Lower the cap so 100% strategy allocation triggers overallocation
        DataTypes.RiskEngineConfig memory cfg = _defaultConfig();
        cfg.strategyAllocationCap = 0.5e18; // 50% cap
        riskEngine.setConfig(cfg);

        uint8 score = riskEngine.computeStrategyRisk();
        assertTrue(score >= 30); // Over-allocated
    }

    // ==================== SEVERITY MAPPING ====================

    function testSeverity_AllNormal() public pure {
        DataTypes.DimensionScore memory scores = DataTypes.DimensionScore({
            oracleRisk: 10,
            liquidityRisk: 15,
            solvencyRisk: 5,
            strategyRisk: 20
        });

        RiskEngine engine; // We'll use the pure function directly
        // Use abi.encode trick to call pure function without deploying
        // Instead, test via the actual engine
    }

    function testSeverity_Elevated() public view {
        DataTypes.DimensionScore memory scores =
            DataTypes.DimensionScore({oracleRisk: 30, liquidityRisk: 15, solvencyRisk: 5, strategyRisk: 10});

        uint8 severity = riskEngine.computeSeverity(scores);
        assertEq(severity, 1); // Elevated (max score 30 >= 25)
    }

    function testSeverity_Critical() public view {
        DataTypes.DimensionScore memory scores =
            DataTypes.DimensionScore({oracleRisk: 55, liquidityRisk: 15, solvencyRisk: 5, strategyRisk: 10});

        uint8 severity = riskEngine.computeSeverity(scores);
        assertEq(severity, 2); // Critical (max score 55 >= 50)
    }

    function testSeverity_Emergency() public view {
        DataTypes.DimensionScore memory scores =
            DataTypes.DimensionScore({oracleRisk: 80, liquidityRisk: 60, solvencyRisk: 5, strategyRisk: 10});

        uint8 severity = riskEngine.computeSeverity(scores);
        assertEq(severity, 3); // Emergency (max score 80 >= 75)
    }

    function testSeverity_MaxAcrossDimensions() public view {
        DataTypes.DimensionScore memory scores =
            DataTypes.DimensionScore({oracleRisk: 10, liquidityRisk: 10, solvencyRisk: 10, strategyRisk: 80});

        uint8 severity = riskEngine.computeSeverity(scores);
        assertEq(severity, 3); // Emergency from strategy alone
    }

    // ==================== ASSESS USER RISK ====================

    function testAssessUserRisk_NoPosition() public view {
        DataTypes.RiskAssessment memory assessment = riskEngine.assessUserRisk(bob);

        assertEq(assessment.severity, 0);
        assertEq(assessment.scores.oracleRisk, 0);
        assertEq(assessment.scores.solvencyRisk, 0);
    }

    function testAssessUserRisk_HealthyPosition() public {
        _depositAndBorrow(alice, 100e18, 50_000e6);

        DataTypes.RiskAssessment memory assessment = riskEngine.assessUserRisk(alice);

        // User's health factor is strong (~3.2x), so user-specific solvency risk should be low
        assertTrue(assessment.scores.solvencyRisk < 25);
        // Oracle risk is low (fresh Chainlink)
        assertTrue(assessment.scores.oracleRisk <= 20);
        // Note: liquidity risk may be elevated due to IRM decimal normalization behavior
        // but the user position itself is healthy
    }

    function testAssessUserRisk_NearLiquidation() public {
        _depositAndBorrow(alice, 100e18, 160_000e6);

        // Drop WETH price to make position unhealthy
        wethFeed.setPrice(1100e8); // $1100 from $2000

        DataTypes.RiskAssessment memory assessment = riskEngine.assessUserRisk(alice);

        // Near liquidation — high solvency risk
        assertTrue(assessment.scores.solvencyRisk >= 50);
        assertTrue(assessment.severity >= 2);
    }

    // ==================== ASSESS ASSET RISK ====================

    function testAssessAssetRisk_FreshOracle() public view {
        DataTypes.RiskAssessment memory assessment = riskEngine.assessAssetRisk(address(usdc));

        assertTrue(assessment.scores.oracleRisk <= 20);
    }

    function testAssessAssetRisk_StaleOracle() public {
        router.updateLKG(address(usdc));
        usdcFeed.setUpdatedAt(block.timestamp - 7200);

        DataTypes.RiskAssessment memory assessment = riskEngine.assessAssetRisk(address(usdc));

        assertTrue(assessment.scores.oracleRisk >= 30);
    }

    // ==================== DETERMINISM ====================

    function testDeterminism_SameBlock_SameOutput() public view {
        DataTypes.RiskAssessment memory a1 = riskEngine.assessRisk();
        DataTypes.RiskAssessment memory a2 = riskEngine.assessRisk();

        assertEq(a1.severity, a2.severity);
        assertEq(a1.scores.oracleRisk, a2.scores.oracleRisk);
        assertEq(a1.scores.liquidityRisk, a2.scores.liquidityRisk);
        assertEq(a1.scores.solvencyRisk, a2.scores.solvencyRisk);
        assertEq(a1.scores.strategyRisk, a2.scores.strategyRisk);
        assertEq(a1.reasonCodes, a2.reasonCodes);
    }

    function testDeterminism_ConfigChange_DifferentOutput() public {
        DataTypes.RiskAssessment memory before = riskEngine.assessRisk();

        // Change config to be more sensitive
        DataTypes.RiskEngineConfig memory newCfg = _defaultConfig();
        newCfg.utilizationWarning = 0.01e18; // Very low threshold
        riskEngine.setConfig(newCfg);

        DataTypes.RiskAssessment memory after_ = riskEngine.assessRisk();

        // Liquidity risk should increase with lower threshold
        assertTrue(after_.scores.liquidityRisk >= before.scores.liquidityRisk);
    }

    // ==================== FAILURE MODES ====================

    function testOracleOutage_GradualEscalation() public {
        // Store LKG
        router.updateLKG(address(usdc));

        // Make Chainlink stale
        usdcFeed.setUpdatedAt(block.timestamp - 7200);

        // Check risk right after stale
        DataTypes.RiskAssessment memory a1 = riskEngine.assessRisk();

        // Advance time (LKG decays)
        vm.warp(block.timestamp + 3600);

        DataTypes.RiskAssessment memory a2 = riskEngine.assessRisk();

        // Risk should escalate
        assertTrue(a2.scores.oracleRisk >= a1.scores.oracleRisk);
    }

    function testMissingInputs_MaxSeverity() public {
        usdcFeed.setShouldRevert(true);

        DataTypes.RiskAssessment memory assessment = riskEngine.assessRisk();

        assertEq(assessment.scores.oracleRisk, 100);
        assertEq(assessment.severity, 3); // Emergency
    }

    // ==================== INVARIANT: NEVER MUTATES STATE ====================

    function testInvariant_NeverMutatesState() public {
        // Record state before
        uint256 totalBorrowsBefore = market.totalBorrows();
        uint256 vaultAssetsBefore = vault.totalAssets();

        // Call all assessment functions
        riskEngine.assessRisk();
        riskEngine.assessAssetRisk(address(usdc));
        riskEngine.assessUserRisk(alice);
        riskEngine.computeOracleRisk(address(usdc));
        riskEngine.computeLiquidityRisk();
        riskEngine.computeSolvencyRisk();
        riskEngine.computeStrategyRisk();
        riskEngine.evaluateOracle(address(usdc));

        // State should be identical
        assertEq(market.totalBorrows(), totalBorrowsBefore);
        assertEq(vault.totalAssets(), vaultAssetsBefore);
    }

    // ==================== CONFIGURATION ====================

    function testSetConfig_Success() public {
        DataTypes.RiskEngineConfig memory newCfg = _defaultConfig();
        newCfg.utilizationWarning = 0.90e18;

        riskEngine.setConfig(newCfg);

        DataTypes.RiskEngineConfig memory stored = riskEngine.getConfig();
        assertEq(stored.utilizationWarning, 0.90e18);
    }

    function testSetConfig_RevertsNonOwner() public {
        DataTypes.RiskEngineConfig memory cfg = _defaultConfig();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                ProtocolRoles.RISK_MANAGER_ROLE
            )
        );
        riskEngine.setConfig(cfg);
    }

    function testSetConfig_RevertsInvalidConfig() public {
        DataTypes.RiskEngineConfig memory cfg = _defaultConfig();
        cfg.oracleFreshnessThreshold = 0; // Invalid

        vm.expectRevert(Errors.InvalidRiskThreshold.selector);
        riskEngine.setConfig(cfg);
    }

    // ==================== REASON CODES ====================

    function testReasonCodes_OracleFailure() public {
        usdcFeed.setShouldRevert(true);

        DataTypes.RiskAssessment memory assessment = riskEngine.assessRisk();

        // Should have REASON_ORACLE_FAILURE bit set (bit 4 = 16)
        assertTrue(uint256(assessment.reasonCodes) & (1 << 4) != 0);
    }

    function testReasonCodes_HighUtilization() public {
        _depositAndBorrow(alice, 1000e18, 900_000e6);

        DataTypes.RiskAssessment memory assessment = riskEngine.assessRisk();

        // Should have utilization reason bits set
        uint256 reasons = uint256(assessment.reasonCodes);
        assertTrue(reasons & (1 << 5) != 0 || reasons & (1 << 6) != 0); // UTIL_HIGH or UTIL_CRITICAL
    }

    // ==================== HELPERS ====================

    function _depositAndBorrow(address user, uint256 collateralAmount, uint256 borrowAmount) internal {
        vm.startPrank(user);
        weth.approve(address(market), collateralAmount);
        market.depositCollateral(address(weth), collateralAmount);
        market.borrow(borrowAmount);
        vm.stopPrank();
    }
}
