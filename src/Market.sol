// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Vault.sol";
import "./InterestRateModel.sol";
import "./PriceOracle.sol";
import "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

contract Market {
    InterestRateModel public interestRateModel;
    PriceOracle public priceOracle;
    IERC20 public loanAsset;
    Vault public loanAssetVault;
    address public owner;
    uint256 public totalRepaid; // Tracks total repaid by borrowers

    // Mapping to track user collateral balances for each collateral token
    mapping(address => mapping(address => uint256))
        public userCollateralBalances;

    // Mapping to track the supported collateral types in the market
    mapping(address => bool) public supportedCollateralTokens;

    // Mapping to track users' borrowed principal amount
    mapping(address => uint256) public borrowerPrincipal; // User -> Amount

    // Mapping to track the last interest rate at the time of borrowing
    mapping(address => uint256) public borrowRateAtTime; // User -> Rate

    // Mapping to track the last update time for interest calculation
    mapping(address => uint256) public borrowTimestamp; // User -> Timestamp

    // Mapping to track the amount of interest accumulated
    mapping(address => uint256) public borrowerInterestAccrued; // User -> Interest

    // Mapping for Loan-to-Value (LTV) ratios for borrowable tokens
    mapping(address => uint256) public ltvRatios; // Token -> LTV ratio (percentage out of 100)

    // Array to track all supported collateral tokens
    address[] public collateralTokens;

    // Array to track borrowers of loan asset
    address[] public borrowers;

    event CollateralTokenAdded(address indexed collateralToken);

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

    event Borrowed(
        address indexed borrower,
        address indexed borrowableToken,
        uint256 amount,
        uint256 borrowRate,
        uint256 interestAmount
    );

    // Event for setting LTV ratio for a borrowable token
    event LTVRatioSet(address indexed borrowableToken, uint256 ltvRatio);

    event Repayment(
        address indexed borrower,
        address indexed borrowableToken,
        uint256 totalRepayAmount
    );

    constructor(
        InterestRateModel _interestRateModel,
        PriceOracle _priceOracle,
        address _loanAsset,
        address _vaultAddress,
        address _owner
    ) {
        interestRateModel = _interestRateModel;
        priceOracle = _priceOracle;
        loanAsset = IERC20(_loanAsset);
        loanAssetVault = Vault(_vaultAddress);
        owner = _owner;
    }

    // Function to add a collateral type to the market
    function addCollateralToken(
        address collateralToken,
        uint256 ltvRatio
    ) external {
        require(
            collateralToken != address(0),
            "Invalid collateral token address"
        );
        require(
            !supportedCollateralTokens[collateralToken],
            "Collateral token already added"
        );

        // Mark the collateral token as supported
        supportedCollateralTokens[collateralToken] = true;

        // Set the LTV ratio for that specific collateral token (users can define their own LTV for now)
        setLTVRatio(collateralToken, ltvRatio);

        // Add collateral to array to track all supported collateral tokens
        collateralTokens.push(collateralToken);

        emit CollateralTokenAdded(collateralToken);
    }

    function removeCollateralToken(address collateralToken) external {
        require(
            supportedCollateralTokens[collateralToken],
            "Token not supported"
        );

        // Remove from mapping
        supportedCollateralTokens[collateralToken] = false;

        // Find index in array
        uint256 index;
        uint256 length = collateralTokens.length;
        for (uint256 i = 0; i < length; i++) {
            if (collateralTokens[i] == collateralToken) {
                index = i;
                break;
            }
        }

        // Swap with the last element and pop
        if (index < length - 1) {
            collateralTokens[index] = collateralTokens[length - 1];
        }
        collateralTokens.pop();

        emit CollateralTokenRemoved(collateralToken);
    }

    function depositCollateral(
        address collateralToken,
        uint256 amount
    ) external {
        // Ensure the collateral token is supported
        require(
            supportedCollateralTokens[collateralToken],
            "Collateral token not supported"
        );

        // Transfer the collateral token from the user to the market contract
        IERC20(collateralToken).transferFrom(msg.sender, address(this), amount);

        // Update the user's collateral balance for this token
        userCollateralBalances[msg.sender][collateralToken] += amount;

        // Emit an event for logging
        emit CollateralDeposited(msg.sender, collateralToken, amount);
    }

    function withdrawCollateral(
        address collateralToken,
        uint256 amount
    ) external {
        // Ensure the user has enough collateral to withdraw
        require(
            userCollateralBalances[msg.sender][collateralToken] >= amount,
            "Insufficient collateral balance"
        );

        // Decrease the user's collateral balance
        userCollateralBalances[msg.sender][collateralToken] -= amount;

        // Transfer the collateral token from the market contract to the user
        IERC20(collateralToken).transfer(msg.sender, amount);

        // Emit an event for logging
        emit CollateralWithdrawn(msg.sender, collateralToken, amount);
    }

    function borrow(uint256 amount) public {
        // Ensure loan asset is supported
        require(loanAsset != address(0), "Loan asset not supported");

        // Get the user's collateral value
        uint256 userCollateralValue = getTotalCollateralValue(msg.sender);

        // Calculate the max borrowable amount (LTV)
        uint256 maxBorrowAmount = userCollateralValue;

        // Ensure the user is not borrowing more than allowed
        require(amount <= maxBorrowAmount, "Borrow amount exceeds LTV limit");

        // Ensure the vault has enough borrowable funds to lend
        uint256 availableFunds = loanAsset.balanceOf(loanAssetVault);
        require(availableFunds >= amount, "Insufficient funds in vault");

        // Call Vault's adminBorrowFunction to withdraw funds to Market contract
        loanAssetVault.adminBorrowFunction(amount);

        // Transfer the borrowed tokens from the market to the borrower
        loanAsset.transfer(msg.sender, amount);

        // Add borrower to the list of borrowers for this token
        if (borrowerPrincipal[msg.sender] == 0) {
            borrowers.push(msg.sender);
        }

        // Get the dynamic borrow rate based on utilization from InterestRateModel
        uint256 borrowRate = interestRateModel.getDynamicBorrowRate(loanAsset);

        // Store the borrow rate and timestamp at the time of borrowing
        borrowRateAtTime[msg.sender] = borrowRate;
        borrowTimestamp[msg.sender] = block.timestamp;

        // This would be the interest to be paid on top of the borrow
        uint256 interestAmount = (amount * borrowRate) / 1e18;

        // Update borrowed amount tracking
        borrowerPrincipal[msg.sender] += amount;

        // Ensure the vault's funds are updated correctly (funds should decrease)
        uint256 updatedVaultFunds = loanAssetVault.totalAssets();
        require(
            updatedVaultFunds < availableFunds,
            "Funds have not been updated"
        );

        // Emit event for borrowed
        emit Borrowed(
            msg.sender,
            loanAsset,
            amount,
            borrowRate,
            interestAmount
        );
    }

    function repay(uint256 amount) public {
        // Ensure the user has borrowed this token
        uint256 principal = borrowerPrincipal[msg.sender];
        require(principal > 0, "No debt to repay");

        // Calculate the interest accrued dynamically
        uint256 interest = calculateBorrowerAccruedInterest(msg.sender);

        // Calculate total outstanding debt (principal + interest)
        uint256 totalDebt = principal + interest;

        require(amount > 0, "Repayment amount must be greater than zero");
        require(amount <= totalDebt, "Repayment amount exceeds debt");

        // Transfer repayment amount from the user to the market
        loanAsset.transferFrom(msg.sender, address(this), amount);

        if (amount == totalDebt) {
            // Full repayment
            principal = 0;
            // Remove borrower from the list of borrowers
            removeFromBorrowerList(msg.sender);
            emit Repayment(msg.sender, loanAsset, amount);
        } else {
            // Partial repayment logic
            if (amount <= interest) {
                // If the repayment is less than or equal to the interest, reduce the interest amount
                emit Repayment(msg.sender, loanAsset, amount);
            } else {
                // Pay interest first, then reduce principal
                uint256 remainingAfterInterest = amount - interest;
                principal -= remainingAfterInterest;
            }
            emit Repayment(msg.sender, loanAsset, amount);
        }
        // Track how much has been repaid
        totalRepaid += amount;

        // Ensure the vault's funds are updated correctly (funds should decrease)
        uint256 updatedVaultFunds = loanAssetVault.totalAssets();
        require(
            updatedVaultFunds < availableFunds,
            "Funds have not been updated"
        );
    }

    // Function to set the LTV ratio for a collateral token
    // Change this for admin control
    function setLTVRatio(address collateralToken, uint256 ratio) internal {
        require(ratio <= 100, "LTV ratio cannot exceed 100");
        require(ratio > 0, "LTV ratio must be greater than 0");

        ltvRatios[collateralToken] = ratio;

        emit LTVRatioSet(collateralToken, ratio);
    }

    // Function to get the LTV ratio for a collateral token
    function getLTVRatio(
        address collateralToken
    ) public view returns (uint256) {
        return ltvRatios[collateralToken];
    }

    // Supporting function to check user/s total collateral
    function getTotalCollateralValue(
        address user
    ) public view returns (uint256 totalBorrowingPower) {
        totalBorrowingPower = 0;

        // Loop through the array of collateral tokens
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            address collateralToken = collateralTokens[i];
            uint256 userCollateralAmount = userCollateralBalances[user][
                collateralToken
            ];
            if (userCollateralAmount > 0) {
                uint256 ltvRatio = getLTVRatio(collateralToken); // LTV per collateral token
                uint8 collateralDecimals = getTokenDecimals(collateralToken); // Get collateral token decimals

                // Get the price of the collateral token from the PriceOracle
                int256 collateralPrice = priceOracle.getLatestPrice(
                    collateralToken
                );
                require(collateralPrice > 0, "Invalid price from Oracle");

                uint256 collateralValue = userCollateralAmount *
                    uint256(collateralPrice);

                // If the collateral token has less decimals than DAI (18 decimals), adjust it
                if (collateralDecimals < 18) {
                    collateralValue =
                        collateralValue *
                        (10 ** (18 - collateralDecimals)); // Scale it up to match DAI's 18 decimals
                } else if (collateralDecimals > 18) {
                    collateralValue =
                        collateralValue /
                        (10 ** (collateralDecimals - 18)); // Scale it down if more than 18 decimals
                }

                // Add the collateral value to the total borrowing power, considering LTV
                totalBorrowingPower += (collateralValue * ltvRatio) / 100;
            }
        }
        return totalBorrowingPower;
    }

    // Function to calculate the interests accrued by a borrower
    function calculateBorrowerAccruedInterest(
        address user
    ) public view returns (uint256) {
        // Get the principal amount borrowed
        uint256 principal = borrowerPrincipal[user];
        require(principal > 0, "No principal borrowed");

        // Get the borrow rate at the time of borrowing
        uint256 initialBorrowRate = borrowRateAtTime[user];

        // Get the last time when the interest was updated (when the loan was taken)
        uint256 lastTimestamp = borrowTimestamp[user];

        // If the loan was taken just now, return 0 interest
        if (lastTimestamp == 0) return 0;

        // Calculate the time elapsed since the last update
        uint256 timeElapsed = block.timestamp - lastTimestamp;

        // Calculate the interest based on the elapsed time and the borrow rate
        // Assume the borrow rate is annual (rate per second)
        uint256 totalInterest = (principal * initialBorrowRate * timeElapsed) /
            (365 days * 1e18);

        // Track the time after the initial period to calculate future interest
        uint256 currentTimestamp = block.timestamp;

        // Calculate the dynamic rate for the future periods if the rate changes
        uint256 newRate = getDynamicBorrowRate(loanAsset);

        // If the borrow rate changes since the loan was taken, calculate the interest for that period
        if (newRate > initialBorrowRate) {
            // Calculate the interest for the remaining time
            uint256 newPeriodElapsed = currentTimestamp - lastTimestamp;
            uint256 newInterest = (principal * newRate * newPeriodElapsed) /
                (365 days * 1e18);
            totalInterest += newInterest;
        }

        return totalInterest;
    }

    // This function calculates what will be paid back to the vault
    function borrowedPlusInterest() external view returns (uint256) {
        uint256 totalPrincipal = 0;
        uint256 totalBorrowerInterest = 0;

        // Loop through all borrowers to calculate total principal and interest separately
        for (uint i = 0; i < borrowers.length; i++) {
            address borrower = borrowers[i];
            totalPrincipal += borrowerPrincipal[borrower]; // Principal borrowed by borrower
            totalBorrowerInterest += calculateBorrowerAccruedInterest(borrower); // Interest owed by borrower
        }

        // Get the lending rate which already accounts for the reserve factor
        uint256 lendingRate = interestRateModel.getLendingRate(loanAsset);

        // Calculate how much of the interest collected by the market will go to the vault
        uint256 vaultInterest = (totalBorrowerInterest * lendingRate) / 1e18;

        // The total amount repaid to the vault is the principal + vault’s share of the interest
        uint256 totalRepaymentToVault = totalPrincipal + vaultInterest;

        return totalRepaymentToVault;
    }

    function repayToVault() external {
        require(totalRepaid > 0, "No repayments available to send to vault");

        // Ensure the market has enough funds
        uint256 marketBalance = loanAsset.balanceOf(address(this));
        require(marketBalance >= totalRepaid, "Insufficient funds in market");

        // Transfer funds to the vault
        loanAssetVault.adminRepayFunction(totalRepaymentToVault);

        // Reset the repayment tracker
        totalRepaid = 0;
    }

    // ======= HELPER FUNCTIONS ========
    // Function that returns the list of collateral tokens
    function getCollateralTokens() public returns (address[] memory) {
        return collateralTokens;
    }

    function getTokenDecimals(address token) internal returns (uint8) {
        return IERC20Metadata(token).decimals();
    }

    function removeFromBorrowerList(address borrower) internal {
        // Find the index of the borrower in the global borrowers array
        for (uint i = 0; i < borrowers.length; i++) {
            if (borrowers[i] == borrower) {
                // Swap with the last element and remove the last element
                borrowers[i] = borrowers[borrowers.length - 1];
                borrowers.pop();
                break;
            }
        }
    }
}
