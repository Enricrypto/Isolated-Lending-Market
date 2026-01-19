// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/core/MarketV1.sol";
import "../src/core/Vault.sol";
import "../src/core/PriceOracle.sol";
import "../src/core/InterestRateModel.sol";
import "../src/governance/GovernanceSetup.sol";

/**
 * @title DeployUpgradeable
 * @notice Deployment script for upgradeable Market with governance
 * @dev Run with: forge script script/DeployUpgradeable.s.sol --rpc-url $RPC_URL --broadcast
 *
 * DEPLOYMENT STEPS:
 * 1. Deploy MarketV1 implementation
 * 2. Deploy ERC1967Proxy with implementation and init data
 * 3. Deploy TimelockController
 * 4. Set guardian on Market
 * 5. Transfer Market ownership to Timelock
 *
 * ENVIRONMENT VARIABLES:
 * - PRIVATE_KEY: Deployer private key
 * - VAULT_ADDRESS: Existing vault address
 * - ORACLE_ADDRESS: Existing oracle address
 * - IRM_ADDRESS: Existing interest rate model address
 * - LOAN_ASSET: Loan asset (e.g., USDC)
 * - TREASURY: Protocol treasury address
 * - BAD_DEBT_ADDRESS: Bad debt accumulator address
 * - MULTISIG: Gnosis Safe multisig address
 * - GUARDIAN: Emergency guardian address
 * - TIMELOCK_DELAY: Timelock delay in seconds (default 2 days)
 */
contract DeployUpgradeable is Script {
    // Configuration
    uint256 public constant DEFAULT_TIMELOCK_DELAY = 2 days;

    function run() external {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address vault = vm.envAddress("VAULT_ADDRESS");
        address oracle = vm.envAddress("ORACLE_ADDRESS");
        address irm = vm.envAddress("IRM_ADDRESS");
        address loanAsset = vm.envAddress("LOAN_ASSET");
        address treasury = vm.envAddress("TREASURY");
        address badDebtAddress = vm.envAddress("BAD_DEBT_ADDRESS");
        address multisig = vm.envAddress("MULTISIG");
        address guardian = vm.envAddress("GUARDIAN");
        uint256 timelockDelay = vm.envOr("TIMELOCK_DELAY", DEFAULT_TIMELOCK_DELAY);

        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== DEPLOYMENT CONFIG ===");
        console.log("Deployer:", deployer);
        console.log("Vault:", vault);
        console.log("Oracle:", oracle);
        console.log("IRM:", irm);
        console.log("Loan Asset:", loanAsset);
        console.log("Treasury:", treasury);
        console.log("Bad Debt:", badDebtAddress);
        console.log("Multisig:", multisig);
        console.log("Guardian:", guardian);
        console.log("Timelock Delay:", timelockDelay);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy MarketV1 implementation
        console.log("1. Deploying MarketV1 implementation...");
        MarketV1 implementation = new MarketV1();
        console.log("   Implementation:", address(implementation));

        // 2. Deploy proxy with initialization
        console.log("2. Deploying ERC1967Proxy...");
        bytes memory initData = abi.encodeWithSelector(
            MarketV1.initialize.selector,
            badDebtAddress,
            treasury,
            vault,
            oracle,
            irm,
            loanAsset,
            deployer // Deployer is initial owner
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        MarketV1 market = MarketV1(address(proxy));
        console.log("   Proxy (Market):", address(proxy));

        // 3. Deploy Timelock
        console.log("3. Deploying TimelockController...");
        address[] memory proposers = new address[](1);
        proposers[0] = multisig;
        address[] memory executors = new address[](1);
        executors[0] = multisig;

        MarketTimelock timelock = new MarketTimelock(timelockDelay, proposers, executors);
        console.log("   Timelock:", address(timelock));

        // 4. Set guardian
        console.log("4. Setting guardian...");
        market.setGuardian(guardian);
        console.log("   Guardian set to:", guardian);

        // 5. Transfer ownership to timelock
        console.log("5. Transferring ownership to Timelock...");
        market.transferOwnership(address(timelock));
        console.log("   Ownership transferred");

        vm.stopBroadcast();

        // Summary
        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("Implementation:", address(implementation));
        console.log("Proxy (Market):", address(proxy));
        console.log("Timelock:", address(timelock));
        console.log("");
        console.log("Market Owner:", market.owner());
        console.log("Market Guardian:", market.guardian());
        console.log("");
        console.log("IMPORTANT: Update Vault and IRM to point to new Market address!");
        console.log("   vault.setMarket(", address(proxy), ")");
        console.log("   irm.setMarketContract(", address(proxy), ")");
    }
}

/**
 * @title UpgradeMarket
 * @notice Script to upgrade Market to a new implementation
 * @dev This script should be run by the Timelock (through multisig proposal)
 *
 * To upgrade:
 * 1. Deploy new implementation
 * 2. Schedule upgrade on Timelock
 * 3. Wait for delay
 * 4. Execute upgrade
 */
contract UpgradeMarket is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAddress = vm.envAddress("MARKET_PROXY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation
        console.log("Deploying new MarketV1 implementation...");
        MarketV1 newImplementation = new MarketV1();
        console.log("New implementation:", address(newImplementation));

        console.log("");
        console.log("To complete upgrade through Timelock:");
        console.log("1. Schedule: timelock.schedule(");
        console.log("     target:", proxyAddress);
        console.log("     value: 0");
        console.log("     data: abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector,");
        console.log("           ", address(newImplementation), ", '')");
        console.log("     predecessor: bytes32(0)");
        console.log("     salt: <unique_salt>");
        console.log("     delay: timelock.getMinDelay()");
        console.log("   )");
        console.log("2. Wait for delay");
        console.log("3. Execute: timelock.execute(...)");

        vm.stopBroadcast();
    }
}
