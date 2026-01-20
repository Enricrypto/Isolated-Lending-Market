// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../../src/core/MarketV1.sol";
import "../../src/core/Vault.sol";
import "../../test/Mocks.sol";

/**
 * @title Scenario_HappyPath
 * @notice Demonstrates a complete lending cycle:
 *         deposit → collateralize → borrow → repay → withdraw → redeem
 *
 * @dev Run with:
 *      source .env &&
 *      forge script script/scenarios/Scenario_HappyPath.s.sol \
 *        --rpc-url sepolia \
 *        --broadcast -vvvv
 */
contract Scenario_HappyPath is Script {
    // Scenario parameters
    uint256 constant LENDER_DEPOSIT = 100_000e6;
    uint256 constant COLLATERAL_AMOUNT = 10e18;
    uint256 constant BORROW_AMOUNT = 10_000e6;

    function run() external {
        uint256 pk = vm.envUint("SCENARIO_PRIVATE_KEY");
        address user = vm.addr(pk);

        // Load addresses from env
        address marketProxy = vm.envAddress("MARKET_V1_PROXY");
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        address loanAssetAddr = vm.envAddress("LOAN_ASSET_ADDRESS");
        address wethAddr = vm.envAddress("WETH_ADDRESS");

        MarketV1 market = MarketV1(marketProxy);
        Vault vault = Vault(vaultAddr);
        MockERC20 loanToken = MockERC20(loanAssetAddr);
        MockERC20 weth = MockERC20(wethAddr);

        console.log("=== SCENARIO: Happy Path ===");
        console.log("Deployer:      ", user);
        console.log("Market:        ", marketProxy);
        console.log("Vault:         ", vaultAddr);
        console.log("Loan asset:    ", loanAssetAddr);
        console.log("WETH collateral:", wethAddr);

        vm.startBroadcast(pk);

        // ------------------------------------------------------------
        // 1. Mint tokens
        // ------------------------------------------------------------
        loanToken.mint(user, LENDER_DEPOSIT + BORROW_AMOUNT);
        weth.mint(user, COLLATERAL_AMOUNT);
        console.log("1. Minted loan asset and collateral");

        // ------------------------------------------------------------
        // 2. Deposit to vault (ERC-4626 asset)
        // ------------------------------------------------------------
        loanToken.approve(address(vault), LENDER_DEPOSIT);
        vault.deposit(LENDER_DEPOSIT, user);
        console.log("2. Deposited to vault:", LENDER_DEPOSIT / 1e6, "loan units");

        // ------------------------------------------------------------
        // 3. Deposit collateral
        // ------------------------------------------------------------
        weth.approve(address(market), COLLATERAL_AMOUNT);
        market.depositCollateral(wethAddr, COLLATERAL_AMOUNT);
        console.log("3. Deposited collateral:", COLLATERAL_AMOUNT / 1e18, "WETH");

        // ------------------------------------------------------------
        // 4. Borrow
        // ------------------------------------------------------------
        market.borrow(BORROW_AMOUNT);
        console.log("4. Borrowed:", BORROW_AMOUNT / 1e6, "loan units");

        // ------------------------------------------------------------
        // 5. Repay
        // ------------------------------------------------------------
        uint256 repayAmount = market.getRepayAmount(user);
        loanToken.approve(address(market), repayAmount);
        market.repay(repayAmount);
        console.log("5. Repaid:", repayAmount / 1e6, "loan units");

        // ------------------------------------------------------------
        // 6. Withdraw collateral
        // ------------------------------------------------------------
        market.withdrawCollateral(wethAddr, COLLATERAL_AMOUNT);
        console.log("6. Withdrew collateral");

        // ------------------------------------------------------------
        // 7. Redeem from vault
        // ------------------------------------------------------------
        uint256 maxRedeem = vault.maxRedeem(user);
        vault.redeem(maxRedeem, user, user);
        console.log("7. Redeemed from vault");

        vm.stopBroadcast();

        console.log("=== SCENARIO COMPLETE ===");
    }
}
