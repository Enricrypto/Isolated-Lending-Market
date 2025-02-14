// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import "./Vault.sol";
import "./PriceOracle.sol";

contract newMarket {
    address public owner; // Admin address
    Vault public vaultContract;
    PriceOracle public priceOracle;
    IERC20 public loanAsset;

    uint256 public totalBorrows; // Tracks total borrowed amount for the loan asset

    // Mapping to track the supported collateral tokens
    mapping(address => bool) public supportedCollateralTokens;

    // Mapping to track if deposites are paused for a specific collateral token
    mapping(address => bool) public depositsPaused;

    // Mapping to track user collateral balances
    mapping(address => mapping(address => uint256))
        public userCollateralBalances;

    // Mapping to track total debt of each user
    mapping(address => uint256) public userTotalDebt;

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

    constructor(
        address _vaultContract,
        address _priceOracle,
        address _loanAsset
    ) {
        owner = msg.sender;
        vaultContract = Vault(_vaultContract);
        priceOracle = PriceOracle(_priceOracle);
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
            getTotalCollateralLocked(collateralToken) == 0,
            "Collateral still in use"
        );

        // TO-DO: before removing collateral token, I'll need to make sure that no users are using token as collateral

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
    ) external {
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
        IERC20(collateralToken).transferFrom(msg.sender, address(this), amount);

        // Update user's collateral balance for this contract
        userCollateralBalances[msg.sender][collateralToken] += amount;

        // Emit an event for the deposit
        emit CollateralDeposited(msg.sender, collateralToken, amount);
    }

    function withdrawCollateral(
        address collateralToken,
        uint256 amount
    ) external {
        require(
            supportedCollateralTokens[collateralToken],
            "Collateral token not supported"
        );
        require(amount > 0, "Withdraw amlunt must be greater than zero");

        // Ensure the user has enough balance to withdraw
        require(
            userCollateralBalances[msg.sender][collateralToken] >= amount,
            "Insufficient collateral balance"
        );

        // Ensure user is not undercollateralized after withdrawal
        require(
            isWithdrawalAllowed(msg.sender, collateralToken, amount),
            "Withdrawal would cause undercollateralization"
        );

        // Transfer the collateral back to the user
        IERC20(collateralToken).transfer(msg.sender, amount);

        // Update user's collateral balance
        userCollateralBalances[msg.sender][collateralToken] -= amount;

        emit CollateralWithdrawn(msg.sender, collateralToken, amount);
    }

    // Function to borrow
    function borrow(uint256 loanAmount) external {
        // Ensure the loan amount is valid
        require(loanAmount > 0, "Loan amount must be greater than zero");

        // Ensure user has enough borrowing power
        uint256 borrowingPower = getUserTotalBorrowingPower(msg.sender);
        require(borrowingPower >= loanAmount, "Not enough borrowing power");

        // MAKE SURE THE USER HAS ENOUGH BORROWING POWER CONSIDERING DEBT
        // Get the user's total outstanding debt before borrowing
        uint256 totalDebt = getUserTotalDebt(msg.sender);

        // Calculate the new total debt after borrowing
        uint256 newTotalDebt = totalDebt + loanAmount;

        // Ensure user can still borrow based on their remaining borrowing power
        uint256 remainingBorrowingPower = totalBorrowingPower > loanAmount
            ? totalBorrowingPower - loanAmount
            : 0;

        // Check if the remaining borrowing power after borrowing is sufficient to cover total debt
        require(
            remainingBorrowingPower >= newTotalDebt,
            "Not enough borrowing power to take this loan"
        );

        // Get the current borrow rate from the InterestRateModel
        uint256 borrowRate = interestRateModel.getDynamicBorrowRate(
            address(loanAsset)
        );

        // Update the user's total debt
        userTotalDebt[msg.sender] += loanAmount;

        // Update the total borrows
        totalBorrows += loanAmount;

        // Call Vault's adminBorrowFunction to withdraw funds to Market contract
        vaultContract.adminBorrowFunction(loanAmount);

        // Transfer the loaned amount from the market to the user
        loanAsset.transfer(msg.sender, loanAmount);
    }

    // ======= HELPER FUNCTIONS ========
    // Helper function to check total collateral locked in the contract
    function getTotalCollateralLocked(
        address collateralToken
    ) public view returns (uint256 totalCollateral) {
        totalCollateral = IERC20(collateralToken).balanceOf(address(this)); // Get the contract's balance
    }

    // Helper function to calculate total borrowable value of a user's collateral
    function getUserTotalBorrowingPower(
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
    function isWithdrawalAllowed(
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
        uint256 totalBorrowingPower = getUserTotalBorrowingPower(user);

        // Get user's total outstanding debt
        uint256 totalDebt = getUserTotalDebt(user);

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
    function getUserTotalDebt(
        address user
    ) public view returns (uint256 totalDebt) {
        totalDebt = userTotalDebt[user];
        return totalDebt;
    }
}
