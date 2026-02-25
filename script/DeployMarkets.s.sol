// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../test/Mocks.sol";
import "../src/core/Vault.sol";
import "../src/core/InterestRateModel.sol";
import "../src/core/MarketV1.sol";

/**
 * @title DeployMarkets
 * @notice Deploys isolated WETH and WBTC lending markets on Sepolia,
 *         reusing the already-deployed OracleRouter and MarketV1 implementation.
 *
 * Prerequisites (already deployed by DeployAll.s.sol):
 *   - Mock tokens: USDC, WETH, WBTC
 *   - OracleRouter with Chainlink feeds for USDC, WETH, WBTC
 *   - MarketV1 implementation (proxy-reusable)
 *
 * Each new market deploys: MockStrategy + Vault + IRM + MarketV1 proxy
 * Governance: deployer stays as owner (testnet only).
 *
 * Run:
 *   forge script script/DeployMarkets.s.sol \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --verify \
 *     -vvv
 */
contract DeployMarkets is Script {

    // ── Existing deployed addresses (DeployAll.s.sol — Jan 30 2026) ──────────

    address constant ORACLE_ROUTER = 0xf0a440147AAC2FF4349ca623f8bf9BD96EA43843;
    address constant MARKET_IMPL   = 0x217547Af931896123Df66354Ce285C13bCD379E5;

    address constant USDC_TOKEN = 0xa23575D09B55c709590F7f5507b246043A8cF49b;
    address constant WETH_TOKEN = 0x655Af45748C1116B95339d189B1556c92d73ff77;
    address constant WBTC_TOKEN = 0x3bCFE4F6f3b11c8dB62f8302dc53f5CCdb51F9c3;

    // Chainlink Sepolia feeds (already registered in OracleRouter)
    address constant USDC_FEED = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;
    address constant WETH_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address constant WBTC_FEED = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;

    address constant DEFAULT_TREASURY = 0xd0D211cCEF07598946bB0dF5ECee0bF75cAF3ECC;

    // ── IRM & market parameters ───────────────────────────────────────────────

    uint256 constant BASE_RATE           = 0.02e18;
    uint256 constant OPTIMAL_UTILIZATION = 0.80e18;
    uint256 constant SLOPE1              = 0.04e18;
    uint256 constant SLOPE2              = 0.60e18;
    uint256 constant LLTV                = 0.85e18;
    uint256 constant LIQUIDATION_PENALTY = 0.05e18;
    uint256 constant PROTOCOL_FEE_RATE   = 0.10e18;

    // ── Script-level state (avoids stack-too-deep in helpers) ────────────────

    address private _deployer;
    address private _treasury;
    address private _badDebt;

    // ── Entry point ───────────────────────────────────────────────────────────

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        _deployer  = vm.addr(pk);
        _treasury  = vm.envOr("PROTOCOL_TREASURY", DEFAULT_TREASURY);
        _badDebt   = vm.envOr("BAD_DEBT_ADDRESS",  DEFAULT_TREASURY);

        vm.startBroadcast(pk);

        // ── WETH market ───────────────────────────────────────────────────────
        address wethVault  = _deployVault(WETH_TOKEN, "WETH Lending Vault", "vWETH", "WETH Strategy", "sWETH");
        address wethIrm    = _deployIrm(wethVault);
        address wethMarket = _deployProxy(wethVault, wethIrm, WETH_TOKEN);
        Vault(wethVault).setMarket(wethMarket);
        InterestRateModel(wethIrm).setMarketContract(wethMarket);
        MarketV1(wethMarket).setMarketParameters(LLTV, LIQUIDATION_PENALTY, PROTOCOL_FEE_RATE);
        MarketV1(wethMarket).addCollateralToken(USDC_TOKEN, USDC_FEED);
        MarketV1(wethMarket).addCollateralToken(WBTC_TOKEN, WBTC_FEED);

        // ── WBTC market ───────────────────────────────────────────────────────
        address wbtcVault  = _deployVault(WBTC_TOKEN, "WBTC Lending Vault", "vWBTC", "WBTC Strategy", "sWBTC");
        address wbtcIrm    = _deployIrm(wbtcVault);
        address wbtcMarket = _deployProxy(wbtcVault, wbtcIrm, WBTC_TOKEN);
        Vault(wbtcVault).setMarket(wbtcMarket);
        InterestRateModel(wbtcIrm).setMarketContract(wbtcMarket);
        MarketV1(wbtcMarket).setMarketParameters(LLTV, LIQUIDATION_PENALTY, PROTOCOL_FEE_RATE);
        MarketV1(wbtcMarket).addCollateralToken(USDC_TOKEN, USDC_FEED);
        MarketV1(wbtcMarket).addCollateralToken(WETH_TOKEN, WETH_FEED);

        vm.stopBroadcast();

        console.log("\n=== WETH MARKET ===");
        console.log("WETH_VAULT=",   wethVault);
        console.log("WETH_IRM=",     wethIrm);
        console.log("WETH_MARKET=",  wethMarket);
        console.log("\n=== WBTC MARKET ===");
        console.log("WBTC_VAULT=",   wbtcVault);
        console.log("WBTC_IRM=",     wbtcIrm);
        console.log("WBTC_MARKET=",  wbtcMarket);
        console.log("\nCopy these into frontend/src/lib/vault-registry.ts");
    }

    // ── Helpers (use script-level state to stay within stack limits) ──────────

    function _deployVault(
        address asset,
        string memory name,
        string memory symbol,
        string memory stratName,
        string memory stratSymbol
    ) internal returns (address) {
        address strategy = address(new MockStrategy(MockERC20(asset), stratName, stratSymbol));
        return address(new Vault(IERC20(asset), address(0), strategy, _deployer, name, symbol));
    }

    function _deployIrm(address vault) internal returns (address) {
        return address(
            new InterestRateModel(
                BASE_RATE, OPTIMAL_UTILIZATION, SLOPE1, SLOPE2,
                vault, address(0), _deployer
            )
        );
    }

    function _deployProxy(address vault, address irm, address loanAsset) internal returns (address) {
        bytes memory init = abi.encodeWithSelector(
            MarketV1.initialize.selector,
            _badDebt, _treasury, vault, ORACLE_ROUTER, irm, loanAsset, _deployer
        );
        return address(new ERC1967Proxy(MARKET_IMPL, init));
    }
}
