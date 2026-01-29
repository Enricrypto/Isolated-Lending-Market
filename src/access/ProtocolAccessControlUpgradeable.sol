// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./ProtocolAccessControl.sol";

/**
 * @title ProtocolAccessControlUpgradeable
 * @notice Access control for upgradeable protocol contracts (e.g., MarketV1)
 * @dev Inherits OpenZeppelin AccessControlUpgradeable which uses ERC-7201 namespaced storage
 *
 * STORAGE SAFETY
 * ==============
 * OpenZeppelin v5 uses ERC-7201 (namespaced storage) for AccessControlUpgradeable.
 * This means role data is stored at computed slots (keccak256 of namespace),
 * NOT in sequential storage. This prevents conflicts with custom storage layouts
 * like MarketStorageV1.
 *
 * USAGE
 * =====
 * 1. Inherit this contract in your upgradeable contract
 * 2. Call __ProtocolAccessControl_init(admin) in your initializer
 * 3. Use role modifiers (onlyMarketAdmin, onlyGuardian, etc.) on functions
 */
abstract contract ProtocolAccessControlUpgradeable is AccessControlUpgradeable {
    /**
     * @notice Initialize access control with an admin
     * @param admin Address to grant DEFAULT_ADMIN_ROLE
     * @dev Must be called in the contract's initialize function
     */
    function __ProtocolAccessControl_init(address admin) internal onlyInitializing {
        __AccessControl_init();
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
