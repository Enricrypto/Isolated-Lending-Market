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

    address badDebtAddress = 0xabCDEF1234567890ABcDEF1234567890aBCDeF12;
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
            address(badDebtAddress),
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

        // Impersonate USDC whale to send tokens to the liquidator
        vm.startPrank(usdcWhale);
        usdc.transfer(liquidator, initialBalance); // whale transfers to liquidator
        vm.stopPrank();

        // Now impersonate liquidator to approve market
        vm.startPrank(liquidator);
        usdc.approve(address(market), type(uint256).max);
        vm.stopPrank();

        // Approve the vault contract for the lender to deposit USDC
        vm.startPrank(lender);
        usdc.approve(address(vault), type(uint256).max); // Approve max amount
        vm.stopPrank();

        // Approve the market contract for the user to use WETH as collateral
        vm.startPrank(user);
        weth.approve(address(market), type(uint256).max);
        vm.stopPrank();

        // Approve the market contract for the user to deposit USDC (repay)
        vm.startPrank(user);
        usdc.approve(address(market), type(uint256).max);
        vm.stopPrank();

        // Simulate the vault contract approving the market contract
        vm.startPrank(address(market));
        usdc.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        // Set the market parameters (these can be whatever defaults you want for most tests)
        uint256 lltv = 0.8e18; // 80%
        uint256 liquidationPenalty = 0.05e18; // 5%
        uint256 protocolFeeRate = 0.1e18; // 10% protocol fee rate

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
        address collateralToken = address(weth);
        address priceFeed = address(wethPrice);
        uint256 lentAmount = 7000 * 1e6; // 5000 USDC
        uint256 depositAmount = 3 * 1e18; // 3 WETH
        uint256 borrowAmount1 = 1000 * 1e6; // First borrow: 1000 USDC
        uint256 borrowAmount2 = 4000 * 1e6; // Second borrow: 2000 USDC

        // Lender deposits USDC into the vault
        vm.startPrank(lender);
        vault.deposit(lentAmount, lender);
        vm.stopPrank();

        // Add collateral token to the market
        vm.startPrank(address(this));
        market.addCollateralToken(collateralToken, priceFeed);
        vm.stopPrank();

        // User deposits collateral into the market
        vm.startPrank(user);
        market.depositCollateral(collateralToken, depositAmount);
        // Fetch and log user's collateral balance
        uint256 userBalance = market.getUserTotalCollateralValue(user);
        console.log("User collateral balance in market: %s", userBalance);
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

        assertApproxEqAbs(
            vaultAssetsAfter,
            strategyAssets + borrowedTotal,
            36e6, // 36 USDC difference
            "Vault totalAssets should equal strategy + borrows"
        );

        assertLe(
            liquidityAfter,
            strategyAssets,
            "Available liquidity should not exceed what strategy can redeem"
        );

        assertGt(liquidityAfter, 0, "There should still be some liquidity");
    }

    function testRepay() public {
        uint256 lentAmount = 5000 * 1e6; // 5000 USDC
        uint256 depositAmount = 2 * 1e18; // 2 WETH
        uint256 borrow1 = 2000 * 1e6; // First borrow
        uint256 borrow2 = 1000 * 1e6; // Second borrow

        // Lender deposits to vault
        vm.startPrank(lender);
        vault.deposit(lentAmount, lender);
        vm.stopPrank();

        // Add WETH as collateral token
        market.addCollateralToken(address(weth), wethPrice);

        // User deposits collateral
        vm.startPrank(user);
        market.depositCollateral(address(weth), depositAmount);
        vm.stopPrank();

        // First borrow
        vm.startPrank(user);
        uint256 userBalBefore = market.userTotalDebt(user);
        uint256 normalizedUserBalBefore = market.testNormalizeAmount(
            userBalBefore,
            6
        ); // 18 decimals
        market.borrow(borrow1);
        vm.stopPrank();

        uint256 normalizedBorrow1 = market.testNormalizeAmount(borrow1, 6); // 18 decimals
        assertEq(market.userTotalDebt(user), normalizedBorrow1);

        // Advance time & second borrow
        vm.warp(block.timestamp + 1 days);

        vm.startPrank(user);
        market.borrow(borrow2);
        vm.stopPrank();

        uint256 totalBorrowed = borrow1 + borrow2;
        uint256 normalizedtotalBorrowed = market.testNormalizeAmount(
            totalBorrowed,
            6
        ); // 18 decimals

        // Advance time & accrue interest
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(user);
        market.updateGlobalBorrowIndex();
        uint256 interest = market.getBorrowerInterestAccrued(user);
        vm.stopPrank();

        // Calculate repayment portions
        uint256 partialRepay = totalBorrowed / 2;
        uint256 normalizedPartialRepay = market.testNormalizeAmount(
            partialRepay,
            6
        ); // 18 decimals

        // Final repay from user
        vm.startPrank(user);
        market.repay(partialRepay);
        vm.stopPrank();

        // Final assertions
        assertEq(
            market.userTotalDebt(user),
            normalizedtotalBorrowed + interest - normalizedPartialRepay
        );

        uint256 userBalance = usdc.balanceOf(user);
        uint256 normalizedUserBal = market.testNormalizeAmount(userBalance, 6);

        assertEq(
            normalizedUserBal,
            normalizedUserBalBefore +
                normalizedtotalBorrowed -
                normalizedPartialRepay
        );
    }

    function testPauseCollateralTriggersLiquidationRisk() public {
        address collateralToken = address(weth);
        address priceFeed = wethPrice;
        uint256 lentAmount = 5000 * 1e6; // 5000 USDC
        uint256 depositAmount = 2 * 1e18; // 2 WETH
        uint256 borrowAmount = 2000 * 1e6; // 2000 USDC

        // Lender deposits USDC into the vault
        vm.startPrank(lender);
        vault.deposit(lentAmount, lender);
        vm.stopPrank();

        // Add collateral token to the market
        vm.startPrank(address(this));
        market.addCollateralToken(collateralToken, priceFeed);
        vm.stopPrank();

        // User deposits collateral
        vm.startPrank(user);
        market.depositCollateral(collateralToken, depositAmount);
        vm.stopPrank();

        // User borrows
        vm.startPrank(user);
        market.borrow(borrowAmount);
        vm.stopPrank();

        // Confirm user is NOT at risk of liquidation yet
        bool initialLiquidationRisk = market.isUserAtRiskOfLiquidation(user);
        assertFalse(
            initialLiquidationRisk,
            "User should not be at liquidation risk initially"
        );

        // Owner pauses collateral deposits for WETH
        address marketOwner = market.owner();
        vm.startPrank(marketOwner);
        market.pauseCollateralDeposits(collateralToken);
        vm.stopPrank();

        // After pausing, the collateral no longer contributes to borrowing power
        // So user should now be at risk of liquidation
        bool postPauseLiquidationRisk = market.isUserAtRiskOfLiquidation(user);
        assertTrue(
            postPauseLiquidationRisk,
            "User should be at risk of liquidation after collateral paused"
        );

        assertFalse(market.isHealthy(user)); // user at risk

        // Resume the collateral
        vm.prank(marketOwner);
        market.resumeCollateralDeposits(address(collateralToken));

        // Now check that the user's position is healthy again
        assertTrue(market.isHealthy(user)); // should now be healthy
    }

    function testValidateAndCalculateMaxLiquidation() public {
        address collateralToken = address(weth);
        address priceFeed = wethPrice;
        uint256 lentAmount = 10_000 * 1e6; // 10000 USDC
        uint256 depositAmount = 2 * 1e18; // 2 WETH
        uint256 borrowAmount = 4200 * 1e6; // 4200 USDC

        // ====== SETUP ======

        // Lender deposits USDC liquidity into the vault
        vm.startPrank(lender);
        vault.deposit(lentAmount, lender);
        vm.stopPrank();

        // Add WETH as collateral with proper price feed
        vm.prank(address(this));
        market.addCollateralToken(collateralToken, priceFeed);

        // Assert token decimals stored correctly (WETH should have 18 decimals)
        assertEq(
            market.tokenDecimals(collateralToken),
            18,
            "Incorrect token decimals stored for WETH"
        );

        // Save pre-deposit balances
        uint256 marketBalanceBefore = weth.balanceOf(address(market));
        uint256 userBalanceBefore = weth.balanceOf(user);

        // User deposits WETH collateral
        vm.startPrank(user);
        market.depositCollateral(collateralToken, depositAmount);
        vm.stopPrank();

        // Assert that user's collateral value is now non-zero
        uint256 totalCollateralBefore = market.getUserTotalCollateralValue(
            user
        );
        assertGt(
            totalCollateralBefore,
            0,
            "Collateral value should be greater than 0 after deposit"
        );

        // Assert market received the correct WETH amount
        assertEq(
            weth.balanceOf(address(market)),
            marketBalanceBefore + depositAmount,
            "Market did not receive WETH"
        );

        // Assert user's WETH balance decreased accordingly
        assertEq(
            weth.balanceOf(user),
            userBalanceBefore - depositAmount,
            "User's WETH balance not reduced correctly"
        );

        // User borrows USDC
        vm.startPrank(user);
        market.borrow(borrowAmount);
        vm.stopPrank();

        // Assert debt recorded
        assertEq(
            market.getUserTotalDebt(user),
            market.testNormalizeAmount(borrowAmount, 6),
            "User debt not recorded correctly"
        );

        // ====== PRICE DROP SIMULATION ======

        // Simulate time passing
        vm.warp(block.timestamp + 10 days);
        market.updateGlobalBorrowIndex();

        // Simulate a 30% drop in WETH price
        int256 oldPrice = priceOracle.getLatestPrice(collateralToken);
        int256 newPrice = (oldPrice * 70) / 100;

        // Mock the oracle to return new price
        vm.mockCall(
            address(priceOracle),
            abi.encodeWithSignature("getLatestPrice(address)", collateralToken),
            abi.encode(newPrice)
        );

        // Assert that the new collateral value has dropped after price change
        uint256 totalCollateralAfter = market.getUserTotalCollateralValue(user);
        assertLt(
            totalCollateralAfter,
            totalCollateralBefore,
            "Collateral value did not decrease after price drop"
        );

        // ====== LIQUIDATION VALIDATION ======

        vm.startPrank(liquidator);

        // Assert that user is now unhealthy and should be liquidatable
        assertFalse(
            market.isHealthy(user),
            "User should be liquidatable after price drop"
        );

        // Get liquidation values
        (uint256 debtToCover, uint256 collateralToSeizeUsd) = market
            .validateAndCalculateMaxLiquidation(user);

        // Assert calculated values are non-zero
        assertGt(debtToCover, 0, "Debt to cover should be greater than 0");
        assertGt(
            collateralToSeizeUsd,
            0,
            "Collateral to seize should be greater than 0"
        );

        // Save pre-liquidation balances
        uint256 protocolTreasuryBefore = usdc.balanceOf(protocolTreasury);
        uint256 liquidatorUSDCBefore = usdc.balanceOf(liquidator);
        uint256 vaultAssetsBefore = vault.totalAssets();

        // Liquidator repays the debt
        market.processLiquidatorRepaymentPublic(user, liquidator, debtToCover);

        // Assert that vault received repayment
        assertGt(
            vault.totalAssets(),
            vaultAssetsBefore,
            "Vault totalAssets should increase after repayment"
        );

        // Assert protocol treasury received liquidation fee
        assertGt(
            usdc.balanceOf(protocolTreasury),
            protocolTreasuryBefore,
            "Protocol treasury should receive fee"
        );

        // Assert liquidator paid some USDC
        assertLt(
            usdc.balanceOf(liquidator),
            liquidatorUSDCBefore,
            "Liquidator USDC balance should decrease after repayment"
        );

        // Save pre-seizure WETH balances
        uint256 liquidatorWETHBefore = weth.balanceOf(liquidator);

        // Liquidator seizes collateral
        (uint256 totalLiquidated, uint256 remainingToSeizeUsd) = market
            .seizeCollateralPublic(user, liquidator, collateralToSeizeUsd);

        uint256 liquidatorWETHAfter = weth.balanceOf(liquidator);

        // Assert liquidator received WETH
        assertGt(
            liquidatorWETHAfter,
            liquidatorWETHBefore,
            "Liquidator did not receive WETH"
        );

        // Assert full collateral was liquidated (with tolerance for rounding)
        assertApproxEqAbs(
            totalLiquidated,
            collateralToSeizeUsd,
            1e12,
            "Total liquidated does not match expected collateral to seize"
        );

        // Assert there is no leftover collateral to seize
        assertEq(
            remainingToSeizeUsd,
            0,
            "Remaining collateral to seize should be zero"
        );

        vm.stopPrank();
    }
}
