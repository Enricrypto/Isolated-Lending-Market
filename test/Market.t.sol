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
    address public liquidator;
    IERC20 public usdc; // testing with USDC as the loan asset
    IERC20 public weth; // collateral asset
    address public wethPrice;
    address public usdcPrice;

    address protocolTreasury = 0x1234567890AbcdEF1234567890aBcdef12345678;
    address usdcAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC address on Ethereum
    address wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH address on Ethereum
    address wethPriceAddress = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // ETH price feed address on Ethereum
    address usdcPriceAddress = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6; // USDC price feed address on Ethereum
    address yearnUsdcStrategy = 0xBe53A109B494E5c9f97b9Cd39Fe969BE68BF6204;

    uint256 public initialDeposit = 5000 * 1e18; // 5000 tokens
    uint256 public initialBalance = 10000 * 1e6; // 10000 USDC for user
    uint256 public wethAmount = 5000 * 1e18; // 5000 WETH transfer to user
    uint256 public initialLiquidatorBalance = 8000 * 1e6; // 8000 USDC for user

    function setUp() public {
        // Fork the Ethereum mainnet at the latest block
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        // Initialize the DAI and WETH instance
        usdc = IERC20(usdcAddress);
        weth = IERC20(wethAddress);

        // Initialize price feed addresses
        wethPrice = wethPriceAddress;
        usdcPrice = usdcPriceAddress;

        // InterestRateModel parameters
        uint256 baseRate = 0.02e18; // 2% base rate
        uint256 optimalUtilization = 0.8e18; // 80% optimal utilization
        uint256 slope1 = 0.1e18; // 10% slope1
        uint256 slope2 = 0.5e18; // 50% slope2

        // Deploy contracts
        vault = new Vault(
            usdc,
            address(0),
            yearnUsdcStrategy,
            "Vault USDC",
            "VUSDC"
        );

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
            address(protocolTreasury),
            address(vault),
            address(priceOracle),
            address(interestRateModel),
            address(usdc)
        );

        // Set the price feeds in the Oracle (using addPriceFeed function)
        priceOracle.addPriceFeed(address(weth), wethPrice); // Register WETH price feed
        priceOracle.addPriceFeed(address(usdc), usdcPrice); // Register USDC price feed

        // Set the correct market address in Vault
        vault.setMarket(address(market));

        // Set the correct market address in InterestRateModel
        interestRateModel.setMarketContract(address(market));

        // Set up account
        user = address(0x123);
        lender = address(0x124);
        liquidator = address(0x125);

        // send some Ether to the user for gas
        vm.deal(user, 10 ether);

        // Impersonate a USDC whale to send tokens to the lender
        address usdcWhale = 0xaD354CfBAa4A8572DD6Df021514a3931A8329Ef5; // Replace with a valid USDC whale address
        vm.startPrank(usdcWhale);
        usdc.transfer(lender, initialBalance); // Transfer 10,000 USDC to user
        vm.stopPrank();

        // Impersonate a WETH whale to send tokens to the user
        address wethWhale = 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E; // Replace with a valid WETH whale address
        vm.startPrank(wethWhale);
        weth.transfer(user, wethAmount); // Transfer 5,000 WETH to user
        vm.stopPrank();

        // Impersonate a USDC whale to send tokens to the liquidator
        vm.startPrank(usdcWhale);
        usdc.transfer(liquidator, initialLiquidatorBalance); // Transfer 10,000 USDC to user
        vm.stopPrank();

        // Approve the vault contract for the lender to deposit USDC
        vm.startPrank(lender);
        usdc.approve(address(vault), type(uint256).max); // Approve max amount
        vm.stopPrank();

        // Approve the market contract for the user to use WETH as collateral
        vm.startPrank(user);
        weth.approve(address(market), type(uint256).max);
        vm.stopPrank();
        console.log("Owner:", address(this));

        // Approve the market contract for the user to deposit USDC (repay)
        vm.startPrank(user);
        usdc.approve(address(market), type(uint256).max);
        vm.stopPrank();

        //Approve the market contract for liquidator to transfer USDC (liquidator repayment)
        vm.startPrank(liquidator);
        usdc.approve(address(market), type(uint256).max);
        vm.stopPrank();

        // Simulate the vault contract approving the market contract
        vm.startPrank(address(market));
        usdc.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        // Set the market parameters (these can be whatever defaults you want for most tests)
        uint256 lltv = 0.8e18; // 80%
        uint256 liquidationPenalty = 0.05e18; // 5%
        uint256 protocolFeeRate = 1e17; // 10% protocol fee rate

        vm.startPrank(address(this)); // Make sure you act as the admin/owner here
        market.setMarketParameters(lltv, liquidationPenalty, protocolFeeRate);
        vm.stopPrank();
    }

    // Function to retrieve the current price of WETH in USD
    function testGetWethPrice() public view returns (int256) {
        // Fetch the latest price of WETH in USD from the PriceOracle
        int256 wethPriceInUSD = priceOracle.getLatestPrice(address(weth));
        return wethPriceInUSD;
    }

    // Test the setMarketParameters function
    function testSetMarketParameters() public {
        // Define new parameters to test
        uint256 lltv = 0.8e18; // Example: 80% liquidation loan-to-value
        uint256 liquidationPenalty = 0.05e18; // Example: 5% liquidation penalty
        uint256 protocolFeeRate = 1e17; // 10% fee rate

        // Call the setMarketParameters function to update the parameters
        vm.startPrank(address(this));
        market.setMarketParameters(lltv, liquidationPenalty, protocolFeeRate);

        // Fetch the market parameters from the contract by destructuring the struct
        (
            uint256 storedLltv,
            uint256 storedLiquidationPenalty,
            uint256 storedProtocolFeeRate
        ) = market.marketParams();
        vm.stopPrank();

        // Assertions to verify the parameters have been updated correctly
        assertEq(storedLltv, lltv, "Liquidation loan-to-value mismatch");
        assertEq(
            storedLiquidationPenalty,
            liquidationPenalty,
            "Liquidation Penalty mismatch"
        );
        assertEq(
            storedProtocolFeeRate,
            protocolFeeRate,
            "Protocol fee rate mismatch"
        );
    }

    // Test Add Collateral Token to market
    function testAddCollateralToken() public {
        address collateralToken = address(weth);
        address priceFeed = wethPrice;

        vm.startPrank(address(this)); // Contract owner adds collateral and set LTV
        market.addCollateralToken(collateralToken, priceFeed);
        vm.stopPrank();

        // Assert that the supportedCollateral mapping is now supported
        assertEq(
            market.supportedCollateralTokens(collateralToken),
            true,
            "Collateral supported by market"
        );
    }

    function testResumeCollateralDeposits() public {
        address collateralToken = address(weth);
        address priceFeed = address(wethPrice);

        // Add collateral token
        vm.startPrank(address(this));
        market.addCollateralToken(collateralToken, priceFeed);
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

        // add Collateral Token
        vm.startPrank(address(this));
        market.addCollateralToken(collateralToken, priceFeed);
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
        uint256 depositAmount = 1000 * 1e18;
        uint256 withdrawAmount = 500 * 1e18;

        // Add collateral token
        vm.startPrank(address(this));
        market.addCollateralToken(collateralToken, priceFeed);
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
        address loanAsset = address(usdc);
        address collateralToken = address(weth);
        address priceFeed = address(wethPrice);
        uint256 lentAmount = 5000 * 1e6; // 5000 USDC
        uint256 depositAmount = 3 * 1e18; // 3 WETH
        uint256 borrowAmount1 = 1000 * 1e6; // First borrow: 1000 USDC
        uint256 borrowAmount2 = 500 * 1e6; // Second borrow: 500 USDC

        // Lender deposits USDC into the vault
        vm.startPrank(lender);
        vault.deposit(lentAmount, lender);
        vm.stopPrank();

        uint256 shares = IERC20(yearnUsdcStrategy).balanceOf(address(vault));
        uint256 usdcInStrategy = ERC4626(yearnUsdcStrategy).convertToAssets(
            shares
        );
        uint256 vaultAssets = vault.convertToAssets(vault.totalSupply());

        console.log("Shares hold by vault after", shares);
        console.log("USDC in strategy", usdcInStrategy);
        console.log("vault assets", vaultAssets);

        // Add collateral token to the market
        vm.startPrank(address(this));
        market.addCollateralToken(collateralToken, priceFeed);
        vm.stopPrank();

        // User deposits collateral into the market
        vm.startPrank(user);
        market.depositCollateral(collateralToken, depositAmount);
        vm.stopPrank();

        // First borrow
        vm.startPrank(user);
        market.borrow(borrowAmount1);
        vm.stopPrank();

        // Simulate time passing to trigger interest accrual
        vm.warp(block.timestamp + 5 days);

        // Update interest and global borrow index without user interaction
        vm.startPrank(address(this));
        market.updateGlobalBorrowIndex();
        vm.stopPrank();

        // Second borrow
        vm.startPrank(user);
        market.borrow(borrowAmount2);
        vm.stopPrank();

        // Validate vault state after borrowing
        uint256 borrowedTotal = borrowAmount1 + borrowAmount2;
        uint256 vaultAssetsAfter = vault.totalAssets();
        uint256 liquidityAfter = vault.availableLiquidity();
        uint256 strategyAssets = ERC4626(yearnUsdcStrategy).convertToAssets(
            IERC20(yearnUsdcStrategy).balanceOf(address(vault))
        );

        console.log("Vault totalAssets after borrow", vaultAssetsAfter);
        console.log("Vault availableLiquidity after borrow", liquidityAfter);
        console.log("Vault strategy assets after borrow", strategyAssets);

        assertApproxEqAbs(
            vaultAssetsAfter,
            strategyAssets + borrowedTotal,
            5e6,
            "Vault totalAssets should equal strategy + borrows"
        );

        assertLe(
            liquidityAfter,
            strategyAssets,
            "Available liquidity should not exceed what strategy can redeem"
        );

        assertGt(liquidityAfter, 0, "There should still be some liquidity");
    }
}
//     function testRepay() public {
//         address collateralToken = address(weth);
//         address priceFeed = wethPrice;
//         uint256 lentAmount = 5000 * 1e18; // 5000 DAI
//         uint256 depositAmount = 2 * 1e18; // 2 WETH
//         uint256 borrowAmount = 2000 * 1e18; // 2000 DAI
//         uint256 additionalBorrowAmount = 1000 * 1e18; // Additional borrow: 500 DAI

