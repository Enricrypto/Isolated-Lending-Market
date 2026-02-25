// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../test/Mocks.sol";
import "../src/core/Vault.sol";
import "../src/core/PriceOracle.sol";
import "../src/core/InterestRateModel.sol";
import "../src/core/MarketV1.sol";
import "../src/core/OracleRouter.sol";
import "../src/core/RiskEngine.sol";
import "../src/governance/GovernanceSetup.sol";
import "../src/governance/RiskProposer.sol";
import "../src/access/ProtocolAccessControl.sol";

/**
 * @title DeployAll
 * @notice Canonical deployment script for the full lending protocol (TESTNET)
 *
 * DEPLOYS (IN ORDER):
 * 1. Mock tokens (USDC, WETH, WBTC)
 * 2. Uses REAL Chainlink Sepolia price feeds (no mock feeds)
 * 3. Mock strategy
 * 4. PriceOracle (underlying Chainlink wrapper)
 * 5. OracleRouter (hierarchical oracle: Chainlink → TWAP → LKG fallback)
 * 6. Vault
 * 7. InterestRateModel
 * 8. MarketV1 implementation
 * 9. ERC1967Proxy (Market with OracleRouter)
 * 10. Links + configuration
 * 11. Timelock + governance handoff
 * 12. RiskEngine
 *
 * OUTPUT:
 * - Fully populated .env-ready address block
 *
 * SINGLE SOURCE OF TRUTH.
 */
