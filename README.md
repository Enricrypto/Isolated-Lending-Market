# Overview
The Isolated Lending Market Protocol is a modular, extendable, and permissionless lending platform built on Solidity. It provides a flexible framework for decentralized lending, enabling users to deposit collateral, borrow assets, and lend tokens within isolated, individual markets. The protocol is designed with scalability and modularity in mind, ensuring future flexibility and easy upgrades via distinct contract modules.

# Key Features
ERC-4626 Vault Implementation
The protocol uses the ERC-4626 standard for vaults, enabling seamless management of assets and vault shares. Users can deposit and withdraw assets within the vaults, receiving shares that represent their stake in the vault.

# Collateral Management
Users can deposit collateral into the market for borrowing. Collateral is tracked per-user and per-collateral-token basis. The protocol calculates the maximum borrowing power based on collateral value and a predefined Loan-to-Value (LTV) ratio. The protocol also tracks collateral utilization to help users monitor their risk levels.

# Borrowing and Debt Management
Users can borrow assets against their collateral, as long as they remain within the allowable LTV ratio. Borrowing power is dynamically calculated based on the user's collateral balance and current debt. The protocol ensures users can only borrow up to a percentage of their collateral's value, preventing over-leveraging.

# Lending and Borrowable Vaults
Users can lend assets by depositing them into the borrowable vaults (ERC-4626), earning vault shares in return. Borrowable assets are stored in separate vaults, each linked to a specific token. The protocol tracks the amount lent by each user.

# Modular and Permissionless
The protocol is modular, allowing new collateral types, borrowable tokens, and vaults to be added. It supports permissionless interaction, enabling anyone to contribute by adding new collateral types or borrowable assets.

# Core Contract Functions
1. Vault Contract (ERC-4626)
deposit: Allows users to deposit tokens, minting vault shares.
withdraw: Allows users to withdraw tokens, burning vault shares.
totalAssets: Returns the total assets held in the vault.
totalIdle: Retrieves the total idle assets.
maxWithdraw: Calculates the maximum withdrawal amount for the user.
maxRedeem: Retrieves the maximum redeemable shares for the user.

2. Market Contract
addCollateralToken: Adds a new collateral token type.
removeCollateralToken: Removes an existing collateral token type.
depositCollateral: Deposits collateral for borrowing.
withdrawCollateral: Withdraws collateral, maintaining the LTV ratio.
borrow & repay: Allows users to borrow and repay tokens.
set and get LTV ratio: Admin functions to set and retrieve LTV ratios for borrowable tokens.
getTotalCollateralValue: Calculates the total value of a user's collateral.
calculateBorrowerAccruedInterest: Tracks and calculates accrued interest for borrowers.

3. Pricing Contract
addPriceFeed: Adds a price feed for supported tokens.
updatePriceFeed: Updates existing price feed values.
removePriceFeed: Removes a price feed.
getLatestPrice: Retrieves the latest price for a token.

4. Interest Contract
setMarketContract: Sets the associated Market contract.
setBaseRate: Sets the base interest rate.
setOptimalUtilization: Sets the optimal utilization ratio for calculating interest.
setSlope1 & Slope2: Set the parameters for interest rate slope.
setReserveFactor: Sets the reserve factor for the protocol.
getTotalSupply: Retrieves the total supply in the market.
getTotalBorrows: Retrieves the total borrowed amount in the market.
getUtilizationRate: Gets the current utilization rate for the market.
getDynamicBorrowRate: Retrieves the dynamic borrow rate based on utilization.
getBorrowRatePerBlock: Calculates the borrow rate per block.

5. Interest Rate and Liquidation Management
The protocol implements dynamic interest rates using the Interest Contract and enables liquidation handling in cases of over-leveraging or default (future enhancement).

# Future Enhancements
Future modular enhancements include:

*Oracle Module*: For dynamic price feeds of collateral and borrowed assets.
*Interest Rate Module*: For calculating dynamic interest rates.
*Factory Module*: For deploying new lending markets with customizable parameters.
*Liquidation Module*: For managing liquidations in cases of under-collateralization.

# Smart Contract Architecture

*Vault Contract (ERC-4626)*
The Vault contract serves as the core for token management, enabling deposit/withdrawal operations while minting or burning vault shares to represent ownership.

*Market Contract*
The Market contract is responsible for managing the lending and borrowing process:
1. Deposit collateral and borrow against it.
2. Lend assets via ERC-4626 vaults.
3. Manage LTV ratios, borrowing power, and associated risk.

By implementing separate, specialized contracts (Vault, Market, Pricing, Interest), the system ensures modularity and extensibility for future development.

<img width="641" alt="Isolated Lending Market Architecture" src="https://github.com/user-attachments/assets/60e0c870-a229-4a5c-82eb-0d8eabf34b9a" />

<img width="661" alt="Screenshot 2025-01-29 at 22 33 36" src="https://github.com/user-attachments/assets/4456df11-1ea0-45e3-bade-23ae6ec0c057" />


