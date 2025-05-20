// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
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
    address[] public collateralTokenList;
    mapping(address => bool) public supportedCollateralTokens;
    mapping(address => bool) public depositsPaused;
    mapping(address => mapping(address => uint256))
        public userCollateralBalances;
    mapping(address => address[]) public userCollateralAssets;

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

        supportedCollateralTokens[token] = true;
        collateralTokenList.push(token);
        priceOracle.addPriceFeed(token, priceFeed);

        emit CollateralTokenAdded(token);
    }

    // I NEED TO DECIDE WHAT TO DO WITH BALANCES ON PAUSED COLLATERAL TOKENS
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

        // Swap-and-pop for efficient array removal
        uint len = collateralTokenList.length;
        for (uint i = 0; i < len; i++) {
            if (collateralTokenList[i] == token) {
                collateralTokenList[i] = collateralTokenList[len - 1];
                collateralTokenList.pop();
                break;
            }
        }

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
        userCollateralBalances[msg.sender][token] += amount;

        // Add to user's collateral list if this is the first deposit for this token
        if (userCollateralBalances[msg.sender][token] == amount) {
            userCollateralAssets[msg.sender].push(token);
        }

        if (userTotalDebt[msg.sender] > 0) {
            lastUpdatedIndex[msg.sender] = globalBorrowIndex;
        }

        emit CollateralDeposited(msg.sender, token, amount);
    }

    function withdrawCollateral(
        address token,
        uint256 amount
    ) external nonReentrant {
        _updateGlobalBorrowIndex();

        require(
            userCollateralBalances[msg.sender][token] >= amount,
            "Insufficient collateral"
        );

        require(
            IERC20(token).balanceOf(address(this)) >= amount,
            "Insufficient protocol liquidity"
        );

        require(IERC20(token).transfer(msg.sender, amount), "Transfer failed");
        userCollateralBalances[msg.sender][token] -= amount;

        // Clean up user's collateral list if balance is now zero
        if (userCollateralBalances[msg.sender][token] == 0) {
            _removeCollateralAsset(msg.sender, token);
        }

        if (userTotalDebt[msg.sender] > 0) {
            lastUpdatedIndex[msg.sender] = globalBorrowIndex;
        }

        emit CollateralWithdrawn(msg.sender, token, amount);
    }

    // --- Debt Operations ---

    function borrow(uint256 amount) external nonReentrant {
        _updateGlobalBorrowIndex();

        uint256 collateralValue = _getUserTotalCollateralValue(msg.sender);
        uint256 newDebt = _getUserTotalDebt(msg.sender) + amount;
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
            amount <= vaultContract.totalIdle(),
            "Insufficient vault liquidity"
        );

        vaultContract.adminBorrow(amount);
        loanAsset.transfer(msg.sender, amount);

        userTotalDebt[msg.sender] += amount;
        totalBorrows += amount;
        lastUpdatedIndex[msg.sender] = globalBorrowIndex;

        emit Borrow(msg.sender, amount);
    }

    function repay(uint256 amount) external nonReentrant {
        _updateGlobalBorrowIndex();

        uint256 interest = _borrowerInterestAccrued(msg.sender);
        require(amount >= interest, "Must cover interest");
        require(
            amount <= _getUserTotalDebt(msg.sender),
            "Exceeds current debt"
        );

        uint256 protocolFee = Math.mulDiv(
            interest,
            marketParams.protocolFeeRate,
            1e18
        );

        // Portion of interest going to the vault
        uint256 interestToVault = interest - protocolFee;

        // Principal repaid is anything above interest
        uint256 principal = amount > interest ? amount - interest : 0;

        // Total sent to vault = principal + interestToVault
        uint256 vaultRepayment = principal + interestToVault;

        require(
            loanAsset.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        require(
            loanAsset.transfer(protocolTreasury, protocolFee),
            "Protocol fee transfer failed"
        );
        vaultContract.adminRepay(vaultRepayment);

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

    // ======= HELPER FUNCTIONS ========

    // Function to calculate lending rate
    function getLendingRate() public view returns (uint256) {
        uint256 totalSupply = vaultContract.totalAssets();
        if (totalSupply == 0) return 0;

        uint256 utilization = Math.mulDiv(totalBorrows, 1e18, totalSupply);
        uint256 borrowRate = interestRateModel.getDynamicBorrowRate();

        // lendingRate = utilization * borrowRate * (1 - protocolFee)
        return
            Math.mulDiv(
                Math.mulDiv(utilization, borrowRate, 1e18),
                (1e18 - marketParams.protocolFeeRate),
                1e18
            );
    }

    // Returns the total value (in USD) of all collateral a user has deposited
    function _getUserTotalCollateralValue(
        address user
    ) internal view returns (uint256 totalValue) {
        for (uint i = 0; i < collateralTokenList.length; i++) {
            address token = collateralTokenList[i];
            uint256 amount = userCollateralBalances[user][token];
            if (amount > 0) {
                totalValue += _getTokenValueInUSD(token, amount);
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

    // Calculates the total debt for a user, including accrued interest
    function _getUserTotalDebt(
        address user
    ) public view returns (uint256 totalDebt) {
        uint256 storedDebt = userTotalDebt[user];

        if (storedDebt == 0) {
            return 0;
        }

        // Add accrued interest to stored debt
        uint256 interestAccrued = _borrowerInterestAccrued(user);
        totalDebt = storedDebt + interestAccrued;

        return totalDebt;
    }

    // Calculates the maximum borrowing capacity of a user
    function _maxBorrowingPower(address user) internal returns (uint256) {
        // Update the global borrow index to ensure interest rates are up-to-date
        _updateGlobalBorrowIndex();

        uint256 borrowingPower = _getUserTotalCollateralValue(user) *
            marketParams.lltv;

        uint256 totalDebtNative = _getUserTotalDebt(user);
        uint256 totalDebt = _getLoanDebtInUSD(totalDebtNative); // Debt in USD terms

        // Ensure borrowing power is not negative
        require(
            borrowingPower >= totalDebt,
            "Negative borrowing power detected"
        );

        uint256 maxBorrowingPower = borrowingPower - totalDebt;
        return maxBorrowingPower;
    }

    // Calculates the accrued interest on a debt considering dynamic rates
    function _borrowerInterestAccrued(
        address borrower
    ) public view returns (uint256) {
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
        uint256 totalSupply = vaultContract.totalAssets(); // Total assets backing the system

        // Skip if no borrows or no liquidity
        if (totalBorrowed == 0 || totalSupply == 0) {
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

    // Function to calculate total borrows plus accrued interest
    function _lentAssets() public view returns (uint256) {
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

    // Function to remove an asset from userCollateralAssets[msg.sender]
    function _removeCollateralAsset(
        address user,
        address collateralToken
    ) internal {
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
        require(
            IERC20(loanAsset).transferFrom(
                liquidator,
                address(this),
                debtToCover
            ),
            "Transfer failed: insufficient allowance or balance"
        );

        uint256 interestAccrued = _borrowerInterestAccrued(borrower);

        uint256 protocolShare = Math.mulDiv(
            interestAccrued,
            marketParams.protocolFeeRate,
            1e18
        );

        uint256 netRepayToVault = debtToCover - protocolShare;

        bool protocolSuccess = loanAsset.transfer(
            protocolTreasury,
            protocolShare
        );
        require(protocolSuccess, "Protocol fee transfer failed");

        vaultContract.adminRepay(netRepayToVault);

        uint256 principalRepayment = debtToCover > interestAccrued
            ? debtToCover - interestAccrued
            : 0;

        userTotalDebt[borrower] -= principalRepayment;
        totalBorrows -= principalRepayment;

        lastUpdatedIndex[borrower] = globalBorrowIndex;
    }

    // Seize a portion of one specific collateral token from a user during liquidation,
    // based on how much USD value needs to be covered.
    function _seizeOneCollateral(
        address user,
        address liquidator,
        address token,
        uint256 remainingToSeizeUsd
    ) internal returns (uint256 usdLiquidated) {
        uint256 userTokenBalance = userCollateralBalances[user][token];

        if (userTokenBalance == 0) {
            return 0;
        }

        uint256 tokenValueUsd = _getTokenValueInUSD(token, userTokenBalance);
        if (tokenValueUsd == 0) {
            return 0;
        }

        uint256 usdToSeize = remainingToSeizeUsd > tokenValueUsd
            ? tokenValueUsd
            : remainingToSeizeUsd;

        // Get token price and convert USD → token units
        int256 price = priceOracle.getLatestPrice(token);
        require(price > 0, "Invalid token price");
        uint256 scaledPrice = uint256(price) * 1e10;

        // Convert USD amount back to token amount
        uint256 tokensToSeize = Math.mulDiv(usdToSeize, 1e18, scaledPrice);

        require(
            tokensToSeize <= userTokenBalance,
            "Trying to seize more than available"
        );

        userCollateralBalances[user][token] -= tokensToSeize;

        require(
            IERC20(token).transfer(liquidator, tokensToSeize),
            "Collateral transfer failed"
        );

        return usdToSeize;
    }

    // Function to seize liquidated collateral
    function _seizeCollateral(
        address user,
        address liquidator,
        uint256 collateralToSeizeUsd
    ) internal returns (uint256 totalLiquidated, uint256 remainingToSeizeUsd) {
        address[] memory collateralTokens = userCollateralAssets[user];
        remainingToSeizeUsd = collateralToSeizeUsd;
        totalLiquidated = 0;

        for (
            uint i = 0;
            i < collateralTokens.length && remainingToSeizeUsd > 0;
            i++
        ) {
            address token = collateralTokens[i];

            uint256 liquidated = _seizeOneCollateral(
                user,
                liquidator,
                token,
                remainingToSeizeUsd
            );

            totalLiquidated += liquidated;
            remainingToSeizeUsd -= liquidated;
        }
    }

    // Get the user's collateral balances for each token in the collateralTokenList, converted to USD
    function _getUserCollateralBalances(
        address user
    ) public view returns (address[] memory, uint256[] memory) {
        uint256 tokenCount = collateralTokenList.length;
        address[] memory tokens = new address[](tokenCount);
        uint256[] memory usdBalances = new uint256[](tokenCount); // Store USD values for each token

        for (uint256 i = 0; i < tokenCount; i++) {
            address token = collateralTokenList[i];
            uint256 balance = userCollateralBalances[user][token]; // Get user's balance for the token

            // Use the existing function to get the USD value of the token balance
            uint256 usdValue = _getTokenValueInUSD(token, balance);

            tokens[i] = token;
            usdBalances[i] = usdValue; // Store USD value
        }

        return (tokens, usdBalances);
    }

    // =============================================================
    // PUBLIC TEST FUNCTIONS (for testing purposes only)
    // =============================================================

    function getUserTotalCollateralValue(
        address user
    ) public view returns (uint256) {
        return _getUserTotalCollateralValue(user);
    }

    function isHealthy(address user) public view returns (bool) {
        return _isHealthy(user);
    }

    function _getMaxBorrowingPower(address user) external returns (uint256) {
        return _maxBorrowingPower(user);
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
}
