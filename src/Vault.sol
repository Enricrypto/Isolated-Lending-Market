// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "./Market.sol";

contract Vault is ERC4626 {
    //Events
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event BorrowedByMarket(address indexed market, uint256 amount);
    event RepaidToVault(address indexed market, uint256 amount);

    Market public market; // Store the market

    constructor(
        IERC20 _asset,
        address _marketContract,
        string memory _name, // name of the vault share token
        string memory _symbol // symbol of the vault share token
    ) ERC20(_name, _symbol) ERC4626(IERC20(_asset)) {
        market = Market(_marketContract);
    }

    modifier onlyMarket() {
        require(
            msg.sender == address(market),
            "Only Market contract can execute this function"
        );
        _;
    }

    /// @notice Deposit ERC-20 tokens into the vault
    function deposit(
        uint256 amount,
        address receiver
    ) public override returns (uint256 shares) {
        require(amount > 0, " Deposit amount must be greater than 0");
        shares = _deposit(amount, receiver);
        return shares;
    }

    function withdraw(
        uint256 amount,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        shares = _withdraw(amount, receiver, owner);
        return shares;
    }

    // Admin function to borrow tokens, only callable by the market contract
    function adminBorrowFunction(uint256 amount) external onlyMarket {
        // Transfer tokens directly from vault to market (without burning shares)
        asset().transfer(msg.sender, amount);

        emit BorrowedByMarket(msg.sender, amount);
    }

    // Admin function to repay tokens back to the vault, only callable by the market contract
    function adminRepayFunction(uint256 amount) external onlyMarket {
        // Transfer tokens from market to vault (without burning shares)
        asset().transferFrom(msg.sender, address(this), amount);

        // Emit an event for the repayment action
        emit RepaidToVault(msg.sender, amount);
    }

    function totalAssets() public view override returns (uint256) {
        // Retrieves the idle (not lent) assets in the Vault.
        uint256 totalVaultAssets = convertToAssets(balanceOf(address(this)));

        // Adds the borrowed assets PLUS interest accrued.
        uint256 totalBorrowedPlusInterest = market.borrowedPlusInterest();

        // Return the total assets including borrowed amounts and interest
        return totalVaultAssets + totalBorrowedPlusInterest;
    }

    function totalLiquidity() public view returns (uint256) {
        // Convert the vault's balance to assets (liquidity available for borrowing)
        return convertToAssets(balanceOf(address(this)));
    }
}
