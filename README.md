# 📘 Overview
The Isolated Lending Market Protocol is a modular, permissionless, and extensible DeFi lending platform built in Solidity. It allows users to deposit collateral, borrow assets, and lend tokens across independently configured markets. Each market isolates risk while remaining composable with the wider ecosystem.

The architecture is built for scalability and capital efficiency, using strategy-integrated ERC-4626 vaults, modular interest models, and on-chain oracles. Vaults may route idle funds into external strategies to enhance yield without compromising liquidity guarantees.

# 🚀 Key Features
✅ Strategy-Integrated ERC-4626 Vaults
The protocol uses a custom implementation of the ERC-4626 tokenized vault standard to represent lending pools. Depositors receive shares representing their stake in the pool. Unlike standard vaults, this system:

Integrates with external yield strategies to improve capital efficiency.

Supports borrowing and repayment logic via a linked market contract.

Distinguishes between idle, borrowed, and strategy-deployed funds.

# 🔍 Asset Breakdown Functions
Function	Description
totalBackingAssets()	Returns total capital under management: strategy-held assets + borrowed assets. Used for internal accounting and interest rate calculations.
totalStrategyAssets()	Returns assets currently deployed in the external strategy (excludes idle and borrowed funds).
availableLiquidity()	Returns how much the vault can immediately withdraw from the strategy (i.e., real-time liquidity).
totalAssets()	Returns vault’s assets in compliance with the ERC-4626 spec (idle + strategy assets; excludes borrowed).

# 🛡️ Collateral & Risk Management
Users can deposit supported collateral tokens, each with an associated Loan-to-Value (LTV) ratio and risk parameters. The system tracks:

Per-user, per-token collateral balances

Real-time collateral valuation using an on-chain PriceOracle

Health factor enforcement based on total collateral value vs. borrowed amount

Collateral cannot be withdrawn if it would violate the user's LTV threshold.

# 💸 Borrowing & Repayment
Users borrow directly from the vault against deposited collateral. Features include:

Borrow caps and LTV enforcement

Interest accrual based on dynamic utilization via the InterestRateModel

Repayment of debt reduces liability and frees up collateral

Internal tracking of debt positions per user and market

# 💰 Lending via Vaults
Lenders provide liquidity by depositing tokens into the ERC-4626-compatible vaults. In return, they receive vault shares, which appreciate over time as borrowers repay with interest.

To maximize returns:

Idle funds not currently lent out can be allocated to external yield strategies

Interest rate dynamics adapt based on real-time utilization, balancing borrower incentives and lender yield

# 🧱 Modular & Permissionless Architecture
Every market is an independent and isolated unit, consisting of:

A dedicated Vault for lending and strategy integration

A Market for collateral management, borrowing, and interest logic

A configurable InterestRateModel to compute dynamic borrow rates

A linked PriceOracle for accurate asset valuation

This design enables:

Tailored risk settings per asset pair

Easy permissionless deployment of new markets

Safe experimentation with different collateral types, strategies, or rate curves

# 🛠️ Governance & Extensibility
Owner Functions exist across modules (e.g., setting rates, adding feeds, updating LTVs)

Ownership can be upgraded via smart contract patterns (ownership transfer, multisig)

New modules (e.g., liquidation engine, rewards, fees) can be added without changing core contracts

# 📈 Interest Rate Model Highlights
The protocol uses a Jump Rate Model with configurable parameters:

Parameter	Description
baseRate	Minimum rate applied even at 0% utilization
optimalUtilization	Utilization threshold at which the slope increases steeply
slope1	Interest rate increase below optimal utilization
slope2	Steeper increase after surpassing the optimal utilization (kink)

The rate updates automatically based on real-time utilization, pulled from the Vault and Market.

# 📡 Oracle System
The PriceOracle contract integrates with Chainlink oracles to retrieve real-time prices of supported collateral tokens.

Feeds can be added, updated, or removed by the owner

Ensures only positive, valid prices are accepted

