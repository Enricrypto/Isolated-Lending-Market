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

    // List to track all collateral tokens
    address[] public collateralTokenList;

    // Events
    event CollateralTokenAdded(address indexed collateralToken, uint256 ltv);
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
    event Borrow(address indexed user, uint256 loanAmount);
    event Repay(address indexed user, uint256 amountRepaid);
    event LogAddress(address);

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
        emit LogAddress(owner);
    }

    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "Only contract owner can execute this function"
        );
        _;
    }

    // Function to set the LTV ratio for a collateral token (only admin)
    function _setLTVRatio(address collateralToken, uint256 ltv) internal {
        require(
            supportedCollateralTokens[collateralToken],
            "Token not supported"
        );
        require(ltv > 0 && ltv <= 100, "Invalid LTV ratio"); // Ensure LTV is between 1-100%

        ltvRatios[collateralToken] = ltv;

        emit LTVRatioSet(collateralToken, ltv);
    }

    function setLTVRatio(
        address collateralToken,
        uint256 ltv
    ) external onlyOwner {
        return _setLTVRatio(collateralToken, ltv);
    }

    // Function to add a collateral token to the market
    function addCollateralToken(
        address collateralToken,
        address priceFeed,
        uint256 ltv
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

        // Set LTV ratio using the existing function
        _setLTVRatio(collateralToken, ltv);

        emit CollateralTokenAdded(collateralToken, ltv);
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
        require(
            supportedCollateralTokens[collateralToken],
            "Collateral token not supported"
        );
        require(amount > 0, "Withdraw amount must be greater than zero");

        // Ensure the user has enough balance to withdraw
        require(
            userCollateralBalances[msg.sender][collateralToken] >= amount,
            "Insufficient collateral balance"
        );

        // Ensure user is not undercollateralized after withdrawal
        require(
            _isWithdrawalAllowed(msg.sender, collateralToken, amount),
            "Withdrawal would cause undercollateralization"
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
        uint256 userDebt = userTotalDebt[msg.sender];
        require(repayAmount <= userDebt, "Repayment exceeds debt");

        // Transfer tokens from the borrower to the market contract
        bool success = loanAsset.transferFrom(
            msg.sender,
            address(this),
            repayAmount
        );

        require(success, "Transfer failed: insufficient allowance or balance");

        // Call Vault's adminRepayFunction to return funds to the Vault
        vaultContract.adminRepay(repayAmount);

        // Update total borrows (subtract only the principal portion)
        require(
            totalBorrows >= principalRepayment,
            "Underflow in total borrows"
        );
        totalBorrows -= principalRepayment;

        // Update the borrower’s debt
        userTotalDebt[msg.sender] -= repayAmount;

        // Update the borrower's last updated index to the current global borrow index
        lastUpdatedIndex[msg.sender] = globalBorrowIndex;

        emit Repay(msg.sender, repayAmount);
    }

    // ======= HELPER FUNCTIONS ========

    // Helper function to check total collateral locked in the contract
    function _getTotalCollateralLocked(
        address collateralToken
    ) public view returns (uint256 totalCollateral) {
        totalCollateral = IERC20(collateralToken).balanceOf(address(this)); // Get the contract's balance
    }

    // Helper function to calculate total borrowable value of a user's collateral
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
                int256 tokenPrice = priceOracle.getLatestPrice(token);
                require(tokenPrice > 0, "Invalid price from Oracle");
                uint256 collateralValue = (collateralAmount *
                    uint256(tokenPrice)) / 1e8; // 8 decimal places (used by Chainlink price feeds)
                totalBorrowingPower += (collateralValue * ltv) / 100;
            }
        }
        return totalBorrowingPower;
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
        int256 tokenPrice = priceOracle.getLatestPrice(collateralToken);
        require(tokenPrice > 0, "Invalid price from oracle");

        // Calculate the USD value of the withdrawing collateral
        uint256 collateralValue = (amount * uint256(tokenPrice)) / 1e8;
        uint256 withdrawalValue = (collateralValue * ltv) / 100;

        // Compute new borrowing power after withdrawal
        uint256 newBorrowingPower = totalBorrowingPower > withdrawalValue
            ? totalBorrowingPower - withdrawalValue
            : 0;

        // Ensure user still has enough borrowing power to cover debt
        return newBorrowingPower >= totalDebt;
    }

    // Helper function to calculate the total debt for a user
    function _getUserTotalDebt(
        address user
    ) public view returns (uint256 totalDebt) {
        // Fetch the user's total debt (principal)
        uint256 principalDebt = userTotalDebt[user];

        // Fetch the accrued interest using the borrower's interest calculation function
        uint256 interestAccrued = _borrowerInterestAccrued(user);

        // Total debt is the sum of the principal debt and accrued interest
        totalDebt = principalDebt + interestAccrued;

        return totalDebt;
    }

    // Helper function to calculate the maximum borrowing power of a user
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
}