//         // Lender deposits DAI into the vault
//         vm.startPrank(lender);
//         vault.deposit(lentAmount, lender);
//         vm.stopPrank();

//         // Add collateral token to the market
//         vm.startPrank(address(this));
//         market.addCollateralToken(collateralToken, priceFeed);
//         vm.stopPrank();

//         // User deposits collateral into the market
//         vm.startPrank(user);
//         market.depositCollateral(collateralToken, depositAmount);
//         // uint256 collateralValue = market.getUserTotalCollateralValue(user);
//         // console.log("Collateral value:", collateralValue);
//         vm.stopPrank();

//         // Initial borrowing checks
//         uint256 userBalanceBeforeBorrow = dai.balanceOf(user);
//         uint256 vaultBalanceBeforeBorrow = dai.balanceOf(address(vault));

//         // User borrows for the first time
//         vm.startPrank(user);
//         market.borrow(borrowAmount);
//         vm.stopPrank();

//         uint256 userDebtAfterFirstBorrow = market.userTotalDebt(user);
//         uint256 userBalanceAfterFirstBorrow = dai.balanceOf(user);
//         uint256 vaultBalanceAfterFirstBorrow = dai.balanceOf(address(vault));

//         // Assert first borrow
//         assertEq(
//             userBalanceAfterFirstBorrow,
//             userBalanceBeforeBorrow + borrowAmount,
//             "User's balance of DAI should increase after borrowing"
//         );
//         assertEq(
//             vaultBalanceAfterFirstBorrow,
//             vaultBalanceBeforeBorrow - borrowAmount,
//             "Vault's balance of DAI should decrease after borrowing"
//         );
//         assertEq(
//             userDebtAfterFirstBorrow,
//             borrowAmount,
//             "User's debt should match the borrowed amount"
//         );

