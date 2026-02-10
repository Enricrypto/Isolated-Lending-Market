// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../src/core/OracleRouter.sol";
import "../src/core/RiskEngine.sol";
import "../src/libraries/DataTypes.sol";

/**
 * @title DeployRiskEngine
 * @notice Standalone deployment script for OracleRouter + RiskEngine
 * @dev Expects the core protocol to already be deployed. Reads addresses from env vars.
 *
 * REQUIRED ENV VARS:
 * - PRIVATE_KEY
 * - MARKET_PROXY
 * - VAULT_ADDRESS
 * - ORACLE_ADDRESS
 * - IRM_ADDRESS
 */
contract DeployRiskEngine is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        address marketProxy = vm.envAddress("MARKET_PROXY");
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        address oracleAddr = vm.envAddress("ORACLE_ADDRESS");
        address irmAddr = vm.envAddress("IRM_ADDRESS");

        vm.startBroadcast(pk);

        // 1. Deploy OracleRouter wrapping existing PriceOracle
        OracleRouter oracleRouter = new OracleRouter(oracleAddr, deployer);

        // 2. Configure OracleRouter defaults
        oracleRouter.setOracleParams(
            0.02e18, // 2% deviation tolerance
            0.05e18, // 5% critical deviation
            1800, // 30 min half-life
            86_400 // 24h max LKG age
        );

        // 3. Deploy RiskEngine with default config
        DataTypes.RiskEngineConfig memory config = DataTypes.RiskEngineConfig({
            oracleFreshnessThreshold: 3600,
            oracleDeviationTolerance: 0.02e18,
            oracleCriticalDeviation: 0.05e18,
            lkgDecayHalfLife: 1800,
            lkgMaxAge: 86_400,
            utilizationWarning: 0.85e18,
            utilizationCritical: 0.95e18,
            healthFactorWarning: 1.2e18,
            healthFactorCritical: 1.05e18,
            badDebtThreshold: 0.01e18,
            strategyAllocationCap: 0.95e18
        });

        RiskEngine riskEngine = new RiskEngine(
            marketProxy, vaultAddr, address(oracleRouter), irmAddr, deployer, config
        );

        vm.stopBroadcast();

        // Log addresses
        console.log("\n================= RISK ENGINE DEPLOYED =================");
        console.log("ORACLE_ROUTER=", address(oracleRouter));
        console.log("RISK_ENGINE=", address(riskEngine));
        console.log("=======================================================\n");
    }
}
