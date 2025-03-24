// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import "../src/Market.sol";
import "../src/Vault.sol";
import "../src/PriceOracle.sol";
import "../src/InterestRateModel.sol";
import "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

contract MarketTest is Test {
    Vault public vault;
    Market public market;
    PriceOracle public priceOracle;
    InterestRateModel public interestRateModel;
    address public user;
    address public lender;
    IERC20 public dai; // testing with DAI as the loan asset
    IERC20 public weth; // collateral asset
    address public wethPrice;

    address daiAddress = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1; // DAI address on Arbitrum
    address wethAddress = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH address on Arbitrum
    address wethPriceAddress = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612; // WETH price feed address on Arbitrum

    uint256 public initialDeposit = 5000 * 1e18; // 5000 tokens
    uint256 public initialBalance = 10000 * 1e18; // 10000 DAI for user
    uint256 public wethAmount = 5000 * 1e18; // 5000 WETH transfer to user

    function setUp() public {
        // Fork the Arbitrum mainnet at the latest block
        vm.createSelectFork(
            "https://arb-mainnet.g.alchemy.com/v2/ADLPIIv6SUjhmaoJYxWLHKDUDaw8RnRj",
            312132545
        );

        // Initialize the DAI and WETH instance
        dai = IERC20(daiAddress);
        weth = IERC20(wethAddress);
        wethPrice = wethPriceAddress;

        // InterestRateModel parameters
        uint256 baseRate = 0.02e18; // 2% base rate
        uint256 optimalUtilization = 0.8e18; // 80% optimal utilization
        uint256 slope1 = 0.1e18; // 10% slope1
        uint256 slope2 = 0.5e18; // 50% slope2

        // Deploy contracts
        vault = new Vault(dai, address(0), "Vault Dai", "VDAI");

        interestRateModel = new InterestRateModel(
            baseRate,
            optimalUtilization,
            slope1,
            slope2,
            address(vault), // Vault contract address
            address(0) // Placeholder market address
        );

        priceOracle = new PriceOracle();

        market = new Market(
            address(vault),
            address(priceOracle),
            address(interestRateModel),
            address(dai)
        );

        // Set the correct market address in Vault
        vault.setMarket(address(market));

        // Set the correct market address in InterestRateModel
        interestRateModel.setMarketContract(address(market));

        // Set up account
        user = address(0x123);
        lender = address(0x124);

        // send some Ether to the user for gas
        vm.deal(user, 10 ether);

        // Impersonate a DAI whale to send tokens to the lender
        address daiWhale = 0xd85E038593d7A098614721EaE955EC2022B9B91B; // Replace with a valid DAI whale address
        vm.startPrank(daiWhale);
        dai.transfer(lender, initialBalance); // Transfer 10,000 DAI to user
        vm.stopPrank();

        // Impersonate a WETH whale to send tokens to the user
        address wethWhale = 0xC6962004f452bE9203591991D15f6b388e09E8D0; // Replace with a valid WETH whale address
        vm.startPrank(wethWhale);
        weth.transfer(user, wethAmount); // Transfer 5,000 WETH to user
        vm.stopPrank();

        // Approve the vault contract for the lender to deposit DAI
        vm.startPrank(lender);
        dai.approve(address(vault), type(uint256).max); // Approve max amount
        vm.stopPrank();

        // Approve the market contract for the user to use WETH as collateral
        vm.startPrank(user);
        weth.approve(address(market), type(uint256).max);
        vm.stopPrank();
        console.log("Owner:", address(this));

        // Approve the market contract for the user to deposit DAI (repay)
        vm.startPrank(user);
        dai.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(address(market)); // Simulate the Market contract calling
        dai.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    // Test Add Collateral Token to market
    function testAddCollateralToken() public {
        address collateralToken = address(weth);
        address priceFeed = address(wethPrice);
        uint256 ltvRatio = 75; // 75% LTV Ratio

        vm.startPrank(address(this)); // Contract owner adds collateral and set LTV
        market.addCollateralToken(collateralToken, priceFeed, ltvRatio);
        vm.stopPrank();

        // Assert that the supportedCollateral mapping is now supported
        assertEq(
            market.supportedCollateralTokens(collateralToken),
            true,
            "Collateral supported by market"
        );
    }

    function testPauseCollateralDeposits() public {
        address collateralToken = address(weth);
        address priceFeed = address(wethPrice);
        uint256 ltvRatio = 75;

        // Add collateral token
        vm.startPrank(address(this));
        market.addCollateralToken(collateralToken, priceFeed, ltvRatio);
        vm.stopPrank();

        // Pause collateral deposits
        vm.startPrank(address(this));
        market.pauseCollateralDeposits(collateralToken);
        vm.stopPrank();

        assertEq(
            market.depositsPaused(collateralToken),
            true,
            "Collateral deposits should be paused"
        );
    }

    function testResumeCollateralDeposits() public {
        address collateralToken = address(weth);
        address priceFeed = address(wethPrice);
        uint256 ltvRatio = 75;

        // Add collateral token
        vm.startPrank(address(this));
        market.addCollateralToken(collateralToken, priceFeed, ltvRatio);
        vm.stopPrank();

        // Pause collateral deposits
        vm.startPrank(address(this));
        market.pauseCollateralDeposits(collateralToken);
        vm.stopPrank();

        // Verify deposits are paused
        assertEq(
            market.depositsPaused(collateralToken),
            true,
            "Collateral deposits should be paused"
        );

        // Resume collateral deposits
        vm.startPrank(address(this));
        market.resumeCollateralDeposits(collateralToken);
        vm.stopPrank();

        // Assert that depositsPaused is now false
        assertEq(
            market.depositsPaused(collateralToken),
            false,
            "Collateral deposits should be resumed"
        );

        // Ensure deposits now works
        vm.startPrank(user);
        market.depositCollateral(collateralToken, 100 * 1e18);
        vm.stopPrank();
    }

    function testRemoveCollateralToken() public {
        address collateralToken = address(weth);
        address priceFeed = address(wethPrice);
        uint256 ltvRatio = 75;

        // add Collateral Token
        vm.startPrank(address(this));
        market.addCollateralToken(collateralToken, priceFeed, ltvRatio);
        vm.stopPrank();

        // Pause collateral deposits
        vm.startPrank(address(this));
        market.pauseCollateralDeposits(collateralToken);
        vm.stopPrank();

        // Ensure no collateral is locked, mock the call
        vm.mockCall(
            address(market),
            abi.encodeWithSignature(
                "_getTotalCollateralLocked(address)",
                collateralToken
            ), // Function signature + argument
            abi.encode(0) // Mock return value 0
        );

        // Remove the collateral token
        vm.startPrank(address(this));
        market.removeCollateralToken(collateralToken);
        vm.stopPrank();

        // Assert that the collateral token is no longer supported
        assertEq(
            market.supportedCollateralTokens(collateralToken),
            false,
            "Collateral token should be removed"
        );
    }

    function testWithdrawCollateral() public {
        address collateralToken = address(weth);
        address priceFeed = address(wethPrice);
        uint256 ltvRatio = 75;
        uint256 depositAmount = 1000 * 1e18;
        uint256 withdrawAmount = 500 * 1e18;

        // Add collateral token
        vm.startPrank(address(this));
        market.addCollateralToken(collateralToken, priceFeed, ltvRatio);
        vm.stopPrank();

        // Ensure deposits works
        vm.startPrank(user);
        market.depositCollateral(collateralToken, depositAmount);
        vm.stopPrank();

        uint256 userBalanceBefore = weth.balanceOf(user);
        uint256 marketBalanceBefore = weth.balanceOf(address(market));

        vm.startPrank(user);
        market.withdrawCollateral(collateralToken, withdrawAmount);
        uint256 userBalanceAfter = weth.balanceOf(user);
        uint256 marketBalanceAfter = weth.balanceOf(address(market));

        assertEq(
            userBalanceAfter,
            userBalanceBefore + withdrawAmount,
            "User's balance should increase after withdrawal"
        );
        assertEq(
            marketBalanceAfter,
            marketBalanceBefore - withdrawAmount,
            "Market's balance should decrease after withdrawal"
        );
    }

    function testBorrow() public {
        address collateralToken = address(weth);
        address priceFeed = address(wethPrice);
        uint256 ltvRatio = 75;
        uint256 lentAmount = 5000 * 1e18; // 5000 DAI
        uint256 depositAmount = 3 * 1e18; // 3 WETH
        uint256 borrowAmount = 1000 * 1e18; // 4000 DAI

        // Lender deposits DAI into the vault
        vm.startPrank(lender);
        vault.deposit(lentAmount, lender);
        vm.stopPrank();

        uint256 userBalanceBefore = dai.balanceOf(user);
        uint256 vaultBalanceBefore = dai.balanceOf(address(vault));

        // Add collateral token to the market
        vm.startPrank(address(this));
        market.addCollateralToken(collateralToken, priceFeed, ltvRatio);
        vm.stopPrank();

        // User deposits collateral into the market
        vm.startPrank(user);
        market.depositCollateral(collateralToken, depositAmount);
        vm.stopPrank();

        // Check initial borrowing power
        uint256 initialBorrowingPower = market._getMaxBorrowingPower(user);
        assertGt(
            initialBorrowingPower,
            borrowAmount,
            "Borrowing power should be sufficient"
        );

        // User borrows loan asset
        vm.startPrank(user);
        market.borrow(borrowAmount);
        vm.stopPrank();

        uint256 userBalanceAfter = dai.balanceOf(user);
        uint256 vaultBalanceAfter = dai.balanceOf(address(vault));

        // Assert user receives the borrowed amount
        assertEq(
            userBalanceAfter,
            userBalanceBefore + borrowAmount,
            "User's DAI balance should increase after borrowing"
        );

        // Assert vault's balance decreases by the borrowed amount
        assertEq(
            vaultBalanceAfter,
            vaultBalanceBefore - borrowAmount,
            "Vault's DAI balance should decrease after borrowing"
        );

        // Assert the user's total debt is updated correctly
        uint256 expectedDebt = borrowAmount; // No prior debt, so debt = borrowAmount
        assertEq(
            market._getUserTotalDebt(user),
            expectedDebt,
            "User's total debt should equal the borrowed amount"
        );

        // Simulate interest accrual and subsequent borrow
        vm.warp(block.timestamp + 1 days); // Advance time to accrue interest

        // // User borrows again
        // uint256 additionalBorrowAmount = 500 * 1e18; // 500 DAI
        // vm.startPrank(user);
        // market.borrow(additionalBorrowAmount);
        // vm.stopPrank();

        uint256 previousGlobalBorrowIndex = market.globalBorrowIndex();
        console.log("previous global borrow index", previousGlobalBorrowIndex);

        // Calculate the interest accrued since the last update
        uint256 interestAccruedSinceLastUpdate = (market.totalBorrows() *
            previousGlobalBorrowIndex) / 1e18;
        console.log(
            "interest accrued since last update:",
            interestAccruedSinceLastUpdate
        );

        market.updateInterestAndGlobalBorrowIndex();

        // uint256 lastBorrowerIndex = market.lastUpdatedIndex(user);
        // console.log("Last borrower index:", lastBorrowerIndex);
        // uint256 currentGlobalIndex = market.globalBorrowIndex();
        // console.log("Current global index:", currentGlobalIndex);

        // uint256 accruedInterest = market._borrowerInterestAccrued(user);

        // // Assert interest is accrued
        // assertGt(accruedInterest, 0, "Interest should accrue over time");

        // uint256 newExpectedDebt = expectedDebt +
        //     additionalBorrowAmount +
        //     accruedInterest;
        // assertEq(
        //     market._getUserTotalDebt(user),
        //     newExpectedDebt,
        //     "User's total debt should include additional borrow and accrued interest"
        // );
    }

    function testRepay() public {
        address collateralToken = address(weth);
        address priceFeed = address(wethPrice);
        uint256 ltvRatio = 75;
        uint256 lentAmount = 5000 * 1e18; // 5000 DAI
        uint256 depositAmount = 3 * 1e18; // 3 WETH
        uint256 borrowAmount = 2000 * 1e18; // 4000 DAI

        // Lender deposits DAi into vault
        vm.startPrank(lender);
        vault.deposit(lentAmount, lender);
        vm.stopPrank();

        // Add collateral token
        vm.startPrank(address(this));
        market.addCollateralToken(collateralToken, priceFeed, ltvRatio);
        vm.stopPrank();

        // User deposits collateral into market
        vm.startPrank(user);
        market.depositCollateral(collateralToken, depositAmount);
        vm.stopPrank();

        uint256 userDebtBeforeBorrow = market.userTotalDebt(user);
        uint256 userBalanceBeforeBorrow = dai.balanceOf(user);
        uint256 vaultBalanceBeforeBorrow = dai.balanceOf(address(vault));

        console.log("User debt before borrow:", userDebtBeforeBorrow);
        console.log("User balance before borrow:", userBalanceBeforeBorrow);
        console.log("Vault balance before borrow:", vaultBalanceBeforeBorrow);

        // User borrows loan asset
        vm.startPrank(user);
        market.borrow(borrowAmount);
        vm.stopPrank();

        // Simulate 2000 blocks passing
        vm.roll(block.number + 200);

        uint256 userDebtAfterBorrow = market.userTotalDebt(user);
        uint256 userBalanceAfterBorrow = dai.balanceOf(user);
        uint256 vaultBalanceAfterBorrow = dai.balanceOf(address(vault));

        console.log("User debt after borrow:", userDebtAfterBorrow);
        console.log("User Balance after borrow:", userBalanceAfterBorrow);
        console.log("vault balance after borrow:", vaultBalanceAfterBorrow);

        assertEq(
            userBalanceAfterBorrow,
            userBalanceBeforeBorrow + borrowAmount,
            "User's balance of DAI should increase after borrowing"
        );

        assertEq(
            vaultBalanceAfterBorrow,
            vaultBalanceBeforeBorrow - borrowAmount,
            "Vault's balance of DAI should decrease after borrowing"
        );

        assertEq(
            userDebtAfterBorrow,
            userDebtBeforeBorrow + borrowAmount,
            "User's debt should increase after borrowing"
        );

        // User borrows again
        vm.startPrank(user);
        market.borrow(500 * 1e18);
        vm.stopPrank();

        // Simulate 2000 blocks passing
        vm.roll(block.number + 200);

        uint256 userDebtBeforeRepay = market.userTotalDebt(user);
        uint256 userBalanceBeforeRepay = dai.balanceOf(user);
        uint256 vaultBalanceBeforeRepay = dai.balanceOf(address(vault));
        uint256 userCollateralBalanceBeforeRepay = market
            .userCollateralBalances(user, address(weth));

        console.log("User debt before repay:", userDebtBeforeRepay);
        console.log("User Balance before repay:", userBalanceBeforeRepay);
        console.log("vault balance before repay:", vaultBalanceBeforeRepay);
        console.log(
            "user collateral balance before repay:",
            userCollateralBalanceBeforeRepay
        );

        uint256 partialRepayment = userDebtBeforeRepay / 2;

        // User partially repays debt
        vm.startPrank(user);
        market.repay(partialRepayment);
        vm.stopPrank();

        uint256 userDebtAfterRepay = market.userTotalDebt(user);
        uint256 userBalanceAfterRepay = dai.balanceOf(user);
        uint256 vaultBalanceAfterRepay = dai.balanceOf(address(vault));
        uint256 userCollateralBalanceAfterRepay = market.userCollateralBalances(
            user,
            address(weth)
        );

        console.log("User debt after repay:", userDebtAfterRepay);
        console.log("User Balance after repay:", userBalanceAfterRepay);
        console.log("vault balance after repay:", vaultBalanceAfterRepay);
        console.log(
            "user collateral balance after repay:",
            userCollateralBalanceAfterRepay
        );
    }
}
