// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../test/Mocks.sol";
import "../src/core/Vault.sol";
import "../src/core/PriceOracle.sol";
import "../src/core/InterestRateModel.sol";
import "../src/core/MarketV1.sol";
import "../src/governance/GovernanceSetup.sol";

/**
 * @title DeployAll
 * @notice Canonical deployment script for the full lending protocol (TESTNET)
 *
 * DEPLOYS (IN ORDER):
 * 1. Mock tokens (USDC, WETH, WBTC)
 * 2. Mock price feeds
 * 3. Mock strategy
 * 4. PriceOracle
 * 5. Vault
 * 6. InterestRateModel
 * 7. MarketV1 implementation
 * 8. ERC1967Proxy (Market)
 * 9. Links + configuration
 * 10. Timelock + governance handoff
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

        // 2. Deploy mock price feeds
        d.usdcFeed = address(new MockPriceFeed(100_000_000)); // $1.00
        d.wethFeed = address(new MockPriceFeed(2_000_000_000_000)); // $2,000
        d.wbtcFeed = address(new MockPriceFeed(5_000_000_000_000)); // $50,000

        // 3. Deploy mock strategy
        d.strategy = address(new MockStrategy(MockERC20(d.usdc), "USDC Strategy", "sUSDC"));

        // 4. Deploy oracle
        d.oracle = address(new PriceOracle(deployer));

        // 5. Deploy vault
        d.vault = address(
            new Vault(IERC20(d.usdc), address(0), d.strategy, VAULT_NAME, VAULT_SYMBOL)
        );

        // 6. Deploy IRM
        d.irm = address(
            new InterestRateModel(BASE_RATE, OPTIMAL_UTILIZATION, SLOPE1, SLOPE2, d.vault, address(0))
        );

        // 7. Deploy market implementation
        d.implementation = address(new MarketV1());

        // 8. Deploy market proxy
        bytes memory initData = abi.encodeWithSelector(
            MarketV1.initialize.selector,
            badDebt,
            treasury,
            d.vault,
            d.oracle,
            d.irm,
            d.usdc,
            deployer
        );
        d.proxy = address(new ERC1967Proxy(d.implementation, initData));

        // 9. Link contracts
        Vault(d.vault).setMarket(d.proxy);
        InterestRateModel(d.irm).setMarketContract(d.proxy);

        // 10. Configure oracle + market
        // Only add USDC feed manually (loan asset)
        // WETH/WBTC feeds are added via addCollateralToken
        PriceOracle(d.oracle).addPriceFeed(d.usdc, d.usdcFeed);
        PriceOracle(d.oracle).transferOwnership(d.proxy);

        MarketV1 market = MarketV1(d.proxy);
        market.setMarketParameters(LLTV, LIQUIDATION_PENALTY, PROTOCOL_FEE_RATE);
        market.addCollateralToken(d.weth, d.wethFeed);
        market.addCollateralToken(d.wbtc, d.wbtcFeed);

        // 11. Deploy timelock + governance handoff
        address[] memory proposers = _toArray(multisig);
        address[] memory executors = _toArray(multisig);
        d.timelock = address(new MarketTimelock(TIMELOCK_DELAY, proposers, executors));

        market.setGuardian(guardian);
        market.transferOwnership(d.timelock);

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
        console.log("=======================================================\n");
    }
}
