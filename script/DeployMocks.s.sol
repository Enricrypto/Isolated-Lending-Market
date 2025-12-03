// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../test/Mocks.sol";

contract DeployMocks is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy Mock Tokens
        console.log("Deploying Mock USDC...");
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        console.log("USDC:", address(usdc));
        
        console.log("\nDeploying Mock WETH...");
        MockERC20 weth = new MockERC20("Wrapped Ether", "WETH", 18);
        console.log("WETH:", address(weth));
        
        console.log("\nDeploying Mock WBTC...");
        MockERC20 wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        console.log("WBTC:", address(wbtc));
        
        // Deploy Price Feeds
        console.log("\nDeploying USDC Price Feed ($1.00)...");
        MockPriceFeed usdcFeed = new MockPriceFeed(100000000);
        console.log("USDC Feed:", address(usdcFeed));
        
        console.log("\nDeploying WETH Price Feed ($2,000)...");
        MockPriceFeed wethFeed = new MockPriceFeed(200000000000);
        console.log("WETH Feed:", address(wethFeed));
        
        console.log("\nDeploying WBTC Price Feed ($50,000)...");
        MockPriceFeed wbtcFeed = new MockPriceFeed(5000000000000);
        console.log("WBTC Feed:", address(wbtcFeed));
        
        // Deploy Strategy
        console.log("\nDeploying Mock Strategy...");
        MockStrategy strategy = new MockStrategy(usdc, "USDC Strategy", "sUSDC");
        console.log("Strategy:", address(strategy));
        
        vm.stopBroadcast();
        
        console.log("\n========================================");
        console.log("MOCKS DEPLOYED - Copy to .env:");
        console.log("========================================");
        console.log("LOAN_ASSET_ADDRESS=", address(usdc));
        console.log("WETH_ADDRESS=", address(weth));
        console.log("WBTC_ADDRESS=", address(wbtc));
        console.log("LOAN_ASSET_FEED=", address(usdcFeed));
        console.log("WETH_FEED=", address(wethFeed));
        console.log("WBTC_FEED=", address(wbtcFeed));
        console.log("STRATEGY_ADDRESS=", address(strategy));
        console.log("========================================\n");
    }
}