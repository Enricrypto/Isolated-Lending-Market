// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "./Vault.sol";
import "./PriceOracle.sol";
import "./InterestRateModel.sol";

contract Market is ReentrancyGuard {
    address public owner; // Admin address
    Vault public vaultContract;
    PriceOracle public priceOracle;
    InterestRateModel public interestRateModel;
    IERC20 public loanAsset;

    // Tracks total borrowed amount for the loan asset
    uint256 public totalBorrows;

    // Total Interest Accrued
    uint256 public lastAccruedInterest;

    // Global borrow index
    uint256 public globalBorrowIndex; // Start with an initial index value, no interest has accrued yet.

    // Track the last time where the global borrow index was updated
    uint256 public lastGlobalUpdateTime;

    // Mapping to track the supported collateral tokens
    mapping(address => bool) public supportedCollateralTokens;

    // Mapping to track if deposites are paused for a specific collateral token
    mapping(address => bool) public depositsPaused;

    // Mapping to track user collateral balances
    mapping(address => mapping(address => uint256))
        public userCollateralBalances;

    // Mapping to track the collateral tokens a user has deposited
    mapping(address => address[]) public userCollateralAssets;

    // Mapping to track total debt of each user
    mapping(address => uint256) public userTotalDebt;

    // Track the last updated index of a user
    mapping(address => uint256) public lastUpdatedIndex;

    // Mapping to store the LTV ratio for each collateral token
    mapping(address => uint256) public ltvRatios;

    // Mapping to store the liquidation threshold for each collateral token
    mapping(address => uint256) public liquidationThresholds;

    // List to track all collateral tokens
    address[] public collateralTokenList;

    // Events
    event CollateralTokenAdded(
        address indexed collateralToken,
        uint256 ltv,
        uint256 threshold
    );
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
    event LTVRatioSet(address indexed collateralToken, uint256 ltvRatio);
    event LiquidationThresholdSet(address collateralToken, uint256 threshold);
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
        uint256 collateralToLiquidate
    );

    constructor(
        address _vaultContract,
        address _priceOracle,
        address _interestRateModel,
        address _loanAsset
    ) {
        vaultContract = Vault(_vaultContract);
        priceOracle = PriceOracle(_priceOracle);
        interestRateModel = InterestRateModel(_interestRateModel);
        loanAsset = IERC20(_loanAsset);
        totalBorrows = 0;
        globalBorrowIndex = 1e18; // Set starting index value
        lastGlobalUpdateTime = block.timestamp;
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

    // Function to set the LTV ratio for a collateral token (only admin)
    function _setLTVRatio(
        address collateralToken,
        uint256 ltv
    ) internal onlyOwner {
        require(
            supportedCollateralTokens[collateralToken],
            "Token not supported"
        );
        require(ltv > 0 && ltv <= 100, "Invalid LTV ratio"); // Ensure LTV is between 1-100%

        ltvRatios[collateralToken] = ltv;

        emit LTVRatioSet(collateralToken, ltv);
    }

    function _setLiquidationThreshold(
        address collateralToken,
        uint256 threshold
    ) internal {
        require(
            supportedCollateralTokens[collateralToken],
            "Token not supported"
        );
        require(
            threshold > 0 && threshold <= 100,
            "Invalid liquidation threshold"
        );

        liquidationThresholds[collateralToken] = threshold;

        emit LiquidationThresholdSet(collateralToken, threshold);
    }

    // Function to add a collateral token to the market
    function addCollateralToken(
        address collateralToken,
        address priceFeed,
        uint256 ltv,
        uint256 liquidationThreshold
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
        require(
            liquidationThreshold >= ltv,
            "Liquidation threshold must be >= LTV"
        );

        // Mark the token as supported
        supportedCollateralTokens[collateralToken] = true;
        collateralTokenList.push(collateralToken); // Track the token

        // Set the price feed for the collateral token in the PriceOracle
        priceOracle.addPriceFeed(collateralToken, priceFeed);

        // Set LTV ratio using the existing function
        _setLTVRatio(collateralToken, ltv);

        // Set liquidation threshold
        _setLiquidationThreshold(collateralToken, liquidationThreshold);

        emit CollateralTokenAdded(collateralToken, ltv, liquidationThreshold);
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

        // TO-DO: before removing collateral token, I'll need to make sure that no users are using token as collateral
        // Check if any collateral of this token is still locked in the contract
        uint256 totalCollateralInContract = _getTotalCollateralLocked(
            collateralToken
        );
        require(
            totalCollateralInContract == 0,
            "Collateral still in use by the system"
        );

        supportedCollateralTokens[collateralToken] = false;
        delete ltvRatios[collateralToken]; // Remove its LTV entry

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
        // Update borrow index before allowing any collateral-related changes
        _updateInterestGlobalBorrowIndex();
        // Ensure the collateral token is supported
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

        // Ensure health factor is still safe (>= 1e18) after adding collateral
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

        // If the user has an active borrow position, update their lastUpdatedIndex
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
        _updateInterestGlobalBorrowIndex();

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
        _updateInterestGlobalBorrowIndex();

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
        require(healthFactor >= 1e18, "Health factor too low");

        // Call Vault's adminBorrowFunction to withdraw funds to Market contract
        vaultContract.adminBorrow(loanAmount);

        // Transfer the loaned amount from the market to the user
        loanAsset.transfer(msg.sender, loanAmount);

        // Adding new debt
        if (userTotalDebt[msg.sender] == 0) {
            // First-time borrower
            userTotalDebt[msg.sender] = loanAmount;
        } else {
            // Existing borrower: Add new loan + interest accrued
            uint256 interestAccrued = _borrowerInterestAccrued(msg.sender);
            userTotalDebt[msg.sender] += loanAmount + interestAccrued;
        }

        // Update the borrower's last interaction index to the current global borrow index
        lastUpdatedIndex[msg.sender] = globalBorrowIndex;

        // Update the total borrows
        totalBorrows += loanAmount;

        emit Borrow(msg.sender, loanAmount);
    }

    function repay(uint256 repayAmount) external nonReentrant {
        // Ensure the repayment amount is valid
        require(repayAmount > 0, "Repayment amount must be greater than zero");

        // Ensure index is up to date before calculating anything related to the user's debt
        _updateInterestGlobalBorrowIndex();

        // Ensure the repay amount covers at least the interest accrued
        uint256 interestAccrued = _borrowerInterestAccrued(msg.sender);
        require(
            repayAmount >= interestAccrued,
            "Repay amount must cover interest"
        );

        // Calculate the principal portion of the repayment
        uint256 principalRepayment = repayAmount - interestAccrued;

        // Update the borrower's total debt and ensure it doesn't go negative
        uint256 currentDebt = _getUserTotalDebt(msg.sender);
        require(repayAmount <= currentDebt, "Repayment exceeds debt");

        uint256 currentCollateralValue = _getUserTotalCollateralValue(
            msg.sender
        );

        // Simulate the new debt after repayment (subtract the repayment amount)
        uint256 simulatedDebt = currentDebt - repayAmount;

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

        // Call Vault's adminRepayFunction to return funds to the Vault
        vaultContract.adminRepay(repayAmount);

        require(
            totalBorrows >= principalRepayment,
            "Underflow in total borrows"
        );

        // Update total borrows (subtract only the principal portion)
        totalBorrows -= principalRepayment;

        // Update the borrower’s debt
        userTotalDebt[msg.sender] -= repayAmount;

        // Update the borrower's last updated index to the current global borrow index
        lastUpdatedIndex[msg.sender] = globalBorrowIndex;

        emit Repay(msg.sender, repayAmount);
    }

    function liquidate(
        address user, // The borrower being liquidated
        address[] memory collateralTokens // Array of collateral tokens to liquidate (optional)
    ) external {
        // Get the user's total debt and collateral value
        uint256 totalDebt = _getUserTotalDebt(user);
        uint256 totalCollateral = _getUserTotalCollateralValue(user);

        uint256 healthFactor = _getHealthFactor(
            user,
            totalDebt,
            totalCollateral
        );
        require(healthFactor < 1e18, "User not eligible for liquidation");

        // Calculate the target debt after liquidation (health factor >= 1.1)
        uint256 safeHealthFactor = 1.1e18;
        uint256 targetDebt = (totalCollateral * 1e18) / safeHealthFactor;

        uint256 debtToCover = totalDebt - targetDebt;
        require(debtToCover > 0, "Loan is already healthy"); // Prevent unnecessary liquidation

        // Apply the liquidation penalty to determine collateral required
        uint256 liquidationPenalty = 5; // 5% penalty
        uint256 collateralToLiquidate = (debtToCover *
            (100 + liquidationPenalty)) / 100;

        // Ensure there is enough collateral to cover liquidation
        require(
            collateralToLiquidate <= totalCollateral,
            "Not enough collateral to liquidate"
        );

        // Liquidate collateral (across all or specified collateral tokens)
        if (collateralTokens.length == 0) {
            // Liquidate across all collateral
            for (uint256 i = 0; i < collateralTokenList.length; i++) {
                address token = collateralTokenList[i];
                uint256 portion = _calculateCollateralToLiquidate(
                    user,
                    token,
                    collateralToLiquidate // Amount including the penalty
                );
                _transferCollateral(user, msg.sender, portion, token);
            }
        } else {
            // Liquidate only the chosen collateral tokens
            uint256 remainingDebt = collateralToLiquidate;
            for (uint256 i = 0; i < collateralTokens.length; i++) {
                address token = collateralTokens[i];

                if (remainingDebt == 0) break; // Stop if the debt is fully covered

                uint256 portion = _calculateCollateralToLiquidate(
                    user,
                    token,
                    remainingDebt // Amount including the penalty
                );
                _transferCollateral(user, msg.sender, portion, token);

                // Reduce remaining debt based on transferred collateral
                remainingDebt -= _getTokenValueInUSD(token, portion);
            }
        }

        // Reduce the borrower's debt
        userTotalDebt[user] -= debtToCover; // Pay off the covered debt

        emit Liquidation(user, msg.sender, debtToCover, collateralToLiquidate);
    }

    // ======= HELPER FUNCTIONS ========

    // Helper function to check total collateral locked in the contract
    function _getTotalCollateralLocked(
        address collateralToken
    ) public view returns (uint256 totalCollateral) {
        totalCollateral = IERC20(collateralToken).balanceOf(address(this)); // Get the contract's balance
    }

    // Helper function to calculate how much a user can borrow based on the value of their
    // collateral and the Loan-to-Value (LTV) ratio.
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
                uint256 ltv = ltvRatios[token]; // Get LTV ratio
                uint256 collateralValue = _getTokenValueInUSD(
                    token,
                    collateralAmount
                );
                totalBorrowingPower += (collateralValue * ltv) / 100;
            }
        }
        return totalBorrowingPower;
    }

    // function calculates the total value of the user's collateral in USD
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

    // View function to expose user total collateral value calculation
    function getUserTotalCollateralValue(
        address user
    ) public view returns (uint256) {
        return _getUserTotalCollateralValue(user);
    }

    function _getHealthFactor(
        address user,
        uint256 userDebt, // User debt after borrowing or other operations
        uint256 userCollateralValue // collateral value (in USD)
    ) internal view returns (uint256) {
        uint256 totalCollateralValue = 0;

        // Loop through all collateral tokens the user has deposited
        for (uint256 i = 0; i < collateralTokenList.length; i++) {
            address token = collateralTokenList[i];

            uint256 userBalance = userCollateralBalances[user][token];
            if (userBalance == 0) continue; // Skip tokens with no deposit

            uint256 collateralValue = _getTokenValueInUSD(token, userBalance); // Convert token amount to USD
            uint256 liquidationThreshold = liquidationThresholds[token]; // Get liquidation threshold (e.g., 80 for 80%)

            // Weighted collateral value based on its liquidation threshold
            totalCollateralValue +=
                (collateralValue * liquidationThreshold) /
                100;
        }

        uint256 totalDebt = userDebt > 0 ? userDebt : _getUserTotalDebt(user);
        if (totalDebt == 0) {
            return type(uint256).max; // Infinite health if no debt
        }

        // Compute the final health factor
        return (totalCollateralValue * 1e18) / totalDebt;
    }

    // View function to expose health factor calculation
    function getHealthFactor(
        address user,
        uint256 userDebt, // debt after borrowing or other operations
        uint256 userCollateralValue //collateral value (in USD)
    ) public view returns (uint256) {
        return _getHealthFactor(user, userDebt, userCollateralValue);
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
        _updateInterestGlobalBorrowIndex();

        // Get the user's current borrowing power
        uint256 totalBorrowingPower = _getUserTotalBorrowingPower(user);

        // Get user's total outstanding debt
        uint256 totalDebt = _getUserTotalDebt(user);

        // Get the LTV and price of collateral token
        uint256 ltv = ltvRatios[collateralToken];

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
        _updateInterestGlobalBorrowIndex();

        uint256 borrowingPower = _getUserTotalBorrowingPower(user);
        uint256 totalDebt = _getUserTotalDebt(user);

        // Ensure borrowing power is not negative
        require(
            borrowingPower >= totalDebt,
            "Negative borrowing power detected"
        );

        uint256 maxBorrowingPower = borrowingPower - totalDebt;
        return maxBorrowingPower;
    }

    // External function to expose max borrowing power calculation
    function _getMaxBorrowingPower(address user) external returns (uint256) {
        return _maxBorrowingPower(user);
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
    function _updateInterestGlobalBorrowIndex() private {
        // Get the current total borrows and total supply in the system
        uint256 totalBorrowed = totalBorrows; // Total amount of borrows in the system
        uint256 totalSupply = vaultContract.totalAssets(); // Total amount of assets in the system

        // Prevent division by zero
        if (totalBorrowed == 0 || totalSupply == 0) {
            return;
        }

        // Store the current global borrow index before the update
        uint256 previousGlobalBorrowIndex = globalBorrowIndex;

        // Get the current dynamic borrow rate (based on utilization rate)
        uint256 dynamicBorrowRate = interestRateModel.getDynamicBorrowRate(); // This is already based on utilization

        // Calculate the interest accrued as a function of utilization-driven rate
        uint256 interestAccrued = (dynamicBorrowRate * totalBorrowed) / 1e18;

        // Calculate the new global borrow index (previousIndex + increment)
        uint256 newGlobalBorrowIndex = previousGlobalBorrowIndex +
            ((previousGlobalBorrowIndex * interestAccrued) / totalSupply);

        // If the new index equals the previous index, skip updating
        if (newGlobalBorrowIndex == previousGlobalBorrowIndex) {
            return;
        }

        // Update the total interest accrued for the platform
        lastAccruedInterest += interestAccrued;

        // Set the new global borrow index
        globalBorrowIndex = newGlobalBorrowIndex;
    }

    function updateInterestAndGlobalBorrowIndex() external {
        _updateInterestGlobalBorrowIndex();
    }

    // Function to calculate total borrows plus accrued interest
    function _lentAssets() public view returns (uint256) {
        uint256 totalBorrowed = totalBorrows;
        if (totalBorrowed == 0) {
            return 0; // No borrowings, no interest
        }
        return totalBorrowed;
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

    // External function to expose _getTokenValueInUSD to the public
    function getTokenValueInUSD(
        address collateralToken,
        uint256 amount
    ) external view returns (uint256) {
        return _getTokenValueInUSD(collateralToken, amount);
    }

    // This function determines the amount of collateral to transfer to the liquidator for the given debt.
    function _calculateCollateralToLiquidate(
        address user,
        address token,
        uint256 debtToCover
    ) internal view returns (uint256) {
        // Get the value of 1 whole token in USD (price per token)
        uint256 pricePerTokenInUSD = _getTokenValueInUSD(token, 1e18);
        require(pricePerTokenInUSD > 0, "Invalid price");

        uint256 userCollateralBalance = userCollateralBalances[user][token]; // User's collateral balance

        // Convert the debt to the equivalent collateral amount (in token units)
        uint256 collateralEquivalent = (debtToCover * 1e18) /
            pricePerTokenInUSD;

        // Ensure we don't take more than the user's actual balance
        return
            collateralEquivalent > userCollateralBalance
                ? userCollateralBalance
                : collateralEquivalent;
    }

    function _transferCollateral(
        address borrower,
        address liquidator,
        uint256 amountToLiquidate,
        address collateralToken
    ) internal {
        uint256 userBalance = userCollateralBalances[borrower][collateralToken];
        require(userBalance >= amountToLiquidate, "Insufficient collateral");

        // Reduce the borrower's collateral balance
        userCollateralBalances[borrower][collateralToken] -= amountToLiquidate;

        // Transfer collateral from contract (market) to the liquidator
        IERC20(collateralToken).transfer(liquidator, amountToLiquidate);

        emit CollateralLiquidated(
            borrower,
            liquidator,
            collateralToken,
            amountToLiquidate
        );
    }
}
