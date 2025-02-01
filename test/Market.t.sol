// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import "../src/Vault.sol";
import "../src/Market.sol";
import "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

contract MarketTest is Test {
    Market public market;
    Vault public daiVault;
    IERC20 public dai;
    IERC20 public usdt;

    address public user;

    function setUp() public {
        // Fork the Arbitrum mainnet at the latest block
        vm.createSelectFork(
            "https://arb-mainnet.g.alchemy.com/v2/ADLPIIv6SUjhmaoJYxWLHKDUDaw8RnRj",
            293933340
        );

        // Set up a user address
        user = address(0x123);

        // send some Ether to the user
        vm.deal(user, 10 ether);

        // DAI and USDT addresses
        dai = IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1); // DAI token address
        usdt = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9); // USDT token address

        // Any user can deploy a market (permissionless)
        vm.startPrank(user);
        market = new Market();
        vm.stopPrank();

        // Any user can deploy a vault for a token
        vm.startPrank(user);
        daiVault = new Vault(address(dai), "vDai", "vDAI");
        vm.stopPrank();

        // Any user can add a vault to the market
        vm.startPrank(user);
        market.addBorrowableVault(address(dai), address(daiVault));
        vm.stopPrank();

        // User approves the Vault contract to spend their DAI
        vm.startPrank(user);
        dai.approve(address(daiVault), type(uint256).max);
        vm.stopPrank();

        // Verify vault registration
        address registeredVault = market.borrowableVaults(address(dai));
        assertEq(
            registeredVault,
            address(daiVault),
            "Vault registration failed"
        );

        // Impersonate a DAI whale to send DAI tokens to the user
        address daiWhale = 0xd85E038593d7A098614721EaE955EC2022B9B91B;
        vm.startPrank(daiWhale);
        dai.transfer(user, 10000 * 1e18); // Transfer 10000 DAI to user
        vm.stopPrank();

        // Impersonate a USDT whale to send USDT tokens to the user
        address usdtWhale = 0xF977814e90dA44bFA03b6295A0616a897441aceC;
        vm.startPrank(usdtWhale);
        usdt.transfer(user, 10000 * 1e6); // Transfer 10000 USDT to user
        vm.stopPrank();

        // User approves the Market contract to spend their DAI and USDT
        vm.startPrank(user);
        dai.approve(address(market), type(uint256).max);
        usdt.approve(address(market), type(uint256).max);
        vm.stopPrank();
    }

    // Test Add Collateral Token to market
    function testAddCollateralToken() public {
        address collateralToken = address(usdt); // Example token address
        uint256 ltvRatio = 75; // 75% LTV Ratio

        vm.startPrank(user); // Any user can now add collateral and set LTV
        market.addCollateralToken(collateralToken, ltvRatio);
        vm.stopPrank();

        // Assert that the supportedCollateral mapping is now supported
        assertEq(
            market.supportedCollateralTokens(collateralToken),
            true,
            "Collateral supported by market"
        );

        assertEq(
            market.getLTVRatio(collateralToken),
            ltvRatio,
            "LTV Ratio has been set correctly"
        );
    }

    // Test depositCollateral for DAI
    function testDepositCollateral() public {
        address collateralToken = address(usdt); // USDT as collateral
        uint256 depositAmount = 5000 * 1e6; // 1000 USDT

        // First, we add USDT as a collateral token
        vm.startPrank(user);
        market.addCollateralToken(collateralToken, 75); // 75% LTV
        vm.stopPrank();

        // Ensure the user has USDT before depositing
        assertGe(
            usdt.balanceOf(user),
            depositAmount,
            "User should have enough USDT"
        );

        // Deposit collateral into the market
        vm.startPrank(user);
        market.depositCollateral(collateralToken, depositAmount);
        vm.stopPrank();

        // Ensure the contract received the USDT
        assertEq(
            usdt.balanceOf(address(market)),
            depositAmount,
            "Market should receive deposited collateral"
        );

        // Ensure the user's collateral balance updated correctly
        assertEq(
            market.userCollateralBalances(user, collateralToken),
            depositAmount,
            "User's collateral balance should be updated"
        );
    }

    // Test for withdraw Collateral
    function testWithdrawCollateral() public {
        address collateralToken = address(usdt);
        uint256 depositAmount = 1000 * 1e6; // 1000 USDT
        uint256 withdrawAmount = 500 * 1e6; // Withdraw 500 USDT

        // First, we add USDT as a collateral token
        vm.startPrank(user);
        market.addCollateralToken(collateralToken, 75); // 75% LTV
        vm.stopPrank();

        // Ensure the user has USDT before depositing
        uint256 initialbalance = usdt.balanceOf(user);
        assertGe(initialbalance, depositAmount, "User should have enough USDT");

        // Deposit collateral into the market
        vm.startPrank(user);
        market.depositCollateral(collateralToken, depositAmount);
        vm.stopPrank();

        // User's collateral balance should be updated
        uint256 balanceAfterDeposit = usdt.balanceOf(user);
        assertEq(
            market.userCollateralBalances(user, collateralToken),
            depositAmount,
            "User should have deposited collateral"
        );

        // Withdraw collateral
        vm.startPrank(user);
        market.withdrawCollateral(collateralToken, withdrawAmount);
        vm.stopPrank();

        // Ensure the contract sent the USDT back to the user
        assertEq(
            usdt.balanceOf(user),
            balanceAfterDeposit + withdrawAmount,
            "User should receive withdrawn USDT"
        );

        // Ensure the user's collateral balance updated correctly
        assertEq(
            market.userCollateralBalances(user, collateralToken),
            depositAmount - withdrawAmount,
            "User's collateral balance should decrease"
        );
    }

    // Test User deposits DAI into Vault & registers lending deposit
    function testDepositAndRegisterLend() public {
        uint256 depositAmount = 1000 * 1e18; // 1000 DAI

        // Step 1: User deposits DAI into the Vault
        vm.startPrank(user);
        uint256 sharesReceived = daiVault.deposit(depositAmount, user);
        vm.stopPrank();

        console.log("Shares received:", sharesReceived);

        // Step 2: User registers the deposit in the Market
        vm.startPrank(user);
        market.registerLendDeposit(address(dai));
        vm.stopPrank();

        // Step 3: Verify the stored share balance in Market contract
        uint256 registeredShares = market.lendAmount(user, address(dai));

        console.log("Registered Shares in Market:", registeredShares);

        // Assert that the Market correctly tracks the user's vault shares
        assertEq(
            registeredShares,
            sharesReceived,
            "Market should track vault shares correctly"
        );
    }
}
