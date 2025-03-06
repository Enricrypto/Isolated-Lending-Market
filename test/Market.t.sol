// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import "lib/forge-std/src/Test.sol";
// import "lib/forge-std/src/console.sol";
// import "../src/Vault.sol";
// import "../src/Market.sol";
// import "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

// contract MarketTest is Test {
//     Market public market;
//     Vault public daiVault;
//     IERC20 public dai;
//     IERC20 public usdt;

//     address public user;

//     function setUp() public {
//         // Fork the Arbitrum mainnet at the latest block
//         vm.createSelectFork(
//             "https://arb-mainnet.g.alchemy.com/v2/ADLPIIv6SUjhmaoJYxWLHKDUDaw8RnRj",
//             293933340
//         );

//         // Set up a user address
//         user = address(0x123);

//         // send some Ether to the user
//         vm.deal(user, 10 ether);

//         // DAI and USDT addresses
//         dai = IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1); // DAI token address
//         usdt = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9); // USDT token address

//         // Any user can deploy a market (permissionless)
//         vm.startPrank(user);
//         market = new Market();
//         vm.stopPrank();

//         // Any user can deploy a vault for a token
//         vm.startPrank(user);
//         daiVault = new Vault(address(dai), "vDai", "vDAI");
//         vm.stopPrank();

//         // Any user can add a vault to the market
//         vm.startPrank(user);
//         market.addBorrowableVault(address(dai), address(daiVault));
//         vm.stopPrank();

//         // User approves the Market contract to spend their DAI
//         vm.startPrank(user);
//         dai.approve(address(market), type(uint256).max);
//         vm.stopPrank();

//         // Verify vault registration
//         address registeredVault = market.borrowableVaults(address(dai));
//         assertEq(
//             registeredVault,
//             address(daiVault),
//             "Vault registration failed"
//         );

//         // Impersonate a DAI whale to send DAI tokens to the user
//         address daiWhale = 0xd85E038593d7A098614721EaE955EC2022B9B91B;
//         vm.startPrank(daiWhale);
//         dai.transfer(user, 10000 * 1e18); // Transfer 10000 DAI to user
//         vm.stopPrank();

//         // Impersonate a USDT whale to send USDT tokens to the user
//         address usdtWhale = 0xF977814e90dA44bFA03b6295A0616a897441aceC;
//         vm.startPrank(usdtWhale);
//         usdt.transfer(user, 10000 * 1e6); // Transfer 10000 USDT to user
//         vm.stopPrank();

//         // User approves the Market contract to spend their DAI and USDT
//         vm.startPrank(user);
//         dai.approve(address(market), type(uint256).max);
//         usdt.approve(address(market), type(uint256).max);
//         vm.stopPrank();

//         // Whale approves the Market contract to spend their DAI
//         vm.startPrank(daiWhale);
//         dai.approve(address(market), type(uint256).max);
//         vm.stopPrank();
//     }

//     // Test Add Collateral Token to market
//     function testAddCollateralToken() public {
//         address collateralToken = address(usdt); // Example token address
//         uint256 ltvRatio = 75; // 75% LTV Ratio

//         vm.startPrank(user); // Any user can now add collateral and set LTV
//         market.addCollateralToken(collateralToken, ltvRatio);
//         vm.stopPrank();

//         // Assert that the supportedCollateral mapping is now supported
//         assertEq(
//             market.supportedCollateralTokens(collateralToken),
//             true,
//             "Collateral supported by market"
//         );

//         assertEq(
//             market.getLTVRatio(collateralToken),
//             ltvRatio,
//             "LTV Ratio has been set correctly"
//         );
//     }

//     // Test depositCollateral for DAI
//     function testDepositCollateral() public {
//         address collateralToken = address(usdt); // USDT as collateral
//         uint256 depositAmount = 5000 * 1e6; // 1000 USDT

//         // First, we add USDT as a collateral token
//         vm.startPrank(user);
//         market.addCollateralToken(collateralToken, 75); // 75% LTV
//         vm.stopPrank();

//         // Ensure the user has USDT before depositing
//         assertGe(
//             usdt.balanceOf(user),
//             depositAmount,
//             "User should have enough USDT"
//         );

