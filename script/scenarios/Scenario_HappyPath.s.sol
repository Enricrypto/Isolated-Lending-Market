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
    // Core contracts (Sepolia)
    address constant MARKET_PROXY = 0xbe4FD219B17C3E55562c9bD9254Bc3F3519D4BB6;
    address constant VAULT_ADDR = 0x17A11c0Da8951765efFd58fA236053C14f779D03;

    // Scenario parameters
    uint256 constant LENDER_DEPOSIT = 100_000e6;
    uint256 constant COLLATERAL_AMOUNT = 10e18;
    uint256 constant BORROW_AMOUNT = 10_000e6;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        // Load expected addresses from env (intent)
        address expectedLoanAsset = vm.envAddress("LOAN_ASSET_ADDRESS");
        address wethAddr = vm.envAddress("WETH_ADDRESS");

        MarketV1 market = MarketV1(MARKET_PROXY);
        Vault vault = Vault(VAULT_ADDR);

        // === Source of truth ===
        address loanAsset = vault.asset();

        // Hard safety check: scenario intent must match protocol reality
        require(
            loanAsset == expectedLoanAsset,
            "Scenario misconfigured: vault.asset != LOAN_ASSET_ADDRESS"
        );

        MockERC20 loanToken = MockERC20(loanAsset);
        MockERC20 weth = MockERC20(wethAddr);

        console.log("=== SCENARIO: Happy Path ===");
        console.log("Deployer:      ", deployer);
        console.log("Vault:         ", address(vault));
        console.log("Loan asset:    ", loanAsset);
        console.log("WETH collateral:", wethAddr);

        vm.startBroadcast(pk);

        // ------------------------------------------------------------
        // 1. Mint tokens
        // ------------------------------------------------------------
        loanToken.mint(deployer, LENDER_DEPOSIT + BORROW_AMOUNT);
        weth.mint(deployer, COLLATERAL_AMOUNT);
        console.log("1. Minted loan asset and collateral");

        // ------------------------------------------------------------
        // 2. Deposit to vault (ERC-4626 asset)
        // ------------------------------------------------------------
        loanToken.approve(address(vault), LENDER_DEPOSIT);
        vault.deposit(LENDER_DEPOSIT, deployer);
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
        uint256 repayAmount = market.getRepayAmount(deployer);
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
        uint256 maxRedeem = vault.maxRedeem(deployer);
        vault.redeem(maxRedeem, deployer, deployer);
        console.log("7. Redeemed from vault");

        vm.stopBroadcast();

        console.log("=== SCENARIO COMPLETE ===");
    }
}
