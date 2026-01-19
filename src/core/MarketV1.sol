// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "./Vault.sol";
import "./PriceOracle.sol";
import "./InterestRateModel.sol";
import "./MarketStorageV1.sol";
import "../libraries/Errors.sol";
import "../libraries/Events.sol";
import "../libraries/DataTypes.sol";

/**
 * @title MarketV1
 * @notice Upgradeable core lending market contract supporting multi-collateral borrowing
 * @dev Implements UUPS proxy pattern for upgradeability
 * @author Your Team
 *
 * Key Features:
 * - UUPS upgradeable proxy pattern
 * - Multi-collateral support with individual pause controls
 * - Dynamic interest rates via InterestRateModel
 * - Health factor-based liquidations
 * - Bad debt tracking and management
 * - Decimal normalization for tokens with 6, 8, or 18 decimals
 * - Emergency pause functionality
 *
 * Architecture:
 * - Uses ERC-4626 vault for liquidity management
 * - Integrates with Chainlink for price oracles
 * - Tracks global borrow index for interest accrual
 * - Normalizes all internal accounting to 18 decimals
 *
 * Storage:
 * - Inherits from MarketStorageV1 for upgrade-safe storage layout
 * - All state variables are defined in MarketStorageV1
 *
 * Upgrade Safety:
 * - Only owner can authorize upgrades
 * - Storage layout preserved via MarketStorageV1 inheritance
 * - Future upgrades must maintain storage compatibility
 */
