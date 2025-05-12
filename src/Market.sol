// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "./Vault.sol";
import "./PriceOracle.sol";
import "./InterestRateModel.sol";

contract Market is ReentrancyGuard {
    // Declare the struct to store market parameters
    struct MarketParameters {
        uint256 liquidationThreshold; // % at which liquidation occurs
        uint256 liquidationPenalty; // Extra collateral taken during liquidation
        uint256 maxLTV; // Max Loan-to-Value ratio
        uint256 minHealthFactor; // Health Factor threshold for liquidation
        uint256 closeFactor; // Max % of debt that can be liquidated in one transaction
        uint256 protocolFeeRate; // Protocol's share of interest, e.g., 1e17 for 10%
    }

    // Store the current market parameters
    MarketParameters public marketParams;

    // Other global variables
    address public protocolTreasury; // Address to capture protocol fees
    address public owner;
    Vault public vaultContract;
    PriceOracle public priceOracle;
    InterestRateModel public interestRateModel;
    IERC20 public loanAsset;
    uint256 public totalBorrows; // Tracks the platform's total principal outstanding
    uint256 public globalBorrowIndex;
    uint256 public lastAccruedInterest;
    uint256 public lastAccrualTimestamp; // used to calculate interest rates based on time elapsed

    // Mapping to track the supported collateral tokens
    mapping(address => bool) public supportedCollateralTokens;

    // Mapping to track if deposites are paused for a specific collateral token
    mapping(address => bool) public depositsPaused;

    // Mapping to track user collateral balances
    mapping(address => mapping(address => uint256))
        public userCollateralBalances;

    // Mapping to track the collateral tokens a user has deposited
    mapping(address => address[]) public userCollateralAssets;

    // Mapping to track total debt of each user (only principal)
    mapping(address => uint256) public userTotalDebt;

    // Track the last updated index of a user
    mapping(address => uint256) public lastUpdatedIndex;

    // List to track all collateral tokens
    address[] public collateralTokenList;

    // Events
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
        totalBorrows = 0;
        globalBorrowIndex = 1e18; // Set starting index value
        lastAccruedInterest = 0;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "Only contract owner can execute this function"
        );
        _;
    }

    // Function to update market parameters (only callable by owner)
    function setMarketParameters(
        uint256 _liquidationThreshold,
        uint256 _liquidationPenalty,
        uint256 _maxLTV,
        uint256 _minHealthFactor,
        uint256 _closeFactor, // Max % of a loan that can be liquidated at once
        uint256 _protocolFeeRate
    ) external onlyOwner {
        require(_liquidationThreshold <= 1e18, "Threshold too high");
        require(_liquidationPenalty <= 1e18, "Penalty too high");
        require(_maxLTV <= 1e18, "LTV too high");
        require(_minHealthFactor >= 1e18, "Health factor must be >= 1");

        marketParams = MarketParameters({
            liquidationThreshold: _liquidationThreshold,
            liquidationPenalty: _liquidationPenalty,
            maxLTV: _maxLTV,
            minHealthFactor: _minHealthFactor,
            closeFactor: _closeFactor,
            protocolFeeRate: _protocolFeeRate
        });
    }

    // Function to add a collateral token to the market
    function addCollateralToken(
        address collateralToken,
        address priceFeed
    ) external onlyOwner {
        require(
            collateralToken != address(0),
            "Invalid collateral token address"
        );
        require(
            !supportedCollateralTokens[collateralToken],
            "Collateral token already added"
        );
        require(priceFeed != address(0), "Invalid price feed address");

        // Mark the token as supported
        supportedCollateralTokens[collateralToken] = true;
        collateralTokenList.push(collateralToken); // Track the token

        // Set the price feed for the collateral token in the PriceOracle
        priceOracle.addPriceFeed(collateralToken, priceFeed);

        emit CollateralTokenAdded(collateralToken);
    }

    // Function to pause deposits for a collateral token
    function pauseCollateralDeposits(
        address collateralToken
    ) external onlyOwner {
        require(
            supportedCollateralTokens[collateralToken],
            "Token not supported"
        );
        depositsPaused[collateralToken] = true;
        emit CollateralDepositsPaused(collateralToken);
    }

    function resumeCollateralDeposits(
        address collateralToken
    ) external onlyOwner {
        require(
            supportedCollateralTokens[collateralToken],
            "Token not supported"
        );
        require(
            depositsPaused[collateralToken],
            "Deposits are already enabled"
        );

        depositsPaused[collateralToken] = false;
        emit CollateralDepositsResumed(collateralToken);
    }

    // Function to remove a collateral token from the market
    function removeCollateralToken(address collateralToken) external onlyOwner {
        require(
            supportedCollateralTokens[collateralToken],
            "Token not supported"
        );
        require(depositsPaused[collateralToken], "Must pause deposits first");
        require(
            _getTotalCollateralLocked(collateralToken) == 0,
            "Collateral still in use"
        );

        // Before removing collateral token, I'll need to make sure that no users are using token as collateral
        // Check if any collateral of this token is still locked in the contract
        uint256 totalCollateralInContract = _getTotalCollateralLocked(
            collateralToken
        );
        require(
            totalCollateralInContract == 0,
            "Collateral still in use by the system"
        );

        supportedCollateralTokens[collateralToken] = false;

        // Remove from collateralTokenList
        for (uint i = 0; i < collateralTokenList.length; i++) {
            if (collateralTokenList[i] == collateralToken) {
                collateralTokenList[i] = collateralTokenList[
                    collateralTokenList.length - 1
                ]; // Swap with last element
                collateralTokenList.pop(); // Remove last element
                break;
            }
        }

        emit CollateralTokenRemoved(collateralToken);
    }

    // Deposit collateral function
    function depositCollateral(
        address collateralToken,
        uint256 amount
    ) external nonReentrant {
        // Update borrow index before allowing any collateral-related changes,
        // ensure interest is accrued propoerly before chanhging user's position.
        _updateGlobalBorrowIndex();
        // Ensure the collateral token is supported (only whitelisted tokens).
        require(
            supportedCollateralTokens[collateralToken],
            "Collateral token not supported"
        );
        require(
            !depositsPaused[collateralToken],
            "Deposits are paused for this token"
        );
        require(amount > 0, "Deposit amount must be greater than zero");

        // Get the current total debt and collateral value
        uint256 currentDebt = _getUserTotalDebt(msg.sender);
        uint256 currentCollateralValue = _getUserTotalCollateralValue(
            msg.sender
        );

        // Simulate the new collateral value after adding the new collateral
        uint256 tokenValueInUSD = _getTokenValueInUSD(collateralToken, amount);
        uint256 simulatedNewCollateralValue = currentCollateralValue +
            tokenValueInUSD;

        // Calculate the simulated health factor after adding collateral
        uint256 simulatedHealthFactor = _getHealthFactor(
            msg.sender,
            currentDebt, // Debt doesn't change when adding collateral
            simulatedNewCollateralValue
        );

        // Ensure health factor is still safe (>= 1e18) after adding collateral.
        // Ensure's deposited token has value and is meaningful collateral
        // Ensure's the user's position does not become liquidatable immediately after deposit.
        require(
            simulatedHealthFactor >= 1e18,
            "Health factor too low after adding collateral"
        );

        // Transfer the collateral token from the user to the contract
        bool success = IERC20(collateralToken).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        require(success, "Transfer failed");

        // Update user's collateral balance for this contract
        userCollateralBalances[msg.sender][collateralToken] += amount;

        // If it's the first time depositing this token, add it to the user's collateral list
        if (userCollateralBalances[msg.sender][collateralToken] == amount) {
            userCollateralAssets[msg.sender].push(collateralToken);
        }

        // If the user has an active borrow position, update their lastUpdatedIndex for interest accounting
        if (userTotalDebt[msg.sender] > 0) {
            lastUpdatedIndex[msg.sender] = globalBorrowIndex;
        }

        // Emit an event for the deposit
        emit CollateralDeposited(msg.sender, collateralToken, amount);
    }

    function withdrawCollateral(
        address collateralToken,
        uint256 amount
    ) external nonReentrant {
        // Update borrow index before allowing any collateral-related changes
        _updateGlobalBorrowIndex();

        require(amount > 0, "Withdraw amount must be greater than zero");

        // Get the current user's collateral balance for the token
        uint256 currentCollateralBalance = userCollateralBalances[msg.sender][
            collateralToken
        ];
        require(currentCollateralBalance >= amount, "Insufficient collateral");

        // Ensure user is not undercollateralized after withdrawal
        require(
            _isWithdrawalAllowed(msg.sender, collateralToken, amount),
            "Withdrawal would cause undercollateralization"
        );

        // Get the current total debt of the user
        uint256 totalDebt = _getUserTotalDebt(msg.sender);

        // Get the current collateral value in USD (this is used to calculate health factor)
        uint256 currentCollateralValue = _getUserTotalCollateralValue(
            msg.sender
        );

        uint256 tokenValueInUSD = _getTokenValueInUSD(collateralToken, amount);

        // Simulate the new collateral value after the withdrawal
        uint256 newCollateralValue = currentCollateralValue - tokenValueInUSD;

        // Calculate the new health factor after the withdrawal using _getHealthFactor with simulatedDebt
        uint256 simulatedHealthFactorAfterWithdrawal = _getHealthFactor(
            msg.sender,
            totalDebt, // Use the current total debt (it doesn't change due to withdrawal)
            newCollateralValue
        );

        // Check if the health factor after withdrawal is still safe (>= 1e18)
        require(
            simulatedHealthFactorAfterWithdrawal >= 1e18,
            "Health factor too low after withdrawal"
        );

        // Transfer the collateral back to the user
        bool success = IERC20(collateralToken).transfer(msg.sender, amount);
        require(success, "Transfer failed");

        // Update user's collateral balance
        userCollateralBalances[msg.sender][collateralToken] -= amount;

        // If user has no more of this collateral, remove it from the collateral assets list
        if (userCollateralBalances[msg.sender][collateralToken] == 0) {
            _removeCollateralAsset(msg.sender, collateralToken);
        }

        // If the user has an active borrow position, update their lastUpdatedIndex
        if (userTotalDebt[msg.sender] > 0) {
            lastUpdatedIndex[msg.sender] = globalBorrowIndex;
        }

        emit CollateralWithdrawn(msg.sender, collateralToken, amount);
    }

    // Function to borrow
    function borrow(uint256 loanAmount) external nonReentrant {
        // Ensure the loan amount is valid
        require(loanAmount > 0, "Loan amount must be greater than zero");

        // Make sure the global borrow index reflects the latest state of the interest rate before any borrowing occurs
        _updateGlobalBorrowIndex();

        // Ensure the vault has enough liquidity to cover the loan amount
        // No borrower can borrow more than what the vault can actually lend, preventing over-borrowing
        uint256 availableLiquidity = vaultContract.totalIdle();
        require(
            loanAmount <= availableLiquidity,
            "Vault has insufficient liquidity for this loan"
        );

        // Calculates the maximum borrowing power by calling _maxBorrowingPower(), which internally calls
        // _getUserTotalDebt() and computes the total debt, including interest accrued, by calling _borrowerInterestAccrued()
        uint256 availableBorrowingPower = _maxBorrowingPower(msg.sender);

        // Ensure user has enough borrowing power to take this loan
        require(
            availableBorrowingPower >= loanAmount,
            "Not enough borrowing power to take this loan"
        );

        uint256 simulatedDebt = _getUserTotalDebt(msg.sender) + loanAmount;
        // Simulate the user's new collateral value (since collateral is unaffected by the loan itself)
        uint256 currentCollateralValue = _getUserTotalCollateralValue(
            msg.sender
        );
        uint256 healthFactor = _getHealthFactor(
            msg.sender,
            simulatedDebt,
            currentCollateralValue
        );
        require(healthFactor >= 1e18, "Health factor too low after");

        // Call Vault's adminBorrowFunction to withdraw funds to Market contract
        vaultContract.adminBorrow(loanAmount);

        // Transfer the loaned amount from the market to the user
        loanAsset.transfer(msg.sender, loanAmount);

        // Adding new debt (just principal)
        userTotalDebt[msg.sender] += loanAmount;

        // Update the total borrows
        totalBorrows += loanAmount;

        // Update the borrower's last interaction index to the current global borrow index
        lastUpdatedIndex[msg.sender] = globalBorrowIndex;

        emit Borrow(msg.sender, loanAmount);
    }

    function repay(uint256 repayAmount) external nonReentrant {
        // Ensure the repayment amount is valid
        require(repayAmount > 0, "Repayment amount must be greater than zero");

        // Ensure index is up to date before calculating anything related to the user's debt
        _updateGlobalBorrowIndex();

        // Ensure the repay amount covers at least the interest accrued
        uint256 interestAccrued = _borrowerInterestAccrued(msg.sender);
        require(
            repayAmount >= interestAccrued,
            "Repay amount must cover interest"
        );

        // Calculate the principal portion of the repayment
        uint256 principalRepayment = repayAmount - interestAccrued;

        // Calculate protocol share (on the interest portion only)
        uint256 protocolShare = (interestAccrued *
            marketParams.protocolFeeRate) / 1e18;

        // Net repayment to the vault after protocol fee (principal + lender share)
        uint256 netRepayToVault = repayAmount - protocolShare;

        // Update the borrower's total debt (including accrued interests) and ensure it doesn't go negative
        uint256 currentDebt = _getUserTotalDebt(msg.sender);
        require(repayAmount <= currentDebt, "Repayment exceeds debt");

        // Simulate the new debt after repayment (subtract the repayment amount)
        uint256 simulatedDebt = currentDebt - repayAmount;

        uint256 currentCollateralValue = _getUserTotalCollateralValue(
            msg.sender
        );

        // Simulate the new health factor after repayment
        uint256 simulatedHealthFactor = _getHealthFactor(
            msg.sender,
            simulatedDebt,
            currentCollateralValue
        );

        // Ensure health factor is still safe after repayment
        require(
            simulatedHealthFactor >= 1e18,
            "Health factor too low after repayment"
        );

        // Transfer tokens from the borrower to the market contract
        bool success = loanAsset.transferFrom(
            msg.sender,
            address(this),
            repayAmount
        );

        require(success, "Transfer failed: insufficient allowance or balance");

        // Pay the protocol fee (interest portion)
        bool protocolSuccess = loanAsset.transfer(
            protocolTreasury,
            protocolShare
        );
        require(protocolSuccess, "Protocol fee transfer failed");

        // Call Vault's adminRepayFunction to return funds to the Vault, excluding market fees
        vaultContract.adminRepay(netRepayToVault);

        require(
            totalBorrows >= principalRepayment,
            "Underflow in total borrows"
        );

        // Update total borrows (subtract only the principal portion)
        if (principalRepayment > 0) {
            require(totalBorrows >= principalRepayment, "Underflow");
            totalBorrows -= principalRepayment;
        }

        // Update the borrower’s debt and reduce only principal
        userTotalDebt[msg.sender] -= principalRepayment;

        // Update the borrower's last updated index to the current global borrow index
        lastUpdatedIndex[msg.sender] = globalBorrowIndex;

        emit Repay(msg.sender, repayAmount);
    }

    function liquidate(
        address user // The borrower being liquidated
    ) external {
        // Ensure index is up to date before calculating anything related to the user's debt
        _updateGlobalBorrowIndex();

        // Step 1: Validate and calculate liquidation parameters
        (
            uint256 debtToCover,
            uint256 collateralToLiquidateUsd
        ) = _validateAndCalculateLiquidation(user);

        // Step 2: Process repayment by liquidator
        _processLiquidatorRepayment(user, msg.sender, debtToCover);

        // Step 3: Seize collateral from the borrower
        (
            uint256 totalLiquidated,
            uint256 remainingToSeizeUsd
        ) = _seizeCollateral(user, msg.sender, collateralToLiquidateUsd);

        // Emit liquidation event
        emit Liquidation(
            user,
            msg.sender,
            debtToCover,
            totalLiquidated,
            remainingToSeizeUsd
        );
    }

    // ======= HELPER FUNCTIONS ========

    // Helper function to check total collateral locked in the contract
    function _getTotalCollateralLocked(
        address collateralToken
    ) public view returns (uint256 totalCollateral) {
        totalCollateral = IERC20(collateralToken).balanceOf(address(this)); // Get the contract's balance
    }

    // Helper function to calculate how much a user can borrow based on the value of their
    // collateral and the Loan-to-Value (LTV) ratio. Borrowing Power in USD
    function _getUserTotalBorrowingPower(
        address user
    ) public view returns (uint256 totalBorrowingPower) {
        totalBorrowingPower = 0;

        // Loop through all tracked collateral tokens
        for (uint i = 0; i < collateralTokenList.length; i++) {
            address token = collateralTokenList[i];

            // If user has collateral in this token
            uint256 collateralAmount = userCollateralBalances[user][token];
            if (collateralAmount > 0) {
                // Use the max LTV ratio from market parameters (applies uniformly across all tokens)
                uint256 ltv = marketParams.maxLTV;
                uint256 collateralValue = _getTokenValueInUSD(
                    token,
                    collateralAmount
                );
                totalBorrowingPower += (collateralValue * ltv) / 1e18;
            }
        }
        return totalBorrowingPower;
    }

    // function calculates the total value of the User's Collateral in USD
    function _getUserTotalCollateralValue(
        address user
    ) internal view returns (uint256) {
        uint256 totalCollateralValue = 0;

        for (uint256 i = 0; i < collateralTokenList.length; i++) {
            address token = collateralTokenList[i];
            uint256 userBalance = userCollateralBalances[user][token];

            // Calculate the collateral value in the native asset's value (USD, for example)
            uint256 collateralValue = _getTokenValueInUSD(token, userBalance); // Adjust for decimals

            totalCollateralValue += collateralValue;
        }

        return totalCollateralValue;
    }

    function _getHealthFactor(
        address user,
        uint256 userDebt, // User debt after borrowing or other operations
        uint256 userCollateralValue // collateral value (in USD)
    ) internal view returns (uint256) {
        uint256 collateralValueInUSD = _getUserTotalCollateralValue(user);
        uint256 liquidationThreshold = marketParams.liquidationThreshold; // Get liquidation threshold

        // Weighted collateral value based on its liquidation threshold
        uint256 totalCollateralValue = (collateralValueInUSD *
            liquidationThreshold) / 1e18;

        uint256 totalDebt = userDebt > 0 ? userDebt : _getUserTotalDebt(user);

        // Convert debt (in native units) to USD
        uint256 totalDebtInUSD = _getLoanDebtInUSD(totalDebt);

        if (totalDebtInUSD == 0) {
            return type(uint256).max; // Infinite health
        }

        return (totalCollateralValue * 1e18) / totalDebtInUSD;
    }

    // Helper function to ensure that withdrawing collateral does not leave the user undercollateralized.
    function _isWithdrawalAllowed(
        address user,
        address collateralToken,
        uint256 amount
    ) internal returns (bool) {
        require(
            supportedCollateralTokens[collateralToken],
            "Token not supported"
        );
        require(
            userCollateralBalances[user][collateralToken] >= amount,
            "Insufficient balance"
        );

        // Update global borrow index to ensure interest rates are up-to-date
        _updateGlobalBorrowIndex();

        // Get the user's current borrowing power
        uint256 totalBorrowingPower = _getUserTotalBorrowingPower(user);

        // Get user's total outstanding debt in USD
        uint256 totalDebtNative = _getUserTotalDebt(user);
        uint256 totalDebt = _getLoanDebtInUSD(totalDebtNative); // debt calculated in USD terms

        // Get the LTV and price of collateral token
        uint256 ltv = marketParams.maxLTV;

        // Calculate the USD value of the withdrawing collateral
        uint256 collateralValue = _getTokenValueInUSD(collateralToken, amount);
        uint256 withdrawalValue = (collateralValue * ltv) / 100;

        // Compute new borrowing power after withdrawal
        uint256 newBorrowingPower = totalBorrowingPower > withdrawalValue
            ? totalBorrowingPower - withdrawalValue
            : 0;

        // Ensure user still has enough borrowing power to cover debt
        require(
            newBorrowingPower >= totalDebt,
            "Insufficient collateral to cover debt"
        );

        return true; // If all conditions are met, the withdrawal is allowed.
    }

    // Helper function to calculate the total debt for a user, including accrued interest
    function _getUserTotalDebt(
        address user
    ) public view returns (uint256 totalDebt) {
        // Fetch the stored debt from the mapping
        uint256 storedDebt = userTotalDebt[user];

        // If the user has no debt, return 0
        if (storedDebt == 0) {
            return 0;
        }

        // Calculate the interest accrued since the last update
        uint256 interestAccrued = _borrowerInterestAccrued(user);

        // Add the interest to the stored debt
        totalDebt = storedDebt + interestAccrued;

        return totalDebt;
    }

    // Helper function to calculate the maximum borrowing capacity of a user
    function _maxBorrowingPower(address user) internal returns (uint256) {
        // Update the global borrow index to ensure the interest rates are up to date
        _updateGlobalBorrowIndex();

        uint256 borrowingPower = _getUserTotalBorrowingPower(user);

        uint256 totalDebtNative = _getUserTotalDebt(user);
        uint256 totalDebt = _getLoanDebtInUSD(totalDebtNative); // debt in USD terms

        // Ensure borrowing power is not negative
        require(
            borrowingPower >= totalDebt,
            "Negative borrowing power detected"
        );

        uint256 maxBorrowingPower = borrowingPower - totalDebt;
        return maxBorrowingPower;
    }

    // Helper function to calculate accrued interest on a debt considering dynamic rates
    function _borrowerInterestAccrued(
        address borrower
    ) public view returns (uint256) {
        // If the borrower has not borrowed or no debt is recorded, return 0
        if (userTotalDebt[borrower] == 0 || lastUpdatedIndex[borrower] == 0) {
            return 0;
        }

        // Get the borrower's last known index and the current global borrow index
        uint256 lastBorrowerIndex = lastUpdatedIndex[borrower];
        uint256 currentGlobalIndex = globalBorrowIndex;

        // Interest accrued is the difference in indices multiplied by the borrower's debt
        uint256 interestAccrued = (userTotalDebt[borrower] *
            (currentGlobalIndex - lastBorrowerIndex)) / 1e18;

        return interestAccrued;
    }

    // Function to update the global borrow index and the total interest accrued for the whole market
    function _updateGlobalBorrowIndex() private {
        // Get the current timestamp
        uint256 currentTimestamp = block.timestamp;

        // On first ever call, initialize lastAccrualTimestamp
        if (lastAccrualTimestamp == 0) {
            lastAccrualTimestamp = currentTimestamp;
            return;
        }

        // Calculate time elapsed
        uint256 timeElapsed = currentTimestamp - lastAccrualTimestamp;
        if (timeElapsed == 0) {
            return; // No time passed, no update needed
        }

        uint256 totalBorrowed = totalBorrows; // Total outstanding borrows
        uint256 totalSupply = vaultContract.totalAssets(); // Total assets backing the system

        // If no borrows or no liquidity, interest accrual doesn't make sense — just skip
        if (totalBorrowed == 0 || totalSupply == 0) {
            return;
        }

        // Store current global borrow index before updating
        uint256 previousGlobalBorrowIndex = globalBorrowIndex;

        // Get the current dynamic borrow rate. Reflects current utilization rate (borrowed/supplied).
        uint256 dynamicBorrowRate = interestRateModel.getDynamicBorrowRate(); // This is an annualized rate (scaled by 1e18)

        // Scale the interest rate based on time elapsed (seconds), to match the actual time the loan was held.
        // Formula: effectiveRate = dynamicRate * timeElapsed / secondsPerYear
        uint256 secondsPerYear = 365 days; // or 31,536,000 seconds
        uint256 effectiveRate = (dynamicBorrowRate * timeElapsed) /
            secondsPerYear;

        // Calculate the new global borrow index
        uint256 newGlobalBorrowIndex = (previousGlobalBorrowIndex *
            (1e18 + effectiveRate)) / 1e18;

        // If the new index equals the previous index, skip updating
        if (newGlobalBorrowIndex == previousGlobalBorrowIndex) {
            lastAccrualTimestamp = currentTimestamp; // Still update timestamp
            return;
        }

        // Set the new global borrow index
        globalBorrowIndex = newGlobalBorrowIndex;

        // Update last accrual timestamp
        lastAccrualTimestamp = currentTimestamp;
    }

    // Function to calculate total borrows plus accrued interest
    function _lentAssets() public view returns (uint256) {
        uint256 totalBorrowed = totalBorrows;
        if (totalBorrowed == 0) {
            return 0; // No borrowings, no interest
        }
        // totalBorrows is just the principal; multiply by globalBorrowIndex to include accrued interest
        uint256 totalWithInterest = (totalBorrows * globalBorrowIndex) / 1e18;

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
        // Get the token's price in USD using the price oracle (assuming the oracle returns price with 8 decimals)
        int256 tokenPrice = priceOracle.getLatestPrice(collateralToken);
        uint256 scaledPrice = uint256(tokenPrice) * 1e10; // Scale price to 18 decimals
        require(scaledPrice > 0, "Invalid token price from Oracle");

        // Convert the withdrawn amount to USD (token's value in USD)
        uint256 tokenValueInUSD = (amount * scaledPrice) / 1e18; // Assuming 8 decimal places for price feeds

        return tokenValueInUSD;
    }

    // Function to calculate loan asset in USD terms
    function _getLoanDebtInUSD(uint256 amount) internal view returns (uint256) {
        // Get the loan asset's price from oracle (e.g., ETH/USD = 3000 * 1e8)
        int256 tokenPrice = priceOracle.getLatestPrice(address(loanAsset));
        uint256 scaledPrice = uint256(tokenPrice) * 1e10; // Scale to 18 decimals
        require(scaledPrice > 0, "Invalid token price from Oracle");

        // Convert debt amount to USD (same logic as collateral)
        uint256 debtInUSD = (amount * scaledPrice) / 1e18;

        return debtInUSD;
    }

    // Helper function to validate and calculate liquidation
    function _validateAndCalculateLiquidation(
        address user
    )
        internal
        view
        returns (uint256 debtToCover, uint256 collateralToLiquidateUsd)
    {
        uint256 totalDebt = _getUserTotalDebt(user);
        uint256 totalCollateral = _getUserTotalCollateralValue(user);

        uint256 healthFactor = _getHealthFactor(
            user,
            totalDebt,
            totalCollateral
        );
        require(healthFactor < 1e18, "User not eligible for liquidation");

        uint256 minHealthFactor = marketParams.minHealthFactor;
        uint256 buffer = marketParams.liquidationPenalty;
        uint256 adjustedMinHealthFactor = (minHealthFactor * (1e18 + buffer)) /
            1e18;

        uint256 targetDebt = (totalCollateral *
            marketParams.liquidationThreshold) / adjustedMinHealthFactor;

        require(
            targetDebt < totalDebt,
            "Loan is already healthy or overcollateralized"
        );

        // Amount of debt that needs to be covered (liquidated)
        debtToCover = totalDebt - targetDebt;
        uint256 liquidationPenalty = marketParams.liquidationPenalty;

        // Calculates the collateral in USD, including the liquidation penalty
        collateralToLiquidateUsd =
            (debtToCover * (1e18 + liquidationPenalty)) /
            1e18;

        require(
            collateralToLiquidateUsd <= totalCollateral,
            "Not enough collateral to liquidate"
        );
    }

    // Helper function to process liquidation repayment
    function _processLiquidatorRepayment(
        address borrower, // The borrower whose debt is being reduced
        address liquidator, // The user paying the debt
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

        // Calculate interest accrued at this point
        uint256 interestAccrued = _borrowerInterestAccrued(borrower);

        // Calculate protocol share (on the interest portion only)
        uint256 protocolShare = (interestAccrued *
            marketParams.protocolFeeRate) / 1e18;

        // Net repayment to the vault after protocol fee (principal + lender share)
        uint256 netRepayToVault = debtToCover - protocolShare;

        // Pay the protocol fee (interest portion = 10% fees)
        bool protocolSuccess = loanAsset.transfer(
            protocolTreasury,
            protocolShare
        );
        require(protocolSuccess, "Protocol fee transfer failed");

        // Return to vault assets (principal + interests (lender fees = 90%))
        vaultContract.adminRepay(netRepayToVault);

        // Principal portion of the debt being covered
        uint256 principalRepayment = debtToCover > interestAccrued
            ? debtToCover - interestAccrued
            : 0;

        // Reduce user's debt and platform total borrows by principal repayment
        userTotalDebt[borrower] -= principalRepayment;
        totalBorrows -= principalRepayment;

        // Update borrower's last index to reflect sync
        lastUpdatedIndex[borrower] = globalBorrowIndex;
    }

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

        int256 tokenPriceUsd = priceOracle.getLatestPrice(token);
        uint256 scaledPrice = uint256(tokenPriceUsd) * 1e10;

        uint256 tokenAmountToSeize = (usdToSeize * 1e18 + scaledPrice - 1) /
            scaledPrice;

        userCollateralBalances[user][token] -= tokenAmountToSeize;

        require(
            IERC20(token).transfer(liquidator, tokenAmountToSeize),
            "Collateral transfer failed"
        );

        return usdToSeize;
    }

    // Function to seize liquidated collateral
    function _seizeCollateral(
        address user,
        address liquidator,
        uint256 collateralToLiquidateUsd
    ) internal returns (uint256 totalLiquidated, uint256 remainingToSeizeUsd) {
        address[] memory collateralTokens = userCollateralAssets[user];
        remainingToSeizeUsd = collateralToLiquidateUsd;
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

    function getHealthFactor(
        address user,
        uint256 userDebt, // debt after borrowing or other operations
        uint256 userCollateralValue //collateral value (in USD)
    ) public view returns (uint256) {
        return _getHealthFactor(user, userDebt, userCollateralValue);
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

    function _loanDebtInUSD(uint256 amount) external returns (uint256) {
        return _getLoanDebtInUSD(amount);
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