Essential for accurate LTV, liquidation, and borrowing logic

# Core Contracts and Functions
# 1. 🏛️ Vault Architecture 
Vault acts as an ERC-4626-compliant tokenized vault with the following key extensions:

🔹 Core Components
ERC-4626 Base: Implements the standard interface for yield-bearing vaults: deposit, withdraw, mint, redeem, etc.

Strategy Integration: Most deposited assets are forwarded to an external strategy contract for yield generation.

Market Integration: The vault links to a Market contract, which can borrow and repay assets through privileged access.

Admin Controls: Enables the protocol or multisig to manage market linkage and possibly emergency controls.

🔹 Flow Overview
User deposits assets → receives shares → assets sent to strategy

User redeems/withdraws → shares burned → assets pulled from strategy if needed

Market borrows from vault (adminBorrow) → increases protocol liquidity

Market repays to vault (adminRepay) → vault regains liquidity

🧩 Vault Function List
✅ ERC-4626 Standard Functions: 
deposit(uint256 assets, address receiver): User deposits assets, receives shares. Assets are deposited into the strategy.

mint(uint256 shares, address receiver): User mints exact number of shares by depositing the required asset amount.

withdraw(uint256 assets, address receiver, address owner): Withdraws assets, burns appropriate shares. May pull from strategy.

redeem(uint256 shares, address receiver, address owner): Burns shares, pulls underlying assets from strategy, transfers to user.

totalAssets(): Returns the total amount of underlying assets managed by the vault (idle + strategy), excluding borrowed.

convertToShares(uint256 assets) / convertToAssets(uint256 shares): Standard ERC-4626 conversion helpers.

maxWithdraw(address owner) / maxRedeem(address owner): Limits based on available liquidity and user balance.

🏦 Strategy Management
harvest(): (Optional) Pulls any pending yield from strategy or reinvests. Usually used in autocompounding strategies.

setStrategy(address newStrategy): Sets or replaces the current yield strategy contract.

_depositIntoStrategy(uint256 amount): Internal function to send idle assets to strategy.

_withdrawFromStrategy(uint256 amount): Internal function to pull assets from strategy when needed.

strategyTotalAssets(): Returns the amount of assets currently held in the strategy.

💼 Market Borrowing & Repayment
setMarket(address marketAddress): Links the vault to a Market contract that is allowed to borrow and repay.

adminBorrow(uint256 amount): Allows the linked Market to borrow assets from the vault.

adminRepay(uint256 amount): Allows the Market to repay previously borrowed assets.

totalBackingAssets(): Returns total vault assets including those borrowed out — used for accounting, TVL, etc.

borrowedAssets(): Returns the amount currently borrowed by the Market.

🔒 Access Control & Safety
pause() / unpause(): (If inherited from Pausable) Disables user deposits and withdrawals.

recoverTokens(address token): Admin function to recover stuck tokens that are not the vault asset.

emergencyWithdrawStrategyFunds(): In case of strategy failure, pull all assets back to the vault.

🔍 View / Helpers
previewDeposit(uint256 assets) / previewMint(uint256 shares): Simulate shares/asset results.

previewWithdraw(uint256 assets) / previewRedeem(uint256 shares): Simulate output of withdraw/redeem.

idleAssets(): Returns vault’s current on-hand asset balance (not in strategy).

isHealthyLiquidity(): Custom check to ensure enough liquidity remains to meet withdrawal demand.

# 2. Market (Borrowing, Collateral, and Accounting):
🏛️ Overall Architecture:
Contract implements core lending functionalities:
- Borrowing/lending: Tracks user debt and calculates interest via a dynamic global borrow index.
- Collateral management: Users can deposit and withdraw various tokens.
- Health check & liquidation: Calculates health factors, enables partial liquidation, and handles bad debt.
- Interest accrual: Efficiently handled via index-based model. -
- USD valuation: Prices are obtained from an external oracle.

✅ Admin / Configuration Functions
addCollateralToken(token, decimals): Enables a token as acceptable collateral.

