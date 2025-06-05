// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "./Vault.sol";
import "./PriceOracle.sol";
import "./InterestRateModel.sol";
import "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

contract Market is ReentrancyGuard {
    using Math for uint256;

    // --- Structs ---
    struct MarketParameters {
        uint256 lltv; // liquidation loan-to-value
        uint256 liquidationPenalty;
        uint256 protocolFeeRate;
    }

    // --- State Variables ---
    MarketParameters public marketParams;

    address public immutable owner;
    address public immutable protocolTreasury;
    Vault public immutable vaultContract;
    PriceOracle public immutable priceOracle;
    InterestRateModel public immutable interestRateModel;
    IERC20 public immutable loanAsset;

    uint256 public totalBorrows;
    uint256 public globalBorrowIndex = 1e18;
    uint256 public lastAccruedInterest;
    uint256 public lastAccrualTimestamp;

    // --- Collateral Management ---
    mapping(address => bool) public supportedCollateralTokens;
    mapping(address => bool) public depositsPaused;
    mapping(address => mapping(address => uint256))
        public userCollateralBalances;
    mapping(address => address[]) public userCollateralAssets;
    mapping(address => uint8) public tokenDecimals;

    // --- Borrowing State ---
    mapping(address => uint256) public userTotalDebt;
    mapping(address => uint256) public lastUpdatedIndex;

    // --- Events ---
    event CollateralTokenAdded(address indexed collateralToken);
    event CollateralDepositsPaused(address indexed collateralToken);
    event CollateralDepositsResumed(address indexed collateralToken);
    event CollateralTokenRemoved(address indexed collateralToken);
    event CollateralDeposited(
        address indexed user,
        address indexed collateralToken,
        uint256 amount
    );
    event CollateralWithdrawn(
        address indexed user,
        address indexed collateralToken,
        uint256 amount
    );
    event Borrow(address indexed user, uint256 loanAmount);
    event Repay(address indexed user, uint256 amountRepaid);
    event CollateralLiquidated(
        address indexed user,
        address indexed liquidator,
        address token,
        uint256 amount
    );
    event CollateralSeized(
        address indexed user,
        address indexed liquidator,
        uint256 totalUsdValueSeized
    );
    event Liquidation(
        address indexed user,
        address indexed liquidator,
        uint256 debtToCover,
        uint256 collateralToLiquidate,
        uint256 remainingToSeizeUsd
    );

    // --- Constructor ---
    constructor(
        address _protocolTreasury,
        address _vaultContract,
        address _priceOracle,
        address _interestRateModel,
        address _loanAsset
    ) {
        protocolTreasury = _protocolTreasury;
        vaultContract = Vault(_vaultContract);
        priceOracle = PriceOracle(_priceOracle);
        interestRateModel = InterestRateModel(_interestRateModel);
        loanAsset = IERC20(_loanAsset);
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "Only contract owner can execute this function"
        );
        _;
    }

    // --- Admin Functions ---

    function setMarketParameters(
        uint256 _lltv,
        uint256 _liquidationPenalty,
        uint256 _protocolFeeRate
    ) external onlyOwner {
        require(_lltv <= 1e18, "Liquidation loan-to-value too high");
        require(_liquidationPenalty <= 1e18, "Penalty too high");

        marketParams = MarketParameters({
            lltv: _lltv,
            liquidationPenalty: _liquidationPenalty,
            protocolFeeRate: _protocolFeeRate
        });
    }

    function addCollateralToken(
        address token,
        address priceFeed
    ) external onlyOwner {
        require(token != address(0), "Invalid token address");
        require(priceFeed != address(0), "Invalid price feed address");
        require(!supportedCollateralTokens[token], "Token already added");

        // store token decimals for normalization
        uint8 decimals = IERC20Metadata(token).decimals();
        require(decimals <= 18, "Token decimals exceed maximum allowed");
        tokenDecimals[token] = decimals;

        supportedCollateralTokens[token] = true;
        priceOracle.addPriceFeed(token, priceFeed);

        emit CollateralTokenAdded(token);
    }

    // Pauses deposits for a collateral token, preventing it from contributing to borrowing power
    function pauseCollateralDeposits(address token) external onlyOwner {
        require(supportedCollateralTokens[token], "Token not supported");

        depositsPaused[token] = true;
        emit CollateralDepositsPaused(token);
    }

    function resumeCollateralDeposits(address token) external onlyOwner {
        require(supportedCollateralTokens[token], "Token not supported");
        require(depositsPaused[token], "Deposits already enabled");

        depositsPaused[token] = false;
        emit CollateralDepositsResumed(token);
    }

    function removeCollateralToken(address token) external onlyOwner {
        require(supportedCollateralTokens[token], "Token not supported");
        require(depositsPaused[token], "Pause deposits first");
        require(
            IERC20(token).balanceOf(address(this)) == 0,
            "Collateral still in use"
        );

        supportedCollateralTokens[token] = false;

        emit CollateralTokenRemoved(token);
    }

    // --- Collateral Management ---

    function depositCollateral(
        address token,
        uint256 amount
    ) external nonReentrant {
        _updateGlobalBorrowIndex();
        require(supportedCollateralTokens[token], "Token not supported");
        require(!depositsPaused[token], "Deposits paused");

        require(
            IERC20(token).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        // Normalize token to 18 decimals
        uint256 normalizedAmount = normalizeAmount(
            amount,
            tokenDecimals[token]
        );

        userCollateralBalances[msg.sender][token] += normalizedAmount;

        // Add to user's collateral list if this is the first deposit for this token
        if (userCollateralBalances[msg.sender][token] == normalizedAmount) {
            userCollateralAssets[msg.sender].push(token);
        }

        if (userTotalDebt[msg.sender] > 0) {
            lastUpdatedIndex[msg.sender] = globalBorrowIndex;
        }

        emit CollateralDeposited(msg.sender, token, normalizedAmount);
    }

    function withdrawCollateral(
        address token,
        uint256 rawAmount
    ) external nonReentrant {
        _updateGlobalBorrowIndex();
        require(supportedCollateralTokens[token], "Unsupported token");

        // Normalize token to 18 decimals
        uint256 normalizedAmount = normalizeAmount(
            rawAmount,
            tokenDecimals[token]
        );

        require(
            userCollateralBalances[msg.sender][token] >= normalizedAmount,
            "Insufficient collateral"
        );

        // Simulate withdrawal
        userCollateralBalances[msg.sender][token] -= normalizedAmount;

        bool stillHealthy = _isHealthy(msg.sender);

        // Revert simulated withdrawal if not healthy
        if (!stillHealthy) {
            userCollateralBalances[msg.sender][token] += normalizedAmount;
            revert("Withdrawal would make position unhealthy");
        }

        // Check protocol liquidity in raw token units (not normalized)
        require(
            IERC20(token).balanceOf(address(this)) >= rawAmount,
            "Insufficient protocol liquidity"
        );

        // Transfer token in raw units
        require(
            IERC20(token).transfer(msg.sender, rawAmount),
            "Transfer failed"
        );

        // Clean up user's collateral list if balance is now zero
        if (userCollateralBalances[msg.sender][token] == 0) {
            _removeCollateralAsset(msg.sender, token);
        }

        if (userTotalDebt[msg.sender] > 0) {
            lastUpdatedIndex[msg.sender] = globalBorrowIndex;
        }

        emit CollateralWithdrawn(msg.sender, token, normalizedAmount);
    }

    // --- Debt Operations ---

    function borrow(uint256 amount) external nonReentrant {
        _updateGlobalBorrowIndex();

        // Collateral value doesn't include paused collateral tokens
        uint256 collateralValue = _getUserTotalCollateralValue(msg.sender);
        uint8 loanDecimals = _getLoanAssetDecimals();

        uint256 normalizedAmount = normalizeAmount(amount, loanDecimals);
        uint256 newDebt = _getUserTotalDebt(msg.sender) + normalizedAmount;
        uint256 borrowingPower = Math.mulDiv(
            collateralValue,
            marketParams.lltv,
            1e18
        );
        require(
            borrowingPower >= newDebt,
            "Not enough collateral to borrow from market"
        );

        require(
            amount <= vaultContract.availableLiquidity(),
            "Insufficient vault liquidity"
        );

        vaultContract.adminBorrow(amount); // raw loan decimals
        loanAsset.transfer(msg.sender, amount); // raw loan decimals

        userTotalDebt[msg.sender] += normalizedAmount;
        totalBorrows += normalizedAmount;
        lastUpdatedIndex[msg.sender] = globalBorrowIndex;

        emit Borrow(msg.sender, amount); // Emit raw amount
    }

    function repay(uint256 amount) external nonReentrant {
        _updateGlobalBorrowIndex();

        uint8 loanDecimals = _getLoanAssetDecimals();

        // Normalize input amount to 18 decimals
        uint256 normalizedAmount = normalizeAmount(amount, loanDecimals);

        // Interest and debt are in 18 decimals
        uint256 interest = _borrowerInterestAccrued(msg.sender);
        uint256 totalDebt = _getUserTotalDebt(msg.sender);

        require(normalizedAmount >= interest, "Must cover interest");
        require(normalizedAmount <= totalDebt, "Exceeds current debt");

        uint256 protocolFee = Math.mulDiv(
            interest,
            marketParams.protocolFeeRate,
            1e18
        );

        // Portion of interest going to the vault
        uint256 interestToVault = interest - protocolFee;

        // Principal repaid is anything above interest
        uint256 principal = normalizedAmount > interest
            ? normalizedAmount - interest
            : 0;

        // Total sent to vault = principal + interestToVault
        uint256 vaultRepayment = principal + interestToVault;

        // Transfer full raw amount from user to contract
        require(
            loanAsset.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        // Transfer protocol fee in raw units
        require(
            loanAsset.transfer(
                protocolTreasury,
                denormalizeAmount(protocolFee, loanDecimals)
            ),
            "Protocol fee transfer failed"
        );
        // Send vault repayment in raw units
        vaultContract.adminRepay(
            denormalizeAmount(vaultRepayment, loanDecimals)
        );

        if (principal > 0) {
            require(totalBorrows >= principal, "Borrow underflow");
            totalBorrows -= principal;
            userTotalDebt[msg.sender] -= principal;
        }

        lastUpdatedIndex[msg.sender] = globalBorrowIndex;

        emit Repay(msg.sender, amount);
    }

    function liquidate(address user) external nonReentrant {
        _updateGlobalBorrowIndex(); // Ensure interest accrual is up to date

        // Step 1: Check if user is eligible for liquidation and calculate how much debt can be repaid and how much collateral can be seized (in USD)
        (
            uint256 debtToCover,
            uint256 collateralToLiquidateUsd
        ) = _validateAndCalculateFullLiquidation(user);

        // Step 2: Liquidator repays the borrower's debt (transfers loan tokens to protocol)
        _processLiquidatorRepayment(user, msg.sender, debtToCover);

        // Step 3: Seize and transfer collateral from borrower to liquidator (USD value-based)
        (
            uint256 totalLiquidated,
            uint256 remainingToSeizeUsd
        ) = _seizeCollateral(user, msg.sender, collateralToLiquidateUsd);

        emit Liquidation(
            user,
            msg.sender,
            debtToCover,
            totalLiquidated,
            remainingToSeizeUsd
        );
    }

    // ======= DEBT CALCULATIONS =======

    // Function to calculate total borrows plus accrued interest
    function totalBorrowsWithInterest() external view returns (uint256) {
        uint256 totalBorrowed = totalBorrows;
        if (totalBorrowed == 0) {
            return 0; // No borrowings, no interest
        }
        // Multiply by globalBorrowIndex to include accrued interest
        uint256 totalWithInterest = Math.mulDiv(
            totalBorrows,
            globalBorrowIndex,
            1e18
        );

        return totalWithInterest;
    }

    // Function to expose market parameters
    function getMarketParameters()
        external
        view
        returns (
            uint256 lltv,
            uint256 liquidationPenalty,
            uint256 protocolFeeRate
        )
    {
        return (
            marketParams.lltv,
            marketParams.liquidationPenalty,
            marketParams.protocolFeeRate
        );
    }

    // Function to calculate lending rate
    function getLendingRate() external view returns (uint256) {
        uint256 totalAssets = vaultContract.totalAssets();
        if (totalAssets == 0) return 0;

        uint256 utilization = Math.mulDiv(totalBorrows, 1e18, totalAssets);
        uint256 borrowRate = interestRateModel.getDynamicBorrowRate();

        // lendingRate = utilization * borrowRate * (1 - protocolFee)
        return
            Math.mulDiv(
                Math.mulDiv(utilization, borrowRate, 1e18),
                (1e18 - marketParams.protocolFeeRate),
                1e18
            );
    }

    // ======= DECIMALS CALCULATIONS =======

    function normalizeAmount(
        uint256 amount,
        uint8 decimals
    ) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        require(decimals < 18, "Too many decimals");
        return amount * (10 ** (18 - decimals));
    }

    function denormalizeAmount(
        uint256 amount,
        uint8 decimals
    ) internal pure returns (uint256) {
        return amount / (10 ** (18 - decimals));
    }

    function _getLoanAssetDecimals() internal view returns (uint8) {
        uint8 decimals = IERC20Metadata(address(loanAsset)).decimals();
        require(decimals <= 18, "Loan asset decimals too high");
        return decimals;
    }

    // ======= USER HEALTH CHECKS =======

    // Returns true if the user's position is currently healthy
    function isHealthy(address user) public view returns (bool) {
        return _isHealthy(user);
    }

    // Returns true if the user's position is currently at risk of liquidation
    function isUserAtRiskOfLiquidation(
        address user
    ) external view returns (bool) {
        return !_isHealthy(user);
    }

    // ======= HELPER FUNCTIONS ========

    // Calculates the total debt for a user, including accrued interest
    function _getUserTotalDebt(
        address user
    ) internal view returns (uint256 totalDebt) {
        uint256 storedDebt = userTotalDebt[user];

        if (storedDebt == 0) {
            return 0;
        }

        // Add accrued interest to stored debt
        uint256 interestAccrued = _borrowerInterestAccrued(user);

        uint8 loanDecimals = _getLoanAssetDecimals();

        // Normalize interest to 18 decimals
        uint256 normalizedInterest = normalizeAmount(
            interestAccrued,
            loanDecimals
        );

        totalDebt = storedDebt + normalizedInterest;
    }

    // Returns the total value (in USD) of all collateral a user has deposited
    function _getUserTotalCollateralValue(
        address user
    ) internal view returns (uint256 totalValue) {
        address[] memory tokens = userCollateralAssets[user];

        for (uint i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            if (!depositsPaused[token]) {
                uint256 amount = userCollateralBalances[user][token];
                if (amount > 0) {
                    totalValue += _getTokenValueInUSD(token, amount);
                }
            }
        }
    }

    // Calculates if a position is healthy
    function _isHealthy(address user) internal view returns (bool) {
        uint256 totalDebt = _getUserTotalDebt(user);
        if (totalDebt == 0) return true; // No debt, always healthy

        // Convert debt (in native units) to USD
        uint256 borrowedAmount = _getLoanDebtInUSD(totalDebt);
        uint256 collateralValue = _getUserTotalCollateralValue(user);

        // Incorporate liquidation penalty in borrowed amount for health check
        uint256 effectiveBorrowedAmount = Math.mulDiv(
            borrowedAmount,
            1e18 + marketParams.liquidationPenalty,
            1e18
        );

        uint256 healthFactor = Math.mulDiv(
            collateralValue,
            marketParams.lltv,
            effectiveBorrowedAmount
        );

        return healthFactor >= 1e18;
    }

    // Calculates the accrued interest on a debt considering dynamic rates
    function _borrowerInterestAccrued(
        address borrower
    ) internal view returns (uint256) {
        // Return 0 if no debt is recorded for the borrower
        if (userTotalDebt[borrower] == 0 || lastUpdatedIndex[borrower] == 0) {
            return 0;
        }

        uint256 lastBorrowerIndex = lastUpdatedIndex[borrower];
        uint256 currentGlobalIndex = globalBorrowIndex;

        // Interest accrued is the difference in indices multiplied by the borrower's debt
        uint256 interestAccrued = Math.mulDiv(
            userTotalDebt[borrower],
            (currentGlobalIndex - lastBorrowerIndex),
            1e18
        );

        return interestAccrued;
    }

    // Updates the global borrow index
    function _updateGlobalBorrowIndex() private {
        uint256 currentTimestamp = block.timestamp;

        // Initialize the timestamp on the first call
        if (lastAccrualTimestamp == 0) {
            lastAccrualTimestamp = currentTimestamp;
            return;
        }

        uint256 timeElapsed = currentTimestamp - lastAccrualTimestamp;
        if (timeElapsed == 0) {
            return; // No time passed, no update needed
        }

        uint256 totalBorrowed = totalBorrows; // Total outstanding borrows
        uint256 totalAssets = vaultContract.totalAssets(); // Total assets backing the system

        // Skip if no borrows or no liquidity
        if (totalBorrowed == 0 || totalAssets == 0) {
            return;
        }

        uint256 previousGlobalBorrowIndex = globalBorrowIndex;

        // Get the current dynamic borrow rate (annualized rate scaled by 1e18)
        uint256 dynamicBorrowRate = interestRateModel.getDynamicBorrowRate();

        // Scale the interest rate based on time elapsed to match the actual time the loan was held
        uint256 secondsPerYear = 365 days;
        uint256 effectiveRate = Math.mulDiv(
            dynamicBorrowRate,
            timeElapsed,
            secondsPerYear
        );

        // Calculate the new global borrow index
        uint256 newGlobalBorrowIndex = Math.mulDiv(
            previousGlobalBorrowIndex,
            (1e18 + effectiveRate),
            1e18
        );

        // Skip updating if the index remains the same
        if (newGlobalBorrowIndex == previousGlobalBorrowIndex) {
            lastAccrualTimestamp = currentTimestamp;
            return;
        }

        // Set the new global borrow index and update the timestamp
        globalBorrowIndex = newGlobalBorrowIndex;
        lastAccrualTimestamp = currentTimestamp;
    }

    // Function to remove an asset from userCollateralAssets[msg.sender]
    function _removeCollateralAsset(
        address user,
        address collateralToken
    ) private {
        uint256 length = userCollateralAssets[user].length;
        for (uint256 i = 0; i < length; i++) {
            if (userCollateralAssets[user][i] == collateralToken) {
                // Swap with last element and pop to avoid gaps
                userCollateralAssets[user][i] = userCollateralAssets[user][
                    length - 1
                ];
                userCollateralAssets[user].pop();
                break;
            }
        }
    }

    // Function to get the token's value in USD
    function _getTokenValueInUSD(
        address collateralToken,
        uint256 amount
    ) internal view returns (uint256) {
        int256 tokenPrice = priceOracle.getLatestPrice(collateralToken);
        uint256 scaledPrice = uint256(tokenPrice) * 1e10; // Scale to 18 decimals
        require(scaledPrice > 0, "Invalid token price from Oracle");

        uint256 tokenValueInUSD = Math.mulDiv(amount, scaledPrice, 1e18);

        return tokenValueInUSD;
    }

    // Function to calculate loan asset in USD terms
    function _getLoanDebtInUSD(uint256 amount) internal view returns (uint256) {
        int256 tokenPrice = priceOracle.getLatestPrice(address(loanAsset));
        uint256 scaledPrice = uint256(tokenPrice) * 1e10; // Scale to 18 decimals
        require(scaledPrice > 0, "Invalid token price from Oracle");

        uint256 debtInUSD = Math.mulDiv(amount, scaledPrice, 1e18);

        return debtInUSD;
    }

    // Helper function to validate and calculate full liquidation
    function _validateAndCalculateFullLiquidation(
        address user
    )
        internal
        view
        returns (uint256 debtToCover, uint256 collateralToSeizeUsd)
    {
        require(!_isHealthy(user), "User not eligible for liquidation");

        uint256 currentDebt = _getUserTotalDebt(user);
        uint256 debtInUSD = _getLoanDebtInUSD(currentDebt); // convert to USD
        uint256 collateralValue = _getUserTotalCollateralValue(user); // in USD terms

        // Liquidator repays full debt
        debtToCover = debtInUSD;

        // Calculate how much collateral should be seized (debt + liquidation penalty)
        collateralToSeizeUsd = Math.mulDiv(
            debtToCover,
            1e18 + marketParams.liquidationPenalty,
            1e18
        );

        require(
            collateralToSeizeUsd <= collateralValue,
            "Not enough collateral to cover liquidation"
        );

        return (debtToCover, collateralToSeizeUsd);
    }

    // Helper function to process liquidation repayment
    function _processLiquidatorRepayment(
        address borrower,
        address liquidator,
        uint256 debtToCover
    ) internal {
        uint8 loanDecimals = _getLoanAssetDecimals();

        // Transfer the repayment amount from liquidator to this contract
        // denormalizeAmount converts from normalized 18 decimals to raw token decimals
        require(
            IERC20(loanAsset).transferFrom(
                liquidator,
                address(this),
                denormalizeAmount(debtToCover, loanDecimals)
            ),
            "Transfer failed: insufficient allowance or balance"
        );

        // Accrued interest on borrower's debt (normalized 18 decimals)
        uint256 interestAccrued = _borrowerInterestAccrued(borrower);

        uint256 protocolShare = Math.mulDiv(
            interestAccrued,
            marketParams.protocolFeeRate,
            1e18
        );

        // Net amount to repay to vault after protocol fee (normalized 18 decimals)
        uint256 netRepayToVault = debtToCover - protocolShare;

        // Transfer protocol fee to treasury in raw token units
        bool protocolSuccess = loanAsset.transfer(
            protocolTreasury,
            denormalizeAmount(protocolShare, loanDecimals)
        );
        require(protocolSuccess, "Protocol fee transfer failed");

        // Repay the vault with the net amount in raw token units
        vaultContract.adminRepay(
            denormalizeAmount(netRepayToVault, loanDecimals)
        );

        // Calculate principal repayment portion (normalized 18 decimals)
        uint256 principalRepayment = debtToCover > interestAccrued
            ? debtToCover - interestAccrued
            : 0;

        // Update user debt and total borrows in normalized units
        userTotalDebt[borrower] -= principalRepayment;
        totalBorrows -= principalRepayment;

        // Update borrow index snapshot for borrower
        lastUpdatedIndex[borrower] = globalBorrowIndex;
    }

    // Seize a portion of one specific collateral token from a user during liquidation,
    // based on how much USD value needs to be covered.
    function _seizeOneCollateral(
        address user,
        address liquidator,
        address token,
        uint256 remainingToSeizeUsd // 18 decimals
    ) internal returns (uint256 usdLiquidated) {
        uint256 userTokenBalanceNormalized = userCollateralBalances[user][
            token
        ]; // 18 decimals

        if (userTokenBalanceNormalized == 0) {
            return 0;
        }

        // Get value of user's collateral balance in USD (18 decimals)
        uint256 tokenValueUsd = _getTokenValueInUSD(
            token,
            userTokenBalanceNormalized
        );
        if (tokenValueUsd == 0) {
            return 0;
        }

        uint256 usdToSeize = remainingToSeizeUsd > tokenValueUsd
            ? tokenValueUsd
            : remainingToSeizeUsd;

        // Get token price and scale to 18 decimals
        int256 price = priceOracle.getLatestPrice(token);
        require(price > 0, "Invalid token price");
        uint256 scaledPrice = uint256(price) * 1e10;

        // Convert USD to token amount (normalized units)
        uint256 tokensToSeizeNormalized = Math.mulDiv(
            usdToSeize,
            1e18,
            scaledPrice
        ); // 18 decimals

        require(
            tokensToSeizeNormalized <= userTokenBalanceNormalized,
            "Trying to seize more than available"
        );

        // Update internal state in normalized units
        userCollateralBalances[user][token] -= tokensToSeizeNormalized;

        // Use stored decimals to denormalize for transfer
        uint8 decimals = tokenDecimals[token];
        uint256 tokensToSeizeRaw = denormalizeAmount(
            tokensToSeizeNormalized,
            decimals
        );

        // Transfer raw tokens to the liquidator
        require(
            IERC20(token).transfer(liquidator, tokensToSeizeRaw),
            "Collateral transfer failed"
        );

        return usdToSeize; // Return seized USD value (18 decimals)
    }

    // Function to seize liquidated collateral
    function _seizeCollateral(
        address user,
        address liquidator,
        uint256 collateralToSeizeUsd // 18 decimals USD units
    ) internal returns (uint256 totalLiquidated, uint256 remainingToSeizeUsd) {
        address[] memory collateralTokens = userCollateralAssets[user];

        remainingToSeizeUsd = collateralToSeizeUsd; // 18-decimal USD value
        totalLiquidated = 0; // 18-decimal USD value

        for (
            uint i = 0;
            i < collateralTokens.length && remainingToSeizeUsd > 0;
            i++
        ) {
            address token = collateralTokens[i];

            // _seizeOneCollateral returns amount seized in USD (18 decimals)
            uint256 liquidated = _seizeOneCollateral(
                user,
                liquidator,
                token,
                remainingToSeizeUsd
            );

            totalLiquidated += liquidated; // Accumulate USD value
            remainingToSeizeUsd -= liquidated; // Decrease remaining USD to seize
        }
        emit CollateralSeized(user, liquidator, totalLiquidated);
        return (totalLiquidated, remainingToSeizeUsd);
    }

    // =============================================================
    // PUBLIC TEST FUNCTIONS (for testing purposes only)
    // =============================================================

    function getUserTotalCollateralValue(
        address user
    ) public view returns (uint256) {
        return _getUserTotalCollateralValue(user);
    }

    function updateGlobalBorrowIndex() external {
        _updateGlobalBorrowIndex();
    }

    function getTokenValueInUSD(
        address collateralToken,
        uint256 amount
    ) external view returns (uint256) {
        return _getTokenValueInUSD(collateralToken, amount);
    }

    function _loanDebtInUSD(uint256 amount) external view returns (uint256) {
        return _getLoanDebtInUSD(amount);
    }

    function validateAndCalculateFullLiquidation(
        address user
    )
        external
        view
        returns (uint256 debtToCover, uint256 collateralToSeizeUsd)
    {
        return _validateAndCalculateFullLiquidation(user);
    }

    function processLiquidatorRepaymentPublic(
        address borrower,
        address liquidator,
        uint256 debtToCover
    ) external {
        _processLiquidatorRepayment(borrower, liquidator, debtToCover);
    }

    function seizeCollateralPublic(
        address user,
        address liquidator,
        uint256 collateralToLiquidateUsd
    ) external returns (uint256 totalLiquidated, uint256 remainingToSeizeUsd) {
        return _seizeCollateral(user, liquidator, collateralToLiquidateUsd);
    }

    function getUserTotalDebt(
        address user
    ) public view returns (uint256 totalDebt) {
        return _getUserTotalDebt(user);
    }

    function getBorrowerInterestAccrued(
        address borrower
    ) public view returns (uint256 interestAccrued) {
        return _borrowerInterestAccrued(borrower);
    }
}
