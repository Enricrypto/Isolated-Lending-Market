# 🏦 DeFi Lending Market Protocol

The Isolated Lending Market Protocol is a modular, high-efficiency lending platform designed to provide a secure environment for users to deposit collateral, borrow a single loan asset, and earn yield. It is built on a robust, integrated architecture featuring dynamic interest rates and comprehensive liquidation logic.

---

## 🏗️ Core Architecture

The protocol is composed of four highly interconnected smart contracts:

1.  **`Market.sol`**: The central ledger for all debt and collateral, managing user positions and liquidation rules.
2.  **`Vault.sol` (ERC-4626)**: The liquidity pool for the single $\text{loanAsset}$, optimized for capital efficiency through an external yield-generating $\text{Strategy}$.
3.  **`InterestRateModel.sol`**: Calculates the dynamic borrowing rate based on market utilization.
4.  **`PriceOracle.sol`**: Provides decentralized, reliable USD price feeds for all collateral and the loan asset.

---

## 💰 Key Financial Mechanisms

### 1. Collateral Management and Risk Tracking

The `Market` contract is responsible for tracking user solvency using the **Health Factor ($\text{HF}$)**.

- **Deposits & Tracking:** Collateral tokens are deposited into the $\text{Market}$ and tracked internally using **18-decimal normalized units** for consistent USD valuation.
- **Borrowing Power:** Determined by the $\text{Liquidation Loan-to-Value}$ ($\text{LLTV}$) ratio.
- **Withdrawal Safety:** Users can only `withdrawCollateral` if their position remains **healthy** ($\text{HF} \ge 1$).

The **Health Factor** is the primary risk metric:
$$\text{Health Factor} = \frac{\text{Collateral Value}_{\text{USD}} \times \text{LLTV}}{\text{Borrowed Amount}_{\text{USD}} \times (1 + \text{Liquidation Penalty})}$$

### 2. Dynamic Interest Rate Model

The **`InterestRateModel`** implements a **Jump-Rate Model** to govern the cost of borrowing, ensuring liquidity protection during periods of high demand.

- **Utilization Rate:** The rate is dynamically adjusted based on the ratio of $\text{totalBorrows}$ to $\text{totalAssets}$ (liquidity).
- **Rate Kink:** The model uses $\text{slope1}$ for utilization below an optimal threshold, and a much steeper $\text{slope2}$ above it. This incentivizes repayment when liquidity is scarce.

### 3. Liquidity and Yield Management

The **`Vault`** contract leverages the **ERC-4626 standard** for efficiency and includes an integrated yield strategy.

- **Lending:** Lenders deposit the $\text{loanAsset}$ and receive $\text{Vault Shares}$ ($\text{ERC20}$ tokens) representing their pro-rata ownership of the principal and accrued yield.
- **Yield Strategy:** Idle assets in the $\text{Vault}$ are automatically deployed into an external, high-yield $\text{Strategy}$ vault, maximizing returns for lenders.
- **Access Control:** The `adminBorrow` and `adminRepay` functions are strictly restricted to the `Market` contract, ensuring the $\text{Vault}$ only services approved lending operations.

### 4. Liquidation and Solvency

The $\text{Market}$ contract contains a comprehensive $\text{liquidate}$ function for maintaining protocol solvency.

- **Liquidation Trigger:** Any external user can call $\text{liquidate}$ if a borrower's $\text{Health Factor}$ drops below $1$.
- **Collateral Seizing:** The liquidator repays the borrower's debt and receives the required collateral amount, plus the configured **Liquidation Penalty**, in return.
- **Bad Debt Handling:** In the event that seized collateral is insufficient to cover the debt, the unrecovered principal is tracked and transferred to the designated $\text{badDebtAddress}$ for protocol risk management.

---

## 🛠️ Contract Details and Dependencies

### `Market.sol`

| Function              | Role                                                                                                                        |
| :-------------------- | :-------------------------------------------------------------------------------------------------------------------------- |
| `setMarketParameters` | Admin function to configure $\text{LLTV}$, $\text{liquidationPenalty}$, and $\text{protocolFeeRate}$.                       |
| `addCollateralToken`  | Admin function to support a new collateral asset and link its $\text{PriceOracle}$ feed.                                    |
| `repay`               | Handles principal and interest. The interest portion is split between the $\text{Vault}$ and the $\text{protocolTreasury}$. |

### `Vault.sol`

| Feature             | Description                                                                                                                                          |
| :------------------ | :--------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Inheritance**     | Inherits from OpenZeppelin's $\text{ERC4626}$ and $\text{ReentrancyGuard}$.                                                                          |
| **Total Assets**    | Calculated as $\text{totalStrategyAssets} + \text{market.totalBorrowsWithInterest()}$.                                                               |
| **Strategy Change** | The $\text{changeStrategy}$ function is $\text{nonReentrant}$ to safely withdraw all assets from the old strategy and deposit them into the new one. |

### `PriceOracle.sol`

- Acts as a mapping between an asset address and its **Chainlink $\text{AggregatorV3Interface}$** feed.
- Provides the external USD value used for all collateral and debt valuation within the $\text{Market}$.

---

## 🔐 Security and Administrative Control

| Mechanism                    | Contract(s)       | Purpose                                                                                        |
| :--------------------------- | :---------------- | :--------------------------------------------------------------------------------------------- |
| **`pragma solidity ^0.8.0`** | All               | Enforces Solidity $0.8$ boundary checks for overflow/underflow safety.                         |
| **`nonReentrant`**           | `Market`, `Vault` | Prevents re-entrancy attacks on all critical state-changing functions.                         |
| **`onlyOwner`**              | All               | Restricts configuration changes to the contract owner.                                         |
| **`onlyMarket`**             | `Vault`           | Restricts liquidity operations (`adminBorrow`, `adminRepay`) to the trusted `Market` contract. |
