// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import "lib/forge-std/src/Test.sol";
// import "lib/forge-std/src/console.sol";
// import "../src/Vault.sol";
// import "../src/Market.sol";
// import "../src/PriceOracle.sol";
// import "../src/InterestRateModel.sol";
// import "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

// contract VaultTest is Test {
//     address treasuryAddress = 0x1234567890AbcdEF1234567890aBcdef12345678;
//     Vault public vault;
//     Market public market;
//     PriceOracle public priceOracle;
//     InterestRateModel public interestRateModel;
//     address public user;
//     IERC20 public dai; // testing with DAI as the loan asset
//     IERC20 public weth; // collateral asset

//     address daiAddress = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1; // DAI address on Arbitrum
//     address wethAddress = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH address on Arbitrum
//     address wethPriceAddress = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612; // WETH price feed address on Arbitrum

//     uint256 public initialDeposit = 5000 * 1e18; // 5000 tokens
//     uint256 public initialBalance = 10000 * 1e18; // 10000 DAI for user
//     uint256 public wethAmount = 5000 * 1e18; // 5000 WETH transfer to user

//     function setUp() public {
//         // Fork the Arbitrum mainnet at the latest block
//         vm.createSelectFork(
//             "https://arb-mainnet.g.alchemy.com/v2/ADLPIIv6SUjhmaoJYxWLHKDUDaw8RnRj",
//             312132545
//         );

//         // Initialize the DAI instance
//         dai = IERC20(daiAddress);
//         weth = IERC20(wethAddress);

//         // InterestRateModel parameters
//         uint256 baseRate = 0.02e18; // 2% base rate
//         uint256 optimalUtilization = 0.8e18; // 80% optimal utilization
//         uint256 slope1 = 0.1e18; // 10% slope1
//         uint256 slope2 = 0.5e18; // 50% slope2

//         // Deploy contracts
//         vault = new Vault(dai, address(0), "Vault Dai", "VDAI");

//         interestRateModel = new InterestRateModel(
//             baseRate,
//             optimalUtilization,
//             slope1,
//             slope2,
//             address(vault), // Vault contract address
//             address(0) // Placeholder market address
//         );

//         priceOracle = new PriceOracle();

//         market = new Market(
//             address(treasuryAddress),
//             address(vault),
//             address(priceOracle),
//             address(interestRateModel),
//             address(dai)
//         );

//         // Set the correct market address in Vault
//         vault.setMarket(address(market));

//         // Set the correct market address in InterestRateModel
//         interestRateModel.setMarketContract(address(market));

//         vm.startPrank(address(this)); // Start impersonating test contract
//         market.addCollateralToken(address(weth), address(wethPriceAddress));
//         vm.stopPrank();

//         // Set up account
//         user = address(0x123);

//         // send some Ether to the user for gas
//         vm.deal(user, 10 ether);

//         // Impersonate a DAI whale to send tokens to the user
//         address daiWhale = 0xd85E038593d7A098614721EaE955EC2022B9B91B; // Replace with a valid DAI whale address
//         vm.startPrank(daiWhale);
//         dai.transfer(user, initialBalance); // Transfer 10,000 DAI to user
//         vm.stopPrank();

//         // Impersonate a WETH whale to send tokens to the user
//         address wethWhale = 0xC6962004f452bE9203591991D15f6b388e09E8D0; // Replace with a valid WETH whale address
//         vm.startPrank(wethWhale);
//         weth.transfer(user, wethAmount); // Transfer 5,000 WETH to user
//         vm.stopPrank();

//         // Approve the vault contract for the user
//         vm.startPrank(user);
//         dai.approve(address(vault), type(uint256).max); // Approve max amount
//         vm.stopPrank();

//         // Approve the market contract for the user
//         vm.startPrank(user);
//         weth.approve(address(market), type(uint256).max);
//         vm.stopPrank();
//     }

//     // Test deposit function
//     function testDeposit() public {
//         uint256 depositAmount = initialDeposit;

//         // Check the initial balance of the user and the vault
//         uint256 initialUserBalance = dai.balanceOf(user);
//         uint256 initialVaultBalance = dai.balanceOf(address(vault));
//         uint256 initialUserShares = vault.balanceOf(user);
//         console.log("Initial user DAI balance:", initialUserBalance);
//         console.log("Initial vault DAI balance:", initialVaultBalance);
//         console.log("Initial user shares balance:", initialUserShares);

//         // User deposits DAI into the vault
//         vm.prank(user);
//         vault.deposit(depositAmount, user);

//         // Check the new balance of the user and the vault
//         uint256 newUserBalance = dai.balanceOf(user);
//         uint256 newVaultBalance = dai.balanceOf(address(vault));
//         uint256 newUserShares = vault.balanceOf(user);
//         console.log("User shares balance after deposit:", newUserShares);

//         // Ensure the user's DAI balance decreased by the deposit amount
//         assertEq(
//             newUserBalance,
//             initialUserBalance - depositAmount,
//             "User's DAI balance didn't decrease after deposit"
//         );

