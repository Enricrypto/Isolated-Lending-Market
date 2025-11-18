# 🏦 Integrated DeFi Lending Market Protocol

The Integrated DeFi Lending Market Protocol is a single-asset, collateralized lending platform built on Solidity, engineered for **capital efficiency** and **solvency**. The protocol uses a robust, non-upgradeable $\text{Market}$ ledger, linked to specialized external contracts for dynamic pricing and interest. The core feature is its liquidity management: all deposited funds flow through an **ERC-4626 Vault** and are automatically deployed into an external **yield-generating strategy**, ensuring lenders earn optimized returns.

---

## 🏗️ Core Architecture

The protocol's structure is highly integrated and composed of four key contracts:

1.  **`Market.sol`**: The central ledger for debt, collateral, and liquidation logic.
2.  **`Vault.sol` (ERC-4626)**: The liquidity pool for the single $\text{loanAsset}$, optimized for yield.
3.  **`InterestRateModel.sol`**: Calculates the dynamic borrowing rate based on utilization.
4.  **`PriceOracle.sol`**: Provides decentralized USD price feeds for all assets.


---

## 💡 Key Features and Mechanisms

### 1. Risk Management and Solvency

* **Integrated Risk:** Solvency is enforced via a comprehensive **Health Factor** calculation ($\text{LLTV} + \text{Liquidation Penalty}$) and supported by a decentralized $\text{Price Oracle}$.
* **Withdrawal Safety:** Users can only `withdrawCollateral` if their position remains **healthy** ($\text{HF} \ge 1$).
* **Solvency Guarantee:** The $\text{Market}$ contains integrated $\text{Bad Debt}$ handling within its $\text{liquidate}$ function, ensuring protocol integrity when collateral is seized.

### 2. Dynamic Interest Rate Model

Interest is determined by a **Jump-Rate Model** (`InterestRateModel`) which dynamically adjusts the borrow rate based on market utilization, promoting liquidity stability.

* The rate adjusts steeply above an optimal utilization threshold to incentivize repayments.


### 3. Liquidity and Yield Optimization

* **ERC-4626 Standard:** The `Vault` adheres to the $\text{ERC-4626}$ standard, issuing shares to lenders and acting as a yield-bearing wrapper for the $\text{loanAsset}$.
* **Strategy-Enabled:** Deposited funds are automatically deployed into an external **yield-generating strategy**, ensuring high capital efficiency.
* **Market-Only Access:** The `Vault` reserves its critical liquidity functions (`adminBorrow`, `adminRepay`) exclusively for the trusted `Market` contract.

---

## ⚙️ Core Contract Functions (Market Ledger)

| Function | Role |
| :--- | :--- |
| `depositCollateral` | Transfers collateral from the user; updates normalized balances. |
| `borrow` | Allows borrowing up to the collateralized $\text{LLTV}$ limit, utilizing liquidity from the $\text{Vault}$. |
| `repay` | Covers principal and accrued interest; interest is split between the $\text{Vault}$ and $\text{protocolTreasury}$. |
| `liquidate` | Allows external users to repay an unhealthy borrower's debt and seize collateral plus penalty. |

---

## 🚀 Setup and Development

This project uses **Foundry** (Forge and Cast) for all development, testing, and deployment tasks.

### Prerequisites

You must have **Foundry** installed. If not, run:

```bash
curl -L [https://foundry.paradigm.xyz](https://foundry.paradigm.xyz) | bash
# Then follow the on-screen instructions to finish the installation.

### Installation

Clone the repository and install dependencies:

```bash
git clone [Your Repository URL]
cd [Your Repository Name]
forge install
```

### 🧪 Running Tests

To run all unit and integration tests:

```bash
forge test
```

To check the code coverage:

```bash
forge coverage
```

### 📦 Deployment Flow

The contracts must be deployed in a specific sequence due to their dependencies:

1.  **Price Oracle:** Deploy `PriceOracle.sol`.
2.  **Interest Rate Model:** Deploy `InterestRateModel.sol` (requires initial parameters).
3.  **Strategy Vault:** Deploy the external $\text{ERC4626}$ strategy contract (address is needed for the main $\text{Vault}$).
4.  **Main Vault:** Deploy `Vault.sol` (requires $\text{loanAsset}$ address and $\text{Strategy}$ address).
5.  **Market:** Deploy `Market.sol` (requires the addresses of `Vault`, $\text{PriceOracle}$, $\text{InterestRateModel}$, and the $\text{loanAsset}$).
6.  **Post-Deployment Setup (Critical Linking):**
    - Call `setMarketContract` on the `Vault` and `InterestRateModel` to link the final `Market` address.
    - The `Market` owner must call $\text{addCollateralToken}$ to register all supported collateral assets and their $\text{PriceOracle}$ feeds.

