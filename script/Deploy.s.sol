// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../src/core/Market.sol";
import "../src/core/Vault.sol";
import "../src/core/PriceOracle.sol";
import "../src/core/InterestRateModel.sol";

/**
 * @title Deploy
 * @notice Deployment script for the entire lending platform
 * @dev Run with: forge script script/Deploy.s.sol --rpc-url <network> --broadcast
 */
contract Deploy is Script {
    // ==================== CONFIGURATION ====================
    
    // Market Parameters
    uint256 constant LLTV = 0.85e18; // 85%
    uint256 constant LIQUIDATION_PENALTY = 0.05e18; // 5%
    uint256 constant PROTOCOL_FEE_RATE = 0.10e18; // 10%

    // Interest Rate Model Parameters
    uint256 constant BASE_RATE = 0.02e18; // 2%
    uint256 constant OPTIMAL_UTILIZATION = 0.8e18; // 80%
    uint256 constant SLOPE1 = 0.04e18; // 4%
    uint256 constant SLOPE2 = 0.60e18; // 60%

    // Vault Parameters
    string constant VAULT_NAME = "Lending Vault Token";
    string constant VAULT_SYMBOL = "vToken";

    // ==================== STATE VARIABLES ====================

    address public deployer;
    
    // Deployed contracts
    PriceOracle public oracle;
    InterestRateModel public interestRateModel;
    Vault public vault;
    Market public market;

    // ==================== DEPLOYMENT ====================

    function run() external {
        // Get deployer from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        // Get configuration from environment
        address loanAsset = vm.envAddress("LOAN_ASSET_ADDRESS");
        address protocolTreasury = vm.envAddress("PROTOCOL_TREASURY");
        address badDebtAddress = vm.envAddress("BAD_DEBT_ADDRESS");
        address strategyVault = vm.envAddress("STRATEGY_ADDRESS");

        console.log("Deploying with account:", deployer);
        console.log("Loan Asset:", loanAsset);
        console.log("Protocol Treasury:", protocolTreasury);
        console.log("Bad Debt Address:", badDebtAddress);
        console.log("Strategy Vault:", strategyVault);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Price Oracle (with deployer as initial owner)
        console.log("\n1. Deploying PriceOracle...");
        oracle = new PriceOracle(deployer);
        console.log("   PriceOracle deployed at:", address(oracle));

        // 2. Deploy Vault (without market initially)
        console.log("\n2. Deploying Vault...");
        vault = new Vault(
            IERC20(loanAsset),
            address(0), // Market will be set later
            strategyVault,
            VAULT_NAME,
            VAULT_SYMBOL
        );
        console.log("   Vault deployed at:", address(vault));

        // 3. Deploy Interest Rate Model
        console.log("\n3. Deploying InterestRateModel...");
        interestRateModel = new InterestRateModel(
            BASE_RATE,
            OPTIMAL_UTILIZATION,
            SLOPE1,
            SLOPE2,
            address(vault),
            address(0) // Market will be set later
        );
        console.log("   InterestRateModel deployed at:", address(interestRateModel));

        // 4. Deploy Market
        console.log("\n4. Deploying Market...");
        market = new Market(
            badDebtAddress,
            protocolTreasury,
            address(vault),
            address(oracle),
            address(interestRateModel),
            loanAsset
        );
        console.log("   Market deployed at:", address(market));

        // 5. Link contracts
        console.log("\n5. Linking contracts...");
        vault.setMarket(address(market));
        console.log("   Vault linked to Market");

        interestRateModel.setMarketContract(address(market));
        console.log("   InterestRateModel linked to Market");

        // 6. Add loan asset price feed (before transferring ownership)
        console.log("\n6. Adding loan asset price feed...");
        try vm.envAddress("LOAN_ASSET_FEED") returns (address loanFeed) {
            oracle.addPriceFeed(loanAsset, loanFeed);
            console.log("   Added loan asset price feed");
        } catch {
            console.log("   WARNING: Loan asset feed not configured!");
        }

        // 7. Transfer oracle ownership to Market
        console.log("\n7. Transferring PriceOracle ownership to Market...");
        oracle.transferOwnership(address(market));
        console.log("   PriceOracle ownership transferred to Market");

        // 8. Configure Market
        console.log("\n8. Configuring Market...");
        market.setMarketParameters(LLTV, LIQUIDATION_PENALTY, PROTOCOL_FEE_RATE);
        console.log("   Market parameters set");

        // 9. Add collateral tokens (Market adds price feeds now)
        _addCollateralTokens();

        vm.stopBroadcast();

        // 8. Print deployment summary
        _printDeploymentSummary();
    }

    // ==================== HELPER FUNCTIONS ====================

    function _addCollateralTokens() internal {
        console.log("\n9. Adding collateral tokens...");

        // Try to get WETH from environment
        try vm.envAddress("WETH_ADDRESS") returns (address wethAddress) {
            address wethFeed = vm.envAddress("WETH_FEED");
            // Market will add the price feed to oracle (since it owns it now)
            market.addCollateralToken(wethAddress, wethFeed);
            console.log("   Added WETH:", wethAddress);
        } catch {
            console.log("   WETH not configured, skipping");
        }

        // Try to get WBTC from environment
        try vm.envAddress("WBTC_ADDRESS") returns (address wbtcAddress) {
            address wbtcFeed = vm.envAddress("WBTC_FEED");
            // Market will add the price feed to oracle (since it owns it now)
            market.addCollateralToken(wbtcAddress, wbtcFeed);
            console.log("   Added WBTC:", wbtcAddress);
        } catch {
            console.log("   WBTC not configured, skipping");
        }
    }

    function _printDeploymentSummary() internal view {
        console.log("\n========================================");
        console.log("DEPLOYMENT COMPLETE");
        console.log("========================================");
        console.log("\nCore Contracts:");
        console.log("  Market:", address(market));
        console.log("  Vault:", address(vault));
        console.log("  PriceOracle:", address(oracle));
        console.log("  InterestRateModel:", address(interestRateModel));
        
        console.log("\nConfiguration:");
        console.log("  LLTV:", LLTV / 1e16, "%");
        console.log("  Liquidation Penalty:", LIQUIDATION_PENALTY / 1e16, "%");
        console.log("  Protocol Fee:", PROTOCOL_FEE_RATE / 1e16, "%");
        console.log("  Base Rate:", BASE_RATE / 1e16, "%");
        console.log("  Optimal Utilization:", OPTIMAL_UTILIZATION / 1e16, "%");
        
        console.log("\nNext Steps:");
        console.log("1. Verify contracts on block explorer");
        console.log("2. Update .env with deployed addresses");
        console.log("3. Test on testnet");
        console.log("4. Set up liquidation bot");
        console.log("========================================\n");
    }

    // ==================== VERIFICATION HELPER ====================

    /**
     * @notice Get constructor arguments for verification
     * @dev Use these for manual verification if auto-verify fails
     */
    function getVerificationArgs() external view returns (string memory) {
        return string(
            abi.encodePacked(
                "Market: ", _addressToString(address(market)), "\n",
                "Vault: ", _addressToString(address(vault)), "\n",
                "Oracle: ", _addressToString(address(oracle)), "\n",
                "IRM: ", _addressToString(address(interestRateModel))
            )
        );
    }

    function _addressToString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }
}