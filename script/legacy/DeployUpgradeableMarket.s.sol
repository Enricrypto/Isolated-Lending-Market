// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/core/MarketV1.sol";
import "../../src/core/Vault.sol";
import "../../src/core/PriceOracle.sol";
import "../../src/core/InterestRateModel.sol";
import "../../src/governance/GovernanceSetup.sol";

/**
 * @title DeployUpgradeableMarket
 * @notice Deployment script for upgradeable MarketV1 with governance
 * @dev Deploys fresh infrastructure with UUPS proxy pattern
 *
 * Run with:
 *   forge script script/DeployUpgradeableMarket.s.sol:DeployUpgradeableMarket \
 *     --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
 */
contract DeployUpgradeableMarket is Script {
    // ==================== CONFIGURATION ====================

    // Market Parameters
    uint256 constant LLTV = 0.85e18; // 85%
    uint256 constant LIQUIDATION_PENALTY = 0.05e18; // 5%
    uint256 constant PROTOCOL_FEE_RATE = 0.1e18; // 10%

    // Interest Rate Model Parameters
    uint256 constant BASE_RATE = 0.02e18; // 2%
    uint256 constant OPTIMAL_UTILIZATION = 0.8e18; // 80%
    uint256 constant SLOPE1 = 0.04e18; // 4%
    uint256 constant SLOPE2 = 0.6e18; // 60%

    // Governance Parameters
    uint256 constant TIMELOCK_DELAY = 2 days;

    // Vault Parameters
    string constant VAULT_NAME = "Lending Vault Token V2";
    string constant VAULT_SYMBOL = "vTokenV2";

    // ==================== STATE VARIABLES ====================

    address public deployer;

    // Deployed contracts
    PriceOracle public oracle;
    InterestRateModel public interestRateModel;
    Vault public vault;
    MarketV1 public implementation;
    ERC1967Proxy public proxy;
    MarketV1 public market;
    MarketTimelock public timelock;

    function run() external {
        // Get deployer from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        // Get configuration from environment
        address loanAsset = vm.envAddress("LOAN_ASSET_ADDRESS");
        address protocolTreasury = vm.envAddress("PROTOCOL_TREASURY");
        address badDebtAddress = vm.envAddress("BAD_DEBT_ADDRESS");
        address strategyVault = vm.envAddress("STRATEGY_ADDRESS");

        // Guardian defaults to deployer if not set
        address guardian = vm.envOr("GUARDIAN_ADDRESS", deployer);
        // Multisig defaults to deployer if not set (for testing)
        address multisig = vm.envOr("MULTISIG_ADDRESS", deployer);

        console.log("=== DEPLOYMENT CONFIG ===");
        console.log("Deployer:", deployer);
        console.log("Loan Asset:", loanAsset);
        console.log("Protocol Treasury:", protocolTreasury);
        console.log("Bad Debt Address:", badDebtAddress);
        console.log("Strategy:", strategyVault);
        console.log("Guardian:", guardian);
        console.log("Multisig:", multisig);
        console.log("Timelock Delay:", TIMELOCK_DELAY);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Price Oracle
        console.log("1. Deploying PriceOracle...");
        oracle = new PriceOracle(deployer);
        console.log("   PriceOracle:", address(oracle));

        // 2. Deploy Vault (with deployer as owner for AccessControl)
        console.log("2. Deploying Vault...");
        vault = new Vault(
            IERC20(loanAsset),
            address(0), // Market will be set later
            strategyVault,
            deployer, // Owner for AccessControl
            VAULT_NAME,
            VAULT_SYMBOL
        );
        console.log("   Vault:", address(vault));

        // 3. Deploy Interest Rate Model (with deployer as owner for AccessControl)
        console.log("3. Deploying InterestRateModel...");
        interestRateModel = new InterestRateModel(
            BASE_RATE,
            OPTIMAL_UTILIZATION,
            SLOPE1,
            SLOPE2,
            address(vault),
            address(0), // Market will be set later
            deployer // Owner for AccessControl
        );
        console.log("   InterestRateModel:", address(interestRateModel));

        // 4. Deploy MarketV1 Implementation
        console.log("4. Deploying MarketV1 Implementation...");
        implementation = new MarketV1();
        console.log("   Implementation:", address(implementation));

        // 5. Deploy ERC1967Proxy with initialization
        console.log("5. Deploying ERC1967Proxy...");
        bytes memory initData = abi.encodeWithSelector(
            MarketV1.initialize.selector,
            badDebtAddress,
            protocolTreasury,
            address(vault),
            address(oracle),
            address(interestRateModel),
            loanAsset,
            deployer // Deployer is initial owner
        );
        proxy = new ERC1967Proxy(address(implementation), initData);
        market = MarketV1(address(proxy));
        console.log("   Proxy (Market):", address(proxy));

        // 6. Link contracts
        console.log("6. Linking contracts...");
        vault.setMarket(address(market));
        console.log("   Vault linked to Market");

        interestRateModel.setMarketContract(address(market));
        console.log("   IRM linked to Market");

        // 7. Add loan asset price feed
        console.log("7. Adding price feeds...");
        try vm.envAddress("LOAN_ASSET_FEED") returns (address loanFeed) {
            oracle.addPriceFeed(loanAsset, loanFeed);
            console.log("   Added loan asset feed");
        } catch {
            console.log("   WARNING: Loan asset feed not configured!");
        }

        // 8. Transfer oracle ownership to Market
        console.log("8. Transferring oracle ownership...");
        oracle.transferOwnership(address(market));
        console.log("   Oracle ownership transferred to Market");

        // 9. Configure Market parameters
        console.log("9. Configuring Market...");
        market.setMarketParameters(LLTV, LIQUIDATION_PENALTY, PROTOCOL_FEE_RATE);
        console.log("   Market parameters set");

        // 10. Add collateral tokens
        _addCollateralTokens();

        // 11. Deploy Timelock
        console.log("11. Deploying TimelockController...");
        address[] memory proposers = new address[](1);
        proposers[0] = multisig;
        address[] memory executors = new address[](1);
        executors[0] = multisig;
        timelock = new MarketTimelock(TIMELOCK_DELAY, proposers, executors);
        console.log("   Timelock:", address(timelock));

        // 12. Set guardian
        console.log("12. Setting guardian...");
        market.setGuardian(guardian);
        console.log("   Guardian set to:", guardian);

        // 13. Transfer ownership to timelock
        console.log("13. Transferring ownership to Timelock...");
        market.transferOwnership(address(timelock));
        console.log("   Ownership transferred to Timelock");

        vm.stopBroadcast();

        // Print deployment summary
        _printDeploymentSummary(guardian, multisig);
    }

    function _addCollateralTokens() internal {
        console.log("10. Adding collateral tokens...");

        // WETH
        try vm.envAddress("WETH_ADDRESS") returns (address wethAddress) {
            address wethFeed = vm.envAddress("WETH_FEED");
            market.addCollateralToken(wethAddress, wethFeed);
            console.log("   Added WETH:", wethAddress);
        } catch {
            console.log("   WETH not configured, skipping");
        }

        // WBTC
        try vm.envAddress("WBTC_ADDRESS") returns (address wbtcAddress) {
            address wbtcFeed = vm.envAddress("WBTC_FEED");
            market.addCollateralToken(wbtcAddress, wbtcFeed);
            console.log("   Added WBTC:", wbtcAddress);
        } catch {
            console.log("   WBTC not configured, skipping");
        }
    }

    function _printDeploymentSummary(address guardian, address multisig) internal view {
        console.log("");
        console.log("========================================");
        console.log("UPGRADEABLE MARKET DEPLOYMENT COMPLETE");
        console.log("========================================");
        console.log("");
        console.log("Core Contracts:");
        console.log("  MarketV1 Implementation:", address(implementation));
        console.log("  MarketV1 Proxy:", address(proxy));
        console.log("  Vault:", address(vault));
        console.log("  PriceOracle:", address(oracle));
        console.log("  InterestRateModel:", address(interestRateModel));
        console.log("");
        console.log("Governance:");
        console.log("  Timelock:", address(timelock));
        console.log("  Guardian:", guardian);
        console.log("  Multisig (proposer/executor):", multisig);
        console.log("  Timelock Delay:", TIMELOCK_DELAY / 1 days, "days");
        console.log("");
        console.log("Ownership:");
        console.log("  Market Owner:", market.owner());
        console.log("  Market Guardian:", market.guardian());
        console.log("");
        console.log("Configuration:");
        console.log("  LLTV:", LLTV / 1e16, "%");
        console.log("  Liquidation Penalty:", LIQUIDATION_PENALTY / 1e16, "%");
        console.log("  Protocol Fee:", PROTOCOL_FEE_RATE / 1e16, "%");
        console.log("");
        console.log("========================================");
        console.log("UPDATE .env WITH:");
        console.log("========================================");
        console.log("MARKET_V1_IMPLEMENTATION=", address(implementation));
        console.log("MARKET_V1_PROXY=", address(proxy));
        console.log("VAULT_V2_ADDRESS=", address(vault));
        console.log("ORACLE_V2_ADDRESS=", address(oracle));
        console.log("IRM_V2_ADDRESS=", address(interestRateModel));
        console.log("TIMELOCK_ADDRESS=", address(timelock));
        console.log("========================================");
    }
}