//         // Deposit collateral into the market
//         vm.startPrank(user);
//         market.depositCollateral(collateralToken, depositAmount);
//         vm.stopPrank();

//         // Ensure the contract received the USDT
//         assertEq(
//             usdt.balanceOf(address(market)),
//             depositAmount,
//             "Market should receive deposited collateral"
//         );

//         // Ensure the user's collateral balance updated correctly
//         assertEq(
//             market.userCollateralBalances(user, collateralToken),
//             depositAmount,
//             "User's collateral balance should be updated"
//         );
//     }

//     // Test for withdraw Collateral
//     function testWithdrawCollateral() public {
//         address collateralToken = address(usdt);
//         uint256 depositAmount = 1000 * 1e6; // 1000 USDT
//         uint256 withdrawAmount = 500 * 1e6; // Withdraw 500 USDT

//         // First, we add USDT as a collateral token
//         vm.startPrank(user);
//         market.addCollateralToken(collateralToken, 75); // 75% LTV
//         vm.stopPrank();

//         // Ensure the user has USDT before depositing
//         uint256 initialbalance = usdt.balanceOf(user);
//         assertGe(initialbalance, depositAmount, "User should have enough USDT");

//         // Deposit collateral into the market
//         vm.startPrank(user);
//         market.depositCollateral(collateralToken, depositAmount);
//         vm.stopPrank();

//         // User's collateral balance should be updated
//         uint256 balanceAfterDeposit = usdt.balanceOf(user);
//         assertEq(
//             market.userCollateralBalances(user, collateralToken),
//             depositAmount,
//             "User should have deposited collateral"
//         );

//         // Withdraw collateral
//         vm.startPrank(user);
//         market.withdrawCollateral(collateralToken, withdrawAmount);
//         vm.stopPrank();

//         // Ensure the contract sent the USDT back to the user
//         assertEq(
//             usdt.balanceOf(user),
//             balanceAfterDeposit + withdrawAmount,
//             "User should receive withdrawn USDT"
//         );

//         // Ensure the user's collateral balance updated correctly
//         assertEq(
//             market.userCollateralBalances(user, collateralToken),
//             depositAmount - withdrawAmount,
//             "User's collateral balance should decrease"
//         );
//     }

//     // Test User deposits DAI into Vault & registers lending deposit
//     function testDepositLendToken() public {
//         uint256 depositAmount = 1000 * 1e18; // 1000 DAI

//         // Step 1: User registers the deposit in the Market
//         vm.startPrank(user);
//         market.depositLendToken(address(dai), depositAmount);
//         vm.stopPrank();

//         // Step 2: Verify the stored share balance in Market contract
//         uint256 registeredShares = market.lendShares(user, address(dai));
//         console.log("Registered Shares in Market:", registeredShares);

//         // Step 3: Verify the stored tokens balance in Market contract
//         uint256 registeredTokens = market.lendTokens(user, address(dai));
//         console.log("Registered Tokens in Market:", registeredTokens);

//         // Assert that the Market correctly tracks the user's vault shares
//         uint256 sharesReceived = daiVault.convertToShares(depositAmount); // Equivalent shares received
//         assertEq(
//             registeredShares,
//             sharesReceived,
//             "Market should track vault shares correctly"
//         );

//         // Assert that the registered token balance matches the amount deposited
//         uint256 tokensRegistered = daiVault.convertToAssets(sharesReceived);
//         assertEq(
//             registeredTokens,
//             tokensRegistered,
//             "Market should track tokens correctly based on shares"
//         );
//     }

//     function testWithdrawLendToken() public {
//         uint256 depositAmount = 1000 * 1e18; // 1000 DAI
//         uint256 withdrawAmount = 500 * 1e18; // Withdraw 500 DAI

//         // Step 1: User deposits DAI into the Market (which deposits into the Vault)
//         vm.startPrank(user);
//         market.depositLendToken(address(dai), depositAmount);
//         vm.stopPrank();

//         // Verify the balances after deposit
//         uint256 registeredShares = market.lendShares(user, address(dai));
//         uint256 registeredTokens = market.lendTokens(user, address(dai));