//         // Simulate time passing to trigger interest accrual
//         uint256 timeToElapse = 1 days;
//         vm.warp(block.timestamp + timeToElapse);

//         // User borrows again
//         vm.startPrank(user);
//         market.borrow(additionalBorrowAmount);
//         vm.stopPrank();

//         uint256 userDebtAfterSecondBorrow = market.userTotalDebt(user);
//         uint256 userBalanceAfterSecondBorrow = dai.balanceOf(user);
//         uint256 vaultBalanceAfterSecondBorrow = dai.balanceOf(address(vault));
//         uint256 totalBorrowed = borrowAmount + additionalBorrowAmount;

//         // Assert second borrow
//         assertEq(
//             userBalanceAfterSecondBorrow,
//             userBalanceAfterFirstBorrow + additionalBorrowAmount,
//             "User's balance of DAI should increase after second borrowing"
//         );
//         assertEq(
//             vaultBalanceAfterSecondBorrow,
//             vaultBalanceAfterFirstBorrow - additionalBorrowAmount,
//             "Vault's balance of DAI should decrease after second borrowing"
//         );
//         assertGt(
//             userDebtAfterSecondBorrow,
//             userDebtAfterFirstBorrow,
//             "User's debt should increase after second borrow"
//         );

//         // Partial repayment
//         uint256 partialRepayment = totalBorrowed / 2;

