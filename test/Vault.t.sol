// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import "../src/Vault.sol";
import "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

contract VaultTest is Test {
    Vault public vault;
    Market public market;
    address public user;
    IERC20 public dai; // testing with DAI as the loan asset

    address daiAddress = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1; // DAI address on Arbitrum

    uint256 public initialDeposit = 5000 * 1e18; // 5000 tokens
    uint256 public initialBalance = 10000 * 1e18; // 10000 DAI for user

    function setUp() public {
        // Fork the Arbitrum mainnet at the latest block
        vm.createSelectFork(
            "https://arb-mainnet.g.alchemy.com/v2/ADLPIIv6SUjhmaoJYxWLHKDUDaw8RnRj",
            301134183
        );

        // Initialize the DAI instance
        dai = IERC20(daiAddress);

        // // Deploy market contract
        // market = new Market();

        // Deploy Vault contract
        vault = new Vault(dai, address(market), "Vault Dai", "VDAI");

        // Set up account
        user = address(0x123);

        // send some Ether to the user for gas
        vm.deal(user, 10 ether);

        // Impersonate a DAI whale to send tokens to the user
        address daiWhale = 0xd85E038593d7A098614721EaE955EC2022B9B91B; // Replace with a valid DAI whale address
        vm.startPrank(daiWhale);
        dai.transfer(user, initialBalance); // Transfer 10,000 DAI to user
        vm.stopPrank();

        // Approve the vault contract for the user
        vm.startPrank(user);
        dai.approve(address(vault), type(uint256).max); // Approve max amount
        vm.stopPrank();
    }

    // Test deposit function
    function testDeposit() public {
        uint256 depositAmount = initialDeposit;

        // Check the initial balance of the user and the vault
        uint256 initialUserBalance = dai.balanceOf(user);
        uint256 initialVaultBalance = dai.balanceOf(address(vault));
        uint256 initialUserShares = vault.balanceOf(user);
        console.log("Initial user DAI balance:", initialUserBalance);
        console.log("Initial vault DAI balance:", initialVaultBalance);
        console.log("Initial user shares balance:", initialUserShares);

        // User deposits DAI into the vault
        vm.prank(user);
        vault.deposit(depositAmount, user);

        // Check the new balance of the user and the vault
        uint256 newUserBalance = dai.balanceOf(user);
        uint256 newVaultBalance = dai.balanceOf(address(vault));
        uint256 newUserShares = vault.balanceOf(user);
        console.log("User shares balance after deposit:", newUserShares);

        // Ensure the user's DAI balance decreased by the deposit amount
        assertEq(
            newUserBalance,
            initialUserBalance - depositAmount,
            "User's DAI balance didn't decrease after deposit"
        );

        // Ensure the vault's DAI balance inc reased by the deposit amount
        assertEq(
            newVaultBalance,
            initialVaultBalance + depositAmount,
            "Vault DAI balance didn't increase after deposit"
        );

        // Assert the user's shares balance is updated correctly
        assertGt(
            newUserShares,
            initialUserShares,
            "User shares should increase after deposit"
        );
    }

    //     function testWithdraw() public {
    //         uint256 withdrawAmount = 500 * 1e18; // Withdraw 500 tokens
    //         uint256 depositAmount = initialDeposit;

    //         // User deposits DAI into the vault
    //         vm.prank(user);
    //         vault.deposit(depositAmount, user);

    //         // Log initial vault token (shares) balance
    //         uint256 initialShares = vault.balanceOf(user);
    //         console.log("Initial shares balance:", initialShares);

    //         // Log initial receiver balance
    //         uint256 initialReceiverBalance = dai.balanceOf(receiver);
    //         console.log("Initial receiver balance:", initialReceiverBalance);

    //         // Log initial vault collateral (total assets)
    //         uint256 initialVaultBalance = vault.totalAssets();
    //         console.log("Initial vault balance:", initialVaultBalance);

    //         // Perform withdrawal
    //         vm.startPrank(user);
    //         uint256 sharesBurned = vault.withdraw(withdrawAmount, receiver, user);
    //         vm.stopPrank();

    //         // Log final vault token (shares) balance
    //         uint256 finalShares = vault.balanceOf(user);
    //         console.log("Final shares balance:", finalShares);

    //         // Log final receiver balance
    //         uint256 finalReceiverBalance = dai.balanceOf(receiver);
    //         console.log("Final receiver balance:", finalReceiverBalance);

    //         // Log final vault collateral (total assets)
    //         uint256 finalVaultBalance = vault.totalAssets();
    //         console.log("Final vault balance:", finalVaultBalance);

    //         // Assert shares were burned
    //         uint256 expectedSharesBurned = vault.previewWithdraw(withdrawAmount);
    //         assertEq(
    //             sharesBurned,
    //             expectedSharesBurned,
    //             "Shares burned should match the expected shares"
    //         );

    //         // Assert receiver's balance increased correctly
    //         assertEq(
    //             finalReceiverBalance,
    //             initialReceiverBalance + withdrawAmount,
    //             "Receiver balance should increase by the withdrawn amount"
    //         );

    //         // Assert user's shares balance decreased
    //         assertEq(
    //             finalShares,
    //             initialShares - sharesBurned,
    //             "User's shares balance should decrease by the burned shares"
    //         );

    //         // Assert vault's total assets decreased
    //         assertEq(
    //             finalVaultBalance,
    //             initialVaultBalance - withdrawAmount,
    //             "Vault's total assets should decrease by the withdrawn amount"
    //         );
    //     }
}
