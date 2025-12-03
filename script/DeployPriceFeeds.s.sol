// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../test/Mocks.sol";

contract DeployPriceFeeds is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // USDC/USD: $1.00
        MockPriceFeed usdcFeed = new MockPriceFeed(100000000);
        console.log("USDC Feed:", address(usdcFeed));
        
        // WETH/USD: $2,000
        MockPriceFeed wethFeed = new MockPriceFeed(200000000000);
        console.log("WETH Feed:", address(wethFeed));
        
        // WBTC/USD: $50,000
        MockPriceFeed wbtcFeed = new MockPriceFeed(5000000000000);
        console.log("WBTC Feed:", address(wbtcFeed));
        
        vm.stopBroadcast();
        
        console.log("\n========================================");
        console.log("PRICE FEEDS DEPLOYED - Copy to .env:");
        console.log("========================================");
        console.log("LOAN_ASSET_FEED=", address(usdcFeed));
        console.log("WETH_FEED=", address(wethFeed));
        console.log("WBTC_FEED=", address(wbtcFeed));
        console.log("========================================\n");
    }
}