//         // Simulate time passing to trigger interest accrual
//         uint256 timeToAdvance = 1 days;
//         vm.warp(block.timestamp + timeToAdvance);

//         // uint256 beforeGlobalBorrowIndex = market.globalBorrowIndex();
//         // console.log("Before global borrow index:", beforeGlobalBorrowIndex);

//         vm.startPrank(user);
//         market.updateGlobalBorrowIndex();

//         // uint256 afterGlobalBorrowIndex = market.globalBorrowIndex();
//         // console.log("After global borrow index:", afterGlobalBorrowIndex);

//         // uint256 interestAccrued = market.borrowerInterestAccrued(user);
//         // console.log("Interest accrued:", interestAccrued);

//         // uint256 principalRepayment = partialRepayment - interestAccrued;
//         // console.log("Principal Repayment:", principalRepayment);
//         // console.log("Partial Repayment:", partialRepayment);

//         // (, , uint256 protocolFeeRate) = market.marketParams();

//         // uint256 protocolFee = (interestAccrued * protocolFeeRate) / 1e18;
//         // console.log("Protocol Fee", protocolFee);

//         // uint256 interestToVault = interestAccrued - protocolFee;
//         // console.log("Interest to vault", interestToVault);

//         // uint256 principal = partialRepayment > interestAccrued
//         //     ? partialRepayment - interestAccrued
//         //     : 0;
//         // console.log("Principal", principal);

//         // uint256 netRepayToVault = principal + interestToVault;
//         // console.log("Net repay to vault:", netRepayToVault);

//         // dai.transferFrom(user, address(market), partialRepayment);

//         // // Pay the protocol fee (interest portion)
//         // dai.transfer(protocolTreasury, protocolFee);

//         // console.log(
//         //     "protocol treasury balance:",
//         //     dai.balanceOf(address(protocolTreasury))
//         // );
//         // vm.stopPrank();

//         // uint256 marketDaiBalance = dai.balanceOf(address(market));
//         // console.log("Market DAI balance:", marketDaiBalance);

//         // vm.startPrank(address(market));
//         // vault.adminRepay(netRepayToVault);

//         // uint256 vaultDaiBalance = dai.balanceOf(address(vault));
//         // console.log("Vault DAI Balance:", vaultDaiBalance);
//         uint256 interestAccrued = market.getBorrowerInterestAccrued(user);

//         vm.startPrank(user);
//         market.repay(partialRepayment);
//         vm.stopPrank();

//         uint256 userDebtAfterRepay = market.userTotalDebt(user);
//         uint256 userBalanceAfterRepay = dai.balanceOf(user);
//         // uint256 vaultBalanceAfterRepay = dai.balanceOf(address(vault));

