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
    address public daiPrice;

    address daiAddress = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1; // DAI address on Arbitrum
    address wethAddress = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH address on Arbitrum
    address wethPriceAddress = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612; // WETH price feed address on Arbitrum
    address daiPriceAddress = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9; // DAI price feed address on Arbitrum; // DAI address on Arbitrum

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

        // Initialize price feed addresses
        wethPrice = wethPriceAddress;
        daiPrice = daiPriceAddress;

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
        address priceFeed = wethPrice;
        uint256 ltvRatio = 75; // 75% LTV Ratio
        uint256 liquidationThreshold = 80; // 80% Liquidation threshold

        vm.startPrank(address(this)); // Contract owner adds collateral and set LTV
        market.addCollateralToken(
            collateralToken,
            priceFeed,
            ltvRatio,
            liquidationThreshold
        );
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
        uint256 liquidationThreshold = 80;

        // Add collateral token
        vm.startPrank(address(this));
        market.addCollateralToken(
            collateralToken,
            priceFeed,
            ltvRatio,
            liquidationThreshold
        );
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
        uint256 liquidationThreshold = 80;

        // Add collateral token
        vm.startPrank(address(this));
        market.addCollateralToken(
            collateralToken,
            priceFeed,
            ltvRatio,
            liquidationThreshold
        );
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
        uint256 liquidationThreshold = 80;

        // add Collateral Token
        vm.startPrank(address(this));
        market.addCollateralToken(
            collateralToken,
            priceFeed,
            ltvRatio,
            liquidationThreshold
        );
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
        uint256 liquidationThreshold = 80;
        uint256 depositAmount = 1000 * 1e18;
        uint256 withdrawAmount = 500 * 1e18;

        // Add collateral token
        vm.startPrank(address(this));
        market.addCollateralToken(
            collateralToken,
            priceFeed,
            ltvRatio,
            liquidationThreshold
        );
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
        // address loanAsset = address(dai);
        address collateralToken = address(weth);
        address priceFeed = address(wethPrice);
        uint256 ltvRatio = 75;
        uint256 liquidationThreshold = 80;
        uint256 lentAmount = 5000 * 1e18; // 5000 DAI
        uint256 depositAmount = 3 * 1e18; // 3 WETH
        uint256 borrowAmount1 = 300 * 1e18; // First borrow: 300 DAI
        uint256 borrowAmount2 = 500 * 1e18; // Second borrow: 500 DAI

        // Lender deposits DAI into the vault
        vm.startPrank(lender);
        vault.deposit(lentAmount, lender);
        vm.stopPrank();

        uint256 vaultBalanceBefore = dai.balanceOf(address(vault));

        // Add collateral token to the market
        vm.startPrank(address(this));
        market.addCollateralToken(
            collateralToken,
            priceFeed,
            ltvRatio,
            liquidationThreshold
        );
        vm.stopPrank();

        // User deposits collateral into the market
        vm.startPrank(user);
        market.depositCollateral(collateralToken, depositAmount);
        vm.stopPrank();

        // First borrow
        vm.startPrank(user);
        market.borrow(borrowAmount1);
        vm.stopPrank();

        uint256 globalBorrowIndex1 = market.globalBorrowIndex();
        uint256 userDebtAfterBorrow1 = market._getUserTotalDebt(user);

        // Assert first borrow updated user's debt correctly
        assertEq(
            userDebtAfterBorrow1,
            borrowAmount1,
            "User's debt should equal the first borrowed amount"
        );

        // Update interest and global borrow index without user interaction
        market.updateInterestAndGlobalBorrowIndex();

        uint256 globalBorrowIndex2 = market.globalBorrowIndex();
        uint256 userDebtAfterUpdate = market._getUserTotalDebt(user);

        // Assert first update is updating user's debt correctly
        assertGt(
            userDebtAfterUpdate,
            userDebtAfterBorrow1,
            "User's debt should increase after first update"
        );

        // Ensure global borrow index increased
        assertGt(
            globalBorrowIndex2,
            globalBorrowIndex1,
            "Global borrow index should increase after interest accrual"
        );

        // Second borrow
        vm.startPrank(user);
        market.borrow(borrowAmount2);
        vm.stopPrank();

        uint256 userDebtAfterBorrow2 = market._getUserTotalDebt(user);
        uint256 totalExpectedDebt = borrowAmount1 + borrowAmount2;

        // Assert total debt is updated after the second borrow
        assertGt(
            userDebtAfterBorrow2,
            userDebtAfterUpdate,
            "User's total debt should increase after second borrow"
        );

        uint256 globalBorrowIndex3 = market.globalBorrowIndex();

        // Ensure global borrow index increased again
        assertGt(
            globalBorrowIndex3,
            globalBorrowIndex2,
            "Global borrow index should increase after second interest accrual"
        );

        // Assert vault balance decreases by the total borrowed amount
        uint256 vaultBalanceAfter = dai.balanceOf(address(vault));
        assertEq(
            vaultBalanceAfter,
            vaultBalanceBefore - totalExpectedDebt,
            "Vault's DAI balance should decrease by the total borrowed amount"
        );
    }

    function testRepay() public {
        address collateralToken = address(weth);
        address priceFeed = wethPrice;
        uint256 ltvRatio = 75;
        uint256 liquidationThreshold = 80;
        uint256 lentAmount = 5000 * 1e18; // 5000 DAI
        uint256 depositAmount = 3 * 1e18; // 3 WETH
        uint256 borrowAmount = 2000 * 1e18; // 2000 DAI
        uint256 additionalBorrowAmount = 500 * 1e18; // Additional borrow: 500 DAI

        // Lender deposits DAI into the vault
        vm.startPrank(lender);
        vault.deposit(lentAmount, lender);
        vm.stopPrank();

        // Add collateral token to the market
        vm.startPrank(address(this));
        market.addCollateralToken(
            collateralToken,
            priceFeed,
            ltvRatio,
            liquidationThreshold
        );
        vm.stopPrank();

        // User deposits collateral into the market
        vm.startPrank(user);
        market.depositCollateral(collateralToken, depositAmount);
        uint256 collateralValue = market.getUserTotalCollateralValue(user);
        console.log("Collateral value:", collateralValue);
        vm.stopPrank();

        // Initial borrowing checks
        uint256 userBalanceBeforeBorrow = dai.balanceOf(user);
        uint256 vaultBalanceBeforeBorrow = dai.balanceOf(address(vault));

        console.log("borrowAmount:", borrowAmount);
        uint256 simulatedDebt = market._getUserTotalDebt(user) + borrowAmount;
        console.log("simulated debt:", simulatedDebt);
        uint256 healthFactor = market.getHealthFactor(
            user,
            simulatedDebt,
            collateralValue
        );
        console.log("health factor:", healthFactor);
        // User borrows for the first time
        vm.startPrank(user);
        market.borrow(borrowAmount);
        vm.stopPrank();

        uint256 userDebtAfterFirstBorrow = market.userTotalDebt(user);
        uint256 userBalanceAfterFirstBorrow = dai.balanceOf(user);
        uint256 vaultBalanceAfterFirstBorrow = dai.balanceOf(address(vault));

        // Assert first borrow
        assertEq(
            userBalanceAfterFirstBorrow,
            userBalanceBeforeBorrow + borrowAmount,
            "User's balance of DAI should increase after borrowing"
        );
        assertEq(
            vaultBalanceAfterFirstBorrow,
            vaultBalanceBeforeBorrow - borrowAmount,
            "Vault's balance of DAI should decrease after borrowing"
        );
        assertEq(
            userDebtAfterFirstBorrow,
            borrowAmount,
            "User's debt should match the borrowed amount"
        );

        // User borrows again
        vm.startPrank(user);
        market.borrow(additionalBorrowAmount);
        vm.stopPrank();

        uint256 userDebtAfterSecondBorrow = market.userTotalDebt(user);
        uint256 userBalanceAfterSecondBorrow = dai.balanceOf(user);
        uint256 vaultBalanceAfterSecondBorrow = dai.balanceOf(address(vault));
        uint256 totalBorrowed = borrowAmount + additionalBorrowAmount;

        // Assert second borrow
        assertEq(
            userBalanceAfterSecondBorrow,
            userBalanceAfterFirstBorrow + additionalBorrowAmount,
            "User's balance of DAI should increase after second borrowing"
        );
        assertEq(
            vaultBalanceAfterSecondBorrow,
            vaultBalanceAfterFirstBorrow - additionalBorrowAmount,
            "Vault's balance of DAI should decrease after second borrowing"
        );
        assertGt(
            userDebtAfterSecondBorrow,
            userDebtAfterFirstBorrow,
            "User's debt should increase after second borrow"
        );

        // Partial repayment
        uint256 partialRepayment = totalBorrowed / 2;

        vm.startPrank(user);
        market.repay(partialRepayment);
        vm.stopPrank();

        uint256 userDebtAfterRepay = market.userTotalDebt(user);
        uint256 userBalanceAfterRepay = dai.balanceOf(user);
        uint256 vaultBalanceAfterRepay = dai.balanceOf(address(vault));

        // Assert partial repayment
        assertEq(
            userDebtAfterRepay,
            userDebtAfterSecondBorrow - partialRepayment,
            "User's debt should decrease by the repaid amount"
        );
        assertEq(
            userBalanceAfterRepay,
            userBalanceAfterSecondBorrow - partialRepayment,
            "User's balance of DAI should decrease by the repaid amount"
        );
        assertEq(
            vaultBalanceAfterRepay,
            vaultBalanceAfterSecondBorrow + partialRepayment,
            "Vault's balance of DAI should increase by the repaid amount"
        );
    }

    function testLiquidate() public {
        address collateralToken = address(weth);
        address priceFeed = wethPrice;
        uint256 ltvRatio = 75;
        uint256 liquidationThreshold = 80;
        uint256 lentAmount = 5000 * 1e18; // 5000 DAI
        uint256 depositAmount = 3 * 1e18; // 3 WETH
        uint256 borrowAmount = 4725 * 1e18; // 4700 DAI
        uint256 additionalBorrowAmount = 500 * 1e18; // Additional borrow: 500 DAI

        // Lender deposits DAI into the vault
        vm.startPrank(lender);
        vault.deposit(lentAmount, lender);
        vm.stopPrank();

        // Add collateral token to the market
        vm.startPrank(address(this));
        market.addCollateralToken(
            collateralToken,
            priceFeed,
            ltvRatio,
            liquidationThreshold
        );
        vm.stopPrank();

        // User deposits collateral into the market
        vm.startPrank(user);
        market.depositCollateral(collateralToken, depositAmount);
        uint256 collateralValue = market.getUserTotalCollateralValue(user);
        console.log("Collateral value:", collateralValue);
        uint256 collateralValueInUSD = market.getTokenValueInUSD(
            collateralToken,
            depositAmount
        );
        console.log("collateral value in USD:", collateralValueInUSD);
        int256 tokenPrice = priceOracle.getLatestPrice(collateralToken);
        console.log("token price:", tokenPrice);
        uint256 totalBorrowingPower = market._getUserTotalBorrowingPower(user);
        console.log("total borrowing power:", totalBorrowingPower);
        uint256 maxBorrowingPower = market._getMaxBorrowingPower(user);
        console.log("max borrowing power:", maxBorrowingPower);
        uint256 healthFactor = market.getHealthFactor(
            user,
            borrowAmount,
            collateralValueInUSD
        );
        console.log("health Factor:", healthFactor);
        vm.stopPrank();

        // Initial borrowing checks
        uint256 userBalanceBeforeBorrow = dai.balanceOf(user);
        uint256 vaultBalanceBeforeBorrow = dai.balanceOf(address(vault));

        // User borrows for the first time
        vm.startPrank(user);
        market.borrow(borrowAmount);
        vm.stopPrank();

        uint256 userDebtAfterFirstBorrow = market.userTotalDebt(user);
        uint256 userBalanceAfterFirstBorrow = dai.balanceOf(user);
        uint256 vaultBalanceAfterFirstBorrow = dai.balanceOf(address(vault));

        // Assert first borrow
        assertEq(
            userBalanceAfterFirstBorrow,
            userBalanceBeforeBorrow + borrowAmount,
            "User's balance of DAI should increase after borrowing"
        );
        assertEq(
            vaultBalanceAfterFirstBorrow,
            vaultBalanceBeforeBorrow - borrowAmount,
            "Vault's balance of DAI should decrease after borrowing"
        );
        assertEq(
            userDebtAfterFirstBorrow,
            borrowAmount,
            "User's debt should match the borrowed amount"
        );
    }
}
