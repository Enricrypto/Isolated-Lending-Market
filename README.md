# 🏦 Integrated DeFi Lending Market Protocol

A production-ready, single-asset collateralized lending platform built with Solidity. Features ERC-4626 vault integration, automated yield strategies, dynamic interest rates, and comprehensive risk management for capital-efficient DeFi lending.

[![Solidity](https://img.shields.io/badge/Solidity-0.8.x-363636?style=flat-square&logo=solidity)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Foundry-✓-blue?style=flat-square)](https://getfoundry.sh/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](https://opensource.org/licenses/MIT)

## 🌟 Overview

The Integrated DeFi Lending Market Protocol is an advanced lending platform engineered for **capital efficiency** and **solvency**. Unlike traditional lending protocols, all deposited funds automatically flow through an **ERC-4626 Vault** and are deployed into external **yield-generating strategies**, ensuring lenders earn optimized returns while maintaining protocol liquidity.

### Key Highlights

- 🏛️ **Single-Asset Design** - Simplified, efficient lending with one loan asset
- 🔐 **ERC-4626 Vault** - Standard-compliant vault with automated yield strategies
- 📊 **Dynamic Interest Rates** - Jump-rate model adapts to market utilization
- 💰 **Capital Efficient** - All idle funds automatically generate yield
- 🛡️ **Robust Risk Management** - Health factor monitoring and liquidation system
- 🔗 **Integrated Architecture** - Tightly coupled contracts for gas optimization

## 📊 Protocol Statistics

| Metric | Value |
|--------|-------|
| Loan-to-Value (LTV) | Configurable per collateral |
| Liquidation Penalty | Configurable (typically 5-10%) |
| Interest Model | Jump-Rate with dynamic adjustments |
| Vault Standard | ERC-4626 compliant |
| Oracle Type | Decentralized price feeds |

## 🏗️ Core Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Market.sol                        │
│         (Central Lending Ledger)                    │
│  • Debt tracking                                    │
│  • Collateral management                            │
│  • Liquidation logic                                │
└───────────┬─────────────────┬──────────────────────┘
            │                 │
    ┌───────▼──────┐   ┌──────▼──────────┐
    │   Vault.sol  │   │ InterestRate    │
    │  (ERC-4626)  │   │ Model.sol       │
    │              │   │                 │
    │ • Liquidity  │   │ • Dynamic rates │
    │   Pool       │   │ • Utilization   │
    │ • Yield      │   │   based         │
    │   Strategy   │   └─────────────────┘
    └──────┬───────┘
           │
    ┌──────▼──────────┐
    │  PriceOracle    │
    │                 │
    │ • USD feeds     │
    │ • Decentralized │
    └─────────────────┘
```

### Contract Overview

#### 1. **Market.sol** - The Central Ledger
The heart of the protocol. Manages all lending operations, debt tracking, and liquidations.

**Key Functions:**
- `depositCollateral()` - Deposit collateral to enable borrowing
- `borrow()` - Borrow up to LTV limit against collateral
- `repay()` - Repay debt principal and accrued interest
- `liquidate()` - Liquidate unhealthy positions
- `withdrawCollateral()` - Withdraw collateral (if health factor permits)

#### 2. **Vault.sol** - ERC-4626 Liquidity Pool
Standard-compliant vault that holds loan assets and automatically deploys them to yield strategies.

**Key Features:**
- ERC-4626 compliant (composable with DeFi ecosystem)
- Automatic yield strategy integration
- Market-only access control for borrowing
- Share-based accounting for lenders

#### 3. **InterestRateModel.sol** - Dynamic Rates
Jump-rate model that adjusts borrowing costs based on utilization.

**Rate Curve:**
```
│ Rate
│     ╱
│    ╱
│   ╱___
│  ╱
│_╱____________ Utilization
  ↑
  Optimal (e.g., 80%)
```

#### 4. **PriceOracle.sol** - Decentralized Pricing
Provides USD-denominated price feeds for all supported assets.

**Features:**
- Chainlink-compatible oracle integration
- Fallback mechanisms
- Stale price protection

---

## 💡 Key Features and Mechanisms

### 1. Risk Management and Solvency

**Health Factor Calculation:**
```
HF = (Collateral Value × LTV) / Debt Value

Where:
- HF ≥ 1: Healthy position
- HF < 1: Subject to liquidation
```

**Safety Mechanisms:**
- ✅ Health factor enforcement on all operations
- ✅ Withdrawal blocked if HF would fall below 1
- ✅ Bad debt handling in liquidation function
- ✅ Liquidation penalty incentivizes liquidators

### 2. Dynamic Interest Rate Model

**Jump-Rate Model Formula:**
```
If Utilization ≤ Optimal:
  Rate = BaseRate + (Utilization / Optimal) × RateSlope1

If Utilization > Optimal:
  Rate = BaseRate + RateSlope1 + 
         ((Utilization - Optimal) / (1 - Optimal)) × RateSlope2
```

**Benefits:**
- Encourages repayment when utilization is high
- Maintains liquidity for withdrawals
- Adapts to market conditions automatically

### 3. Liquidity and Yield Optimization

**Automated Yield Strategy:**
```
User Deposit → Vault → Strategy (e.g., Aave, Compound)
                ↓
              Yield
                ↓
         Distributed to Lenders
```

**Capital Efficiency:**
- 100% of idle funds earn yield
- No funds sitting unproductive
- Lenders earn base APY + strategy yield
- Strategy can be upgraded by governance

### 4. Liquidation Mechanism

**Liquidation Flow:**
```
1. Position becomes unhealthy (HF < 1)
2. Liquidator repays borrower's debt
3. Liquidator receives collateral + penalty
4. Protocol remains solvent
```

**Example:**
```
Borrower: $1000 debt, $1050 collateral (HF = 0.95)
Liquidator: Repays $1000
Liquidator Receives: $1050 collateral ($50 profit)
```

---

## 🚀 Getting Started

### Prerequisites

Install Foundry:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Installation

```bash
# Clone repository
git clone https://github.com/yourusername/isolated-lending-market.git
cd isolated-lending-market

# Install dependencies
forge install

# Build contracts
forge build
```

### Testing

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test testBorrow

# Coverage report
forge coverage

# Gas report
forge test --gas-report
```

---

## 📖 Usage Examples

### For Lenders

```solidity
// 1. Approve vault to spend loan asset
loanAsset.approve(address(vault), 10000e18);

// 2. Deposit into vault (receive shares)
uint256 shares = vault.deposit(10000e18, msg.sender);

// 3. Earn yield automatically from strategy

// 4. Redeem shares for assets + yield
vault.redeem(shares, msg.sender, msg.sender);
```

### For Borrowers

```solidity
// 1. Deposit collateral
collateralToken.approve(address(market), 1e18);
market.depositCollateral(address(collateralToken), 1e18);

// 2. Borrow against collateral
// If collateral worth $2000, LTV 80%, can borrow $1600
market.borrow(1600e6); // USDC has 6 decimals

// 3. Repay loan + interest
loanAsset.approve(address(market), repayAmount);
market.repay(repayAmount);

// 4. Withdraw collateral
market.withdrawCollateral(address(collateralToken), 1e18);
```

### For Liquidators

```solidity
// 1. Find unhealthy position (HF < 1)
bool isUnhealthy = market.isLiquidatable(borrower);

// 2. Approve repayment
loanAsset.approve(address(market), debtAmount);

// 3. Liquidate and receive collateral + penalty
market.liquidate(borrower, address(collateralToken));
```

---

## 📦 Deployment Guide

### Deployment Sequence (Critical)

Contracts must be deployed in this exact order due to dependencies:

```bash
# 1. Deploy PriceOracle
forge script script/DeployOracle.s.sol --broadcast

# 2. Deploy InterestRateModel
forge script script/DeployInterestModel.s.sol --broadcast

# 3. Deploy external Strategy (ERC4626)
forge script script/DeployStrategy.s.sol --broadcast

# 4. Deploy Vault (needs loanAsset + Strategy addresses)
forge script script/DeployVault.s.sol --broadcast

# 5. Deploy Market (needs all previous addresses)
forge script script/DeployMarket.s.sol --broadcast

# 6. Link contracts (critical!)
forge script script/LinkContracts.s.sol --broadcast
```

### Post-Deployment Setup

```solidity
// 1. Link Market to Vault
vault.setMarketContract(address(market));

// 2. Link Market to InterestRateModel
interestRateModel.setMarketContract(address(market));

// 3. Add supported collateral tokens
market.addCollateralToken(
    address(collateralToken),
    8000, // 80% LTV (basis points)
    address(priceOracle)
);

// 4. Set protocol parameters
market.setLiquidationPenalty(500); // 5% penalty
market.setProtocolFeeRate(1000); // 10% of interest
```

---

## 🧪 Testing Strategy

### Test Coverage

- **Unit Tests**: Individual function testing
- **Integration Tests**: Full borrow → repay → liquidation flows
- **Fuzz Tests**: Randomized inputs for edge cases
- **Invariant Tests**: Protocol-level guarantees
- **Scenario Tests**: Complex multi-user interactions

### Key Invariants

```solidity
// 1. Solvency Invariant
assert(totalCollateralValue >= totalDebtValue);

// 2. Vault Invariant
assert(vault.totalAssets() >= market.totalBorrowed());

// 3. Interest Invariant
assert(accruedInterest >= 0);

// 4. Health Factor Invariant
assert(position.healthFactor < 1 → liquidatable);
```

### Target Coverage: 95%+

---

## 📁 Project Structure

```
isolated-lending-market/
├── src/
│   ├── Market.sol                  # Central lending ledger
│   ├── Vault.sol                   # ERC-4626 vault
│   ├── InterestRateModel.sol       # Jump-rate model
│   ├── PriceOracle.sol             # Price feeds
│   └── interfaces/
│       ├── IMarket.sol
│       ├── IVault.sol
│       └── IInterestRateModel.sol
├── test/
│   ├── unit/
│   │   ├── Market.t.sol
│   │   ├── Vault.t.sol
│   │   └── InterestRateModel.t.sol
│   ├── integration/
│   │   └── FullFlow.t.sol
│   └── fuzzing/
│       └── MarketFuzz.t.sol
├── script/
│   └── Deploy.s.sol
└── README.md
```

---

## 🔧 Configuration

### Default Parameters

```solidity
// Interest Rate Model
BASE_RATE = 200;              // 2% base APR
RATE_SLOPE_1 = 800;           // 8% slope before kink
RATE_SLOPE_2 = 5000;          // 50% slope after kink
OPTIMAL_UTILIZATION = 8000;   // 80% optimal

// Risk Parameters
DEFAULT_LTV = 8000;           // 80% LTV
LIQUIDATION_PENALTY = 500;    // 5% penalty
PROTOCOL_FEE_RATE = 1000;     // 10% of interest

// Vault
INITIAL_EXCHANGE_RATE = 1e18; // 1:1 shares to assets
```

---

## 🚧 Roadmap

### Phase 1: Core Protocol ✅
- [x] Market ledger implementation
- [x] ERC-4626 vault
- [x] Dynamic interest rates
- [x] Liquidation mechanism

### Phase 2: Advanced Features (In Progress)
- [ ] Multi-collateral support
- [ ] Flash loan integration
- [ ] Governance system
- [ ] Protocol revenue distribution

### Phase 3: Optimization (Planned)
- [ ] Gas optimizations
- [ ] L2 deployment
- [ ] Cross-chain compatibility
- [ ] Advanced yield strategies

---

## 📊 Gas Estimates

| Function | Gas Cost (approx) |
|----------|-------------------|
| depositCollateral() | ~120k gas |
| borrow() | ~180k gas |
| repay() | ~150k gas |
| liquidate() | ~200k gas |
| vault.deposit() | ~140k gas |
| vault.withdraw() | ~130k gas |

*Note: Gas costs vary based on state changes and strategy interactions.*

---

## 🔒 Security Considerations

### Implemented Protections

- ✅ **Reentrancy Guards** on all state-changing functions
- ✅ **Health Factor Checks** before all risky operations
- ✅ **Oracle Price Validation** with staleness checks
- ✅ **Access Control** on admin functions
- ✅ **Bad Debt Handling** in liquidations
- ✅ **Strategy Upgrade Timelock** for security

### Audit Status

⚠️ **Not audited.** This is an educational/portfolio project. Do not use in production with real funds without a professional security audit.

### Known Risks

- Oracle manipulation risk
- Strategy contract risk
- Flash loan attack vectors (mitigated)
- Liquidation cascade scenarios

---

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit changes (`git commit -m 'Add AmazingFeature'`)
4. Push to branch (`git push origin feature/AmazingFeature`)
5. Open Pull Request

---

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- Inspired by [Aave](https://aave.com/), [Compound](https://compound.finance/), and [Morpho](https://www.morpho.org/)
- Built with [Foundry](https://getfoundry.sh/)
- Uses [OpenZeppelin](https://openzeppelin.com/) contracts
- ERC-4626 standard by [EIP-4626](https://eips.ethereum.org/EIPS/eip-4626)

---

## 📧 Contact

Your Name - [@yourtwitter](https://twitter.com/yourtwitter)

Project Link: [https://github.com/yourusername/isolated-lending-market](https://github.com/yourusername/isolated-lending-market)

---

**⭐ If you find this project useful, please consider giving it a star!**