contract DeployAll is Script {
    // ==================== MARKET PARAMETERS ====================

    uint256 constant LLTV = 0.85e18; // 85%
    uint256 constant LIQUIDATION_PENALTY = 0.05e18; // 5%
    uint256 constant PROTOCOL_FEE_RATE = 0.1e18; // 10%

    // ==================== IRM PARAMETERS ====================

    uint256 constant BASE_RATE = 0.02e18; // 2%
    uint256 constant OPTIMAL_UTILIZATION = 0.8e18; // 80%
    uint256 constant SLOPE1 = 0.04e18; // 4%
    uint256 constant SLOPE2 = 0.6e18; // 60%

    // ==================== CHAINLINK SEPOLIA FEEDS ====================

    address constant CHAINLINK_USDC_USD = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;
    address constant CHAINLINK_ETH_USD = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address constant CHAINLINK_BTC_USD = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;

    // ==================== GOVERNANCE ====================

    uint256 constant TIMELOCK_DELAY = 2 days;

    // ==================== VAULT ====================

    string constant VAULT_NAME = "Lending Vault Token";
    string constant VAULT_SYMBOL = "vToken";

    // ==================== DEPLOYED ADDRESSES ====================

    struct Deployed {
        address usdc;
        address weth;
        address wbtc;
        address usdcFeed;
        address wethFeed;
        address wbtcFeed;
        address strategy;
        address oracle;
        address vault;
        address irm;
        address implementation;
        address proxy;
        address timelock;
        address oracleRouter;
        address riskEngine;
        address emergencyGuardian;
        address riskProposer;
    }

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        address guardian = vm.envOr("GUARDIAN_ADDRESS", deployer);
        address multisig = vm.envOr("MULTISIG_ADDRESS", deployer);
        address treasury = vm.envOr("PROTOCOL_TREASURY", deployer);
        address badDebt = vm.envOr("BAD_DEBT_ADDRESS", deployer);

        vm.startBroadcast(pk);

        Deployed memory d;

        // 1. Deploy mock tokens
        d.usdc = address(new MockERC20("USD Coin", "USDC", 6));
        d.weth = address(new MockERC20("Wrapped Ether", "WETH", 18));
        d.wbtc = address(new MockERC20("Wrapped Bitcoin", "WBTC", 8));

        // 2. Use real Chainlink Sepolia price feeds (no mocks)
        d.usdcFeed = CHAINLINK_USDC_USD;
        d.wethFeed = CHAINLINK_ETH_USD;
        d.wbtcFeed = CHAINLINK_BTC_USD;

        // 3. Deploy mock strategy
        d.strategy = address(new MockStrategy(MockERC20(d.usdc), "USDC Strategy", "sUSDC"));

        // 4. Deploy PriceOracle (underlying Chainlink wrapper)
        d.oracle = address(new PriceOracle(deployer));

        // 4b. Increase maxPriceAge for Sepolia (testnet feeds have longer heartbeats)
        PriceOracle(d.oracle).setMaxPriceAge(4 hours);

        // 5. Deploy OracleRouter wrapping PriceOracle
        OracleRouter oracleRouter = new OracleRouter(d.oracle, deployer);
        oracleRouter.setOracleParams(0.02e18, 0.05e18, 1800, 86_400);
        d.oracleRouter = address(oracleRouter);

        // 6. Add ALL price feeds before transferring PriceOracle ownership
        PriceOracle(d.oracle).addPriceFeed(d.usdc, d.usdcFeed);
        PriceOracle(d.oracle).addPriceFeed(d.weth, d.wethFeed);
        PriceOracle(d.oracle).addPriceFeed(d.wbtc, d.wbtcFeed);

        // 7. Transfer PriceOracle ownership to OracleRouter
        // Future feeds must be added via OracleRouter.addPriceFeed (requires OracleRouter owner)
        PriceOracle(d.oracle).transferOwnership(d.oracleRouter);

        // 8. Deploy vault (with deployer as initial owner for role-based access control)
        d.vault = address(
            new Vault(IERC20(d.usdc), address(0), d.strategy, deployer, VAULT_NAME, VAULT_SYMBOL)
        );

        // 9. Deploy IRM (with deployer as initial owner for role-based access control)
        d.irm = address(
            new InterestRateModel(
                BASE_RATE, OPTIMAL_UTILIZATION, SLOPE1, SLOPE2, d.vault, address(0), deployer
            )
        );

        // 10. Deploy market implementation
        d.implementation = address(new MarketV1());

        // 11. Deploy market proxy (with OracleRouter, not PriceOracle)
        bytes memory initData = abi.encodeWithSelector(
            MarketV1.initialize.selector,
            badDebt,
            treasury,
            d.vault,
            d.oracleRouter, // Use OracleRouter instead of PriceOracle
            d.irm,
            d.usdc,
            deployer
        );
        d.proxy = address(new ERC1967Proxy(d.implementation, initData));

        // 12. Link contracts
        Vault(d.vault).setMarket(d.proxy);
        InterestRateModel(d.irm).setMarketContract(d.proxy);

        // 13. Configure market
        MarketV1 market = MarketV1(d.proxy);
        market.setMarketParameters(LLTV, LIQUIDATION_PENALTY, PROTOCOL_FEE_RATE);
        // Price feeds already registered, just enable collateral tokens
        market.addCollateralToken(d.weth, d.wethFeed);
        market.addCollateralToken(d.wbtc, d.wbtcFeed);

        // 14. Deploy RiskEngine (before timelock, as deployer needs to be owner initially)
        DataTypes.RiskEngineConfig memory riskConfig = DataTypes.RiskEngineConfig({
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
        d.riskEngine = address(
            new RiskEngine(d.proxy, d.vault, d.oracleRouter, d.irm, deployer, riskConfig)
        );

        // 15. Deploy timelock (proposers: multisig, executors: multisig, admin: deployer for setup)
        address[] memory proposers = _toArray(multisig);
        address[] memory executors = _toArray(multisig);
        d.timelock = address(new MarketTimelock(TIMELOCK_DELAY, proposers, executors, deployer));

        // 16. Deploy EmergencyGuardian (can pause market instantly)
        // Timelock owns it
        d.emergencyGuardian = address(new EmergencyGuardian(d.proxy, guardian, d.timelock));

        // 17. Deploy RiskProposer (auto-creates proposals when severity >= 2)
        d.riskProposer = address(
            new RiskProposer(
                d.riskEngine,
                payable(d.timelock),
                d.proxy,
                2, // Severity threshold
                1 hours // Cooldown period
            )
        );

        // 18. Grant PROPOSER_ROLE to RiskProposer on Timelock
        // Grant proposer powers. RiskProposer can now schedule governance actions.
        MarketTimelock(payable(d.timelock))
            .grantRole(MarketTimelock(payable(d.timelock)).PROPOSER_ROLE(), d.riskProposer);

        // 18b. Transfer RiskProposer ownership to Timelock
        // Transfer RiskProposer ownership. Now only Timelock can change risk parameters.
        RiskProposer(d.riskProposer).transferOwnership(d.timelock);

        // 18c. Transfer Guardian ownership to Timelock. 
        // Transfer Guardian ownership. Now only Timelock can manage guardians.
        EmergencyGuardian(d.emergencyGuardian).transferOwnership(d.timelock);

        // 18d. Renounce deployer's admin role on Timelock (no more role changes after this).
        // Renounce deployer admin role. Now deployer has zero power forever.
        MarketTimelock(payable(d.timelock))
            .renounceRole(MarketTimelock(payable(d.timelock)).DEFAULT_ADMIN_ROLE(), deployer);

        // 19. Set guardian and transfer Market ownership to Timelock
        market.setGuardian(d.emergencyGuardian);
        market.transferOwnership(d.timelock);

        // 20. Transfer ownership of other contracts to Timelock
        // Note: In production, each contract should have its ownership transferred
        // For simplicity, we transfer to timelock which can then manage roles
        OracleRouter(d.oracleRouter).transferOwnership(d.timelock);
        InterestRateModel(d.irm).transferOwnership(d.timelock);
        Vault(d.vault).transferMarketOwnership(d.timelock);
        RiskEngine(d.riskEngine).transferOwnership(d.timelock);

        // 21. Revoke deployer's admin roles (final step - deployer no longer has access)
        // This should be done via Timelock after verifying deployment is correct
        // For testnet, we leave deployer with access for easier testing

        vm.stopBroadcast();

        // Output .env
        _logDeployment(d);
    }

    // ==================== HELPERS ====================

    function _toArray(address addr) internal pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = addr;
        return arr;
    }

    function _toArray(address addr1, address addr2) internal pure returns (address[] memory) {
        address[] memory arr = new address[](2);
        arr[0] = addr1;
        arr[1] = addr2;
        return arr;
    }

    function _logDeployment(Deployed memory d) internal pure {
        console.log("\n================= DEPLOYMENT COMPLETE =================");
        console.log("LOAN_ASSET_ADDRESS=", d.usdc);
        console.log("WETH_ADDRESS=", d.weth);
        console.log("WBTC_ADDRESS=", d.wbtc);
        console.log("LOAN_ASSET_FEED=", d.usdcFeed);
        console.log("WETH_FEED=", d.wethFeed);
        console.log("WBTC_FEED=", d.wbtcFeed);
        console.log("STRATEGY_ADDRESS=", d.strategy);
        console.log("VAULT_ADDRESS=", d.vault);
        console.log("ORACLE_ADDRESS=", d.oracle);
        console.log("IRM_ADDRESS=", d.irm);
        console.log("MARKET_IMPLEMENTATION=", d.implementation);
        console.log("MARKET_PROXY=", d.proxy);
        console.log("TIMELOCK_ADDRESS=", d.timelock);
        console.log("ORACLE_ROUTER=", d.oracleRouter);
        console.log("RISK_ENGINE=", d.riskEngine);
        console.log("EMERGENCY_GUARDIAN=", d.emergencyGuardian);
        console.log("RISK_PROPOSER=", d.riskProposer);
        console.log("=======================================================\n");
    }
}
