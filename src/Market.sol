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

    // Global borrow index
    uint256 public globalBorrowIndex = 1e18; // Start with an initial index value, no interest has accrued yet.

    // Track the last block where the global borrow index was updated
    uint256 public lastGlobalUpdateBlock;

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

    // Track the last block number each user took a loan
    mapping(address => uint256) public lastUpdatedBlock;

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
    event Borrow(address indexed user, uint256 loanAmount, uint256 borrowRate);
    event Repay(
        address indexed user,
        uint256 amountRepaid,
        uint256 collateralReturned
    );

    constructor(
        address _vaultContract,
        address _priceOracle,
        address _interestRateModel,
        address _loanAsset
    ) {
        owner = msg.sender;
        vaultContract = Vault(_vaultContract);
        priceOracle = PriceOracle(_priceOracle);
        interestRateModel = InterestRateModel(_interestRateModel);
        loanAsset = _loanAsset;
    }

    modifier onlyAdmin() {
        require(msg.sender == owner, "Only admin can execute this function");
        _;
    }

    // Function to set the LTV ratio for a collateral token (only admin)
    function setLTVRatio(
        address collateralToken,
        uint256 ltv
    ) external onlyAdmin {
        require(
            supportedCollateralTokens[collateralToken],
            "Token not supported"
        );
        require(ltv > 0 && ltv <= 100, "Invalid LTV ratio"); // Ensure LTV is between 1-100%

        ltvRatios[collateralToken] = ltv;

        emit LTVRatioSet(collateralToken, ltv);
    }

    // Function to add a collateral token to the market
    function addCollateralToken(
        address collateralToken,
        uint256 ltv
    ) external onlyAdmin {
        require(
            collateralToken != address(0),
            "Invalid collateral token address"
        );
        require(
            !supportedCollateralTokens[collateralToken],
            "Collateral token already added"
        );

        // Mark the token as supported
        supportedCollateralTokens[collateralToken] = true;
        collateralTokenList.push(collateralToken); // Track the token

        // Set LTV ratio using the existing function
        setLTVRatio(collateralToken, ltv);

        emit CollateralTokenAdded(collateralToken, ltv);
    }

    // Function to pause deposits for a collateral token
    function pauseCollateralDeposits(
        address collateralToken
    ) external onlyAdmin {
        require(
            supportedCollateralTokens[collateralToken],
            "Token not supported"
        );
        depositsPaused[collateralToken] = true;
        emit CollateralDepositsPaused(collateralToken);
    }

    function resumeCollateralDeposits(
        address collateralToken
    ) external onlyAdmin {
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
    function removeCollateralToken(address collateralToken) external onlyAdmin {
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
        if (userCollateralbalances[msg.sender][collateralToken] == amount) {
            userCollateralAssets[msg.sender].push(collateralToken);
        }

        // Emit an event for the deposit
        emit CollateralDeposited(msg.sender, collateralToken, amount);
    }

    function withdrawCollateral(
        address collateralToken,
        uint256 amount
    ) external nonReentrant {
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
        if (userCollateralBlances[msg.sender][collateralToken] == 0) {
            _removeCollateralAsset(msg.sender, collateralToken);
        }

        emit CollateralWithdrawn(msg.sender, collateralToken, amount);
    }

    // Function to borrow
    function borrow(uint256 loanAmount) external nonReentrant {
        // Ensure the loan amount is valid
        require(loanAmount > 0, "Loan amount must be greater than zero");

        // Ensure the vault has enough liquidity to cover the loan amount
        // No borrower can borrow more than what the vault can actually lend, preventing over-borrowing
        uint256 availableLiquidity = vaultContract.totalLiquidity();
        require(
            loanAmount <= availableLiquidity,
            "Vault has insufficient liquidity for this loan"
        );

        uint256 availableBorrowingPower = _getMaxBorrowingPower(msg.sender);

        // Ensure user has enough borrowing power to take this loan
        require(
            availableBorrowingPower >= loanAmount,
            "Not enough borrowing power to take this loan"
        );

        // Fetch the borrow rate at this moment
        uint256 currentBorrowRate = interestRateModel.getBorrowRatePerBlock();

        // Call Vault's adminBorrowFunction to withdraw funds to Market contract
        vaultContract.adminBorrowFunction(loanAmount);

        // Transfer the loaned amount from the market to the user
        loanAsset.transfer(msg.sender, loanAmount);

        // Ensure index is up to date after a successful transfer
        _updateGlobalBorrowIndex();

        // Adding new debt
        if (userTotalDebt[msg.sender] == 0) {
            // First-time borrower
            userTotalDebt[msg.sender] = loanAmount;
        } else {
            // Existing borrower: Add new loan, interest accerued already accounted for afrter calling _getMaxBorrowingPower.
            userTotalDebt[msg.sender] += loanAmount;
        }

        // Update last updated block per user
        // It tracks when this specific borrower last took a loan
        lastUpdatedBlock[msg.sender] = block.number;

        // Update the total borrows
        totalBorrows += loanAmount;

        emit Borrow(msg.sender, loanAmount, currentBorrowRate);
    }

    function repay(uint256 repaymentAmount) external nonReentrant {
        // Ensure the repayment amount is valid
        require(
            repaymentAmount > 0,
            "Repayment amount must be greater than zero"
        );
        uint256 userDebt = _getUserTotalDebt(msg.sender);
        require(userDebt > 0, "No outstanding debt to repay");

        // Ensure user is not repaying more than what they owe
        uint256 actualRepayment = repaymentAmount > userDebt
            ? userDebt
            : repaymentAmount;

        // Transfer tokens from the borrower to the market contract
        loanAsset.transferFrom(msg.sender, address(this), actualRepayment);

        // Call Vault's adminRepayFunction to return funds to the Vault
        vaultContract.adminRepayFunction(actualRepayment);

        // Calculate the proportion of debt repayment
        uint256 repaymentRatio = (actualRepayment * 1e18) / userDebt;

        // Get all user's collateral assets
        address[] memory userCollateralTokens = userCollateralAssets[user];

        uint256 totalCollateralReturned = 0; // Track total collateral returned

        for (uint256 i = 0; i < userCollateralTokens.length; i++) {
            address collateralToken = userCollateralTokens[i];
            uint256 userCollateral = userCollateralBalances[user][
                collateralToken
            ];

            if (userCollateral > 0) {
                // Calculate the collateral amount to return based on repayment ratio
                uint256 collateralToReturn = (userCollateral * repaymentRatio) /
                    1e18;

                // Transfer collateral back to the user
                if (collateralToReturn > 0) {
                    IERC20(collateralToken).transfer(
                        msg.sender,
                        collateralToReturn
                    );
                    // Update user's collateral balance (reduce collateral balance)
                    userCollateralBalances[msg.sender][
                        collateralToken
                    ] -= collateralToReturn;

                    // Track total collateral returned
                    totalCollateralReturned += collateralToReturn;
                }
            }
        }
        // Updates the borrower’s debt
        userTotalDebt[msg.sender] -= actualRepayment;

        // If fully paid, reset last updated block
        if (userTotalDebt[msg.sender] == 0) {
            lastUpdatedBlock[msg.sender] = 0;
        } else {
            lastUpdatedBlock[msg.sender] = block.number;
        }

        // Update total borrows in the system
        totalBorrows -= actualRepayment;
        emit Repay(msg.sender, actualRepayment, totalCollateralReturned);
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
    ) public view returns (bool) {
        require(
            supportedCollateralTokens[collateralToken],
            "Token not supported"
        );
        require(
            userCollateralBalances[user][collateralToken] >= amount,
            "Insufficient balance"
        );

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
        // Ensure global borrow index is updated before fetching user debt
        // Ensure interest is calculated using the latest index.
        _updateGlobalBorrowIndex();

        // Now the interest is calculated using the latest globalBorrowIndex, ensuring no interest is skipped.
        totalDebt = userTotalDebt[user] + _borrowerInterestAccrued(user);
        return totalDebt;
    }

    // Helper function to calculate the maximum borrowing power of a user
    function _getMaxBorrowingPower(address user) public view returns (uint256) {
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

    // Helper function to calculate accrued interest on a debt considering dynamic rates
    function _borrowerInterestAccrued(
        address borrower
    ) public view returns (uint256) {
        // This gives us the current interest rate per block.
        uint256 borrowRatePerBlock = interestRateModel.getBorrowRatePerBlock();

        // Get the last block when the user's debt was updated
        uint256 lastBlock = lastUpdatedBlock[borrower];
        if (lastBlock == 0) return 0; // No borrowing yet

        uint256 blocksElapsed = block.number - lastBlock;

        uint256 previousIndex = globalBorrowIndex;
        // The new index is calculated by applying the interest over blocksElapsed to the previous globalBorrowIndex.
        // This formula compounds interest over time
        uint256 newIndex = (previousIndex *
            (1e18 + (borrowRatePerBlock * blocksElapsed) / 1e18)) / 1e18;

        // We multiply this difference by the user's debt to get the interest accrued
        uint256 interestAccrued = (userTotalDebt[borrower] *
            (newIndex - previousIndex)) / 1e18; // Adjusted for precision

        return interestAccrued;
    }

    // Function to update the global borrow index
    function _updateGlobalBorrowIndex() private {
        // Get the current borrow rate per block from the interest rate model
        uint256 borrowRatePerBlock = interestRateModel.getBorrowRatePerBlock();

        // Update the global borrow index based on the time elapsed (in blocks)
        uint256 blocksElapsed = block.number - lastGlobalUpdateBlock;

        // Formula: newIndex = oldIndex * (1 + borrowRatePerBlock * blocksElapsed)
        uint256 newGlobalBorrowIndex = (globalBorrowIndex *
            (1e18 + (borrowRatePerBlock * blocksElapsed) / 1e18)) / 1e18;

        // Update the global borrow index
        globalBorrowIndex = newGlobalBorrowIndex;

        // Update the last block where the borrow index was updated
        lastGlobalUpdateBlock = block.number;
    }

    // Function to calculate the total interest accrued (excluding principal)
    function _getTotalInterestAccrued() public view returns (uint256) {
        // Ensure the global borrow index is up to date
        uint256 blocksElapsed = block.number - lastGlobalUpdateBlock;
        uint256 borrowRatePerBlock = interestRateModel.getBorrowRatePerBlock();

        // Estimate new global borrow index
        uint256 newGlobalBorrowIndex = (globalBorrowIndex *
            (1e18 + (borrowRatePerBlock * blocksElapsed) / 1e18)) / 1e18;

        // Calculate the interest accrued since last update
        uint256 totalInterestAccrued = (totalBorrows *
            (newGlobalBorrowIndex - globalBorrowIndex)) / 1e18;

        return totalInterestAccrued;
    }

    // Function to calculate total borrows plus accrued interest
    function _borrowedPlusInterest() public view returns (uint256) {
        uint256 totalInterestAccrued = _getTotalInterestAccrued(); // Get the total interest accrued
        return totalBorrows + totalInterestAccrued; // Add principal + interest
    }

    // function to remove an asset from userCollateralAssets[msg.sender]
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