//         uint256 daiBalanceAfterDeposit = dai.balanceOf(user);
//         console.log("User DaiBalance after deposit:", daiBalanceAfterDeposit);

//         console.log("Registered Shares in Market:", registeredShares);
//         console.log("Registered Tokens in Market:", registeredTokens);

//         assertEq(
//             registeredTokens,
//             depositAmount,
//             "Market should track deposited tokens correctly"
//         );

//         // User approves the market contract to withdraw from the DAI Vault
//         vm.startPrank(user);
//         daiVault.approve(address(market), type(uint256).max);
//         vm.stopPrank();

//         console.log(
//             "Allowance of Market for Vault:",
//             IERC20(address(dai)).allowance(address(market), address(daiVault))
//         );

//         // Step 2: User withdraws from the Vault via the Market
//         vm.startPrank(user);
//         market.withdrawLendToken(address(dai), withdrawAmount);
//         vm.stopPrank();

//         // Verify the balances after withdrawal
//         uint256 remainingShares = market.lendShares(user, address(dai));
//         uint256 remainingTokens = market.lendTokens(user, address(dai));

//         console.log("Remaining Shares in Market:", remainingShares);
//         console.log("Remaining Tokens in Market:", remainingTokens);

//         assertEq(
//             remainingTokens,
//             depositAmount - withdrawAmount,
//             "Market should track withdrawn tokens correctly"
//         );

//         // Ensure the user's actual DAI balance increased after withdrawal
//         uint256 userDAIBalance = dai.balanceOf(user);
//         console.log("User's DAI Balance After Withdrawal:", userDAIBalance);
//         assertEq(
//             userDAIBalance,
//             daiBalanceAfterDeposit + withdrawAmount,
//             "User should receive the correct amount of DAI"
//         );
//     }

//     function testBorrow() public {
//         uint256 collateralAmount = 1000 * 1e6; // 1000 USDT
//         uint256 borrowAmount = 500 * 1e18; // 100 DAI
//         uint256 depositVault = 2000 * 1e18; // 2000 DAI
//         address daiWhale = 0xd85E038593d7A098614721EaE955EC2022B9B91B;
//         uint256 ltvRatio = 75;

//         // First, we add USDT as a collateral token
//         vm.startPrank(user);
//         market.addCollateralToken(address(usdt), ltvRatio); // 75% LTV
//         vm.stopPrank();

//         console.log("LTV for token:", address(usdt), "is", ltvRatio);

//         // Check the balance of the user for the borriwing token
//         uint256 initialDaiBalance = dai.balanceOf(user);
//         console.log("Initial DAI balance:", initialDaiBalance);

//         // Ensure the user has USDT before depositing
//         uint256 initialUsdtBalance = usdt.balanceOf(user);
//         assertGe(
//             initialUsdtBalance,
//             collateralAmount,
//             "User should have enough USDT"
//         );

//         // Deposit collateral into the market
//         vm.startPrank(user);
//         market.depositCollateral(address(usdt), collateralAmount);
//         vm.stopPrank();

//         // User's collateral balance should be updated
//         uint256 balanceAfterDeposit = usdt.balanceOf(user);
//         assertEq(
//             market.userCollateralBalances(user, address(usdt)),
//             collateralAmount,
//             "User should have deposited collateral"
//         );

//         // Get user's total collateral value
//         vm.startPrank(user);
//         uint256 totalCollateral = market.getTotalCollateralValue(user);
//         vm.stopPrank();
//         console.log("User's total collateral value:", totalCollateral);

//         vm.startPrank(daiWhale);
//         market.depositLendToken(address(dai), depositVault);
//         vm.stopPrank();

//         uint256 daiMarketBalance = dai.balanceOf(address(market));
//         console.log("daiMarketBalance:", daiMarketBalance);

//         // User tries to borrow within their availabkle collateral
//         vm.startPrank(user);
//         market.borrow(address(dai), borrowAmount);
//         vm.stopPrank();

//         // Assert that the user received the correct amount of borrowed tokens
//         uint256 userBalance = dai.balanceOf(user);
//         assertEq(
//             userBalance,
//             initialDaiBalance + borrowAmount,
//             "User should have received the correct amount of borrowed tokens"
//         );
//     }
// }