//         // Assert partial repayment
//         assertEq(
//             userDebtAfterRepay,
//             userDebtAfterSecondBorrow + interestAccrued - partialRepayment,
//             "User's debt should decrease by the repaid amount"
//         );
//         assertEq(
//             userBalanceAfterRepay,
//             userBalanceAfterSecondBorrow - partialRepayment,
//             "User's balance of DAI should decrease by the repaid amount"
//         );
//     }

//     function testValidateAndCalculateFullLiquidation() public {
//         address collateralToken = address(weth);
//         address priceFeed = wethPrice;
//         uint256 lentAmount = 10000 * 1e18; // 10000 DAI
//         uint256 depositAmount = 3 * 1e18; // 3 WETH
//         uint256 borrowAmount = 4700 * 1e18; // 4700 DAI

//         // Lender deposits DAI into the vault
//         vm.startPrank(lender);
//         vault.deposit(lentAmount, lender);
//         vm.stopPrank();

//         // Add collateral token to the market
//         vm.startPrank(address(this));
//         market.addCollateralToken(collateralToken, priceFeed);
//         vm.stopPrank();

//         // User deposits collateral into the market
//         vm.startPrank(user);
//         market.depositCollateral(collateralToken, depositAmount);
//         uint256 collateral = market.getUserTotalCollateralValue(user);
//         console.log("collateral", collateral);
//         vm.stopPrank();

//         console.log(dai.balanceOf(user));

//         // User borrows DAI
//         vm.startPrank(user);
//         market.borrow(borrowAmount);
//         vm.stopPrank();

//         // ====== SIMULATE COLLATERAL PRICE DROP ======
//         // Assume the WETH price drops by 30%, making the user go underwater.
//         int256 newPrice = (priceOracle.getLatestPrice(collateralToken) * 70) /
//             100;

//         // Mock the price oracle to return the new price
//         vm.mockCall(
//             address(priceOracle), // Contract to mock
//             abi.encodeWithSignature("getLatestPrice(address)", collateralToken),
//             abi.encode(newPrice) // New mocked price
//         );

//         vm.startPrank(liquidator);
//         // market.liquidate(user);
//         uint256 totalDebt = market.getUserTotalDebt(user);
//         console.log("Total debt:", totalDebt);
//         uint256 debtInUSD = market._loanDebtInUSD(totalDebt);
//         uint256 totalCollateral = market.getUserTotalCollateralValue(user);
//         console.log("Total collateral:", totalCollateral);

//         uint256 debtToCover = debtInUSD;
//         console.log("Debt to cover", debtToCover);

//         (, uint256 liquidationPenalty, ) = market.marketParams();
//         uint256 collateralToSeizeUsd = Math.mulDiv(
//             debtToCover,
//             1e18 + liquidationPenalty,
//             1e18
//         );
//         console.log("Collateral to seize USD", collateralToSeizeUsd);
//     }

//     function testProcessLiquidatorRepayment() public {
//         address collateralToken = address(weth);
//         address priceFeed = wethPrice;
//         uint256 lentAmount = 10000 * 1e18; // 10000 DAI
//         uint256 depositAmount = 3 * 1e18; // 3 WETH
//         uint256 borrowAmount = 4700 * 1e18; // 4700 DAI

//         // Lender deposits DAI into the vault
//         vm.startPrank(lender);
//         vault.deposit(lentAmount, lender);
//         vm.stopPrank();

//         // Add collateral token to the market
//         vm.startPrank(address(this));
//         market.addCollateralToken(collateralToken, priceFeed);
//         vm.stopPrank();

//         // User deposits collateral into the market
//         vm.startPrank(user);
//         market.depositCollateral(collateralToken, depositAmount);
//         uint256 collateral = market.getUserTotalCollateralValue(user);
//         console.log("collateral", collateral);
//         vm.stopPrank();

//         console.log(dai.balanceOf(user));

//         // User borrows DAI
//         vm.startPrank(user);
//         market.borrow(borrowAmount);
//         vm.stopPrank();

//         // ====== SIMULATE COLLATERAL PRICE DROP ======
//         // Assume the WETH price drops by 20%, making the user go underwater.
//         int256 newPrice = (priceOracle.getLatestPrice(collateralToken) * 80) /
//             100;

