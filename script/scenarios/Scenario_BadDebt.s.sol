// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../../src/core/MarketV1.sol";
import "../../src/core/Vault.sol";
import "../../test/Mocks.sol";

/**
 * @title Scenario_BadDebt
 * @notice Demonstrates bad debt from extreme price crash (black swan)
 * @dev Run with: source .env && forge script script/scenarios/Scenario_BadDebt.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast -vvvv
 */
contract Scenario_BadDebt is Script {
    // Scenario parameters
    uint256 constant LENDER_DEPOSIT = 100_000e6;
    uint256 constant COLLATERAL_AMOUNT = 10e18;
    uint256 constant BORROW_AMOUNT = 16_000e6;

    // Prices (8 decimals)
    int256 constant INITIAL_PRICE = 200_000_000_000; // $2000
    int256 constant CRASHED_PRICE = 40_000_000_000; // $400 (80% drop)

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        // Load addresses from env
        address marketProxy = vm.envAddress("MARKET_V1_PROXY");
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        address usdcAddr = vm.envAddress("LOAN_ASSET_ADDRESS");
        address wethAddr = vm.envAddress("WETH_ADDRESS");
        address wethFeedAddr = vm.envAddress("WETH_FEED");

        MarketV1 market = MarketV1(marketProxy);
        Vault vault = Vault(vaultAddr);
        MockERC20 usdc = MockERC20(usdcAddr);
        MockERC20 weth = MockERC20(wethAddr);
        MockPriceFeed feed = MockPriceFeed(wethFeedAddr);

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
        market.depositCollateral(wethAddr, COLLATERAL_AMOUNT);
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
