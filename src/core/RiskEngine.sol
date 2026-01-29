// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OracleRouter} from "./OracleRouter.sol";
import {MarketV1} from "./MarketV1.sol";
import {Vault} from "./Vault.sol";
import {InterestRateModel} from "./InterestRateModel.sol";
import "../interfaces/IRiskEngine.sol";
import "../libraries/DataTypes.sol";
import "../libraries/Errors.sol";
import "../libraries/Events.sol";
import "../access/ProtocolAccessControl.sol";

/// @title RiskEngine
/// @notice Read-only risk assessment engine for the Isolated Lending Market
/// @dev Computes multi-dimensional risk scores across oracle, liquidity, solvency, and strategy dimensions.
///      Never mutates protocol state. All public assessment functions are view.
///      Uses AccessControl for role-based permissions (RISK_MANAGER_ROLE).
contract RiskEngine is ProtocolAccessControl {
    // ==================== STATE VARIABLES ====================

    /// @notice Legacy owner variable (deprecated, use AccessControl roles)
    address public owner;
    MarketV1 public immutable market;
    Vault public immutable vault;
    OracleRouter public immutable oracleRouter;
    InterestRateModel public immutable interestRateModel;

    DataTypes.RiskEngineConfig public config;

    // ==================== CONSTANTS ====================

    uint256 private constant PRECISION = 1e18;
    uint8 private constant MAX_SCORE = 100;

    // ==================== REASON CODE BIT POSITIONS ====================

    uint256 private constant REASON_ORACLE_STALE = 1 << 0;
    uint256 private constant REASON_ORACLE_DEVIATION = 1 << 1;
    uint256 private constant REASON_ORACLE_LKG_FALLBACK = 1 << 2;
    uint256 private constant REASON_ORACLE_NO_TWAP = 1 << 3;
    uint256 private constant REASON_ORACLE_FAILURE = 1 << 4;
    uint256 private constant REASON_UTIL_HIGH = 1 << 5;
    uint256 private constant REASON_UTIL_CRITICAL = 1 << 6;
    uint256 private constant REASON_LIQUIDITY_LOW = 1 << 7;
    uint256 private constant REASON_HF_LOW = 1 << 8;
    uint256 private constant REASON_HF_CRITICAL = 1 << 9;
    uint256 private constant REASON_BAD_DEBT_HIGH = 1 << 10;
    uint256 private constant REASON_STRATEGY_OVERALLOC = 1 << 11;
    uint256 private constant REASON_STRATEGY_CHANGING = 1 << 12;
    uint256 private constant REASON_BORROWING_PAUSED = 1 << 13;
    uint256 private constant REASON_LKG_DECAYED = 1 << 14;

    // ==================== CONSTRUCTOR ====================

    /// @param _market The MarketV1 proxy address
    /// @param _vault The Vault address
    /// @param _oracleRouter The OracleRouter address
    /// @param _interestRateModel The InterestRateModel address
    /// @param _owner The owner for configuration management
    /// @param _config Initial risk engine configuration
    constructor(
        address _market,
        address _vault,
        address _oracleRouter,
        address _interestRateModel,
        address _owner,
        DataTypes.RiskEngineConfig memory _config
    ) {
        if (_market == address(0)) revert Errors.ZeroAddress();
        if (_vault == address(0)) revert Errors.ZeroAddress();
        if (_oracleRouter == address(0)) revert Errors.ZeroAddress();
        if (_interestRateModel == address(0)) revert Errors.ZeroAddress();
        if (_owner == address(0)) revert Errors.ZeroAddress();

        market = MarketV1(_market);
        vault = Vault(_vault);
        oracleRouter = OracleRouter(_oracleRouter);
        interestRateModel = InterestRateModel(_interestRateModel);
        owner = _owner;

        // Initialize AccessControl
        _initializeAccessControl(_owner);
        _grantRole(ProtocolRoles.RISK_MANAGER_ROLE, _owner);

        _validateConfig(_config);
        config = _config;
    }

    // Note: Role-based modifiers inherited from ProtocolAccessControl

    // ==================== CORE ASSESSMENT ====================

    /// @notice Compute full risk assessment for the protocol
    /// @return assessment The complete risk assessment with scores and severity
    function assessRisk() external view returns (DataTypes.RiskAssessment memory assessment) {
        DataTypes.DimensionScore memory scores;
        uint256 reasons;

        // 1. Oracle Risk — evaluate loan asset oracle as baseline
        (scores.oracleRisk, reasons) = _computeOracleRiskScore(reasons);

        // 2. Liquidity Risk
        (scores.liquidityRisk, reasons) = _computeLiquidityRiskScore(reasons);

        // 3. Solvency Risk
        (scores.solvencyRisk, reasons) = _computeSolvencyRiskScore(reasons);

        // 4. Strategy Risk
        (scores.strategyRisk, reasons) = _computeStrategyRiskScore(reasons);

        uint8 severity = _computeSeverityFromScores(scores);

        assessment = DataTypes.RiskAssessment({
            scores: scores,
            severity: severity,
            timestamp: uint64(block.timestamp),
            reasonCodes: bytes32(reasons)
        });
    }

    /// @notice Compute risk assessment focused on a specific asset's oracle
    /// @param asset The asset to evaluate
    /// @return assessment The risk assessment
    function assessAssetRisk(address asset) external view returns (DataTypes.RiskAssessment memory assessment) {
        DataTypes.DimensionScore memory scores;
        uint256 reasons;

        // Oracle risk for the specific asset
        DataTypes.OracleEvaluation memory eval = oracleRouter.evaluate(asset);
        scores.oracleRisk = eval.oracleRiskScore;

        if (eval.isStale) reasons |= REASON_ORACLE_STALE;
        if (eval.sourceUsed == 2) reasons |= REASON_ORACLE_LKG_FALLBACK;
        if (eval.deviation > config.oracleDeviationTolerance) reasons |= REASON_ORACLE_DEVIATION;
        if (eval.confidence == 0) {
            reasons |= REASON_ORACLE_FAILURE;
            scores.oracleRisk = MAX_SCORE;
        }

        // Protocol-wide dimensions
        (scores.liquidityRisk, reasons) = _computeLiquidityRiskScore(reasons);
        (scores.solvencyRisk, reasons) = _computeSolvencyRiskScore(reasons);
        (scores.strategyRisk, reasons) = _computeStrategyRiskScore(reasons);

        uint8 severity = _computeSeverityFromScores(scores);

        assessment = DataTypes.RiskAssessment({
            scores: scores,
            severity: severity,
            timestamp: uint64(block.timestamp),
            reasonCodes: bytes32(reasons)
        });
    }

    /// @notice Compute risk assessment for a specific user position
    /// @param user The user whose position to evaluate
    /// @return assessment The risk assessment for the user
    function assessUserRisk(address user) external view returns (DataTypes.RiskAssessment memory assessment) {
        DataTypes.DimensionScore memory scores;
        uint256 reasons;

        DataTypes.UserPosition memory pos = market.getUserPosition(user);

        // If no position, return zero-risk
        if (pos.totalDebt == 0 && pos.collateralValue == 0) {
            return DataTypes.RiskAssessment({
                scores: scores,
                severity: 0,
                timestamp: uint64(block.timestamp),
                reasonCodes: bytes32(0)
            });
        }

        // Oracle risk from loan asset
        (scores.oracleRisk, reasons) = _computeOracleRiskScore(reasons);

        // Liquidity risk (protocol-wide)
        (scores.liquidityRisk, reasons) = _computeLiquidityRiskScore(reasons);

        // Solvency risk: user-specific health factor
        if (pos.totalDebt > 0) {
            DataTypes.RiskEngineConfig memory cfg = config;
            if (pos.healthFactor < cfg.healthFactorCritical) {
                scores.solvencyRisk = 90;
                reasons |= REASON_HF_CRITICAL;
            } else if (pos.healthFactor < cfg.healthFactorWarning) {
                uint256 range = cfg.healthFactorWarning - cfg.healthFactorCritical;
                uint256 distance = pos.healthFactor - cfg.healthFactorCritical;
                scores.solvencyRisk = uint8(90 - (60 * distance / range));
                reasons |= REASON_HF_LOW;
            } else {
                // Healthy — low score proportional to how close to warning
                uint256 score256 = (30 * cfg.healthFactorWarning) / pos.healthFactor;
                scores.solvencyRisk = uint8(score256 > 30 ? 30 : score256);
            }
        }

        // Strategy risk (protocol-wide)
        (scores.strategyRisk, reasons) = _computeStrategyRiskScore(reasons);

        uint8 severity = _computeSeverityFromScores(scores);

        assessment = DataTypes.RiskAssessment({
            scores: scores,
            severity: severity,
            timestamp: uint64(block.timestamp),
            reasonCodes: bytes32(reasons)
        });
    }

    // ==================== INDIVIDUAL DIMENSION ACCESSORS ====================

    /// @notice Compute oracle risk score for the loan asset
    /// @param asset The asset to evaluate
    /// @return score 0-100 risk score
    /// @return evaluation Detailed oracle evaluation data
    function computeOracleRisk(address asset)
        external
        view
        returns (uint8 score, DataTypes.OracleEvaluation memory evaluation)
    {
        evaluation = oracleRouter.evaluate(asset);
        score = evaluation.oracleRiskScore;
        if (evaluation.confidence == 0) score = MAX_SCORE;
    }

    /// @notice Compute liquidity risk score
    /// @return score 0-100 risk score
    function computeLiquidityRisk() external view returns (uint8 score) {
        uint256 reasons;
        (score, reasons) = _computeLiquidityRiskScore(0);
    }

    /// @notice Compute solvency risk score
    /// @return score 0-100 risk score
    function computeSolvencyRisk() external view returns (uint8 score) {
        uint256 reasons;
        (score, reasons) = _computeSolvencyRiskScore(0);
    }

    /// @notice Compute strategy risk score
    /// @return score 0-100 risk score
    function computeStrategyRisk() external view returns (uint8 score) {
        uint256 reasons;
        (score, reasons) = _computeStrategyRiskScore(0);
    }

    // ==================== ORACLE EVALUATION ====================

    /// @notice Evaluate an asset's oracle using the hierarchical logic
    /// @param asset The asset to evaluate
    /// @return evaluation Full oracle evaluation result
    function evaluateOracle(address asset) external view returns (DataTypes.OracleEvaluation memory evaluation) {
        return oracleRouter.evaluate(asset);
    }

    // ==================== SEVERITY ====================

    /// @notice Convert dimension scores to severity level
    /// @param scores The four dimension scores
    /// @return severity 0-3 severity level
    function computeSeverity(DataTypes.DimensionScore memory scores) external pure returns (uint8 severity) {
        return _computeSeverityFromScores(scores);
    }

    // ==================== CONFIGURATION ====================

    /// @notice Get current risk engine configuration
    /// @return The active configuration
    function getConfig() external view returns (DataTypes.RiskEngineConfig memory) {
        return config;
    }

    /// @notice Update risk engine configuration (RISK_MANAGER_ROLE only)
    /// @param _config New configuration
    function setConfig(DataTypes.RiskEngineConfig calldata _config) external onlyRiskManager {
        _validateConfig(_config);
        config = _config;
        emit Events.RiskEngineConfigUpdated(msg.sender);
    }

    /// @notice Transfer ownership (grants all admin roles to new owner)
    /// @param newOwner The new owner address
    function transferOwnership(address newOwner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newOwner == address(0)) revert Errors.ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, newOwner);
        _grantRole(ProtocolRoles.RISK_MANAGER_ROLE, newOwner);

        owner = newOwner;
    }

    // ==================== INTERNAL: DIMENSION SCORING ====================

    /// @notice Compute oracle risk score for the loan asset
    function _computeOracleRiskScore(uint256 reasons) internal view returns (uint8 score, uint256 updatedReasons) {
        updatedReasons = reasons;

        address loanAsset = address(market.loanAsset());
        DataTypes.OracleEvaluation memory eval = oracleRouter.evaluate(loanAsset);

        score = eval.oracleRiskScore;

        if (eval.isStale) updatedReasons |= REASON_ORACLE_STALE;
        if (eval.sourceUsed == 2) updatedReasons |= REASON_ORACLE_LKG_FALLBACK;
        if (eval.deviation > config.oracleDeviationTolerance) updatedReasons |= REASON_ORACLE_DEVIATION;
        if (eval.confidence == 0) {
            updatedReasons |= REASON_ORACLE_FAILURE;
            score = MAX_SCORE;
        }
    }

    /// @notice Compute liquidity risk score from utilization and available liquidity
    function _computeLiquidityRiskScore(uint256 reasons) internal view returns (uint8 score, uint256 updatedReasons) {
        updatedReasons = reasons;
        DataTypes.RiskEngineConfig memory cfg = config;

        uint256 utilization = interestRateModel.getUtilizationRate();
        uint256 totalAssets = vault.totalAssets();

        if (utilization >= cfg.utilizationCritical) {
            score = 70;
            updatedReasons |= REASON_UTIL_CRITICAL;
        } else if (utilization >= cfg.utilizationWarning) {
            uint256 range = cfg.utilizationCritical - cfg.utilizationWarning;
            uint256 excess = utilization - cfg.utilizationWarning;
            score = uint8(30 + (40 * excess / range));
            updatedReasons |= REASON_UTIL_HIGH;
        } else {
            if (cfg.utilizationWarning > 0) {
                score = uint8(30 * utilization / cfg.utilizationWarning);
            }
        }

        // Boost if available liquidity is zero
        if (totalAssets > 0) {
            uint256 available = vault.availableLiquidity();
            if (available == 0) {
                score = score > 80 ? MAX_SCORE : score + 20;
                updatedReasons |= REASON_LIQUIDITY_LOW;
            }
        }
    }

    /// @notice Compute solvency risk score from bad debt and pause state
    function _computeSolvencyRiskScore(uint256 reasons) internal view returns (uint8 score, uint256 updatedReasons) {
        updatedReasons = reasons;
        DataTypes.RiskEngineConfig memory cfg = config;

        uint256 totalBorrows = market.totalBorrows();

        if (totalBorrows == 0) {
            return (0, updatedReasons);
        }

        // Check bad debt ratio
        address badDebtAddr = market.badDebtAddress();
        uint256 badDebtAccumulated = market.userTotalDebt(badDebtAddr);

        if (badDebtAccumulated > 0) {
            uint256 badDebtRatio = (badDebtAccumulated * PRECISION) / totalBorrows;
            if (badDebtRatio >= cfg.badDebtThreshold) {
                uint256 excess = badDebtRatio - cfg.badDebtThreshold;
                uint256 scaling = (excess * 40) / cfg.badDebtThreshold;
                score = uint8(40 + (scaling > 40 ? 40 : scaling));
                updatedReasons |= REASON_BAD_DEBT_HIGH;
            }
        }

        // Borrowing paused indicates emergency condition
        if (market.paused()) {
            if (score < 30) score = 30;
            updatedReasons |= REASON_BORROWING_PAUSED;
        }
    }

    /// @notice Compute strategy risk score from allocation and migration state
    function _computeStrategyRiskScore(uint256 reasons) internal view returns (uint8 score, uint256 updatedReasons) {
        updatedReasons = reasons;
        DataTypes.RiskEngineConfig memory cfg = config;

        // Strategy mid-migration is very high risk
        if (vault.isStrategyChanging()) {
            score = 80;
            updatedReasons |= REASON_STRATEGY_CHANGING;
            return (score, updatedReasons);
        }

        uint256 totalAssets = vault.totalAssets();
        if (totalAssets == 0) return (0, updatedReasons);

        uint256 strategyAssets = vault.totalStrategyAssets();
        uint256 allocationRatio = (strategyAssets * PRECISION) / totalAssets;

        if (allocationRatio > cfg.strategyAllocationCap) {
            uint256 excess = allocationRatio - cfg.strategyAllocationCap;
            uint256 maxExcess = PRECISION - cfg.strategyAllocationCap;
            score = uint8(30 + (maxExcess > 0 ? (70 * excess / maxExcess) : 70));
            updatedReasons |= REASON_STRATEGY_OVERALLOC;
        } else {
            // Low risk proportional to allocation
            score = uint8((allocationRatio * 20) / PRECISION);
        }
    }

    // ==================== INTERNAL: SEVERITY ====================

    /// @notice Compute severity as max score across all dimensions
    function _computeSeverityFromScores(DataTypes.DimensionScore memory scores)
        internal
        pure
        returns (uint8)
    {
        uint8 maxScore = scores.oracleRisk;
        if (scores.liquidityRisk > maxScore) maxScore = scores.liquidityRisk;
        if (scores.solvencyRisk > maxScore) maxScore = scores.solvencyRisk;
        if (scores.strategyRisk > maxScore) maxScore = scores.strategyRisk;

        if (maxScore >= 75) return 3; // Emergency
        if (maxScore >= 50) return 2; // Critical
        if (maxScore >= 25) return 1; // Elevated
        return 0; // Normal
    }

    // ==================== INTERNAL: VALIDATION ====================

    /// @notice Validate risk engine configuration
    function _validateConfig(DataTypes.RiskEngineConfig memory _config) internal pure {
        if (_config.oracleFreshnessThreshold == 0) revert Errors.InvalidRiskThreshold();
        if (_config.oracleDeviationTolerance == 0) revert Errors.InvalidRiskThreshold();
        if (_config.oracleCriticalDeviation <= _config.oracleDeviationTolerance) revert Errors.InvalidRiskThreshold();
        if (_config.lkgDecayHalfLife == 0) revert Errors.InvalidHalfLife();
        if (_config.lkgMaxAge == 0) revert Errors.InvalidMaxAge();
        if (_config.utilizationWarning == 0) revert Errors.InvalidRiskThreshold();
        if (_config.utilizationCritical <= _config.utilizationWarning) revert Errors.InvalidRiskThreshold();
        if (_config.healthFactorWarning == 0) revert Errors.InvalidRiskThreshold();
        if (_config.healthFactorCritical == 0) revert Errors.InvalidRiskThreshold();
        if (_config.healthFactorCritical >= _config.healthFactorWarning) revert Errors.InvalidRiskThreshold();
        if (_config.badDebtThreshold == 0) revert Errors.InvalidRiskThreshold();
        if (_config.strategyAllocationCap == 0 || _config.strategyAllocationCap > PRECISION) {
            revert Errors.InvalidRiskThreshold();
        }
    }
}