contract MarketV1 is
    Initializable,
    MarketStorageV1,
    ReentrancyGuard,
    UUPSUpgradeable
{
    using Math for uint256;

    // ==================== CONSTANTS ====================
    // Constants are not stored in contract storage, safe to define here

    uint256 private constant PRECISION = 1e18;
    uint256 private constant SECONDS_PER_YEAR = 365 days;
    uint8 private constant TARGET_DECIMALS = 18;

    // ==================== CONSTRUCTOR ====================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ==================== INITIALIZER ====================

    /**
     * @notice Initialize the Market contract (replaces constructor for proxy)
     * @param _badDebtAddress Address to accumulate bad debt
     * @param _protocolTreasury Address to receive protocol fees
     * @param _vaultContract Vault contract address
     * @param _priceOracle Price oracle address
     * @param _interestRateModel Interest rate model address
     * @param _loanAsset Loan asset address (e.g., USDC)
     * @param _owner Initial owner address
     * @dev Can only be called once due to initializer modifier
     */
    function initialize(
        address _badDebtAddress,
        address _protocolTreasury,
        address _vaultContract,
        address _priceOracle,
        address _interestRateModel,
        address _loanAsset,
        address _owner
    ) external initializer {
        // Validate inputs
        if (_badDebtAddress == address(0)) revert Errors.InvalidBadDebtAddress();
        if (_protocolTreasury == address(0)) revert Errors.InvalidTreasuryAddress();
        if (_vaultContract == address(0)) revert Errors.ZeroAddress();
        if (_priceOracle == address(0)) revert Errors.ZeroAddress();
        if (_interestRateModel == address(0)) revert Errors.ZeroAddress();
        if (_loanAsset == address(0)) revert Errors.InvalidTokenAddress();
        if (_owner == address(0)) revert Errors.ZeroAddress();

        // Note: In OZ v5, ReentrancyGuard uses transient storage and
        // UUPSUpgradeable doesn't require initialization

        // Initialize storage variables (inherited from MarketStorageV1)
        badDebtAddress = _badDebtAddress;
        protocolTreasury = _protocolTreasury;
        vaultContract = Vault(_vaultContract);
        priceOracle = PriceOracle(_priceOracle);
        interestRateModel = InterestRateModel(_interestRateModel);
        loanAsset = IERC20(_loanAsset);
        owner = _owner;

        // Initialize borrow index to PRECISION (1e18)
        globalBorrowIndex = PRECISION;

        // Approve vault to spend loan assets for repayments
        IERC20(_loanAsset).approve(_vaultContract, type(uint256).max);
    }

    // ==================== MODIFIERS ====================

    modifier onlyOwner() {
        if (msg.sender != owner) revert Errors.OnlyOwner();
        _;
    }

    modifier onlyOwnerOrGuardian() {
        if (msg.sender != owner && msg.sender != guardian) revert Errors.OnlyOwner();
        _;
    }

    /**
     * @notice Modifier to prevent borrowing when paused
     * @dev Only blocks leverage-increasing actions (borrow)
     *      Allows: deposits, withdrawals, repayments, liquidations
     *      This ensures users are NEVER trapped
     */
    modifier whenBorrowingNotPaused() {
        if (paused) revert Errors.BorrowingPaused();
        _;
    }

    modifier notSystemAddress() {
        if (msg.sender == badDebtAddress || msg.sender == protocolTreasury) {
            revert Errors.SystemAddressRestricted();
        }
        _;
    }

    // ==================== UUPS UPGRADE AUTHORIZATION ====================

    /**
     * @notice Authorize an upgrade to a new implementation
     * @param newImplementation Address of new implementation contract
     * @dev Only owner can authorize upgrades
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ==================== OWNERSHIP ====================

    /**
     * @notice Transfer ownership to a new address
     * @param newOwner Address of new owner
     * @dev Used to transfer ownership to Timelock in governance setup
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert Errors.ZeroAddress();
        address oldOwner = owner;
        owner = newOwner;
        emit Events.OwnershipTransferred(oldOwner, newOwner);
    }

    // ==================== ADMIN FUNCTIONS ====================

    /**
     * @notice Set market parameters
     * @param _lltv Liquidation Loan-to-Value ratio (e.g., 0.85e18 for 85%)
     * @param _liquidationPenalty Liquidation bonus (e.g., 0.05e18 for 5%)
     * @param _protocolFeeRate Protocol fee rate (e.g., 0.10e18 for 10%)
     */
    function setMarketParameters(
        uint256 _lltv,
        uint256 _liquidationPenalty,
        uint256 _protocolFeeRate
    ) external onlyOwner {
        if (_lltv == 0 || _lltv > PRECISION) {
            revert Errors.LiquidationLoanToValueTooHigh();
        }
        if (_liquidationPenalty > PRECISION) revert Errors.LiquidationPenaltyTooHigh();
        if (_protocolFeeRate > PRECISION) revert Errors.ParameterTooHigh();

        marketParams = DataTypes.MarketParameters({
            lltv: _lltv,
            liquidationPenalty: _liquidationPenalty,
            protocolFeeRate: _protocolFeeRate
        });

        emit Events.MarketParametersUpdated(_lltv, _liquidationPenalty, _protocolFeeRate);
    }

    /**
     * @notice Add a new supported collateral token
     * @param token Token address
     * @param priceFeed Chainlink price feed address
     */
    function addCollateralToken(address token, address priceFeed) external onlyOwner {
        if (token == address(0)) revert Errors.InvalidTokenAddress();
        if (priceFeed == address(0)) revert Errors.InvalidPriceFeedAddress();
        if (supportedCollateralTokens[token]) revert Errors.TokenAlreadyAdded();

        // Get token decimals
        uint8 decimals = IERC20Metadata(token).decimals();
        if (decimals > TARGET_DECIMALS) revert Errors.TokenDecimalsTooHigh();

        // Add price feed FIRST (reverts if invalid)
        priceOracle.addPriceFeed(token, priceFeed);

        // Then mark as supported
        tokenDecimals[token] = decimals;
        supportedCollateralTokens[token] = true;

        emit Events.CollateralTokenAdded(token, priceFeed, decimals);
    }

    /**
     * @notice Pause deposits for a specific collateral token
     * @param token Token address
     * @dev Existing collateral remains, new deposits blocked
     */
    function pauseCollateralDeposits(address token) external onlyOwner {
        if (!supportedCollateralTokens[token]) revert Errors.TokenNotSupported();
        if (depositsPaused[token]) revert Errors.DepositsPaused();

        depositsPaused[token] = true;
        emit Events.CollateralDepositsPaused(token);
    }

    /**
     * @notice Resume deposits for a paused collateral token
     * @param token Token address
     */
    function resumeCollateralDeposits(address token) external onlyOwner {
        if (!supportedCollateralTokens[token]) revert Errors.TokenNotSupported();
        if (!depositsPaused[token]) revert Errors.DepositsNotPaused();

        depositsPaused[token] = false;
        emit Events.CollateralDepositsResumed(token);
    }

    /**
     * @notice Remove a collateral token from supported list
     * @param token Token address
     * @dev Requires deposits to be paused and no remaining balance
     */
    function removeCollateralToken(address token) external onlyOwner {
        if (!supportedCollateralTokens[token]) revert Errors.TokenNotSupported();
        if (!depositsPaused[token]) revert Errors.DepositsPaused();
        if (IERC20(token).balanceOf(address(this)) != 0) revert Errors.CollateralStillInUse();

        supportedCollateralTokens[token] = false;
        delete tokenDecimals[token];

        emit Events.CollateralTokenRemoved(token);
    }

    /**
     * @notice Emergency pause/unpause borrowing
     * @param _paused True to pause borrowing, false to resume
     * @dev When paused:
     *      - Borrowing is blocked
     *      - Deposits, withdrawals, repayments, and liquidations are ALLOWED
     *      - Users can always exit their positions
     */
    function setBorrowingPaused(bool _paused) external onlyOwnerOrGuardian {
        paused = _paused;
        emit Events.BorrowingPausedChanged(_paused);
    }

    /**
     * @notice Set the guardian address
     * @param _guardian New guardian address (or address(0) to disable)
     * @dev Guardian can only pause, not unpause or perform other actions
     */
    function setGuardian(address _guardian) external onlyOwner {
        address oldGuardian = guardian;
        guardian = _guardian;
        emit Events.GuardianChanged(oldGuardian, _guardian);
    }

    // ==================== COLLATERAL MANAGEMENT ====================

    /**
     * @notice Deposit collateral to enable borrowing
     * @param token Collateral token address
     * @param amount Amount in token's native decimals
     */
    function depositCollateral(
        address token,
        uint256 amount
    ) external nonReentrant notSystemAddress {
        _updateGlobalBorrowIndex();

        if (!supportedCollateralTokens[token]) revert Errors.TokenNotSupported();
        if (depositsPaused[token]) revert Errors.DepositsPaused();
        if (amount == 0) revert Errors.InvalidAmount();

        // Transfer tokens from user
        bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
        if (!success) revert Errors.TransferFailed();

        // Normalize to 18 decimals for internal accounting
        uint256 normalizedAmount = _normalizeAmount(amount, tokenDecimals[token]);

        // Update balance
        uint256 previousBalance = userCollateralBalances[msg.sender][token];
        userCollateralBalances[msg.sender][token] += normalizedAmount;

        // Add to user's collateral list if first deposit of this token
        if (previousBalance == 0) {
            userCollateralAssets[msg.sender].push(token);
        }

        // Update borrow index snapshot if user has debt
        if (userTotalDebt[msg.sender] > 0) {
            lastUpdatedIndex[msg.sender] = globalBorrowIndex;
        }

        emit Events.CollateralDeposited(msg.sender, token, normalizedAmount);
    }

    /**
     * @notice Withdraw collateral from market
     * @param token Collateral token address
     * @param rawAmount Amount in token's native decimals
     */
    function withdrawCollateral(
        address token,
        uint256 rawAmount
    ) external nonReentrant notSystemAddress {
        _updateGlobalBorrowIndex();

        if (!supportedCollateralTokens[token]) revert Errors.TokenNotSupported();
        if (rawAmount == 0) revert Errors.InvalidAmount();

        // Normalize amount
        uint256 normalizedAmount = _normalizeAmount(rawAmount, tokenDecimals[token]);

        if (userCollateralBalances[msg.sender][token] < normalizedAmount) {
            revert Errors.InsufficientCollateral();
        }

        // Simulate withdrawal to check health
        userCollateralBalances[msg.sender][token] -= normalizedAmount;

        if (!_isHealthy(msg.sender)) {
            // Revert simulated withdrawal
            userCollateralBalances[msg.sender][token] += normalizedAmount;
            revert Errors.WithdrawalWouldMakePositionUnhealthy();
        }

        // Check protocol has enough tokens
        if (IERC20(token).balanceOf(address(this)) < rawAmount) {
            // Revert simulated withdrawal
            userCollateralBalances[msg.sender][token] += normalizedAmount;
            revert Errors.InsufficientProtocolLiquidity();
        }

        // Transfer tokens to user
        bool success = IERC20(token).transfer(msg.sender, rawAmount);
        if (!success) {
            // Revert simulated withdrawal
            userCollateralBalances[msg.sender][token] += normalizedAmount;
            revert Errors.TransferFailed();
        }

        // Clean up if balance is zero
        if (userCollateralBalances[msg.sender][token] == 0) {
            _removeCollateralAsset(msg.sender, token);
        }

        // Update borrow index snapshot if user has debt
        if (userTotalDebt[msg.sender] > 0) {
            lastUpdatedIndex[msg.sender] = globalBorrowIndex;
        }

        emit Events.CollateralWithdrawn(msg.sender, token, normalizedAmount);
    }

    // ==================== BORROWING OPERATIONS ====================

    /**
     * @notice Borrow loan assets against deposited collateral
     * @param amount Amount to borrow in loan asset's native decimals
     */
    function borrow(uint256 amount) external nonReentrant whenBorrowingNotPaused notSystemAddress {
        _updateGlobalBorrowIndex();

        if (amount == 0) revert Errors.InvalidAmount();

        // Get user's collateral value (excludes paused tokens)
        uint256 collateralValue = _getUserTotalCollateralValue(msg.sender);

        // Normalize borrow amount
        uint8 loanDecimals = _getLoanAssetDecimals();
        uint256 normalizedAmount = _normalizeAmount(amount, loanDecimals);

        // Calculate new total debt
        uint256 currentDebt = _getUserTotalDebt(msg.sender);
        uint256 newDebt = currentDebt + normalizedAmount;

        // Calculate borrowing power
        uint256 borrowingPower = Math.mulDiv(collateralValue, marketParams.lltv, PRECISION);

        if (borrowingPower < newDebt) revert Errors.InsufficientBorrowingPower();

        // Check vault has enough liquidity
        if (amount > vaultContract.availableLiquidity()) {
            revert Errors.InsufficientVaultLiquidity();
        }

        // Borrow from vault
        vaultContract.adminBorrow(amount);

        // Transfer to borrower
        bool success = loanAsset.transfer(msg.sender, amount);
        if (!success) revert Errors.TransferFailed();

        // Update state
        userTotalDebt[msg.sender] += normalizedAmount;
        totalBorrows += normalizedAmount;
        lastUpdatedIndex[msg.sender] = globalBorrowIndex;

        emit Events.Borrowed(msg.sender, amount, userTotalDebt[msg.sender]);
    }

    /**
     * @notice Repay borrowed loan assets
     * @param amount Amount to repay in loan asset's native decimals
     */
    function repay(uint256 amount) external nonReentrant notSystemAddress {
        _updateGlobalBorrowIndex();

        if (amount == 0) revert Errors.InvalidAmount();

        uint8 loanDecimals = _getLoanAssetDecimals();
        uint256 normalizedAmount = _normalizeAmount(amount, loanDecimals);

        // Get interest and total debt (both normalized)
        uint256 interest = _borrowerInterestAccrued(msg.sender);
        uint256 totalDebt = _getUserTotalDebt(msg.sender);

        // Must cover interest first
        if (normalizedAmount < interest) revert Errors.MustCoverInterest();

        // Cannot repay more than debt (allow tiny overpayment for rounding)
        uint256 maxOverpayment = 10 ** (TARGET_DECIMALS - loanDecimals);
        if (normalizedAmount > totalDebt + maxOverpayment) revert Errors.RepaymentExceedsDebt();

        // Calculate protocol fee on interest
        uint256 protocolFee = Math.mulDiv(interest, marketParams.protocolFeeRate, PRECISION);
        uint256 interestToVault = interest - protocolFee;

        // Calculate principal repayment (cap at actual debt)
        uint256 principal = normalizedAmount > interest ? normalizedAmount - interest : 0;
        if (principal > userTotalDebt[msg.sender]) {
            principal = userTotalDebt[msg.sender];
        }

        // Total going to vault = principal + interest (minus protocol fee)
        uint256 vaultRepayment = principal + interestToVault;

        // Transfer full amount from user
        bool transferSuccess = loanAsset.transferFrom(msg.sender, address(this), amount);
        if (!transferSuccess) revert Errors.TransferFailed();

        // Send protocol fee to treasury
        bool feeSuccess = loanAsset.transfer(
            protocolTreasury,
            _denormalizeAmount(protocolFee, loanDecimals)
        );
        if (!feeSuccess) revert Errors.TransferFailed();

        // Repay to vault
        vaultContract.adminRepay(_denormalizeAmount(vaultRepayment, loanDecimals));

        // Update state - reduce principal only
        if (principal > 0) {
            if (totalBorrows < principal) revert Errors.BorrowUnderflow();
            totalBorrows -= principal;
            userTotalDebt[msg.sender] -= principal;
        }

        lastUpdatedIndex[msg.sender] = globalBorrowIndex;

        emit Events.Repaid(msg.sender, amount, interest, principal);
    }

    // ==================== LIQUIDATION ====================

    /**
     * @notice Liquidate an unhealthy position
     * @param borrower Address of borrower to liquidate
     * @dev Liquidator must approve this contract to spend loan tokens
     */
    function liquidate(address borrower) external nonReentrant notSystemAddress {
        _updateGlobalBorrowIndex();

        // Calculate liquidation amounts
        (uint256 debtToCover, uint256 collateralToSeizeUsd, uint256 badDebt) =
            _calculateLiquidation(borrower);

        // Process liquidator's repayment
        _processLiquidatorRepayment(borrower, msg.sender, debtToCover);

        // Seize collateral
        uint256 totalSeized = _seizeCollateral(borrower, msg.sender, collateralToSeizeUsd);

        emit Events.Liquidated(borrower, msg.sender, debtToCover, totalSeized, badDebt);
    }

    // ==================== INTERNAL - LIQUIDATION HELPERS ====================

    /**
     * @notice Calculate liquidation amounts
     * @param borrower Address of borrower
     * @return debtToCover Debt to cover in USD (18 decimals)
     * @return collateralToSeize Collateral to seize in USD (18 decimals)
     * @return badDebt Bad debt amount in USD (18 decimals)
     */
    function _calculateLiquidation(
        address borrower
    ) internal returns (uint256 debtToCover, uint256 collateralToSeize, uint256 badDebt) {
        if (_isHealthy(borrower)) revert Errors.PositionIsHealthy();

        uint256 currentDebt = _getUserTotalDebt(borrower);
        uint256 debtInUSD = _getLoanDebtInUSD(currentDebt);
        uint256 collateralValue = _getUserTotalCollateralValue(borrower);

        // Full liquidation - cover all debt
        debtToCover = debtInUSD;

        // Calculate collateral to seize with liquidation penalty
        uint256 collateralWithPenalty =
            Math.mulDiv(debtToCover, PRECISION + marketParams.liquidationPenalty, PRECISION);

        // Can only seize up to available collateral
        collateralToSeize = Math.min(collateralWithPenalty, collateralValue);

        // Calculate bad debt if collateral insufficient
        if (collateralToSeize < debtToCover) {
            badDebt = debtToCover - collateralToSeize;
            _handleBadDebt(borrower, badDebt);
        }
    }

    /**
     * @notice Process liquidator's debt repayment
     * @param borrower Address of borrower being liquidated
     * @param liquidator Address of liquidator
     * @param debtToCover Amount of debt to cover in USD (18 decimals)
     */
    function _processLiquidatorRepayment(
        address borrower,
        address liquidator,
        uint256 debtToCover
    ) internal {
        uint8 loanDecimals = _getLoanAssetDecimals();

        // Transfer repayment from liquidator
        bool transferSuccess = loanAsset.transferFrom(
            liquidator,
            address(this),
            _denormalizeAmount(debtToCover, loanDecimals)
        );
        if (!transferSuccess) revert Errors.TransferFailed();

        // Calculate interest and protocol fee
        uint256 interestAccrued = _borrowerInterestAccrued(borrower);
        uint256 protocolShare =
            Math.mulDiv(interestAccrued, marketParams.protocolFeeRate, PRECISION);

        // Net amount to vault after protocol fee
        uint256 netRepayToVault = debtToCover - protocolShare;

        // Transfer protocol fee
        bool feeSuccess =
            loanAsset.transfer(protocolTreasury, _denormalizeAmount(protocolShare, loanDecimals));
        if (!feeSuccess) revert Errors.TransferFailed();

        // Repay vault
        vaultContract.adminRepay(_denormalizeAmount(netRepayToVault, loanDecimals));

        // Calculate principal repayment
        uint256 principalRepayment = debtToCover > interestAccrued
            ? debtToCover - interestAccrued
            : 0;

        // Cap principal at user's actual debt
        if (principalRepayment > userTotalDebt[borrower]) {
            principalRepayment = userTotalDebt[borrower];
        }

        // Update state
        userTotalDebt[borrower] -= principalRepayment;
        totalBorrows -= principalRepayment;
        lastUpdatedIndex[borrower] = globalBorrowIndex;
    }

    /**
     * @notice Seize collateral from borrower and transfer to liquidator
     * @param borrower Address of borrower
     * @param liquidator Address of liquidator
     * @param collateralToSeizeUsd USD value to seize (18 decimals)
     * @return totalSeized Total USD value actually seized
     */
    function _seizeCollateral(
        address borrower,
        address liquidator,
        uint256 collateralToSeizeUsd
    ) internal returns (uint256 totalSeized) {
        address[] memory collateralTokens = userCollateralAssets[borrower];
        uint256 remainingToSeize = collateralToSeizeUsd;

        for (uint256 i = 0; i < collateralTokens.length && remainingToSeize > 0; i++) {
            address token = collateralTokens[i];
            uint256 seized = _seizeOneCollateral(borrower, liquidator, token, remainingToSeize);

            totalSeized += seized;
            remainingToSeize -= seized;
        }
    }

    /**
     * @notice Seize one type of collateral token
     * @param borrower Address of borrower
     * @param liquidator Address of liquidator
     * @param token Collateral token address
     * @param usdToSeize USD value to seize (18 decimals)
     * @return usdSeized USD value actually seized
     */
    function _seizeOneCollateral(
        address borrower,
        address liquidator,
        address token,
        uint256 usdToSeize
    ) internal returns (uint256 usdSeized) {
        uint256 userBalance = userCollateralBalances[borrower][token];
        if (userBalance == 0) return 0;

        // Get token value in USD
        uint256 tokenValueUsd = _getTokenValueInUSD(token, userBalance);
        if (tokenValueUsd == 0) return 0;

        // Calculate how much USD to seize from this token
        uint256 usdAmount = usdToSeize > tokenValueUsd ? tokenValueUsd : usdToSeize;

        // Get token price (18 decimals)
        uint256 price = priceOracle.getLatestPrice(token);
        if (price == 0) revert Errors.InvalidPrice();

        // Convert USD to token amount (normalized 18 decimals)
        uint256 tokensToSeizeNormalized = Math.mulDiv(usdAmount, PRECISION, price);

        // Safety check
        if (tokensToSeizeNormalized > userBalance) {
            tokensToSeizeNormalized = userBalance;
        }

        // Update state
        userCollateralBalances[borrower][token] -= tokensToSeizeNormalized;

        // Denormalize for transfer
        uint8 decimals = tokenDecimals[token];
        uint256 tokensToSeizeRaw = _denormalizeAmount(tokensToSeizeNormalized, decimals);

        // Transfer to liquidator
        bool success = IERC20(token).transfer(liquidator, tokensToSeizeRaw);
        if (!success) revert Errors.TransferFailed();

        // Clean up if balance is zero
        if (userCollateralBalances[borrower][token] == 0) {
            _removeCollateralAsset(borrower, token);
        }

        emit Events.CollateralSeized(borrower, liquidator, token, tokensToSeizeNormalized);

        return usdAmount;
    }

    /**
     * @notice Handle bad debt by transferring to bad debt address
     * @param borrower Address of borrower
     * @param badDebtAmount Amount of bad debt in USD (18 decimals)
     */
    function _handleBadDebt(address borrower, uint256 badDebtAmount) internal {
        if (badDebtAmount == 0) return;

        if (userTotalDebt[borrower] < badDebtAmount) revert Errors.InsufficientCollateral();

        // Transfer debt from user to bad debt address
        userTotalDebt[borrower] -= badDebtAmount;
        userTotalDebt[badDebtAddress] += badDebtAmount;

        // Track for statistics
        unrecoveredDebt[borrower] += badDebtAmount;

        emit Events.BadDebtRecorded(borrower, badDebtAmount);
    }

    // ==================== VIEW FUNCTIONS ====================

    /**
     * @notice Get total borrows including accrued interest
     * @return Total borrows in loan asset's native decimals
     */
    function totalBorrowsWithInterest() external view returns (uint256) {
        if (totalBorrows == 0) return 0;

        // Multiply by global index to include interest
        uint256 totalWithInterest = Math.mulDiv(totalBorrows, globalBorrowIndex, PRECISION);

        // Return in loan asset's native decimals
        uint8 loanDecimals = _getLoanAssetDecimals();
        return _denormalizeAmount(totalWithInterest, loanDecimals);
    }

    /**
     * @notice Get market parameters
     * @return lltv Liquidation loan-to-value
     * @return liquidationPenalty Liquidation bonus
     * @return protocolFeeRate Protocol fee rate
     */
    function getMarketParameters()
        external
        view
        returns (uint256 lltv, uint256 liquidationPenalty, uint256 protocolFeeRate)
    {
        return (marketParams.lltv, marketParams.liquidationPenalty, marketParams.protocolFeeRate);
    }

    /**
     * @notice Calculate lending rate for vault depositors
     * @return Lending APR as 18-decimal percentage
     */
    function getLendingRate() external view returns (uint256) {
        uint256 totalAssets = vaultContract.totalAssets();
        if (totalAssets == 0) return 0;

        uint256 utilization = Math.mulDiv(totalBorrows, PRECISION, totalAssets);
        uint256 borrowRate = interestRateModel.getDynamicBorrowRate();

        // lendingRate = utilization * borrowRate * (1 - protocolFee)
        return Math.mulDiv(
            Math.mulDiv(utilization, borrowRate, PRECISION),
            (PRECISION - marketParams.protocolFeeRate),
            PRECISION
        );
    }

    /**
     * @notice Check if a user's position is healthy
     * @param user Address of user
     * @return True if position is healthy
     */
    function isHealthy(address user) external view returns (bool) {
        return _isHealthy(user);
    }

    /**
     * @notice Get user's complete position data
     * @param user Address of user
     * @return position User's position data
     */
    function getUserPosition(
        address user
    ) external view returns (DataTypes.UserPosition memory position) {
        position.collateralValue = _getUserTotalCollateralValue(user);
        position.totalDebt = _getUserTotalDebt(user);
        position.healthFactor = _calculateHealthFactor(user);

        if (position.collateralValue > 0) {
            position.borrowingPower =
                Math.mulDiv(position.collateralValue, marketParams.lltv, PRECISION);
        }
    }

    /**
     * @notice Get user's total debt including interest
     * @param user Address of user
     * @return Total debt in 18 decimals
     */
    function getUserTotalDebt(address user) external view returns (uint256) {
        return _getUserTotalDebt(user);
    }

    /**
     * @notice Get user's accrued interest
     * @param borrower Address of borrower
     * @return Interest accrued in 18 decimals
     */
    function getBorrowerInterestAccrued(address borrower) external view returns (uint256) {
        return _borrowerInterestAccrued(borrower);
    }

    /**
     * @notice Calculate the exact token amount needed to repay full debt
     * @param borrower Address of borrower
     * @return amount Amount of loan tokens needed (in loan asset decimals)
     * @dev Rounds up to ensure full debt coverage
     */
    function getRepayAmount(address borrower) external view returns (uint256 amount) {
        uint256 debt = _getUserTotalDebt(borrower);
        if (debt == 0) return 0;

        uint8 loanDecimals = _getLoanAssetDecimals();
        return _denormalizeAmountRoundUp(debt, loanDecimals);
    }

    /**
     * @notice Get user's total collateral value in USD
     * @param user Address of user
     * @return Total collateral value in 18 decimals
     */
    function getUserTotalCollateralValue(address user) external view returns (uint256) {
        return _getUserTotalCollateralValue(user);
    }

    /**
     * @notice Get user's bad debt amount
     * @param user Address of user
     * @return Bad debt in 18 decimals
     */
    function getBadDebt(address user) external view returns (uint256) {
        return unrecoveredDebt[user];
    }

    /**
     * @notice Get loan asset decimals
     * @return Decimals of loan asset
     */
    function getLoanAssetDecimals() external view returns (uint8) {
        return _getLoanAssetDecimals();
    }

    // ==================== INTERNAL - HEALTH & DEBT ====================

    /**
     * @notice Check if a position is healthy
     * @param user Address of user
     * @return True if healthy (health factor >= 1)
     */
    function _isHealthy(address user) internal view returns (bool) {
        uint256 totalDebt = _getUserTotalDebt(user);
        if (totalDebt == 0) return true;

        uint256 borrowedAmountUsd = _getLoanDebtInUSD(totalDebt);
        uint256 collateralValue = _getUserTotalCollateralValue(user);

        // Calculate effective borrowed amount including liquidation penalty
        // This creates a safety buffer before actual liquidation
        uint256 effectiveBorrowedAmount =
            Math.mulDiv(borrowedAmountUsd, PRECISION + marketParams.liquidationPenalty, PRECISION);

        // Health factor = (collateralValue * LLTV) / effectiveBorrowedAmount
        uint256 healthFactor =
            Math.mulDiv(collateralValue, marketParams.lltv, effectiveBorrowedAmount);

        return healthFactor >= PRECISION;
    }

    /**
     * @notice Calculate health factor
     * @param user Address of user
     * @return Health factor in 18 decimals (1e18 = healthy threshold)
     */
    function _calculateHealthFactor(address user) internal view returns (uint256) {
        uint256 totalDebt = _getUserTotalDebt(user);
        if (totalDebt == 0) return type(uint256).max;

        uint256 borrowedAmountUsd = _getLoanDebtInUSD(totalDebt);
        uint256 collateralValue = _getUserTotalCollateralValue(user);

        if (borrowedAmountUsd == 0) return type(uint256).max;

        uint256 effectiveBorrowedAmount =
            Math.mulDiv(borrowedAmountUsd, PRECISION + marketParams.liquidationPenalty, PRECISION);

        return Math.mulDiv(collateralValue, marketParams.lltv, effectiveBorrowedAmount);
    }

    /**
     * @notice Get user's total debt including interest
     * @param user Address of user
     * @return Total debt in 18 decimals
     */
    function _getUserTotalDebt(address user) internal view returns (uint256) {
        uint256 storedDebt = userTotalDebt[user];
        if (storedDebt == 0) return 0;

        uint256 interestAccrued = _borrowerInterestAccrued(user);
        return storedDebt + interestAccrued;
    }

    /**
     * @notice Calculate accrued interest for a borrower
     * @param borrower Address of borrower
     * @return Interest accrued in 18 decimals
     */
    function _borrowerInterestAccrued(address borrower) internal view returns (uint256) {
        if (userTotalDebt[borrower] == 0 || lastUpdatedIndex[borrower] == 0) {
            return 0;
        }

        uint256 lastBorrowerIndex = lastUpdatedIndex[borrower];
        uint256 currentIndex = globalBorrowIndex;

        // Interest = debt * (currentIndex - lastIndex) / PRECISION
        return Math.mulDiv(userTotalDebt[borrower], (currentIndex - lastBorrowerIndex), PRECISION);
    }

    /**
     * @notice Get total collateral value for a user in USD
     * @param user Address of user
     * @return totalValue Total value in 18 decimals
     */
    function _getUserTotalCollateralValue(address user) internal view returns (uint256 totalValue) {
        address[] memory tokens = userCollateralAssets[user];

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];

            // Skip paused tokens - they don't count towards borrowing power
            if (depositsPaused[token]) continue;

            uint256 amount = userCollateralBalances[user][token];
            if (amount > 0) {
                totalValue += _getTokenValueInUSD(token, amount);
            }
        }
    }

    // ==================== INTERNAL - PRICE CONVERSIONS ====================

    /**
     * @notice Get token value in USD
     * @param token Token address
     * @param amount Amount in 18 decimals
     * @return Value in USD (18 decimals)
     */
    function _getTokenValueInUSD(address token, uint256 amount) internal view returns (uint256) {
        uint256 price = priceOracle.getLatestPrice(token);
        return Math.mulDiv(amount, price, PRECISION);
    }

    /**
     * @notice Convert loan debt to USD
     * @param amount Amount in 18 decimals
     * @return Value in USD (18 decimals)
     */
    function _getLoanDebtInUSD(uint256 amount) internal view returns (uint256) {
        uint256 price = priceOracle.getLatestPrice(address(loanAsset));
        return Math.mulDiv(amount, price, PRECISION);
    }

    // ==================== INTERNAL - INTEREST ACCRUAL ====================

    /**
     * @notice Update global borrow index
     * @dev Called before every operation that changes debt
     */
    function _updateGlobalBorrowIndex() private {
        uint256 currentTimestamp = block.timestamp;

        // Initialize on first call
        if (lastAccrualTimestamp == 0) {
            lastAccrualTimestamp = currentTimestamp;
            return;
        }

        uint256 timeElapsed = currentTimestamp - lastAccrualTimestamp;
        if (timeElapsed == 0) return;

        uint256 totalBorrowed = totalBorrows;
        uint256 totalAssets = vaultContract.totalAssets();

        // Skip if no borrows or no assets
        if (totalBorrowed == 0 || totalAssets == 0) {
            lastAccrualTimestamp = currentTimestamp;
            return;
        }

        uint256 previousIndex = globalBorrowIndex;

        // Get dynamic borrow rate
        uint256 dynamicBorrowRate = interestRateModel.getDynamicBorrowRate();

        // Calculate effective rate for time elapsed
        uint256 effectiveRate = Math.mulDiv(dynamicBorrowRate, timeElapsed, SECONDS_PER_YEAR);

        // Calculate new index
        uint256 newIndex = Math.mulDiv(previousIndex, (PRECISION + effectiveRate), PRECISION);

        // Only update if index changed
        if (newIndex != previousIndex) {
            globalBorrowIndex = newIndex;
            emit Events.GlobalBorrowIndexUpdated(previousIndex, newIndex, currentTimestamp);
        }

        lastAccrualTimestamp = currentTimestamp;
    }

    // ==================== INTERNAL - DECIMAL UTILITIES ====================

    /**
     * @notice Normalize amount to 18 decimals
     * @param amount Amount in token's native decimals
     * @param decimals Token decimals
     * @return Normalized amount (18 decimals)
     */
    function _normalizeAmount(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == TARGET_DECIMALS) return amount;
        if (decimals > TARGET_DECIMALS) revert Errors.TokenDecimalsTooHigh();
        return amount * (10 ** (TARGET_DECIMALS - decimals));
    }

    /**
     * @notice Denormalize amount from 18 decimals
     * @param amount Amount in 18 decimals
     * @param decimals Target token decimals
     * @return Denormalized amount
     */
    function _denormalizeAmount(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == TARGET_DECIMALS) return amount;
        return amount / (10 ** (TARGET_DECIMALS - decimals));
    }

    /**
     * @notice Denormalize amount from 18 decimals with rounding up
     * @param amount Amount in 18 decimals
     * @param decimals Target token decimals
     * @return Denormalized amount (rounded up)
     * @dev Used when we need to ensure full payment (e.g., repayments)
     */
    function _denormalizeAmountRoundUp(
        uint256 amount,
        uint8 decimals
    ) internal pure returns (uint256) {
        if (decimals == TARGET_DECIMALS) return amount;
        uint256 divisor = 10 ** (TARGET_DECIMALS - decimals);
        return Math.ceilDiv(amount, divisor);
    }

    /**
     * @notice Get loan asset decimals
     * @return Decimals of loan asset
     */
    function _getLoanAssetDecimals() internal view returns (uint8) {
        uint8 decimals = IERC20Metadata(address(loanAsset)).decimals();
        if (decimals > TARGET_DECIMALS) revert Errors.TokenDecimalsTooHigh();
        return decimals;
    }

    // ==================== INTERNAL - UTILITIES ====================

    /**
     * @notice Remove collateral asset from user's list
     * @param user Address of user
     * @param token Token to remove
     */
    function _removeCollateralAsset(address user, address token) private {
        uint256 length = userCollateralAssets[user].length;
        for (uint256 i = 0; i < length; i++) {
            if (userCollateralAssets[user][i] == token) {
                // Swap with last element and pop
                userCollateralAssets[user][i] = userCollateralAssets[user][length - 1];
                userCollateralAssets[user].pop();
                break;
            }
        }
    }

    /**
     * @notice Force update of global borrow index (admin function)
     * @dev Useful for testing or manual updates
     */
    function updateGlobalBorrowIndex() external {
        _updateGlobalBorrowIndex();
    }
}
