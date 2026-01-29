// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "../interfaces/IOracleRouter.sol";
import "../interfaces/ITWAPOracle.sol";
import "../interfaces/IPriceOracle.sol";
import "../libraries/DataTypes.sol";
import "../libraries/Errors.sol";
import "../libraries/Events.sol";
import "../access/ProtocolAccessControl.sol";
import {PriceOracle} from "./PriceOracle.sol";

/// @title OracleRouter
/// @notice Hierarchical oracle evaluation with Chainlink primary, DEX TWAP cross-validation, and LKG fallback
/// @dev Wraps the existing PriceOracle. The only mutable state is LKG price storage and configuration.
///      Uses AccessControl for role-based permissions (ORACLE_MANAGER_ROLE).
contract OracleRouter is ProtocolAccessControl {
    // ==================== STATE VARIABLES ====================

    /// @notice Legacy owner variable (deprecated, use AccessControl roles)
    /// @dev Kept for storage compatibility and event emission
    address public owner;
    PriceOracle public immutable priceOracle;

    /// @notice TWAP oracle sources per asset
    mapping(address => ITWAPOracle) public twapOracles;

    /// @notice Last Known Good prices per asset
    mapping(address => DataTypes.LKGPrice) public lkgPrices;

    /// @notice Max acceptable Chainlink-vs-TWAP deviation (e.g., 0.02e18 = 2%)
    uint256 public deviationTolerance;

    /// @notice Deviation that triggers critical risk (e.g., 0.05e18 = 5%)
    uint256 public criticalDeviation;

    /// @notice Half-life for LKG confidence decay in seconds (e.g., 1800 = 30 min)
    uint256 public lkgDecayHalfLife;

    /// @notice Maximum age before LKG is considered fully decayed (e.g., 86400 = 24h)
    uint256 public lkgMaxAge;

    // ==================== CONSTANTS ====================

    uint32 public constant TWAP_PERIOD = 1800; // 30-minute TWAP
    uint256 private constant PRECISION = 1e18;
    uint8 private constant MAX_SCORE = 100;

    // ==================== CONSTRUCTOR ====================

    /// @param _priceOracle The existing PriceOracle contract
    /// @param _owner The owner address for admin operations
    constructor(address _priceOracle, address _owner) {
        if (_priceOracle == address(0)) revert Errors.ZeroAddress();
        if (_owner == address(0)) revert Errors.ZeroAddress();

        priceOracle = PriceOracle(_priceOracle);
        owner = _owner;

        // Initialize AccessControl
        _initializeAccessControl(_owner);
        _grantRole(ProtocolRoles.ORACLE_MANAGER_ROLE, _owner);

        // Sensible defaults
        deviationTolerance = 0.02e18; // 2%
        criticalDeviation = 0.05e18; // 5%
        lkgDecayHalfLife = 1800; // 30 minutes
        lkgMaxAge = 86400; // 24 hours
    }

    // Note: Role-based modifiers inherited from ProtocolAccessControl

    // ==================== CORE EVALUATION ====================

    /// @notice Evaluate oracle for an asset using the hierarchical logic
    /// @param asset The asset to evaluate
    /// @return eval Full oracle evaluation result
    function evaluate(address asset) external view returns (DataTypes.OracleEvaluation memory eval) {
        // Step 1: Try primary Chainlink oracle
        (bool chainlinkOk, uint256 chainlinkPrice, bool isFresh) = _tryChainlink(asset);

        if (chainlinkOk && isFresh) {
            // Chainlink is fresh — cross-validate with TWAP (Step 2)
            eval = _crossValidate(asset, chainlinkPrice);
            return eval;
        }

        if (chainlinkOk && !isFresh) {
            // Chainlink returned a price but it's stale — use LKG fallback
            eval = _lkgFallback(asset);
            eval.isStale = true;
            // If LKG also failed, try the stale chainlink price with low confidence
            if (eval.confidence == 0 && chainlinkPrice > 0) {
                eval.resolvedPrice = chainlinkPrice;
                eval.confidence = PRECISION / 10; // 10% confidence for stale data
                eval.oracleRiskScore = 90;
                eval.sourceUsed = 2;
            }
            return eval;
        }

        // Step 3: Chainlink completely failed — use LKG fallback
        eval = _lkgFallback(asset);
    }

    // ==================== MARKET-COMPATIBLE INTERFACE ====================

    /// @notice Get the latest price for an asset using hierarchical evaluation
    /// @param asset The asset to price
    /// @return price Price in USD with 18 decimals
    /// @dev Uses Chainlink → TWAP cross-validation → LKG fallback
    ///      Reverts if no valid price available (confidence = 0)
    function getLatestPrice(address asset) external view returns (uint256 price) {
        DataTypes.OracleEvaluation memory eval = this.evaluate(asset);
        if (eval.confidence == 0) revert Errors.InvalidPrice();
        return eval.resolvedPrice;
    }

    /// @notice Add a price feed for an asset (delegates to underlying PriceOracle)
    /// @param asset The asset address
    /// @param feed The Chainlink price feed address
    /// @dev Only callable by addresses with ORACLE_MANAGER_ROLE
    function addPriceFeed(address asset, address feed) external onlyOracleManager {
        priceOracle.addPriceFeed(asset, feed);
    }

    /// @notice Check if an asset has a price feed configured
    /// @param asset The asset address
    /// @return exists True if price feed exists
    function hasPriceFeed(address asset) external view returns (bool exists) {
        return priceOracle.hasPriceFeed(asset);
    }

    // ==================== SIMPLE PRICE INTERFACE ====================

    /// @notice Returns price and confidence level for an asset (IOracleModule-compatible)
    /// @param asset Address of the asset
    /// @return price Current price in USD with 18 decimals
    /// @return confidence 0-100, where 100 = fully confident
    function getPrice(address asset) external view returns (uint256 price, uint8 confidence) {
        DataTypes.OracleEvaluation memory eval = this.evaluate(asset);
        price = eval.resolvedPrice;
        // Convert confidence from 0-1e18 to 0-100
        confidence = uint8(eval.confidence * 100 / PRECISION);
    }

    /// @notice Returns timestamp of last valid update for an asset
    /// @param asset Address of the asset
    /// @return timestamp The last LKG update timestamp
    function lastUpdate(address asset) external view returns (uint256 timestamp) {
        return lkgPrices[asset].timestamp;
    }

    // ==================== LKG MANAGEMENT ====================

    /// @notice Update the LKG price for an asset when Chainlink is confirmed fresh
    /// @param asset The asset to update
    function updateLKG(address asset) external {
        // This reverts if the price is stale via getLatestPrice
        uint256 price = priceOracle.getLatestPrice(asset);

        lkgPrices[asset] = DataTypes.LKGPrice({
            price: price,
            timestamp: uint64(block.timestamp),
            updatedAt: uint64(block.timestamp)
        });

        emit Events.LKGPriceUpdated(asset, price, uint64(block.timestamp));
    }

    /// @notice Get the stored LKG price for an asset
    /// @param asset The asset address
    /// @return lkg The LKG price entry
    function getLKGPrice(address asset) external view returns (DataTypes.LKGPrice memory lkg) {
        return lkgPrices[asset];
    }

    // ==================== ADMIN FUNCTIONS ====================

    /// @notice Register a TWAP oracle for an asset
    /// @param asset The asset address
    /// @param _twapOracle The TWAP oracle address
    function setTWAPOracle(address asset, address _twapOracle) external onlyOracleManager {
        if (asset == address(0)) revert Errors.ZeroAddress();
        if (_twapOracle == address(0)) revert Errors.ZeroAddress();

        ITWAPOracle twap = ITWAPOracle(_twapOracle);
        if (!twap.supportsAsset(asset)) revert Errors.AssetNotRegistered();

        twapOracles[asset] = twap;
        emit Events.TWAPOracleRegistered(asset, _twapOracle);
    }

    /// @notice Remove a TWAP oracle for an asset
    /// @param asset The asset address
    function removeTWAPOracle(address asset) external onlyOracleManager {
        if (address(twapOracles[asset]) == address(0)) revert Errors.TWAPOracleNotSet();

        delete twapOracles[asset];
        emit Events.TWAPOracleRemoved(asset);
    }

    /// @notice Set oracle evaluation parameters
    /// @param _deviationTolerance Max acceptable deviation (18 decimals)
    /// @param _criticalDeviation Critical deviation threshold (18 decimals)
    /// @param _lkgDecayHalfLife Half-life in seconds
    /// @param _lkgMaxAge Max LKG age in seconds
    function setOracleParams(
        uint256 _deviationTolerance,
        uint256 _criticalDeviation,
        uint256 _lkgDecayHalfLife,
        uint256 _lkgMaxAge
    ) external onlyOracleManager {
        if (_deviationTolerance == 0 || _deviationTolerance > PRECISION) revert Errors.InvalidRiskThreshold();
        if (_criticalDeviation <= _deviationTolerance) revert Errors.InvalidRiskThreshold();
        if (_lkgDecayHalfLife == 0) revert Errors.InvalidHalfLife();
        if (_lkgMaxAge == 0) revert Errors.InvalidMaxAge();

        deviationTolerance = _deviationTolerance;
        criticalDeviation = _criticalDeviation;
        lkgDecayHalfLife = _lkgDecayHalfLife;
        lkgMaxAge = _lkgMaxAge;
    }

    /// @notice Transfer ownership (grants all admin roles to new owner)
    /// @param newOwner The new owner address
    /// @dev Grants DEFAULT_ADMIN_ROLE and ORACLE_MANAGER_ROLE to newOwner
    function transferOwnership(address newOwner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newOwner == address(0)) revert Errors.ZeroAddress();

        // Grant roles to new owner
        _grantRole(DEFAULT_ADMIN_ROLE, newOwner);
        _grantRole(ProtocolRoles.ORACLE_MANAGER_ROLE, newOwner);

        // Update legacy storage
        owner = newOwner;
    }

    // ==================== INTERNAL FUNCTIONS ====================

    /// @notice Try to get a price from Chainlink with freshness check
    /// @param asset The asset to price
    /// @return ok Whether Chainlink returned a valid price
    /// @return price The price (18 decimals) if ok
    /// @return isFresh Whether the price passes the freshness check
    function _tryChainlink(address asset) internal view returns (bool ok, uint256 price, bool isFresh) {
        if (!priceOracle.hasPriceFeed(asset)) {
            return (false, 0, false);
        }

        // Use unsafe getter (doesn't revert on staleness)
        try priceOracle.getLatestPriceUnsafe(asset) returns (uint256 unsafePrice) {
            if (unsafePrice == 0) return (false, 0, false);
            price = unsafePrice;
            ok = true;
        } catch {
            return (false, 0, false);
        }

        // Check freshness manually by querying the Chainlink feed directly
        address feedAddr = address(priceOracle.priceFeeds(asset));
        if (feedAddr == address(0)) return (false, 0, false);

        AggregatorV3Interface feed = AggregatorV3Interface(feedAddr);
        try feed.latestRoundData() returns (uint80 roundId, int256, uint256, uint256 updatedAt, uint80 answeredInRound) {
            if (updatedAt == 0 || answeredInRound < roundId) {
                isFresh = false;
            } else {
                isFresh = (block.timestamp - updatedAt) <= priceOracle.maxPriceAge();
            }
        } catch {
            isFresh = false;
        }
    }

    /// @notice Cross-validate Chainlink price against TWAP (Step 2)
    /// @param asset The asset being evaluated
    /// @param chainlinkPrice The fresh Chainlink price (18 decimals)
    /// @return eval The oracle evaluation result
    function _crossValidate(address asset, uint256 chainlinkPrice)
        internal
        view
        returns (DataTypes.OracleEvaluation memory eval)
    {
        eval.resolvedPrice = chainlinkPrice;
        eval.isStale = false;

        ITWAPOracle twap = twapOracles[asset];
        if (address(twap) == address(0)) {
            // No TWAP registered — accept Chainlink but note lack of cross-validation
            eval.confidence = PRECISION; // Full confidence in fresh Chainlink
            eval.sourceUsed = 0;
            eval.oracleRiskScore = 10; // Small residual risk — no cross-validation
            eval.deviation = 0;
            return eval;
        }

        // Get TWAP price
        try twap.getTWAP(asset, TWAP_PERIOD) returns (uint256 twapPrice, uint256) {
            if (twapPrice == 0) {
                // TWAP returned zero — treat like no TWAP
                eval.confidence = PRECISION;
                eval.sourceUsed = 0;
                eval.oracleRiskScore = 15;
                eval.deviation = 0;
                return eval;
            }

            // Compute deviation: |chainlink - twap| / chainlink
            uint256 deviation;
            if (chainlinkPrice >= twapPrice) {
                deviation = ((chainlinkPrice - twapPrice) * PRECISION) / chainlinkPrice;
            } else {
                deviation = ((twapPrice - chainlinkPrice) * PRECISION) / chainlinkPrice;
            }
            eval.deviation = deviation;

            if (deviation <= deviationTolerance) {
                // Sources agree — low risk
                eval.confidence = PRECISION;
                eval.sourceUsed = 1; // Chainlink+TWAP consensus
                eval.oracleRiskScore = uint8((deviation * 20) / deviationTolerance); // 0-20 range
            } else if (deviation <= criticalDeviation) {
                // Moderate deviation — elevated risk
                uint256 range = criticalDeviation - deviationTolerance;
                uint256 excess = deviation - deviationTolerance;
                eval.confidence = PRECISION - ((excess * PRECISION / 2) / range); // 100% to 50%
                eval.sourceUsed = 1;
                eval.oracleRiskScore = uint8(20 + (40 * excess / range)); // 20-60 range
            } else {
                // Critical deviation — high risk
                uint256 beyondCritical = deviation - criticalDeviation;
                uint256 maxBeyond = PRECISION / 10; // 10% beyond critical = max score
                uint256 scaled = beyondCritical > maxBeyond ? maxBeyond : beyondCritical;
                eval.confidence = PRECISION / 4; // 25% confidence
                eval.sourceUsed = 1;
                eval.oracleRiskScore = uint8(60 + (40 * scaled / maxBeyond)); // 60-100 range
            }
        } catch {
            // TWAP call failed — accept Chainlink with reduced confidence
            eval.confidence = PRECISION * 3 / 4; // 75% confidence
            eval.sourceUsed = 0;
            eval.oracleRiskScore = 20;
            eval.deviation = 0;
        }
    }

    /// @notice Fallback to LKG price with exponential confidence decay (Step 3)
    /// @param asset The asset being evaluated
    /// @return eval The oracle evaluation result
    function _lkgFallback(address asset) internal view returns (DataTypes.OracleEvaluation memory eval) {
        DataTypes.LKGPrice memory lkg = lkgPrices[asset];

        eval.sourceUsed = 2;
        eval.isStale = true;

        // No LKG stored
        if (lkg.price == 0 || lkg.timestamp == 0) {
            eval.resolvedPrice = 0;
            eval.confidence = 0;
            eval.oracleRiskScore = MAX_SCORE;
            return eval;
        }

        uint256 age = block.timestamp - lkg.timestamp;

        // LKG too old — fully decayed
        if (age >= lkgMaxAge) {
            eval.resolvedPrice = lkg.price;
            eval.confidence = 0;
            eval.oracleRiskScore = MAX_SCORE;
            return eval;
        }

        // Compute exponential decay via bit-shift approximation
        // confidence = 2^(-age/halfLife) ≈ PRECISION >> (age / halfLife)
        // with linear interpolation within each half-life period
        uint256 fullHalfLives = age / lkgDecayHalfLife;
        uint256 remainder = age % lkgDecayHalfLife;

        uint256 confidence;
        if (fullHalfLives >= 64) {
            confidence = 0;
        } else {
            // Base confidence after full half-lives
            confidence = PRECISION >> fullHalfLives;
            // Linear interpolation for the remainder within the current half-life
            // Subtract proportional fraction of the next halving
            uint256 nextHalf = confidence / 2;
            uint256 decay = (nextHalf * remainder) / lkgDecayHalfLife;
            confidence = confidence - decay;
        }

        eval.resolvedPrice = lkg.price;
        eval.confidence = confidence;

        // Risk score: inversely proportional to confidence
        // confidence 1e18 → score ~30 (baseline stale risk)
        // confidence 0 → score 100
        if (confidence == 0) {
            eval.oracleRiskScore = MAX_SCORE;
        } else {
            // 30 + 70 * (1 - confidence/PRECISION)
            uint256 inverseConfidence = PRECISION - confidence;
            eval.oracleRiskScore = uint8(30 + (70 * inverseConfidence / PRECISION));
        }
    }
}