//         // Mock the price oracle to return the new price
//         vm.mockCall(
//             address(priceOracle), // Contract to mock
//             abi.encodeWithSignature("getLatestPrice(address)", collateralToken),
//             abi.encode(newPrice) // New mocked price
//         );

//         vm.startPrank(liquidator);
//         market.validateAndCalculateFullLiquidation(user);
//         // uint256 currentDebt = market.getUserTotalDebt(user);
//         // uint256 debtInUSD = market._loanDebtInUSD(currentDebt); // convert to USD
//         // uint256 collateralValue = market.getUserTotalCollateralValue(user); // in USD terms
//         // console.log("collateral value ", collateralValue);

//         // // Liquidator repays full debt
//         // uint256 debtToCover = debtInUSD;

//         // (, uint256 liquidationPenalty, ) = market.marketParams();
//         // // Calculate how much collateral should be seized (debt + liquidation penalty)
//         // uint256 collateralToSeizeUsd = Math.mulDiv(
//         //     debtToCover,
//         //     1e18 + liquidationPenalty,
//         //     1e18
//         // );
//         // console.log("collateral to seize USD", collateralToSeizeUsd);
//         vm.stopPrank();

//         // uint256 liquidatorBalance = IERC20(address(dai)).balanceOf(liquidator);
//         // console.log("Liquidator DAI balance:", liquidatorBalance);
//         // vm.startPrank(address(market));
//         // bool success = IERC20(address(dai)).transferFrom(
//         //     liquidator,
//         //     address(market),
//         //     debtToCover
//         // );
//         // assertTrue(success, "Transfer failed");
//         // vault.adminRepay(debtToCover);
//         // uint256 balanceAfterRepayment = IERC20(address(dai)).balanceOf(
//         //     liquidator
//         // );
//         // console.log("Balance After Repayment", balanceAfterRepayment);

//         // uint256 debtAfterRepayment = userDebt - debtToCover;
//         // console.log("Debt after repayment:", debtAfterRepayment);
//         // vm.stopPrank();
//     }
//     function testLentAssets() public {
//         address collateralToken = address(weth);
//         address priceFeed = wethPrice;
//         uint256 lentAmount = 5000 * 1e18; // 5000 DAI
//         uint256 depositAmount = 2 * 1e18; // 2 WETH
//         uint256 borrowAmount = 2000 * 1e18; // 2000 DAI

//         // Lender deposits DAI into the vault
//         vm.startPrank(lender);
//         vault.deposit(lentAmount, lender);
//         vm.stopPrank();

//         // Add collateral token to the market
//         vm.startPrank(address(this));
//         market.addCollateralToken(collateralToken, priceFeed);
//         vm.stopPrank();

//         // User deposits collateral into the market
//         vm.startPrank(user);
//         market.depositCollateral(collateralToken, depositAmount);
//         uint256 collateralValue = market.getUserTotalCollateralValue(user);
//         console.log("Collateral value:", collateralValue);
//         vm.stopPrank();

//         // User borrows for the first time
//         vm.startPrank(user);
//         market.borrow(borrowAmount);
//         vm.stopPrank();

//         // Check vault lent assets
//         uint256 totalBorrows = market.totalBorrows();
//         console.log("total Borrows", totalBorrows);

//         uint256 beforeGlobalBorrowIndex = market.globalBorrowIndex();
//         console.log("Before global borrow index:", beforeGlobalBorrowIndex);

//         // Simulate time passing to trigger interest accrual
//         uint256 timeToAdvance = 1 days;
//         vm.warp(block.timestamp + timeToAdvance);

//         market.updateGlobalBorrowIndex();

//         uint256 afterGlobalBorrowIndex = market.globalBorrowIndex();
//         console.log("After global borrow index:", afterGlobalBorrowIndex);

//         uint256 totalWithInterest = (totalBorrows *
//             market.globalBorrowIndex()) / 1e18;
//         console.log("Total with interest:", totalWithInterest);

//         uint256 totalAssets = vault.totalAssets();
//         console.log("Total assets:", totalAssets);
//     }
// }
