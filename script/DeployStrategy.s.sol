// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../test/Mocks.sol";

contract DeployStrategy is Script {
    function run() external {
        address loanAsset = 0x4949E3c0fBA71d2A0031D9a648A17632E65ae495;
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        MockStrategy strategy = new MockStrategy(
            IERC20(loanAsset),
            "USDC Strategy",
            "sUSDC"
        );
        
        vm.stopBroadcast();
        
        console.log("Strategy deployed at:", address(strategy));
        console.log("\nAdd to .env:");
        console.log("STRATEGY_ADDRESS=", address(strategy));
    }
}