removeCollateralToken(token): Disables a token as collateral.

setMarketParameters(lltv, liquidationPenalty, protocolFeeRate): Sets the loan-to-value threshold, liquidation penalty, and protocol fee rate for the market.

updateGlobalBorrowIndex(): Public version of _updateGlobalBorrowIndex; updates accrued interest system-wide.

💰 User Deposit & Withdrawal
depositCollateral(token, amount): Allows a user to deposit a supported token as collateral.

withdrawCollateral(token, amount): Withdraws collateral (if healthy) from a user's deposited balance.

_removeCollateralAsset(user, token): Internal helper to clean up collateral asset list when balance is zero.

🏦 Borrowing & Repayment
borrow(amount): User borrows assets up to their limit based on collateral.

repay(amount): Repays debt, reducing borrower's liability.

_getUserTotalDebt(user): Internal function to compute total debt including accrued interest.

_borrowerInterestAccrued(user): Calculates interest accrued for a borrower since their last update.

🔍 View / External Helpers
getUserTotalCollateralValue(user): Public wrapper to calculate total collateral in USD.

getUserTotalDebt(user): Returns full debt for a user including interest.

getBorrowerInterestAccrued(user): Returns the accrued interest for a borrower.

getLoanAssetDecimals(): Fetches decimals of the loan token.

testNormalizeAmount(amount, decimals) / testDenormalizeAmount(amount, decimals): Converts between 18-decimal format and token decimals.

getBadDebt(user): Returns amount of unrecovered debt attributed to user.

getTokenValueInUSD(token, amount): Returns USD value of a token amount using oracle pricing.

_getLoanDebtInUSD(amount): Internal function for converting loan amount to USD.

totalBorrowsWithInterest(): Returns total borrowed value including accrued interest.

getMarketParameters(): Returns current market settings (LLTV, liquidation penalty, protocol fee).

getLendingRate(): Computes current lending APY based on utilization.

isHealthy(user) / isUserAtRiskOfLiquidation(user): Indicates whether a user is safe from liquidation.

_isHealthy(user): Internal helper for health check.

_getUserTotalCollateralValue(user): Internal version of total collateral calc.

💥 Liquidation
validateAndCalculateMaxLiquidation(user): Public interface to check and compute full liquidation parameters.

processLiquidatorRepaymentPublic(borrower, liquidator, amount): Allows liquidation repayment flow to be tested.

seizeCollateralPublic(user, liquidator, collateralToLiquidateUsd): Public access to test seizing collateral.

_validateAndCalculateMaxLiquidation(user): Internal liquidation pre-check & calculation.

_processLiquidatorRepayment(borrower, liquidator, amount): Handles logic for liquidator repayments including fees and debt updates.

_seizeCollateral(user, liquidator, usdValue): Iterates through a user's collateral to seize enough to cover liquidation.

_seizeOneCollateral(user, liquidator, token, usdToSeize): Seizes a single token's worth of collateral based on USD value.

_handleBadDebt(user, unrecoveredAmount): Moves unrecovered portion of liquidated debt to badDebtAddress.

🔧 Internal Mechanics
_updateGlobalBorrowIndex(): Core logic to compute and update borrow interest index over time.

_getTokenValueInUSD(token, amount): Computes value of a token amount using the oracle.

normalizeAmount(amount, decimals) / denormalizeAmount(amount, decimals): Helpers for token amount scaling.

_getLoanAssetDecimals(): Returns loan token decimals, with limit check.

# 3. Pricing Contract:
🔮 PriceOracle Architecture 
PriceOracle contract acts as a minimal, admin-controlled registry and interface for Chainlink-based price feeds. It's used by your protocol components (like Market or Vault) to fetch up-to-date price information for collateral valuation, debt tracking, or LTV calculations.

🔹 Core Design
Price Feed Mapping: Each supported asset address is mapped to a Chainlink AggregatorV3Interface instance.

Admin-Controlled: Only the owner can add, update, or remove feeds.

