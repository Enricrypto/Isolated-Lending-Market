// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../src/adapters/CompoundV2Adapter.sol";
import "../src/adapters/AaveV3Adapter.sol";

contract DeployAdapters is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        address vault = vm.envAddress("VAULT_ADDRESS");

        // ==================== Compound V2 ====================
        address cUSDC = vm.envAddress("C_USDC_ADDRESS");
        address cDAI  = vm.envAddress("C_DAI_ADDRESS");
        address cUSDT = vm.envAddress("C_USDT_ADDRESS");
        address cWETH = vm.envAddress("C_WETH_ADDRESS");

        // ==================== Aave V3 ====================
        address aaveProvider = vm.envAddress("AAVE_PROVIDER_ADDRESS");

        // Underlying tokens
        address USDC = vm.envAddress("LOAN_ASSET_ADDRESS");
        address DAI  = vm.envAddress("DAI_ADDRESS");
        address USDT = vm.envAddress("USDT_ADDRESS");
        address WETH = vm.envAddress("WETH_ADDRESS");

        vm.startBroadcast(pk);

        // ======== Deploy Compound V2 adapters ========
        CompoundV2Adapter compUSDC = new CompoundV2Adapter(vault, USDC, cUSDC);
        CompoundV2Adapter compDAI  = new CompoundV2Adapter(vault, DAI,  cDAI);
        CompoundV2Adapter compUSDT = new CompoundV2Adapter(vault, USDT, cUSDT);
        CompoundV2Adapter compWETH = new CompoundV2Adapter(vault, WETH, cWETH);

        // ======== Deploy Aave V3 adapters ========
        AaveV3Adapter aaveUSDC = new AaveV3Adapter(vault, aaveProvider, USDC);
        AaveV3Adapter aaveDAI  = new AaveV3Adapter(vault, aaveProvider, DAI);
        AaveV3Adapter aaveUSDT = new AaveV3Adapter(vault, aaveProvider, USDT);
        AaveV3Adapter aaveWETH = new AaveV3Adapter(vault, aaveProvider, WETH);

        vm.stopBroadcast();

        console.log("Compound V2 Adapters:");
        console.log("USDC:", address(compUSDC));
        console.log("DAI: ", address(compDAI));
        console.log("USDT:", address(compUSDT));
        console.log("WETH:", address(compWETH));

        console.log("Aave V3 Adapters:");
        console.log("USDC:", address(aaveUSDC));
        console.log("DAI: ", address(aaveDAI));
        console.log("USDT:", address(aaveUSDT));
        console.log("WETH:", address(aaveWETH));
    }
}
