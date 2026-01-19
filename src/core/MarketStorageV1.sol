// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./Vault.sol";
import "./PriceOracle.sol";
import "./InterestRateModel.sol";
import "../libraries/DataTypes.sol";

/**
 * @title MarketStorageV1
 * @notice Storage layout for the Market contract - Version 1
 * @dev This contract defines the storage layout for upgradeable Market implementations.
 *
 * CRITICAL RULES FOR UPGRADEABILITY:
 * 1. NEVER remove or reorder existing variables
 * 2. NEVER change the type of existing variables
 * 3. Only ADD new variables at the end (before the gap)
 * 4. Decrement the gap size when adding new variables
 * 5. All future versions must inherit from this contract
 *
 * Storage Layout Philosophy:
 * - Immutable references (vault, oracle, etc.) become mutable for upgradeability
 * - Owner becomes mutable to support ownership transfer
 * - All mappings and state preserved in exact order
 */
abstract contract MarketStorageV1 {
    // ==================== SLOT 0-6: CORE REFERENCES ====================
    // These were immutable in the original contract.
    // For upgradeability, they become regular storage variables.
    // They are set once during initialization and protected by access control.

    /// @notice Contract owner with admin privileges
    /// @dev Slot 0
    address public owner;

    /// @notice Protocol treasury address for fee collection
    /// @dev Slot 1
    address public protocolTreasury;

    /// @notice Bad debt accumulator address
    /// @dev Slot 2
    address public badDebtAddress;

    /// @notice Vault contract for liquidity management (ERC-4626)
    /// @dev Slot 3
    Vault public vaultContract;

    /// @notice Price oracle for asset valuation (Chainlink-based)
    /// @dev Slot 4
    PriceOracle public priceOracle;

    /// @notice Interest rate model for borrow rate calculation
    /// @dev Slot 5
    InterestRateModel public interestRateModel;

    /// @notice Loan asset (e.g., USDC) - the asset users borrow
    /// @dev Slot 6
    IERC20 public loanAsset;

    // ==================== SLOT 7-9: MARKET PARAMETERS ====================

    /// @notice Market configuration parameters (LLTV, liquidation penalty, protocol fee)
    /// @dev Slots 7-9 (struct has 3 uint256 fields = 3 slots)
    DataTypes.MarketParameters public marketParams;

    // ==================== SLOT 10-12: BORROW STATE ====================

    /// @notice Total borrowed amount across all users (normalized to 18 decimals)
    /// @dev Slot 10
    uint256 public totalBorrows;

    /// @notice Global borrow index for interest calculation
    /// @dev Starts at 1e18 (PRECISION), increases over time as interest accrues
    /// @dev Slot 11
    uint256 public globalBorrowIndex;

    /// @notice Last timestamp when global borrow index was updated
    /// @dev Slot 12
    uint256 public lastAccrualTimestamp;

    // ==================== SLOT 13: FLAGS & GUARDIAN (PACKED) ====================

    /// @notice Emergency pause state - blocks borrowing when true
    /// @dev Slot 13, byte 0 (packed with guardian)
    bool public paused;

    /// @notice Guardian address that can pause borrowing (no timelock required)
    /// @dev Slot 13, bytes 1-20 (packed with paused) - Can only pause, not unpause or perform other actions
    address public guardian;

    // ==================== SLOT 14+: MAPPINGS ====================
    // Mappings don't occupy sequential slots - they use keccak256(key, slot) for storage
    // But we document their "slot numbers" for clarity in storage layout

    /// @notice Supported collateral tokens whitelist
    /// @dev Slot 14
    mapping(address => bool) public supportedCollateralTokens;

    /// @notice Paused deposits per collateral token
    /// @dev Slot 15
    mapping(address => bool) public depositsPaused;

    /// @notice User collateral balances: user => token => normalized amount (18 decimals)
    /// @dev Slot 16
    mapping(address => mapping(address => uint256)) public userCollateralBalances;

    /// @notice User's list of deposited collateral asset addresses
    /// @dev Slot 17
    mapping(address => address[]) public userCollateralAssets;

    /// @notice Token decimals cache for normalization
    /// @dev Slot 18
    mapping(address => uint8) public tokenDecimals;

    /// @notice User's principal debt (normalized to 18 decimals, excludes interest)
    /// @dev Slot 19
    mapping(address => uint256) public userTotalDebt;

    /// @notice User's last borrow index snapshot for interest calculation
    /// @dev Slot 20
    mapping(address => uint256) public lastUpdatedIndex;

    /// @notice Unrecovered debt per user (bad debt statistics)
    /// @dev Slot 21
    mapping(address => uint256) public unrecoveredDebt;

    // ==================== STORAGE GAP ====================
    // Reserve 50 slots for future storage variables in upgrades.
    // When adding new variables:
    // 1. Add them above this gap
    // 2. Reduce the gap size by the number of slots used
    // Example: Adding 2 new uint256 variables → change __gap to [48]

    /// @dev Reserved storage space for future upgrades
    /// @dev Slots 22-70 reserved (49 slots after mappings end at slot 21)
    uint256[49] private __gap;
}