//         // Ensure the vault's DAI balance inc reased by the deposit amount
//         assertEq(
//             newVaultBalance,
//             initialVaultBalance + depositAmount,
//             "Vault DAI balance didn't increase after deposit"
//         );

//         // Assert the user's shares balance is updated correctly
//         assertGt(
//             newUserShares,
//             initialUserShares,
//             "User shares should increase after deposit"
//         );
//     }

//     function testWithdraw() public {
//         uint256 depositAmount = initialDeposit; // 5000 tokens
//         uint256 withdrawAmount = 3000 * 1e18; // 3000 tokens

//         vm.prank(user);
//         vault.deposit(depositAmount, user);

//         uint256 vaultBalance = dai.balanceOf(address(vault));
//         uint256 userBalance = dai.balanceOf(user);
//         console.log("User Balance:", userBalance);
//         console.log("Vault Balance:", vaultBalance);

//         vm.prank(user);
//         vault.withdraw(withdrawAmount, user, user);

//         uint256 newUserBalance = dai.balanceOf(user);
//         console.log("New User Balance:", newUserBalance);

//         uint256 newVaultBalance = dai.balanceOf(address(vault));
//         console.log("New Vault Balance:", newVaultBalance);
//     }

//     function testAdminBorrow() public {
//         uint256 depositAmount = initialDeposit; // 5000 tokens

//         vm.prank(user);
//         vault.deposit(depositAmount, user);

//         uint256 initialVaultBalance = dai.balanceOf(address(vault));

//         // Make sure the intial balance of the market contract is zero
//         uint256 initialMarketBalance = dai.balanceOf(address(market));
//         uint256 amountToBorrow = 1000 * 1e18; // Borrow 1000 DAI

//         vm.startPrank(address(market));
//         vault.adminBorrow(amountToBorrow);
//         vm.stopPrank();

//         uint256 finalMarketBalance = dai.balanceOf(address(market));
//         assertEq(
//             finalMarketBalance,
//             initialMarketBalance + amountToBorrow,
//             "Market contract should have received the tokens"
//         );

//         uint256 finalVaultBalance = dai.balanceOf(address(vault));
//         assertEq(
//             finalVaultBalance,
//             initialVaultBalance - amountToBorrow,
//             "Vault contract balance should decrease by the borrow amount"
//         );
//     }

//     function testAdminRepay() public {
//         uint256 amountToBorrow = 1000 * 1e18;
//         uint256 amountToRepay = 500 * 1e18; // Repay 500 DAI
//         uint256 depositAmount = initialDeposit; // 5000 tokens

//         vm.prank(user);
//         vault.deposit(depositAmount, user);

//         // Approve the Vault to transfer tokens from the Market contract
//         vm.startPrank(address(market)); // Impersonate the Market contract
//         dai.approve(address(vault), amountToRepay); // Approve the vault to spend tokens
//         vm.stopPrank();

//         vm.startPrank(address(market));
//         vault.adminBorrow(amountToBorrow);
//         vm.stopPrank();

//         uint256 initialMarketBalance = dai.balanceOf(address(market));
//         uint256 initialVaultBalance = dai.balanceOf(address(vault));

//         console.log(initialVaultBalance);

//         vm.startPrank(address(market));
//         vault.adminRepay(amountToRepay);
//         vm.stopPrank();

//         uint256 finalMarketBalance = dai.balanceOf(address(market));
//         uint256 finalVaultBalance = dai.balanceOf(address(vault));

//         console.log(finalVaultBalance);

//         assertEq(
//             finalMarketBalance,
//             initialMarketBalance - amountToRepay,
//             "Market balance should decrease after repayment"
//         );
//         assertEq(
//             finalVaultBalance,
//             initialVaultBalance + amountToRepay,
//             "Vault balance should increase after repayment"
//         );
//     }

//     function testTotalAssets() public {
//         uint256 initialIdleAssets = vault.totalIdle();

//         // Ensure the idle assets are initially as expected
//         assertEq(initialIdleAssets, 0, "Idle assets should be zero initially");

//         // Deposit funds into vault
//         uint256 depositAmount = initialDeposit; // 5000 tokens

//         vm.prank(user);
//         vault.deposit(depositAmount, user);

//         // User deposits collateral
//         uint256 collateralDepositAmount = 5000 * 1e18;

//         vm.startPrank(user);
//         market.depositCollateral(address(weth), collateralDepositAmount);
//         vm.stopPrank();

//         uint256 marketCollateralBalance = weth.balanceOf(address(market));

//         console.log("Market collateral Balance:", marketCollateralBalance);

//         // User borrows from lending market
//         uint256 amountToBorrow = 1000 * 1e18;

//         vm.startPrank(address(user));
//         market.borrow(amountToBorrow);
//         vm.stopPrank();

//         uint256 userBalance = dai.balanceOf(address(user));
//         console.log("User balance:", userBalance);
//     }
// }
