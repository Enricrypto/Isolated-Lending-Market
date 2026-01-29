// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title ProtocolRoles
 * @notice Library defining all protocol role constants
 * @dev Shared across all contracts for consistent role management
 *
 * ROLE HIERARCHY
 * ==============
 *
 * DEFAULT_ADMIN_ROLE (0x00)
 * └── Can grant/revoke all roles
 * └── Should be held by Timelock only
 *
 * GUARDIAN_ROLE
 * └── Emergency pause only (cannot unpause)
 * └── Held by EmergencyGuardian contract or security team multisig
 *
 * MARKET_ADMIN_ROLE
 * └── Market parameter management
 * └── setMarketParameters, addCollateralToken, pauseCollateralDeposits
 *
 * ORACLE_MANAGER_ROLE
 * └── Oracle configuration
 * └── addPriceFeed, setTWAPOracle, setOracleParams
 *
 * RISK_MANAGER_ROLE
 * └── Risk engine configuration
 * └── setConfig on RiskEngine
 *
 * RATE_MANAGER_ROLE
 * └── Interest rate model configuration
 * └── setBaseRate, setOptimalUtilization, setSlope1, setSlope2
 *
 * STRATEGY_MANAGER_ROLE
 * └── Vault strategy management
 * └── changeStrategy
 *
 * UPGRADER_ROLE
 * └── Contract upgrade authorization (most sensitive)
 * └── _authorizeUpgrade
 * └── Should only be held by Timelock
 */
library ProtocolRoles {
    /// @notice Role for emergency pause operations (one-way, cannot unpause)
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    /// @notice Role for market administration (parameters, collateral management)
    bytes32 public constant MARKET_ADMIN_ROLE = keccak256("MARKET_ADMIN_ROLE");

    /// @notice Role for oracle management (price feeds, TWAP oracles)
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");

    /// @notice Role for risk engine configuration
    bytes32 public constant RISK_MANAGER_ROLE = keccak256("RISK_MANAGER_ROLE");

    /// @notice Role for interest rate model configuration
    bytes32 public constant RATE_MANAGER_ROLE = keccak256("RATE_MANAGER_ROLE");

    /// @notice Role for vault strategy management
    bytes32 public constant STRATEGY_MANAGER_ROLE = keccak256("STRATEGY_MANAGER_ROLE");

    /// @notice Role for contract upgrades (most sensitive, Timelock only)
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
}

/**
 * @title ProtocolAccessControl
 * @notice Base access control for non-upgradeable protocol contracts
 * @dev Inherits OpenZeppelin AccessControl and adds protocol-specific modifiers
 *
 * DEPLOYMENT SETUP
 * ================
 *
 * 1. Deploy contracts with deployer as initial admin
 * 2. Grant roles to Timelock:
 *    - DEFAULT_ADMIN_ROLE
 *    - Relevant manager roles for each contract
 * 3. Grant GUARDIAN_ROLE to EmergencyGuardian (for Market)
 * 4. Revoke deployer's DEFAULT_ADMIN_ROLE
 */
abstract contract ProtocolAccessControl is AccessControl {
    /**
     * @notice Initialize access control with an admin
     * @param admin Address to grant DEFAULT_ADMIN_ROLE
     * @dev The admin can then grant other roles as needed
     */
    function _initializeAccessControl(address admin) internal {
        if (admin == address(0)) revert("ProtocolAccessControl: zero admin");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /**
     * @notice Check if caller has guardian role
     */
    modifier onlyGuardian() {
        _checkRole(ProtocolRoles.GUARDIAN_ROLE);
        _;
    }

    /**
     * @notice Check if caller has market admin role
     */
    modifier onlyMarketAdmin() {
        _checkRole(ProtocolRoles.MARKET_ADMIN_ROLE);
        _;
    }

    /**
     * @notice Check if caller has oracle manager role
     */
    modifier onlyOracleManager() {
        _checkRole(ProtocolRoles.ORACLE_MANAGER_ROLE);
        _;
    }

    /**
     * @notice Check if caller has risk manager role
     */
    modifier onlyRiskManager() {
        _checkRole(ProtocolRoles.RISK_MANAGER_ROLE);
        _;
    }

    /**
     * @notice Check if caller has rate manager role
     */
    modifier onlyRateManager() {
        _checkRole(ProtocolRoles.RATE_MANAGER_ROLE);
        _;
    }

    /**
     * @notice Check if caller has strategy manager role
     */
    modifier onlyStrategyManager() {
        _checkRole(ProtocolRoles.STRATEGY_MANAGER_ROLE);
        _;
    }

    /**
     * @notice Check if caller has upgrader role
     */
    modifier onlyUpgrader() {
        _checkRole(ProtocolRoles.UPGRADER_ROLE);
        _;
    }

    /**
     * @notice Check if caller has market admin OR guardian role
     * @dev Used for pause operations where both roles can act
     */
    modifier onlyMarketAdminOrGuardian() {
        if (
            !hasRole(ProtocolRoles.MARKET_ADMIN_ROLE, msg.sender)
                && !hasRole(ProtocolRoles.GUARDIAN_ROLE, msg.sender)
        ) {
            revert("ProtocolAccessControl: missing role");
        }
        _;
    }
}
