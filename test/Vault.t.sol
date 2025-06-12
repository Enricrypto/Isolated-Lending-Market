// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import "../src/Vault.sol";
import "../src/Market.sol";
import "../src/PriceOracle.sol";
import "../src/InterestRateModel.sol";
import "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

contract VaultTest is Test {
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

    uint256 public initialDeposit = 5000 * 1e6; // 5000 USDC
    uint256 public initialBalance = 10000 * 1e6; // 10000 USDC for user
    uint256 public wethAmount = 5000 * 1e18; // 5000 WETH transfer to user

    function setUp() public {
        // Fork the Ethereum mainnet at the latest block
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        // Initialize the USDC and WETH instances
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

        // Approve the vault contract for the lender to deposit USDC
        vm.startPrank(lender);
        usdc.approve(address(vault), type(uint256).max); // Approve max amount
        vm.stopPrank();

        // Approve the market contract for the user
        vm.startPrank(user);
        weth.approve(address(market), type(uint256).max);
        vm.stopPrank();

        // Simulate the market contract approving the vault contract
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

    // Test deposit function
    function testDeposit() public {
        uint256 depositAmount = initialDeposit;

        // Check the initial balance of the user and the vault
        uint256 initialLenderBalance = usdc.balanceOf(lender);
        uint256 initialVaultAssets = vault.totalAssets();
        uint256 initialLenderShares = vault.balanceOf(lender);
        console.log("Initial lender USDC balance:", initialLenderBalance);
        console.log("Initial vault assets balance:", initialVaultAssets);
        console.log("Initial lender shares balance:", initialLenderShares);

        // User deposits USDC into the vault
        vm.prank(lender);
        vault.deposit(depositAmount, lender);

        // Check the new balance of the lender and the vault
        uint256 newLenderBalance = usdc.balanceOf(lender);
        uint256 newVaultAssets = vault.totalAssets();
        uint256 newLenderShares = vault.balanceOf(lender);
        console.log("Lender shares balance after deposit:", newLenderShares);

        // Ensure the user's USDC balance decreased by the deposit amount
        assertEq(
            newLenderBalance,
            initialLenderBalance - depositAmount,
            "Lender's USDC balance didn't decrease after deposit"
        );

        // Ensure the vault's assets balance increased
        assertApproxEqAbs(
            newVaultAssets,
            initialVaultAssets + depositAmount,
            1, // allow 1 wei difference
            "Vault's assets balance didn't increase correctly"
        );

        // Assert the lender's shares balance is updated correctly
        assertGt(
            newLenderShares,
            initialLenderShares,
            "Lender shares should increase after deposit"
        );
    }

    function testWithdraw() public {
        uint256 depositAmount = initialDeposit; // 5000 USDC
        uint256 withdrawAmount = 3000 * 1e6; // 3000 USDC

        // Step 1: Lender deposits into the vault
        vm.prank(lender);
        vault.deposit(depositAmount, lender);

        // Step 2: Record balances before withdrawal
        uint256 vaultAssetsBefore = vault.totalAssets();
        uint256 lenderUsdcBefore = usdc.balanceOf(lender);
        uint256 lenderSharesBefore = vault.balanceOf(lender);

        // Step 3: Withdraw from vault
        vm.prank(lender);
        vault.withdraw(withdrawAmount, lender, lender);

        // Step 4: Record balances after withdrawal
        uint256 vaultAssetsAfter = vault.totalAssets();
        uint256 lenderUsdcAfter = usdc.balanceOf(lender);
        uint256 lenderSharesAfter = vault.balanceOf(lender);

        // Step 5: Assertions

        // USDC balance of lender should increase by approximately the withdrawal amount
        assertApproxEqAbs(
            lenderUsdcAfter,
            lenderUsdcBefore + withdrawAmount,
            1,
            "Lender USDC balance incorrect after withdrawal"
        );

        // Vault assets should decrease by the withdrawn amount
        assertApproxEqAbs(
            vaultAssetsAfter,
            vaultAssetsBefore - withdrawAmount,
            1,
            "Vault assets incorrect after withdrawal"
        );

        // Lender shares should decrease
        assertLt(
            lenderSharesAfter,
            lenderSharesBefore,
            "Lender shares did not decrease after withdrawal"
        );
    }

    function testMint() public {
        uint256 sharesToMint = 1000 * 1e6; // 1000 USDC worth of shares

        vm.startPrank(lender);
        uint256 assetsRequired = vault.previewMint(sharesToMint);
        console.log("Assets required for minting shares:", assetsRequired);

        uint256 balanceBefore = usdc.balanceOf(lender);

        uint256 actualAssetsUsed = vault.mint(sharesToMint, lender);
        console.log("Actual assets used:", actualAssetsUsed);

        uint256 balanceAfter = usdc.balanceOf(lender);
        uint256 vaultBalance = vault.totalAssets();

        console.log("USDC Balance Before:", balanceBefore);
        console.log("USDC Balance After:", balanceAfter);
        console.log("Vault Total Assets:", vaultBalance);

        assertEq(
            balanceBefore - balanceAfter,
            actualAssetsUsed,
            "Lender balance should decrease by amount used"
        );
        assertEq(
            vault.balanceOf(lender),
            sharesToMint,
            "Lender should receive correct number of shares"
        );

        vm.stopPrank();
    }

    function testRedeem() public {
        uint256 depositAmount = 5000 * 1e6; // 5000 USDC
        uint256 sharesToRedeem;

        // Lender deposits into the vault first
        vm.startPrank(lender);
        vault.deposit(depositAmount, lender);
        sharesToRedeem = vault.balanceOf(lender);
        vm.stopPrank();

        // Check initial balances
        uint256 lenderBalanceBefore = usdc.balanceOf(lender);
        uint256 vaultAssetsBefore = vault.totalAssets();
        uint256 lenderSharesBefore = vault.balanceOf(lender);

        // Redeem shares
        vm.startPrank(lender);
        uint256 assetsReceived = vault.redeem(sharesToRedeem, lender, lender);
        vm.stopPrank();

        // Check lender and vault balances after redeem
        uint256 lenderBalanceAfter = usdc.balanceOf(lender);
        uint256 vaultAssetsAfter = vault.totalAssets();
        uint256 lenderSharesAfter = vault.balanceOf(lender);

        // Assert shares burned
        assertEq(
            lenderSharesAfter,
            lenderSharesBefore - sharesToRedeem,
            "Shares should be burned"
        );

        // Assert assets returned to lender (approximate, small rounding differences possible)
        assertApproxEqAbs(
            lenderBalanceAfter,
            lenderBalanceBefore + assetsReceived,
            1,
            "Assets not returned correctly"
        );

        // Vault assets should decrease by roughly assetsReceived
        assertApproxEqAbs(
            vaultAssetsAfter,
            vaultAssetsBefore - assetsReceived,
            1,
            "Vault assets did not decrease correctly"
        );
    }

    function testAdminBorrow() public {
        uint256 depositAmount = 5000 * 1e6; // 5000 USDC
        uint256 borrowAmount = 1000 * 1e6; // 1000 USDC to borrow

        // Step 1: Lender deposits to vault to fund strategy
        vm.startPrank(lender);
        vault.deposit(depositAmount, lender);
        vm.stopPrank();

        // Check vault and strategy balances before borrow
        uint256 marketBalanceBefore = usdc.balanceOf(address(market));
        uint256 strategyAssetsBefore = vault.totalStrategyAssets();

        // Step 2: Simulate market calling adminBorrow
        vm.startPrank(address(market));
        vault.adminBorrow(borrowAmount);
        vm.stopPrank();

        // Check balances after borrow
        uint256 marketBalanceAfter = usdc.balanceOf(address(market));
        uint256 strategyAssetsAfter = vault.totalStrategyAssets();

        // Asserts

        // Market's balance should increase by borrowAmount
        assertApproxEqAbs(
            marketBalanceAfter,
            marketBalanceBefore + borrowAmount,
            1,
            "Market balance didn't increase correctly"
        );

        // Strategy assets should decrease accordingly (strategy withdrew funds)
        assertLt(
            strategyAssetsAfter,
            strategyAssetsBefore,
            "Strategy assets should decrease after withdraw"
        );
    }

    function testAdminRepay() public {
        uint256 deposit = 5000 * 1e6; // 5000 USDC
        uint256 repayAmount = 1000 * 1e6; // 1000 USDC to repay

        // Step 1: Lender deposits tokens to vault, which forwards to strategy
        vm.startPrank(lender);
        vault.deposit(deposit, lender);
        vm.stopPrank();

        // Step 2: Market balance setup - send market tokens to simulate it having funds to repay
        deal(address(usdc), address(market), repayAmount);

        // Record balances before repay
        uint256 marketBalanceBefore = usdc.balanceOf(address(market));
        uint256 strategyAssetsBefore = vault.totalStrategyAssets();

        // Step 3: Market approves vault to pull tokens and calls adminRepay
        vm.startPrank(address(market));
        usdc.approve(address(vault), repayAmount);
        vault.adminRepay(repayAmount);
        vm.stopPrank();

        // Record balances after repay
        uint256 vaultBalanceAfter = usdc.balanceOf(address(vault));
        uint256 marketBalanceAfter = usdc.balanceOf(address(market));
        uint256 strategyAssetsAfter = vault.totalStrategyAssets();

        // Assertions:

        // Market balance should decrease by repayAmount
        assertEq(
            marketBalanceAfter,
            marketBalanceBefore - repayAmount,
            "Market balance didn't decrease correctly"
        );

        // Vault balance should be near zero since tokens get forwarded to strategy
        assertLe(
            vaultBalanceAfter,
            1,
            "Vault balance should be near zero after repay"
        );

        // Strategy assets should increase by approx repayAmount
        assertApproxEqAbs(
            strategyAssetsAfter,
            strategyAssetsBefore + repayAmount,
            1,
            "Strategy assets didn't increase correctly"
        );
    }
}
