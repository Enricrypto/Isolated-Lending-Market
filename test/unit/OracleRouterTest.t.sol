// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../src/core/OracleRouter.sol";
import "../../src/core/PriceOracle.sol";
import "../../src/libraries/DataTypes.sol";
import "../../src/libraries/Errors.sol";
import "../../src/access/ProtocolAccessControl.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "../Mocks.sol";

contract OracleRouterTest is Test {
    OracleRouter public router;
    PriceOracle public oracle;
    MockConfigurablePriceFeed public usdcFeed;
    MockTWAPOracle public twapOracle;

    address public owner;
    address public usdc;

    uint256 constant PRECISION = 1e18;

    function setUp() public {
        // Warp to a reasonable timestamp so staleness math doesn't underflow
        vm.warp(100_000);

        owner = address(this);
        usdc = makeAddr("usdc");

        // Deploy price feed ($1.00 with 8 decimals)
        usdcFeed = new MockConfigurablePriceFeed(1e8);

        // Deploy oracle
        oracle = new PriceOracle(owner);
        oracle.addPriceFeed(usdc, address(usdcFeed));

        // Deploy TWAP oracle
        twapOracle = new MockTWAPOracle();
        twapOracle.setPrice(usdc, 1e18); // $1.00 normalized to 18 decimals

        // Deploy router
        router = new OracleRouter(address(oracle), owner);
    }

    // ==================== CONSTRUCTION ====================

    function testConstructor_SetsState() public view {
        assertEq(address(router.priceOracle()), address(oracle));
        assertEq(router.owner(), owner);
        assertEq(router.deviationTolerance(), 0.02e18);
        assertEq(router.criticalDeviation(), 0.05e18);
        assertEq(router.lkgDecayHalfLife(), 1800);
        assertEq(router.lkgMaxAge(), 86_400);
    }

    function testConstructor_RevertsZeroOracle() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new OracleRouter(address(0), owner);
    }

    function testConstructor_RevertsZeroOwner() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new OracleRouter(address(oracle), address(0));
    }

    // ==================== EVALUATE: FRESH CHAINLINK, NO TWAP ====================

    function testEvaluate_FreshChainlink_NoTWAP() public view {
        DataTypes.OracleEvaluation memory eval = router.evaluate(usdc);

        assertEq(eval.resolvedPrice, 1e18); // $1.00
        assertEq(eval.confidence, PRECISION); // Full confidence
        assertEq(eval.sourceUsed, 0); // Chainlink
        assertEq(eval.oracleRiskScore, 10); // Small residual risk (no cross-validation)
        assertFalse(eval.isStale);
        assertEq(eval.deviation, 0);
    }

    // ==================== EVALUATE: FRESH CHAINLINK + TWAP CONSENSUS ====================

    function testEvaluate_FreshChainlink_TWAPConsensus() public {
        router.setTWAPOracle(usdc, address(twapOracle));

        DataTypes.OracleEvaluation memory eval = router.evaluate(usdc);

        assertEq(eval.resolvedPrice, 1e18);
        assertEq(eval.confidence, PRECISION);
        assertEq(eval.sourceUsed, 1); // Chainlink+TWAP consensus
        assertTrue(eval.oracleRiskScore <= 20); // Low risk
        assertFalse(eval.isStale);
        assertEq(eval.deviation, 0);
    }

    // ==================== EVALUATE: FRESH CHAINLINK + TWAP DEVIATION ====================

    function testEvaluate_FreshChainlink_TWAPMinorDeviation() public {
        router.setTWAPOracle(usdc, address(twapOracle));

        // Set TWAP to 1.5% deviation (within 2% tolerance)
        twapOracle.setPrice(usdc, 1.015e18); // $1.015

        DataTypes.OracleEvaluation memory eval = router.evaluate(usdc);

        assertEq(eval.resolvedPrice, 1e18); // Still uses Chainlink
        assertEq(eval.confidence, PRECISION);
        assertEq(eval.sourceUsed, 1);
        assertTrue(eval.oracleRiskScore <= 20);
        assertTrue(eval.deviation > 0);
    }

    function testEvaluate_FreshChainlink_TWAPElevatedDeviation() public {
        router.setTWAPOracle(usdc, address(twapOracle));

        // Set TWAP to 3% deviation (between 2% tolerance and 5% critical)
        twapOracle.setPrice(usdc, 1.03e18); // $1.03

        DataTypes.OracleEvaluation memory eval = router.evaluate(usdc);

        assertEq(eval.resolvedPrice, 1e18);
        assertTrue(eval.confidence < PRECISION); // Reduced confidence
        assertTrue(eval.confidence > PRECISION / 2); // But above 50%
        assertEq(eval.sourceUsed, 1);
        assertTrue(eval.oracleRiskScore >= 20);
        assertTrue(eval.oracleRiskScore <= 60);
    }

    function testEvaluate_FreshChainlink_TWAPCriticalDeviation() public {
        router.setTWAPOracle(usdc, address(twapOracle));

        // Set TWAP to 8% deviation (above 5% critical)
        twapOracle.setPrice(usdc, 1.08e18); // $1.08

        DataTypes.OracleEvaluation memory eval = router.evaluate(usdc);

        assertEq(eval.resolvedPrice, 1e18);
        assertEq(eval.confidence, PRECISION / 4); // 25% confidence
        assertEq(eval.sourceUsed, 1);
        assertTrue(eval.oracleRiskScore >= 60);
    }

    // ==================== EVALUATE: TWAP FAILURE ====================

    function testEvaluate_FreshChainlink_TWAPReverts() public {
        router.setTWAPOracle(usdc, address(twapOracle));
        twapOracle.setShouldRevert(true);

        DataTypes.OracleEvaluation memory eval = router.evaluate(usdc);

        assertEq(eval.resolvedPrice, 1e18);
        assertEq(eval.confidence, PRECISION * 3 / 4); // 75% confidence
        assertEq(eval.sourceUsed, 0); // Falls back to Chainlink-only
        assertEq(eval.oracleRiskScore, 20);
    }

    function testEvaluate_FreshChainlink_TWAPReturnsZero() public {
        router.setTWAPOracle(usdc, address(twapOracle));
        twapOracle.setPrice(usdc, 0);

        DataTypes.OracleEvaluation memory eval = router.evaluate(usdc);

        assertEq(eval.resolvedPrice, 1e18);
        assertEq(eval.sourceUsed, 0);
        assertEq(eval.oracleRiskScore, 15);
    }

    // ==================== EVALUATE: STALE CHAINLINK + LKG FALLBACK ====================

    function testEvaluate_StaleChainlink_LKGRecent() public {
        // First, store a fresh LKG
        router.updateLKG(usdc);

        // Make Chainlink stale (2 hours old, max is 1 hour)
        usdcFeed.setUpdatedAt(block.timestamp - 7200);

        DataTypes.OracleEvaluation memory eval = router.evaluate(usdc);

        assertEq(eval.resolvedPrice, 1e18); // Uses LKG
        assertTrue(eval.confidence > 0);
        assertEq(eval.sourceUsed, 2); // LKG fallback
        assertTrue(eval.isStale);
        assertTrue(eval.oracleRiskScore >= 30);
    }

    function testEvaluate_StaleChainlink_LKGDecayed() public {
        // Store LKG
        router.updateLKG(usdc);

        // Make Chainlink stale
        usdcFeed.setUpdatedAt(block.timestamp - 7200);

        // Advance time so LKG decays (2 half-lives = 1 hour)
        vm.warp(block.timestamp + 3600);

        DataTypes.OracleEvaluation memory eval = router.evaluate(usdc);

        assertEq(eval.resolvedPrice, 1e18); // Still the LKG price
        assertTrue(eval.confidence < PRECISION / 2); // Decayed below 50%
        assertTrue(eval.oracleRiskScore >= 50);
    }

    function testEvaluate_StaleChainlink_LKGExpired() public {
        // Store LKG
        router.updateLKG(usdc);

        // Make Chainlink stale
        usdcFeed.setUpdatedAt(block.timestamp - 7200);

        // Advance time past lkgMaxAge (24 hours)
        vm.warp(block.timestamp + 86_401);

        DataTypes.OracleEvaluation memory eval = router.evaluate(usdc);

        // LKG expired, but stale chainlink data exists with low confidence
        assertTrue(eval.isStale);
        assertTrue(eval.oracleRiskScore >= 90);
    }

    // ==================== EVALUATE: CHAINLINK COMPLETELY DOWN ====================

    function testEvaluate_ChainlinkDown_NoLKG() public {
        usdcFeed.setShouldRevert(true);

        DataTypes.OracleEvaluation memory eval = router.evaluate(usdc);

        assertEq(eval.resolvedPrice, 0);
        assertEq(eval.confidence, 0);
        assertEq(eval.sourceUsed, 2);
        assertEq(eval.oracleRiskScore, 100); // Max severity
    }

    function testEvaluate_ChainlinkDown_HasLKG() public {
        // Store LKG first
        router.updateLKG(usdc);

        // Kill Chainlink
        usdcFeed.setShouldRevert(true);

        DataTypes.OracleEvaluation memory eval = router.evaluate(usdc);

        assertEq(eval.resolvedPrice, 1e18); // Uses LKG
        assertTrue(eval.confidence > 0);
        assertEq(eval.sourceUsed, 2);
        assertTrue(eval.oracleRiskScore >= 30);
    }

    function testEvaluate_NoPriceFeed() public {
        address unknown = makeAddr("unknown");

        DataTypes.OracleEvaluation memory eval = router.evaluate(unknown);

        assertEq(eval.resolvedPrice, 0);
        assertEq(eval.confidence, 0);
        assertEq(eval.oracleRiskScore, 100);
    }

    // ==================== LKG CONFIDENCE DECAY ====================

    function testLKGDecay_HalfLifeAccuracy() public {
        router.updateLKG(usdc);

        // Advance exactly 1 half-life (1800 seconds)
        usdcFeed.setUpdatedAt(block.timestamp - 7200); // Make Chainlink stale
        vm.warp(block.timestamp + 1800);

        DataTypes.OracleEvaluation memory eval = router.evaluate(usdc);

        // After 1 half-life, confidence should be approximately PRECISION/2
        // With linear interpolation: base = PRECISION >> 1 = 0.5e18, remainder = 0
        assertEq(eval.confidence, PRECISION / 2);
    }

    function testLKGDecay_TwoHalfLives() public {
        router.updateLKG(usdc);

        usdcFeed.setUpdatedAt(block.timestamp - 7200);
        vm.warp(block.timestamp + 3600); // 2 half-lives

        DataTypes.OracleEvaluation memory eval = router.evaluate(usdc);

        // After 2 half-lives: confidence = PRECISION >> 2 = 0.25e18
        assertEq(eval.confidence, PRECISION / 4);
    }

    function testLKGDecay_MaxAge_ZeroConfidence() public {
        router.updateLKG(usdc);

        // Kill Chainlink entirely so there's no stale fallback
        usdcFeed.setShouldRevert(true);

        vm.warp(block.timestamp + 86_400); // Exactly max age

        DataTypes.OracleEvaluation memory eval = router.evaluate(usdc);

        assertEq(eval.confidence, 0);
        assertEq(eval.oracleRiskScore, 100);
    }

    // ==================== UPDATE LKG ====================

    function testUpdateLKG_StoresFreshPrice() public {
        router.updateLKG(usdc);

        DataTypes.LKGPrice memory lkg = router.getLKGPrice(usdc);
        assertEq(lkg.price, 1e18);
        assertEq(lkg.timestamp, uint64(block.timestamp));
    }

    function testUpdateLKG_RevertsIfStale() public {
        usdcFeed.setUpdatedAt(block.timestamp - 7200); // 2 hours old

        vm.expectRevert(Errors.StalePrice.selector);
        router.updateLKG(usdc);
    }

    function testUpdateLKG_CanBeCalledByAnyone() public {
        address alice = makeAddr("alice");
        vm.prank(alice);
        router.updateLKG(usdc);

        DataTypes.LKGPrice memory lkg = router.getLKGPrice(usdc);
        assertEq(lkg.price, 1e18);
    }

    // ==================== ADMIN: SET TWAP ORACLE ====================

    function testSetTWAPOracle_Success() public {
        router.setTWAPOracle(usdc, address(twapOracle));
        assertEq(address(router.twapOracles(usdc)), address(twapOracle));
    }

    function testSetTWAPOracle_RevertsNonOwner() public {
        address alice = makeAddr("alice");
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                ProtocolRoles.ORACLE_MANAGER_ROLE
            )
        );
        router.setTWAPOracle(usdc, address(twapOracle));
    }

    function testSetTWAPOracle_RevertsZeroAsset() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        router.setTWAPOracle(address(0), address(twapOracle));
    }

    function testSetTWAPOracle_RevertsZeroOracle() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        router.setTWAPOracle(usdc, address(0));
    }

    function testSetTWAPOracle_RevertsUnsupportedAsset() public {
        address unknown = makeAddr("unknown");
        vm.expectRevert(Errors.AssetNotRegistered.selector);
        router.setTWAPOracle(unknown, address(twapOracle));
    }

    // ==================== ADMIN: REMOVE TWAP ORACLE ====================

    function testRemoveTWAPOracle_Success() public {
        router.setTWAPOracle(usdc, address(twapOracle));
        router.removeTWAPOracle(usdc);
        assertEq(address(router.twapOracles(usdc)), address(0));
    }

    function testRemoveTWAPOracle_RevertsNotSet() public {
        vm.expectRevert(Errors.TWAPOracleNotSet.selector);
        router.removeTWAPOracle(usdc);
    }

    function testRemoveTWAPOracle_RevertsNonOwner() public {
        router.setTWAPOracle(usdc, address(twapOracle));

        address alice = makeAddr("alice");
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                ProtocolRoles.ORACLE_MANAGER_ROLE
            )
        );
        router.removeTWAPOracle(usdc);
    }

    // ==================== ADMIN: SET ORACLE PARAMS ====================

    function testSetOracleParams_Success() public {
        router.setOracleParams(0.03e18, 0.08e18, 3600, 172_800);

        assertEq(router.deviationTolerance(), 0.03e18);
        assertEq(router.criticalDeviation(), 0.08e18);
        assertEq(router.lkgDecayHalfLife(), 3600);
        assertEq(router.lkgMaxAge(), 172_800);
    }

    function testSetOracleParams_RevertsNonOwner() public {
        address alice = makeAddr("alice");
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                ProtocolRoles.ORACLE_MANAGER_ROLE
            )
        );
        router.setOracleParams(0.03e18, 0.08e18, 3600, 172_800);
    }

    function testSetOracleParams_RevertsCriticalBelowTolerance() public {
        vm.expectRevert(Errors.InvalidRiskThreshold.selector);
        router.setOracleParams(0.05e18, 0.03e18, 1800, 86_400); // critical < tolerance
    }

    function testSetOracleParams_RevertsZeroHalfLife() public {
        vm.expectRevert(Errors.InvalidHalfLife.selector);
        router.setOracleParams(0.02e18, 0.05e18, 0, 86_400);
    }

    function testSetOracleParams_RevertsZeroMaxAge() public {
        vm.expectRevert(Errors.InvalidMaxAge.selector);
        router.setOracleParams(0.02e18, 0.05e18, 1800, 0);
    }

    // ==================== ADMIN: TRANSFER OWNERSHIP ====================

    function testTransferOwnership_Success() public {
        address newOwner = makeAddr("newOwner");
        router.transferOwnership(newOwner);
        assertEq(router.owner(), newOwner);
    }

    function testTransferOwnership_RevertsZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        router.transferOwnership(address(0));
    }

    function testTransferOwnership_RevertsNonOwner() public {
        address alice = makeAddr("alice");
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                0x00 // DEFAULT_ADMIN_ROLE
            )
        );
        router.transferOwnership(alice);
    }
}
