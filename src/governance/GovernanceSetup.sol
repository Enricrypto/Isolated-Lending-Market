// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title GovernanceSetup
 * @notice Documentation and helper for governance setup
 * @dev This file documents the governance architecture and provides deployment helpers
 *
 * GOVERNANCE ARCHITECTURE
 * =======================
 *
 * The protocol uses a Timelock + Multisig governance model:
 *
 * 1. MarketV1 (Proxy)
 *    └── owner: TimelockController address
 *
 * 2. TimelockController
 *    └── PROPOSER_ROLE: Gnosis Safe multisig
 *    └── EXECUTOR_ROLE: Gnosis Safe multisig (or address(0) for anyone)
 *    └── CANCELLER_ROLE: Gnosis Safe multisig
 *    └── minDelay: 24-48 hours (configurable)
 *
 * 3. Gnosis Safe (Multisig)
 *    └── Signers: Protocol team members
 *    └── Threshold: e.g., 3/5 or 4/7
 *
 * UPGRADE FLOW
 * ============
 *
 * 1. Multisig creates proposal on Timelock to call `upgradeToAndCall()`
 * 2. Timelock enforces delay (e.g., 48 hours)
 * 3. After delay, Multisig (or anyone if executor is open) executes
 * 4. Upgrade completes
 *
 * PARAMETER CHANGE FLOW
 * =====================
 *
 * 1. Multisig creates proposal on Timelock to call `setMarketParameters()`
 * 2. Timelock enforces delay
 * 3. After delay, execution proceeds
 *
 * EMERGENCY OPERATIONS
 * ====================
 *
 * Emergency pause (setBorrowingPaused) can be:
 * - Option A: Direct on Multisig (no delay) - faster but less secure
 * - Option B: Through Timelock with shorter delay - more secure
 *
 * Recommendation: Use a separate "Guardian" role for emergency pause
 * that doesn't go through Timelock, but can only pause (not unpause or upgrade).
 *
 * SETUP CHECKLIST
 * ===============
 *
 * 1. Deploy TimelockController with:
 *    - minDelay: 172800 (48 hours recommended)
 *    - proposers: [multisig_address]
 *    - executors: [multisig_address] or [address(0)] for anyone
 *    - admin: address(0) (renounced after setup)
 *
 * 2. Deploy MarketV1 proxy with owner = deployer
 *
 * 3. Transfer MarketV1 ownership to TimelockController:
 *    market.transferOwnership(timelock_address)
 *
 * 4. (Optional) Setup Guardian for emergency pause:
 *    - Deploy Guardian contract that can only call setBorrowingPaused(true)
 *    - Give Guardian direct access or use AccessControl pattern
 */

/**
 * @title MarketTimelock
 * @notice TimelockController configured for Market governance
 * @dev Wrapper to make deployment easier with sensible defaults
 */
contract MarketTimelock is TimelockController {
    /**
     * @notice Deploy a timelock for Market governance
     * @param minDelay Minimum delay for operations (in seconds)
     * @param proposers Addresses that can propose (typically the multisig)
     * @param executors Addresses that can execute (address(0) means anyone after delay)
     * @dev Admin is set to address(0) so no one can modify roles after deployment
     */
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors
    ) TimelockController(minDelay, proposers, executors, address(0)) {}
}

/**
 * @title EmergencyGuardian
 * @notice Allows fast emergency pause without timelock delay
 * @dev Can only pause, not unpause or perform any other action
 *
 * IMPORTANT: This is a powerful role. The guardian should be:
 * - A multisig with lower threshold (e.g., 2/5 vs 3/5 for upgrades)
 * - Or a trusted security team member for immediate response
 *
 * The guardian CANNOT:
 * - Unpause the market
 * - Upgrade the contract
 * - Change parameters
 * - Access funds
 */
interface IMarketPausable {
    function setBorrowingPaused(bool _paused) external;
}

contract EmergencyGuardian {
    /// @notice The market contract that can be paused
    IMarketPausable public immutable market;

    /// @notice Addresses authorized to trigger emergency pause
    mapping(address => bool) public guardians;

    /// @notice Owner who can add/remove guardians
    address public owner;

    event GuardianAdded(address indexed guardian);
    event GuardianRemoved(address indexed guardian);
    event EmergencyPauseTriggered(address indexed guardian);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error OnlyOwner();
    error OnlyGuardian();
    error ZeroAddress();
    error AlreadyGuardian();
    error NotGuardian();

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    modifier onlyGuardian() {
        if (!guardians[msg.sender]) revert OnlyGuardian();
        _;
    }

    constructor(address _market, address _initialGuardian) {
        if (_market == address(0)) revert ZeroAddress();
        if (_initialGuardian == address(0)) revert ZeroAddress();

        market = IMarketPausable(_market);
        owner = msg.sender;
        guardians[_initialGuardian] = true;

        emit GuardianAdded(_initialGuardian);
    }

    /**
     * @notice Emergency pause the market
     * @dev Can only pause, never unpause. Only guardians can call.
     *      This is intentionally one-way to prevent abuse.
     *      Unpause must go through normal governance (Timelock).
     */
    function emergencyPause() external onlyGuardian {
        market.setBorrowingPaused(true);
        emit EmergencyPauseTriggered(msg.sender);
    }

    /**
     * @notice Add a new guardian
     * @param guardian Address to add as guardian
     */
    function addGuardian(address guardian) external onlyOwner {
        if (guardian == address(0)) revert ZeroAddress();
        if (guardians[guardian]) revert AlreadyGuardian();

        guardians[guardian] = true;
        emit GuardianAdded(guardian);
    }

    /**
     * @notice Remove a guardian
     * @param guardian Address to remove
     */
    function removeGuardian(address guardian) external onlyOwner {
        if (!guardians[guardian]) revert NotGuardian();

        guardians[guardian] = false;
        emit GuardianRemoved(guardian);
    }

    /**
     * @notice Transfer ownership
     * @param newOwner New owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();

        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}
