// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../../src/core/MarketV1.sol";
import "../../src/core/Vault.sol";
import "../../test/Mocks.sol";

/**
 * @title Scenario_HappyPath
 * @notice Demonstrates a complete lending cycle: deposit collateral → borrow → repay → withdraw
 * @dev Run with: forge script script/scenarios/Scenario_HappyPath.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast -vvvv
 */
contract Scenario_HappyPath is Script {
    // Deployed addresses (Sepolia)
    address constant MARKET_PROXY = 0xbe4FD219B17C3E55562c9bD9254Bc3F3519D4BB6;
    address constant VAULT_ADDR = 0x17A11c0Da8951765efFd58fA236053C14f779D03;
    address constant USDC_ADDR = 0x4949E3c0fBA71d2A0031D9a648A17632E65ae495;
    address constant WETH_ADDR = 0x4F61DeD7391d6F7EbEb8002481aFEc2ebd1D535c;

    // Scenario parameters
    uint256 constant LENDER_DEPOSIT = 100_000e6;
    uint256 constant COLLATERAL_AMOUNT = 10e18;
    uint256 constant BORROW_AMOUNT = 10_000e6;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        MarketV1 market = MarketV1(MARKET_PROXY);
        Vault vault = Vault(VAULT_ADDR);
        MockERC20 usdc = MockERC20(USDC_ADDR);
        MockERC20 weth = MockERC20(WETH_ADDR);

        console.log("=== SCENARIO: Happy Path ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(pk);

        // Step 1: Mint tokens
        usdc.mint(deployer, LENDER_DEPOSIT + BORROW_AMOUNT);
        weth.mint(deployer, COLLATERAL_AMOUNT);
        console.log("1. Minted tokens");

        // Step 2: Deposit to vault
        usdc.approve(address(vault), LENDER_DEPOSIT);
        vault.deposit(LENDER_DEPOSIT, deployer);
        console.log("2. Deposited to vault:", LENDER_DEPOSIT / 1e6, "USDC");

        // Step 3: Deposit collateral
        weth.approve(address(market), COLLATERAL_AMOUNT);
        market.depositCollateral(WETH_ADDR, COLLATERAL_AMOUNT);
        console.log("3. Deposited collateral:", COLLATERAL_AMOUNT / 1e18, "WETH");

        // Step 4: Borrow
        market.borrow(BORROW_AMOUNT);
        console.log("4. Borrowed:", BORROW_AMOUNT / 1e6, "USDC");

        // Step 5: Repay
        uint256 repayAmount = market.getRepayAmount(deployer);
        usdc.approve(address(market), repayAmount);
        market.repay(repayAmount);
        console.log("5. Repaid:", repayAmount / 1e6, "USDC");

        // Step 6: Withdraw collateral
        market.withdrawCollateral(WETH_ADDR, COLLATERAL_AMOUNT);
        console.log("6. Withdrew collateral");

        // Step 7: Redeem from vault
        uint256 maxRedeem = vault.maxRedeem(deployer);
        vault.redeem(maxRedeem, deployer, deployer);
        console.log("7. Redeemed from vault");

        vm.stopBroadcast();

        console.log("=== COMPLETE ===");
    }
}
