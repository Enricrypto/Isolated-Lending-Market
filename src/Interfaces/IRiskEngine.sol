// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../libraries/DataTypes.sol";

/// @title IRiskEngine
/// @notice Interface for the read-only Risk Engine
/// @dev Computes multi-dimensional risk scores and severity levels without mutating protocol state
interface IRiskEngine {
    // ==================== CORE ASSESSMENT ====================

    /// @notice Compute full risk assessment for the protocol
    /// @return assessment The complete risk assessment with scores and severity
    function assessRisk() external view returns (DataTypes.RiskAssessment memory assessment);

    /// @notice Compute risk assessment for a specific asset's oracle
    /// @param asset The asset to evaluate oracle risk for
    /// @return assessment The risk assessment focused on the given asset
    function assessAssetRisk(address asset) external view returns (DataTypes.RiskAssessment memory assessment);

    /// @notice Compute risk assessment for a specific user position
    /// @param user The user whose position to evaluate
    /// @return assessment The risk assessment for the user
    function assessUserRisk(address user) external view returns (DataTypes.RiskAssessment memory assessment);

    // ==================== INDIVIDUAL DIMENSIONS ====================

    /// @notice Compute oracle risk score for an asset
    /// @param asset The asset to evaluate
    /// @return score 0-100 risk score
    /// @return evaluation Detailed oracle evaluation data
    function computeOracleRisk(address asset)
        external
        view
        returns (uint8 score, DataTypes.OracleEvaluation memory evaluation);

    /// @notice Compute liquidity risk score
    /// @return score 0-100 risk score
    function computeLiquidityRisk() external view returns (uint8 score);

    /// @notice Compute solvency risk score
    /// @return score 0-100 risk score
    function computeSolvencyRisk() external view returns (uint8 score);

    /// @notice Compute strategy risk score
    /// @return score 0-100 risk score
    function computeStrategyRisk() external view returns (uint8 score);

    // ==================== ORACLE EVALUATION ====================

    /// @notice Evaluate an asset's oracle using the hierarchical logic
    /// @param asset The asset to evaluate
    /// @return evaluation Full oracle evaluation result
    function evaluateOracle(address asset) external view returns (DataTypes.OracleEvaluation memory evaluation);

    // ==================== CONFIGURATION ====================

    /// @notice Get current risk engine configuration
    /// @return config The active configuration
    function getConfig() external view returns (DataTypes.RiskEngineConfig memory config);

    /// @notice Update risk engine configuration (owner only)
    /// @param config New configuration
    function setConfig(DataTypes.RiskEngineConfig calldata config) external;

    // ==================== SEVERITY HELPERS ====================

    /// @notice Convert dimension scores to severity level
    /// @param scores The four dimension scores
    /// @return severity 0-3 severity level
    function computeSeverity(DataTypes.DimensionScore memory scores) external pure returns (uint8 severity);

    // ==================== STATE VARIABLES ====================

    function market() external view returns (address);
    function vault() external view returns (address);
    function oracleRouter() external view returns (address);
    function interestRateModel() external view returns (address);
    function owner() external view returns (address);
}
