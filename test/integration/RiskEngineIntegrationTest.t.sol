// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/core/RiskEngine.sol";
import "../../src/core/OracleRouter.sol";
import "../../src/core/MarketV1.sol";
import "../../src/core/Vault.sol";
import "../../src/core/PriceOracle.sol";
import "../../src/core/InterestRateModel.sol";
import "../../src/libraries/DataTypes.sol";
import "../Mocks.sol";

/// @title RiskEngineIntegrationTest
/// @notice Integration tests exercising the Risk Engine against the full protocol stack
contract RiskEngineIntegrationTest is Test {
    // Core protocol
    MarketV1 public market;
    Vault public vault;
    PriceOracle public oracle;
    InterestRateModel public irm;
    MockStrategy public strategy;

    // Risk Engine stack
    OracleRouter public router;
    RiskEngine public riskEngine;
    MockTWAPOracle public twapOracle;

    // Mocks
    MockERC20 public usdc;
    MockERC20 public weth;
    MockConfigurablePriceFeed public usdcFeed;
    MockConfigurablePriceFeed public wethFeed;

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
        MarketV1 impl = new MarketV1();
        bytes memory initData = abi.encodeWithSelector(
            MarketV1.initialize.selector,
            badDebtAddr,
            treasury,
            address(vault),
            address(router),
            address(irm),
            address(usdc),
            owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        market = MarketV1(address(proxy));

        // Link contracts
        vault.setMarket(address(market));
        irm.setMarketContract(address(market));

        // Configure market
        market.setMarketParameters(0.85e18, 0.05e18, 0.1e18);
        market.addCollateralToken(address(weth), address(wethFeed));

        // Deploy Risk Engine stack
        twapOracle = new MockTWAPOracle();
        twapOracle.setPrice(address(usdc), 1e18);

        DataTypes.RiskEngineConfig memory cfg = DataTypes.RiskEngineConfig({
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
            strategyAllocationCap: 1e18
        });
        riskEngine = new RiskEngine(address(market), address(vault), address(router), address(irm), owner, cfg);

        // Fund vault with liquidity
        usdc.mint(address(this), 1_000_000e6);
        usdc.approve(address(vault), 1_000_000e6);
        vault.deposit(1_000_000e6, address(this));

        // Fund users
        usdc.mint(alice, 500_000e6);
        weth.mint(alice, 500e18);
        usdc.mint(bob, 500_000e6);
        weth.mint(bob, 500e18);
    }

    // ==================== FULL PROTOCOL: NORMAL CONDITIONS ====================

    function testFullProtocol_NormalConditions() public view {
        DataTypes.RiskAssessment memory assessment = riskEngine.assessRisk();

        assertEq(assessment.severity, 0); // Normal
        assertTrue(assessment.scores.oracleRisk <= 20);
        assertTrue(assessment.scores.solvencyRisk == 0);
    }

    // ==================== FULL PROTOCOL: PRICE DROP SCENARIO ====================

    function testFullProtocol_PriceDropScenario() public {
        // Alice borrows against WETH collateral
        vm.startPrank(alice);
        weth.approve(address(market), 100e18);
        market.depositCollateral(address(weth), 100e18);
        market.borrow(150_000e6);
        vm.stopPrank();

        // Check risk before price drop
        DataTypes.RiskAssessment memory beforeDrop = riskEngine.assessUserRisk(alice);
        uint8 solvencyBefore = beforeDrop.scores.solvencyRisk;

        // Drop WETH price by 30%
        wethFeed.setPrice(1400e8); // $1400 from $2000

        // Check risk after price drop
        DataTypes.RiskAssessment memory afterDrop = riskEngine.assessUserRisk(alice);

        // Solvency risk should increase
        assertTrue(afterDrop.scores.solvencyRisk > solvencyBefore);
        assertTrue(afterDrop.severity >= 1);
    }

    // ==================== FULL PROTOCOL: ORACLE FAILURE DURING ACTIVE LOANS ====================

    function testFullProtocol_OracleFailureDuringActiveLoans() public {
        // Alice borrows
        vm.startPrank(alice);
        weth.approve(address(market), 100e18);
        market.depositCollateral(address(weth), 100e18);
        market.borrow(100_000e6);
        vm.stopPrank();

        // Store LKG while oracle is fresh
        router.updateLKG(address(usdc));

        // Kill the oracle (complete failure, no data at all)
        usdcFeed.setShouldRevert(true);

        // LKG was just stored so confidence is still high — advance time past max age
        vm.warp(block.timestamp + 86401);

        DataTypes.RiskAssessment memory assessment = riskEngine.assessRisk();

        // Oracle failure with expired LKG should trigger max oracle risk
        assertEq(assessment.scores.oracleRisk, 100);
        assertEq(assessment.severity, 3); // Emergency
    }

    // ==================== FULL PROTOCOL: ORACLE STALE + DECAY ====================

    function testFullProtocol_OracleStaleWithDecay() public {
        // Store LKG
        router.updateLKG(address(usdc));

        // Make oracle stale
        usdcFeed.setUpdatedAt(block.timestamp - 7200);

        // Check immediately
        DataTypes.RiskAssessment memory early = riskEngine.assessRisk();

        // Advance 1 hour (2 half-lives of decay)
        vm.warp(block.timestamp + 3600);

        DataTypes.RiskAssessment memory later = riskEngine.assessRisk();

        // Oracle risk should increase over time
        assertTrue(later.scores.oracleRisk >= early.scores.oracleRisk);
    }

    // ==================== FULL PROTOCOL: COMBINED STRESS ====================

    function testFullProtocol_CombinedStress() public {
        // Create active loans
        vm.startPrank(alice);
        weth.approve(address(market), 200e18);
        market.depositCollateral(address(weth), 200e18);
        market.borrow(300_000e6);
        vm.stopPrank();

        // Store LKG
        router.updateLKG(address(usdc));

        // 1. Make oracle stale
        usdcFeed.setUpdatedAt(block.timestamp - 7200);

        // 2. Drop collateral price
        wethFeed.setPrice(1200e8);

        // 3. Pause borrowing (simulating emergency response)
        market.setBorrowingPaused(true);

        DataTypes.RiskAssessment memory assessment = riskEngine.assessRisk();

        // Multiple stress factors should compound
        assertTrue(assessment.severity >= 2);
        assertTrue(assessment.scores.oracleRisk >= 30); // Stale oracle
        assertTrue(assessment.scores.solvencyRisk >= 30); // Paused borrowing
    }

    // ==================== FULL PROTOCOL: TWAP CROSS-VALIDATION ====================

    function testFullProtocol_TWAPCrossValidation() public {
        // Register TWAP oracle
        router.setTWAPOracle(address(usdc), address(twapOracle));

        // Consensus: TWAP agrees with Chainlink
        DataTypes.RiskAssessment memory consensus = riskEngine.assessRisk();
        assertTrue(consensus.scores.oracleRisk <= 20);

        // Deviation: TWAP disagrees
        twapOracle.setPrice(address(usdc), 1.04e18); // 4% deviation

        DataTypes.RiskAssessment memory deviation = riskEngine.assessRisk();
        assertTrue(deviation.scores.oracleRisk > consensus.scores.oracleRisk);
    }

    // ==================== FULL PROTOCOL: MULTIPLE USERS ====================

    function testFullProtocol_MultipleUserRiskProfiles() public {
        // Alice: conservative position
        vm.startPrank(alice);
        weth.approve(address(market), 100e18);
        market.depositCollateral(address(weth), 100e18);
        market.borrow(50_000e6);
        vm.stopPrank();

        // Bob: aggressive position
        vm.startPrank(bob);
        weth.approve(address(market), 100e18);
        market.depositCollateral(address(weth), 100e18);
        market.borrow(160_000e6);
        vm.stopPrank();

        DataTypes.RiskAssessment memory aliceRisk = riskEngine.assessUserRisk(alice);
        DataTypes.RiskAssessment memory bobRisk = riskEngine.assessUserRisk(bob);

        // Bob's position should be riskier than Alice's
        assertTrue(bobRisk.scores.solvencyRisk >= aliceRisk.scores.solvencyRisk);
    }

    // ==================== PROTOCOL-LEVEL: GETPRICE INTERFACE ====================

    function testGetPriceInterface() public view {
        (uint256 price, uint8 confidence) = router.getPrice(address(usdc));

        assertEq(price, 1e18); // $1.00
        assertEq(confidence, 100); // Full confidence
    }

    function testGetPriceInterface_Degraded() public {
        router.updateLKG(address(usdc));
        usdcFeed.setUpdatedAt(block.timestamp - 7200); // Make stale

        // Advance time so LKG confidence decays (1 half-life = 1800 seconds)
        vm.warp(block.timestamp + 1800);

        (uint256 price, uint8 confidence) = router.getPrice(address(usdc));

        assertEq(price, 1e18); // LKG price
        assertTrue(confidence < 100); // Degraded confidence
    }
}