Chainlink Compatible: Relies on Chainlink’s latestRoundData() to return reliable, tamper-resistant prices.

Single Responsibility: The contract strictly handles price registry and retrieval—no economic logic or transformation.

🧩 Function List
✅ Admin Feed Management
These functions are permissioned and callable only by the contract owner:

addPriceFeed(address asset, address feed)

Adds a new asset → Chainlink feed mapping.

Emits PriceFeedAdded.

updatePriceFeed(address asset, address newFeed)

Replaces the feed for an already-supported asset.

Emits PriceFeedUpdated.

removePriceFeed(address asset)

Deletes the feed mapping for a given asset.

Emits PriceFeedRemoved.

onlyOwner modifier

Restricts sensitive functions to the contract deployer or manually set owner.

📈 Price Retrieval
getLatestPrice(address asset) → int256

Reads the latest price data from the linked Chainlink feed.

Validates feed existence and ensures a positive price.

Used for collateral valuation, debt computation, etc.

# 4. Interest Contract:
🧠 InterestRateModel Architecture 
The InterestRateModel contract implements a Jump Rate Model, a widely used dynamic interest rate mechanism in DeFi lending protocols. It adjusts the borrow rate based on real-time utilization of funds in the vault, helping balance liquidity availability and borrowing incentives.

This model is core to your protocol’s risk management and capital efficiency.

🔹 Core Design Highlights
Utilization-Based Interest Model: Interest rate dynamically shifts based on the proportion of borrowed funds to total capital.

Jump Rate Logic: Applies a gentler slope (slope1) before a threshold (optimalUtilization) and a steeper slope (slope2) after the kink.

Modular Integration: Pulls real-time data from linked Vault and Market contracts to determine capital states.

Admin Configurable: Fully tunable by owner to adapt to market conditions or protocol adjustments.

🧩 Function List
📈 Interest Rate Calculation
getUtilizationRate() → uint256
Calculates the utilization rate 
𝑈
U as:

𝑈
=
totalBorrows
totalStrategyAssets
+
totalBorrows
U= 
totalStrategyAssets+totalBorrows
totalBorrows
​
 
Uses fixed-point arithmetic with 1e18 precision.

Returns 0 if the denominator is zero to avoid division by zero errors.

getDynamicBorrowRate() → uint256
Returns the current borrow interest rate based on utilization 
𝑈
U:

If 
𝑈
<
optimalUtilization
U<optimalUtilization:

Rate
=
baseRate
+
𝑈
×
slope1
Rate=baseRate+U×slope1
If 
𝑈
≥
optimalUtilization
U≥optimalUtilization:

Rate
=
baseRate
+
𝑈
×
slope2
Rate=baseRate+U×slope2
The rate is expressed as an annualized APR with 1e18 fixed-point precision
(e.g., 16% APR = 0.16 × 1e18).

🔍 Vault & Market Integration
getTotalBorrows() → uint256

Reads total borrowed assets from the Market contract.

getTotalAssets() → uint256

Returns sum of:

Vault's totalStrategyAssets()

Outstanding totalBorrows()

Used for utilization rate calculation.

🛠️ Configuration Functions (onlyOwner)
These allow governance or protocol admins to tune the model:

setMarketContract(address _market)

Sets the Market contract (once only).

setBaseRate(uint256)

setOptimalUtilization(uint256)

setSlope1(uint256)

setSlope2(uint256)

All setter functions are restricted via the onlyOwner modifier.

🧰 Access Control
owner: Admin address initialized in constructor.

onlyOwner: Modifier ensuring restricted access to config functions.


<img width="641" alt="Isolated Lending Market Architecture" src="https://github.com/user-attachments/assets/60e0c870-a229-4a5c-82eb-0d8eabf34b9a" />

<img width="661" alt="Screenshot 2025-01-29 at 22 33 36" src="https://github.com/user-attachments/assets/4456df11-1ea0-45e3-bade-23ae6ec0c057" />


