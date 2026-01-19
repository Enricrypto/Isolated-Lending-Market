// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./Vault.sol";
import "./Market.sol";
import "../libraries/Errors.sol";
import "../libraries/Events.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title InterestRateModel
 * @notice Implements a Jump Rate Model for dynamic interest rates
 * @dev Interest rate increases gradually until optimal utilization, then jumps steeply
 * @author Your Team
 *
 * Formula:
 * - If utilization < optimal: rate = baseRate + (utilization * slope1)
 * - If utilization >= optimal: rate = baseRate + (optimal * slope1) + ((utilization - optimal) * slope2)
 */
contract InterestRateModel {
    using Math for uint256;

    // ==================== STATE VARIABLES ====================

    /// @notice Base interest rate (minimum rate when utilization is 0)
    uint256 public baseRate;

    /// @notice Optimal utilization threshold (e.g., 80%)
    uint256 public optimalUtilization;

    /// @notice Slope of interest rate below optimal utilization
    uint256 public slope1;

    /// @notice Slope of interest rate above optimal utilization (steep)
    uint256 public slope2;

    /// @notice Contract owner
    address public immutable owner;

    /// @notice Reference to vault contract
    Vault public immutable vaultContract;

    /// @notice Reference to market contract
    Market public marketContract;

    // ==================== CONSTANTS ====================

    uint256 private constant PRECISION = 1e18;
    uint256 private constant MAX_RATE = 10e18; // 1000% APR maximum
    uint256 private constant MAX_BASE_RATE = 0.2e18; // 20% maximum base rate
    uint256 private constant MAX_SLOPE = 5e18; // 500% maximum slope

    // ==================== CONSTRUCTOR ====================

    /**
     * @notice Initialize the interest rate model
     * @param _baseRate Base interest rate (e.g., 0.02e18 for 2%)
     * @param _optimalUtilization Optimal utilization rate (e.g., 0.8e18 for 80%)
     * @param _slope1 Slope before optimal (e.g., 0.04e18 for 4%)
     * @param _slope2 Slope after optimal (e.g., 0.60e18 for 60%)
     * @param _vaultContract Address of vault contract
     * @param _marketContract Address of market contract (can be set later)
     */
    constructor(
        uint256 _baseRate,
        uint256 _optimalUtilization,
        uint256 _slope1,
        uint256 _slope2,
        address _vaultContract,
        address _marketContract
    ) {
        if (_vaultContract == address(0)) revert Errors.ZeroAddress();

        // Validate parameters
        _validateParameters(_baseRate, _optimalUtilization, _slope1, _slope2);

        baseRate = _baseRate;
        optimalUtilization = _optimalUtilization;
        slope1 = _slope1;
        slope2 = _slope2;
        vaultContract = Vault(_vaultContract);

        if (_marketContract != address(0)) {
            marketContract = Market(_marketContract);
        }

        owner = msg.sender;
    }

    // ==================== MODIFIERS ====================

    modifier onlyOwner() {
        if (msg.sender != owner) revert Errors.OnlyOwner();
        _;
    }

    // ==================== ADMIN FUNCTIONS ====================

    /**
     * @notice Set the market contract address
     * @param _market Address of market contract
     */
    function setMarketContract(address _market) external onlyOwner {
        if (address(marketContract) != address(0)) revert Errors.MarketAlreadySet();
        if (_market == address(0)) revert Errors.InvalidMarketAddress();

        Market newMarket = Market(_market);
        // Verify it's a valid market by checking it has the loanAsset
        try newMarket.loanAsset() returns (IERC20) {
            marketContract = newMarket;
            emit Events.MarketContractSet(_market);
        } catch {
            revert Errors.InvalidMarketAddress();
        }
    }

    /**
     * @notice Update base rate
     * @param _newBaseRate New base rate
     */
    function setBaseRate(uint256 _newBaseRate) external onlyOwner {
        if (_newBaseRate > MAX_BASE_RATE) revert Errors.InvalidBaseRate();

        uint256 oldRate = baseRate;
        baseRate = _newBaseRate;

        emit Events.BaseRateUpdated(oldRate, _newBaseRate);
    }

    /**
     * @notice Update optimal utilization
     * @param _newOptimalUtilization New optimal utilization
     */
    function setOptimalUtilization(uint256 _newOptimalUtilization) external onlyOwner {
        if (_newOptimalUtilization == 0 || _newOptimalUtilization > PRECISION) {
            revert Errors.InvalidOptimalUtilization();
        }

        uint256 oldUtilization = optimalUtilization;
        optimalUtilization = _newOptimalUtilization;

        emit Events.OptimalUtilizationUpdated(oldUtilization, _newOptimalUtilization);
    }

    /**
     * @notice Update slope1
     * @param _newSlope1 New slope1
     */
    function setSlope1(uint256 _newSlope1) external onlyOwner {
        if (_newSlope1 > MAX_SLOPE) revert Errors.InvalidSlope();

        // Verify new parameters don't create excessive rates
        uint256 maxRateAtOptimal = baseRate + Math.mulDiv(optimalUtilization, _newSlope1, PRECISION);
        if (maxRateAtOptimal > MAX_RATE) revert Errors.ParameterTooHigh();

        uint256 oldSlope = slope1;
        slope1 = _newSlope1;

        emit Events.Slope1Updated(oldSlope, _newSlope1);
    }

    /**
     * @notice Update slope2
     * @param _newSlope2 New slope2
     */
    function setSlope2(uint256 _newSlope2) external onlyOwner {
        if (_newSlope2 > MAX_SLOPE) revert Errors.InvalidSlope();

        uint256 oldSlope = slope2;
        slope2 = _newSlope2;

        emit Events.Slope2Updated(oldSlope, _newSlope2);
    }

    // ==================== VIEW FUNCTIONS ====================

    /**
     * @notice Get total borrows from market (principal + interest)
     * @return Total borrowed amount including accrued interest
     */
    function getTotalBorrows() public view returns (uint256) {
        if (address(marketContract) == address(0)) revert Errors.MarketNotSet();
        return marketContract.totalBorrows();
    }

    /**
     * @notice Get total assets (strategy assets + borrows)
     * @return Total assets backing the system
     * @dev Does not include accrued interest to avoid circular dependency
     */
    function getTotalAssets() public view returns (uint256) {
        uint256 strategyAssets = vaultContract.totalStrategyAssets();
        uint256 totalBorrows = getTotalBorrows();
        return strategyAssets + totalBorrows;
    }

    /**
     * @notice Calculate current utilization rate
     * @return Utilization rate as 18-decimal percentage (e.g., 0.75e18 = 75%)
     * @dev Utilization = totalBorrows / (strategyAssets + totalBorrows)
     */
    function getUtilizationRate() public view returns (uint256) {
        uint256 totalAssets = getTotalAssets();
        if (totalAssets == 0) return 0;

        uint256 totalBorrows = getTotalBorrows();
        return Math.mulDiv(totalBorrows, PRECISION, totalAssets);
    }

    /**
     * @notice Calculate dynamic borrow rate based on utilization
     * @return Annual borrow rate as 18-decimal percentage (e.g., 0.08e18 = 8% APR)
     * @dev Implements proper jump rate model:
     *      - Below optimal: baseRate + (utilization * slope1)
     *      - Above optimal: baseRate + (optimal * slope1) + ((utilization - optimal) * slope2)
     */
    function getDynamicBorrowRate() public view returns (uint256) {
        uint256 utilization = getUtilizationRate();

        if (utilization <= optimalUtilization) {
            // Below or at optimal: gradual increase
            return baseRate + Math.mulDiv(utilization, slope1, PRECISION);
        } else {
            // Above optimal: base + optimal portion + excess portion (FIXED FORMULA)
            uint256 optimalRate = baseRate + Math.mulDiv(optimalUtilization, slope1, PRECISION);
            uint256 excessUtilization = utilization - optimalUtilization;
            uint256 excessRate = Math.mulDiv(excessUtilization, slope2, PRECISION);

            return optimalRate + excessRate;
        }
    }

    /**
     * @notice Get the rate at optimal utilization (kink point)
     * @return Rate at optimal utilization
     */
    function getRateAtOptimal() external view returns (uint256) {
        return baseRate + Math.mulDiv(optimalUtilization, slope1, PRECISION);
    }

    /**
     * @notice Get the maximum possible rate (at 100% utilization)
     * @return Maximum rate
     */
    function getMaxRate() external view returns (uint256) {
        uint256 optimalRate = baseRate + Math.mulDiv(optimalUtilization, slope1, PRECISION);
        uint256 excessUtilization = PRECISION - optimalUtilization;
        uint256 excessRate = Math.mulDiv(excessUtilization, slope2, PRECISION);

        return optimalRate + excessRate;
    }

    /**
     * @notice Get all model parameters
     * @return _baseRate Current base rate
     * @return _optimalUtilization Current optimal utilization
     * @return _slope1 Current slope1
     * @return _slope2 Current slope2
     */
    function getParameters()
        external
        view
        returns (uint256 _baseRate, uint256 _optimalUtilization, uint256 _slope1, uint256 _slope2)
    {
        return (baseRate, optimalUtilization, slope1, slope2);
    }

    // ==================== INTERNAL FUNCTIONS ====================

    /**
     * @notice Validate interest rate model parameters
     * @param _baseRate Base rate to validate
     * @param _optimalUtilization Optimal utilization to validate
     * @param _slope1 Slope1 to validate
     * @param _slope2 Slope2 to validate
     */
    function _validateParameters(
        uint256 _baseRate,
        uint256 _optimalUtilization,
        uint256 _slope1,
        uint256 _slope2
    ) internal pure {
        // Validate base rate
        if (_baseRate > MAX_BASE_RATE) revert Errors.InvalidBaseRate();

        // Validate optimal utilization
        if (_optimalUtilization == 0 || _optimalUtilization > PRECISION) {
            revert Errors.InvalidOptimalUtilization();
        }

        // Validate slopes
        if (_slope1 > MAX_SLOPE) revert Errors.InvalidSlope();
        if (_slope2 > MAX_SLOPE) revert Errors.InvalidSlope();

        // Verify that rate at optimal utilization is reasonable
        uint256 rateAtOptimal = _baseRate + Math.mulDiv(_optimalUtilization, _slope1, PRECISION);
        if (rateAtOptimal > MAX_RATE) revert Errors.ParameterTooHigh();

        // Verify that maximum rate (at 100% utilization) is reasonable
        uint256 excessUtilization = PRECISION - _optimalUtilization;
        uint256 excessRate = Math.mulDiv(excessUtilization, _slope2, PRECISION);
        uint256 maxRate = rateAtOptimal + excessRate;

        if (maxRate > MAX_RATE) revert Errors.ParameterTooHigh();
    }
}
