# Overview
The Isolated Lending Market Protocol is a modular, extendable, and permissionless lending platform built with Solidity. It provides a flexible framework for decentralized lending, enabling users to deposit collateral, borrow assets, and lend tokens within isolated markets. The protocol is designed for scalability and upgradability through separate, purpose-built modules. Additionally, idle funds in the vaults can be deployed into yield-generating strategies for enhanced capital efficiency.

# Key Features
Strategy-Integrated ERC-4626 Vaults
The protocol leverages the ERC-4626 standard for managing borrowable assets. Users deposit tokens into a Vault and receive shares that represent their proportional ownership. Unlike standard ERC-4626 implementations, this vault integrates with external strategies to maximize asset utilization.

# Idle vs Backing Assets:
- totalAssets(): Returns the total backing of the vault, including assets currently deployed in the strategy plus outstanding borrowed funds (market.totalBorrowsWithInterest()). This provides a full accounting of assets the vault is responsible for, useful for internal tracking and risk management, not standard ERC-4626 integrations.
- totalStrategyAssets(): Returns only the amount of assets currently deployed in the strategy (excluding borrowed amounts and idle assets).
- availableLiquidity(): Reflects how much of the strategy’s assets the vault can immediately withdraw, i.e., the actual liquidity available for user redemptions and withdrawals.

# Collateral and Risk Management
Users can deposit supported tokens as collateral, tracked on a per-user and per-token basis. Collateral value is used to determine the borrowing capacity based on a defined Loan-to-Value (LTV) ratio. The system tracks utilization and automatically enforces LTV constraints during borrowing and collateral withdrawal.

# Borrowing and Repayment
Users may borrow assets from the vault against their collateral, provided they remain within their LTV bounds. Borrowed funds are tracked internally and interest accrues over time based on a dynamic interest rate model. Repayments reduce outstanding debt and allow users to reclaim collateral.

# Lending Through Vaults
Lenders provide liquidity by depositing tokens into ERC-4626-compatible vaults. In return, they receive vault shares, which accrue value over time as interest is repaid by borrowers. Funds not immediately lent out are allocated to external strategies to maximize yield until needed.

# Modular and Permissionless Architecture
Each market is isolated and independently configurable. New markets can be deployed permissionlessly, each with its own vault, collateral types, interest model, and oracle configuration. This modularity allows tailored risk settings per asset pair and easy protocol extension.

# Core Contracts and Functions
1. Vault (ERC-4626 + Strategy Integration)
- deposit: Accepts assets and mints shares, then deposits assets into strategy.
- mint: Mints exact shares and deposits the required asset amount into strategy.
- withdraw: Withdraws assets (pulling from strategy if needed), burns shares.
- redeem: Burns shares, pulls underlying assets from strategy, then transfers to user.
- totalAssets: Returns vault’s idle + strategy-held assets, excluding borrowed funds.
- totalBackingAssets: Returns the full backing including borrowed assets, for internal accounting.
- maxWithdraw / maxRedeem: Limits based on user balance and vault’s available liquidity.
- setMarket: Links the vault to a Market contract for authorized borrowing/repayment.
- adminBorrow / adminRepay: Authorized borrowing and repayment between the vault and linked market.

2. Market (Borrowing, Collateral, and Accounting)
- addCollateralToken / removeCollateralToken: Enables or disables supported collateral types.
- depositCollateral: Users deposit tokens to gain borrowing capacity.
- withdrawCollateral: Users reclaim unused collateral, provided LTV remains healthy.
- borrow: Allows users to borrow from the linked vault, increasing their debt position.
- repay: Repays outstanding debt and reduces liability.
- setMarketParameters: Sets LTV, liquidation penalty, and protocol fee per market.
- getTotalCollateralValue: Calculates a user's total collateral value based on oracle prices.
- calculateBorrowerAccruedInterest: Computes accrued interest for borrowers over time.

3. Pricing Contract
- addPriceFeed: Adds a price feed for supported tokens.
- updatePriceFeed: Updates existing price feed values.
- removePriceFeed: Removes a price feed.
- getLatestPrice: Retrieves the latest price for a token.

4. Interest Contract
- setMarketContract: Sets the associated Market contract.
- setBaseRate: Sets the base interest rate.
- setOptimalUtilization: Sets the optimal utilization ratio for calculating interest.
- setSlope1 & Slope2: Set the parameters for interest rate slope.
- setReserveFactor: Sets the reserve factor for the protocol.
- getTotalSupply: Retrieves the total supply in the market.
- getTotalBorrows: Retrieves the total borrowed amount in the market.
- getUtilizationRate: Gets the current utilization rate for the market.
- getDynamicBorrowRate: Retrieves the dynamic borrow rate based on utilization.
- getBorrowRatePerBlock: Calculates the borrow rate per block.

*Interest Rate and Liquidation Management*
- The protocol implements dynamic interest rates using the Interest Contract and enables liquidation handling in cases of over-leveraging or default (future enhancement).

# Future Enhancements
Future modular enhancements include:

- Oracle Module: For dynamic price feeds of collateral and borrowed assets.
- Interest Rate Module: For calculating dynamic interest rates.
- Factory Module: For deploying new lending markets with customizable parameters.
- Liquidation Module: For managing liquidations in cases of under-collateralization.

# Smart Contract Architecture

*Vault Contract (ERC-4626)*
- The Vault contract serves as the core for token management, enabling deposit/withdrawal operations while minting or burning vault shares to represent ownership.

*Market Contract*

The Market contract is responsible for managing the lending and borrowing process:
- Deposit collateral and borrow against it.
- Lend assets via ERC-4626 vaults.
- Manage LTV ratios, borrowing power, and associated risk.

By implementing separate, specialized contracts (Vault, Market, Pricing, Interest), the system ensures modularity and extensibility for future development.

<img width="641" alt="Isolated Lending Market Architecture" src="https://github.com/user-attachments/assets/60e0c870-a229-4a5c-82eb-0d8eabf34b9a" />

<img width="661" alt="Screenshot 2025-01-29 at 22 33 36" src="https://github.com/user-attachments/assets/4456df11-1ea0-45e3-bade-23ae6ec0c057" />


