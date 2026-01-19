// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../../src/core/MarketV1.sol";
import "../../src/core/Vault.sol";
import "../../test/Mocks.sol";

/**
 * @title Scenario_BadDebt
 * @notice Demonstrates bad debt from extreme price crash (black swan)
 * @dev Run with: forge script script/scenarios/Scenario_BadDebt.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast -vvvv
 */
contract Scenario_BadDebt is Script {
    // Deployed addresses (Sepolia)
    address constant MARKET_PROXY = 0xbe4FD219B17C3E55562c9bD9254Bc3F3519D4BB6;
    address constant VAULT_ADDR = 0x17A11c0Da8951765efFd58fA236053C14f779D03;
    address constant USDC_ADDR = 0x4949E3c0fBA71d2A0031D9a648A17632E65ae495;
    address constant WETH_ADDR = 0x4F61DeD7391d6F7EbEb8002481aFEc2ebd1D535c;
    address constant WETH_FEED = 0x0Ab1720cC82968937D7F1bdF71Abb8A9312CAd71;

    // Scenario parameters
    uint256 constant LENDER_DEPOSIT = 100_000e6;
    uint256 constant COLLATERAL_AMOUNT = 10e18;
    uint256 constant BORROW_AMOUNT = 16_000e6;

    // Prices (8 decimals)
    int256 constant INITIAL_PRICE = 2000_00000000;
    int256 constant CRASHED_PRICE = 400_00000000; // 80% drop

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        MarketV1 market = MarketV1(MARKET_PROXY);
        Vault vault = Vault(VAULT_ADDR);
        MockERC20 usdc = MockERC20(USDC_ADDR);
        MockERC20 weth = MockERC20(WETH_ADDR);
        MockPriceFeed feed = MockPriceFeed(WETH_FEED);

        console.log("=== SCENARIO: Bad Debt (Black Swan) ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(pk);

        // Setup
        usdc.mint(deployer, LENDER_DEPOSIT + BORROW_AMOUNT * 2);
        weth.mint(deployer, COLLATERAL_AMOUNT);
        feed.setPrice(INITIAL_PRICE);
        console.log("1. Setup complete, WETH price: $2000");

        // Deposit to vault
        usdc.approve(address(vault), LENDER_DEPOSIT);
        vault.deposit(LENDER_DEPOSIT, deployer);
        console.log("2. Deposited to vault");

        // Deposit collateral
        weth.approve(address(market), COLLATERAL_AMOUNT);
        market.depositCollateral(WETH_ADDR, COLLATERAL_AMOUNT);
        console.log("3. Deposited 10 WETH ($20,000 value)");

        // Max borrow
        market.borrow(BORROW_AMOUNT);
        console.log("4. Borrowed:", BORROW_AMOUNT / 1e6, "USDC");

        // Black swan crash
        feed.setPrice(CRASHED_PRICE);
        console.log("5. BLACK SWAN! WETH crashed to $400 (80% drop)");
        console.log("   Collateral now worth only $4,000");
        console.log("   Debt: $16,000 - UNDERWATER!");

        // Liquidate with bad debt
        usdc.approve(address(market), type(uint256).max);
        market.liquidate(deployer);
        console.log("6. Liquidation executed");

        // Check bad debt
        uint256 badDebt = market.getBadDebt(deployer);
        console.log("7. Bad debt generated:", badDebt / 1e18, "USD");

        // Restore price
        feed.setPrice(INITIAL_PRICE);
        console.log("8. Price restored to $2000");

        vm.stopBroadcast();

        console.log("=== COMPLETE ===");
        console.log("Bad debt shows unrecoverable losses");
    }
}
