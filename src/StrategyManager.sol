// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Vault.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";

contract StrategyManager is Ownable, ReentrancyGuard {
    struct StrategyConfig {
        uint256 targetUtilizationBps; // % of idle assets to deploy (in basis points, max 10,000 = 100%)
        IStrategy strategy; // The yield protocol adapter, must implement IStrategy (e.g., AaveStrategy)
        Vault vault;
        IERC20 asset;
    }

    mapping(address => StrategyConfig) public strategyConfigs; // vault => config

    event StrategyConfigured(
        address indexed vault,
        address strategy,
        uint256 targetUtilizationBps
    );
    event DeployedToStrategy(address indexed vault, uint256 amount);
    event WithdrawnFromStrategy(address indexed vault, uint256 amount);

    constructor(address _protocolAdmin) Ownable(_protocolAdmin) {
        require(_protocolAdmin != address(0), "Invalid admin");
    }

    // --- Admin Config ---

    function configureStrategy(
        address _vault,
        address _strategy, // deployed strategy contract (e.g., AaveStrategy)
        uint256 _targetUtilizationBps
    ) external onlyOwner {
        require(_vault != address(0), "Invalid vault");
        require(_strategy != address(0), "Invalid strategy");
        require(_targetUtilizationBps <= 10_000, "Invalid BPS");

        Vault vault = Vault(_vault);
        IERC20 asset = IERC20(vault.asset());

        strategyConfigs[_vault] = StrategyConfig({
            targetUtilizationBps: _targetUtilizationBps,
            strategy: IStrategy(_strategy),
            vault: vault,
            asset: asset
        });

        emit StrategyConfigured(_vault, _strategy, _targetUtilizationBps);
    }

    // --- Deploy Idle Assets ---

    function deployToStrategy(
        address vaultAddress
    ) external onlyOwner nonReentrant {
        StrategyConfig memory config = strategyConfigs[vaultAddress];
        require(
            address(config.strategy) != address(0),
            "Strategy not configured"
        );

        IStrategy strategy = IStrategy(config.strategy);

        uint256 idleAssets = config.vault.totalIdle();
        uint256 amount = (idleAssets * config.targetUtilizationBps) / 10_000;
        require(amount > 0, "Nothing to deploy");

        // Move funds from Vault to StrategyManager
        config.vault.withdrawIdle(amount);

        // Approve contract to transfer funds from Strategy Manager into Strategy
        config.asset.approve(address(strategy), amount);
        strategy.deposit(amount);

        emit DeployedToStrategy(vaultAddress, amount);
    }

    // --- Withdraw Logic ---

    function withdrawFromStrategy(
        address vaultAddress,
        uint256 amount
    ) external onlyOwner nonReentrant {
        StrategyConfig memory config = strategyConfigs[vaultAddress];
        require(address(config.strategy) != address(0), "Not configured");

        IStrategy strategy = IStrategy(config.strategy);

        // Withdraw funds to this contract
        strategy.withdraw(amount);
        config.asset.transfer(address(config.vault), amount); // forward funds to vault

        emit WithdrawnFromStrategy(vaultAddress, amount);
    }

    function getDeployedBalance(
        address vaultAddress
    ) external view returns (uint256) {
        StrategyConfig memory config = strategyConfigs[vaultAddress];
        require(address(config.strategy) != address(0), "Not configured");

        IStrategy strategy = IStrategy(config.strategy);
        return strategy.balanceOf(address(this));
    }
}
