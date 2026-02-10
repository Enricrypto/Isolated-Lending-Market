// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/governance/TimelockController.sol";
import "../core/RiskEngine.sol";
import "../core/MarketV1.sol";
import "../libraries/DataTypes.sol";
import "../libraries/Errors.sol";

/**
 * @title RiskProposer
 * @notice Automatically creates TimelockController proposals based on Risk Engine severity
 * @dev Bridges the Risk Engine monitoring to governance action by creating proposals
 *      when severity thresholds are crossed.
 *
 * FLOW
 * ====
 * 1. Anyone can call `checkAndPropose()` to check Risk Engine severity
 * 2. If severity >= threshold, a proposal is created on the Timelock
 * 3. Multisig reviews and executes the proposal after delay
 * 4. Cooldown prevents duplicate proposals within a configurable window
 *
 * IMPORTANT
 * =========
 * - This contract only CREATES proposals, it does NOT execute them
 * - Execution requires multisig approval (human-in-the-loop)
 * - Only creates "pause borrowing" proposals for severity >= 2
 */
contract RiskProposer {
    // ==================== STATE ====================

    /// @notice Contract owner for configuration
    address public owner;

    /// @notice Risk Engine to monitor
    RiskEngine public immutable riskEngine;

    /// @notice Timelock to submit proposals to
    TimelockController public immutable timelock;

    /// @notice Market contract for pause proposals
    MarketV1 public immutable market;

    /// @notice Minimum severity level to trigger a proposal (0-3)
    uint8 public severityThreshold;

    /// @notice Cooldown period between proposals (prevents spam)
    uint256 public cooldownPeriod;

    /// @notice Timestamp of last proposal creation
    uint256 public lastProposalTime;

    /// @notice Active proposal ID (0 if none)
    bytes32 public activeProposalId;

    /// @notice Mapping of proposal ID to creation timestamp
    mapping(bytes32 => uint256) public proposalTimestamps;

    // ==================== EVENTS ====================

    event ProposalCreated(
        bytes32 indexed proposalId, uint8 severity, string description, uint256 timestamp
    );
    event SeverityThresholdUpdated(uint8 oldThreshold, uint8 newThreshold);
    event CooldownPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ==================== ERRORS ====================

    error OnlyOwner();
    error CooldownNotElapsed();
    error SeverityBelowThreshold();
    error InvalidThreshold();
    error ProposalAlreadyActive();
    error ZeroAddress();

    // ==================== CONSTRUCTOR ====================

    /**
     * @notice Initialize the RiskProposer
     * @param _riskEngine Risk Engine contract address
     * @param _timelock TimelockController address
     * @param _market Market contract address
     * @param _severityThreshold Minimum severity to trigger proposal (default 2)
     * @param _cooldownPeriod Cooldown between proposals in seconds (default 1 hour)
     */
    constructor(
        address _riskEngine,
        address payable _timelock,
        address _market,
        uint8 _severityThreshold,
        uint256 _cooldownPeriod
    ) {
        if (_riskEngine == address(0)) revert ZeroAddress();
        if (_timelock == address(0)) revert ZeroAddress();
        if (_market == address(0)) revert ZeroAddress();
        if (_severityThreshold > 3) revert InvalidThreshold();

        riskEngine = RiskEngine(_riskEngine);
        timelock = TimelockController(_timelock);
        market = MarketV1(_market);
        owner = msg.sender;
        severityThreshold = _severityThreshold;
        cooldownPeriod = _cooldownPeriod;
    }

    // ==================== MODIFIERS ====================

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    // ==================== CORE FUNCTIONS ====================

    /**
     * @notice Check Risk Engine and create a proposal if severity >= threshold
     * @return proposalId The created proposal ID, or bytes32(0) if no proposal was created
     * @dev Anyone can call this function (permissionless monitoring)
     */
    function checkAndPropose() external returns (bytes32 proposalId) {
        // Check cooldown
        if (block.timestamp < lastProposalTime + cooldownPeriod) {
            revert CooldownNotElapsed();
        }

        // Get current risk assessment
        DataTypes.RiskAssessment memory assessment = riskEngine.assessRisk();

        // Check if severity meets threshold
        if (assessment.severity < severityThreshold) {
            revert SeverityBelowThreshold();
        }

        // Check if there's already an active pending proposal
        if (activeProposalId != bytes32(0)) {
            // Check if the previous proposal is still pending
            if (!_isProposalExecutedOrCancelled(activeProposalId)) {
                revert ProposalAlreadyActive();
            }
        }

        // Create the pause proposal
        proposalId = _createPauseProposal(assessment);

        // Update state
        lastProposalTime = block.timestamp;
        activeProposalId = proposalId;
        proposalTimestamps[proposalId] = block.timestamp;

        emit ProposalCreated(
            proposalId,
            assessment.severity,
            _getSeverityDescription(assessment.severity),
            block.timestamp
        );
    }

    /**
     * @notice Get the current risk assessment without creating a proposal
     * @return assessment The current risk assessment
     */
    function getCurrentRisk() external view returns (DataTypes.RiskAssessment memory assessment) {
        return riskEngine.assessRisk();
    }

    /**
     * @notice Check if conditions are met for creating a proposal
     * @return canPropose True if a proposal can be created
     * @return reason Description of why (or why not)
     */
    function canCreateProposal() external view returns (bool canPropose, string memory reason) {
        // Check cooldown
        if (block.timestamp < lastProposalTime + cooldownPeriod) {
            return (false, "Cooldown not elapsed");
        }

        // Check severity
        DataTypes.RiskAssessment memory assessment = riskEngine.assessRisk();
        if (assessment.severity < severityThreshold) {
            return (false, "Severity below threshold");
        }

        // Check active proposal
        if (activeProposalId != bytes32(0) && !_isProposalExecutedOrCancelled(activeProposalId)) {
            return (false, "Active proposal exists");
        }

        return (true, "Ready to propose");
    }

    /**
     * @notice Get active proposal status
     * @return id Proposal ID
     * @return timestamp Creation timestamp
     * @return state Proposal state (0=Pending, 1=Ready, 2=Done)
     */
    function getActiveProposal()
        external
        view
        returns (bytes32 id, uint256 timestamp, uint8 state)
    {
        id = activeProposalId;
        timestamp = proposalTimestamps[id];

        if (id == bytes32(0)) {
            state = 0; // No proposal
        } else if (timelock.isOperationDone(id)) {
            state = 2; // Executed
        } else if (timelock.isOperationReady(id)) {
            state = 1; // Ready to execute
        } else {
            state = 0; // Pending
        }
    }

    // ==================== ADMIN FUNCTIONS ====================

    /**
     * @notice Update severity threshold
     * @param newThreshold New threshold (0-3)
     */
    function setSeverityThreshold(uint8 newThreshold) external onlyOwner {
        if (newThreshold > 3) revert InvalidThreshold();

        uint8 oldThreshold = severityThreshold;
        severityThreshold = newThreshold;

        emit SeverityThresholdUpdated(oldThreshold, newThreshold);
    }

    /**
     * @notice Update cooldown period
     * @param newPeriod New cooldown in seconds
     */
    function setCooldownPeriod(uint256 newPeriod) external onlyOwner {
        uint256 oldPeriod = cooldownPeriod;
        cooldownPeriod = newPeriod;

        emit CooldownPeriodUpdated(oldPeriod, newPeriod);
    }

    /**
     * @notice Clear active proposal ID (for cleanup after execution)
     * @dev Only callable by owner, useful if proposal was cancelled externally
     */
    function clearActiveProposal() external onlyOwner {
        activeProposalId = bytes32(0);
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

    // ==================== INTERNAL FUNCTIONS ====================

    /**
     * @notice Create a pause proposal on the Timelock
     * @param assessment Current risk assessment
     * @return proposalId The proposal ID
     */
    function _createPauseProposal(DataTypes.RiskAssessment memory assessment)
        internal
        returns (bytes32 proposalId)
    {
        // Prepare the call data to pause borrowing
        bytes memory callData = abi.encodeWithSelector(MarketV1.setBorrowingPaused.selector, true);

        // Create arrays for batch operation (single operation)
        address[] memory targets = new address[](1);
        targets[0] = address(market);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = callData;

        // Generate a unique salt using timestamp and severity
        bytes32 salt = keccak256(
            abi.encodePacked(
                "RiskProposer", block.timestamp, assessment.severity, assessment.reasonCodes
            )
        );

        // Get the minimum delay from timelock
        uint256 delay = timelock.getMinDelay();

        // Schedule the operation
        // Note: This will revert if the proposer doesn't have PROPOSER_ROLE
        timelock.scheduleBatch(
            targets,
            values,
            payloads,
            bytes32(0), // predecessor (none)
            salt,
            delay
        );

        // Calculate the proposal ID (same formula as TimelockController)
        proposalId = timelock.hashOperationBatch(targets, values, payloads, bytes32(0), salt);
    }

    /**
     * @notice Check if a proposal has been executed or cancelled
     * @param proposalId Proposal ID to check
     * @return True if executed or cancelled (not pending)
     */
    function _isProposalExecutedOrCancelled(bytes32 proposalId) internal view returns (bool) {
        // If operation is done, it was executed
        if (timelock.isOperationDone(proposalId)) {
            return true;
        }

        // If operation doesn't exist (cancelled or never created), consider it done
        if (!timelock.isOperationPending(proposalId) && !timelock.isOperationReady(proposalId)) {
            return true;
        }

        return false;
    }

    /**
     * @notice Get human-readable description for severity level
     * @param severity Severity level (0-3)
     * @return description Description string
     */
    function _getSeverityDescription(uint8 severity) internal pure returns (string memory) {
        if (severity == 0) return "Normal - No action needed";
        if (severity == 1) return "Elevated - Monitor closely";
        if (severity == 2) return "Critical - Emergency pause recommended";
        if (severity == 3) return "Emergency - Immediate pause required";
        return "Unknown severity";
    }
}
