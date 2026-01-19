# 🏦 DeFi Lending Platform V2

A comprehensive, production-ready decentralized lending protocol built with Solidity 0.8.30 and Foundry. Features **UUPS upgradeable contracts**, **multi-sig governance with Timelock**, multi-collateral borrowing with dynamic interest rates, health factor-based liquidations, and ERC-4626 vault integration.

[![Solidity](https://img.shields.io/badge/Solidity-0.8.30-blue)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Foundry-Latest-orange)](https://book.getfoundry.sh/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/Tests-91%20Passing-brightgreen)](test/)
[![Upgradeable](https://img.shields.io/badge/UUPS-Upgradeable-purple)](https://docs.openzeppelin.com/contracts/5.x/api/proxy)

---

## 📋 Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Smart Contracts](#smart-contracts)
- [Installation](#installation)
- [Testing](#testing)
- [Deployment](#deployment)
- [Usage Examples](#usage-examples)
- [Security](#security)
- [Gas Optimization](#gas-optimization)
- [Configuration](#configuration)
- [Contributing](#contributing)
- [License](#license)

---

## ✨ Features

### Core Functionality

- **Multi-Collateral Support**: Deposit any whitelisted ERC20 token as collateral (WETH, WBTC, etc.)
- **Dynamic Interest Rates**: Jump Rate Model adjusts rates based on utilization (2%-60% APR range)
- **Health Factor System**: Prevents over-leveraging and ensures protocol solvency
- **Liquidation Mechanism**: Automated liquidations with 5% bonus protect lenders
- **ERC-4626 Vaults**: Standard-compliant yield-bearing vault tokens
- **Decimal Normalization**: Seamless support for 6, 8, and 18 decimal tokens

### Upgradeability & Governance

- **UUPS Proxy Pattern**: Market contract is upgradeable via OpenZeppelin's UUPS pattern
- **TimelockController**: All upgrades require a 2-day delay for community review
- **Emergency Guardian**: Designated address can pause borrowing instantly (no timelock)
- **Multi-sig Ready**: Designed for Gnosis Safe multisig ownership
- **Storage Gaps**: 49-slot storage gap for safe future upgrades

### Advanced Features

- **Strategy Integration**: Deployable yield strategies for idle capital optimization
- **Bad Debt Management**: Systematic tracking and handling of underwater positions
- **Protocol Fees**: 10% of interest revenue to protocol treasury
- **Borrow-Only Pause**: Emergency pause affects borrowing only; deposits, withdrawals, repayments, and liquidations remain functional
- **Price Oracle Integration**: Chainlink-compatible price feeds with staleness checks
- **Precision Accounting**: 18-decimal internal accounting prevents cumulative rounding errors

### Developer Experience

- **Comprehensive Tests**: 91 unit, integration, governance, and upgrade simulation tests
- **Gas Optimized**: Efficient storage patterns and minimal external calls (~140k gas per operation)
- **Detailed Events**: Complete event coverage for off-chain indexing and monitoring
- **Custom Errors**: Gas-efficient error handling with descriptive messages
- **NatSpec Documentation**: Thorough inline documentation for all public functions

---

---

## 🌐 Deployed Contracts

### Sepolia Testnet (V1 - Upgradeable)

The protocol is currently deployed and operational on Sepolia testnet with **UUPS upgradeability** and **multi-sig governance**:

**Core Contracts:**

| Contract | Address | Description |
|----------|---------|-------------|
| **MarketV1 (Proxy)** | [`0xbe4f...4bb6`](https://sepolia.etherscan.io/address/0xbe4fd219b17c3e55562c9bd9254bc3f3519d4bb6) | Main entry point for users |
| **MarketV1 (Implementation)** | [`0x383b...8266`](https://sepolia.etherscan.io/address/0x383bbcd792d6c60f6b87ae7522cfccfac9b68266) | Logic contract |
| **Vault** | [`0x17a1...9d03`](https://sepolia.etherscan.io/address/0x17a11c0da8951765effd58fa236053c14f779d03) | ERC-4626 liquidity vault |
| **PriceOracle** | [`0xdeae...3af8`](https://sepolia.etherscan.io/address/0xdeae17840f1111d032f16a6dec4126bd22b03af8) | Chainlink price feeds |
| **InterestRateModel** | [`0x4820...7a44`](https://sepolia.etherscan.io/address/0x48205953f4ef7b432d0a4f3d0880b21a9bc97a44) | Jump rate model |
| **MarketTimelock** | [`0xc3a5...2ac0`](https://sepolia.etherscan.io/address/0xc3a57b3b0df30312ce7b1db08b652c6216e22ac0) | 2-day governance delay |

**Test Assets:**

| Token | Address | Decimals |
|-------|---------|----------|
| **USDC (Mock)** | `0x4949E3c0fBA71d2A0031D9a648A17632E65ae495` | 6 |
| **WETH (Mock)** | `0x4F61DeD7391d6F7EbEb8002481aFEc2ebd1D535c` | 18 |
| **WBTC (Mock)** | `0x773269dE75Ec35Bd786337407af9E725e0E32dD5` | 8 |

**Try it out:**

```bash
# Get testnet ETH: https://sepoliafaucet.com/
# Mint test tokens and interact with the protocol!
```

### Mainnet

_Coming soon after security audit_

---

## 🎬 Protocol Demonstration (Sepolia)

We provide **deterministic, reproducible scenarios** on Sepolia testnet that demonstrate the full protocol lifecycle. These scenarios run via GitHub Actions using a funded Sepolia wallet.

### Available Scenarios

| Scenario | Description | Key Operations |
|----------|-------------|----------------|
| **Happy Path** | Complete lending cycle | Deposit → Borrow → Repay → Withdraw |
| **Liquidation** | Price crash triggers liquidation | Collateral deposit → Aggressive borrow → Price drop → Liquidation |
| **Bad Debt** | Black swan event creates bad debt | Max borrow → 80% price crash → Partial recovery → Bad debt recorded |

### Running Scenarios Locally

```bash
# Set environment variables
export SEPOLIA_RPC_URL="https://sepolia.infura.io/v3/YOUR_KEY"
export PRIVATE_KEY="0x..."  # Funded Sepolia wallet

# Run Happy Path scenario
forge script script/scenarios/Scenario_HappyPath.s.sol:Scenario_HappyPath \
  --rpc-url $SEPOLIA_RPC_URL --broadcast -vvvv

# Run Liquidation scenario
forge script script/scenarios/Scenario_Liquidation.s.sol:Scenario_Liquidation \
  --rpc-url $SEPOLIA_RPC_URL --broadcast -vvvv

# Run Bad Debt scenario
forge script script/scenarios/Scenario_BadDebt.s.sol:Scenario_BadDebt \
  --rpc-url $SEPOLIA_RPC_URL --broadcast -vvvv
```

### Running via GitHub Actions

1. Add secrets to your repository:
   - `SEPOLIA_RPC_URL` - Your RPC endpoint (Alchemy/Infura/Ankr)
   - `DEMO_PRIVATE_KEY` - Private key of funded testnet wallet

2. Trigger workflow manually:
   - Go to **Actions** → **Sepolia Protocol Scenarios**
   - Click **Run workflow**
   - Select scenario: `all`, `happy-path`, `liquidation`, or `bad-debt`

### Scenario Details

#### 1. Happy Path (`Scenario_HappyPath.s.sol`)
Demonstrates a complete, successful lending cycle:
- Lender deposits 100k USDC into Vault
- Borrower deposits 10 WETH as collateral ($20,000 value)
- Borrower takes 10k USDC loan
- Borrower repays loan with interest
- Borrower withdraws collateral
- Lender redeems shares with earnings

#### 2. Liquidation (`Scenario_Liquidation.s.sol`)
Demonstrates liquidation mechanics when collateral value drops:
- Borrower deposits 10 WETH collateral
- Borrower takes aggressive 15k USDC loan
- WETH price crashes 40% ($2,000 → $1,200)
- Position becomes unhealthy (health factor < 1)
- Liquidator seizes collateral with 5% bonus
- Price restored for next scenario

#### 3. Bad Debt (`Scenario_BadDebt.s.sol`)
Demonstrates bad debt handling in extreme market conditions:
- Borrower takes maximum capacity loan
- Black swan event: WETH crashes 80% ($2,000 → $400)
- Position becomes deeply underwater (debt > collateral)
- Liquidation recovers partial debt
- Bad debt is recorded and socialized
- Demonstrates importance of conservative risk parameters

---

## 🏗️ Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                         User Interface                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     Governance Layer                         │
│  ┌─────────────────┐  ┌─────────────────┐                   │
│  │   Multisig      │  │    Guardian     │                   │
│  │  (Proposer/     │  │  (Emergency     │                   │
│  │   Executor)     │  │   Pause Only)   │                   │
│  └────────┬────────┘  └────────┬────────┘                   │
│           │                    │                             │
│           ▼                    │                             │
│  ┌─────────────────┐          │                             │
│  │  Timelock       │          │                             │
│  │  (2-day delay)  │◄─────────┘ (no delay for pause)        │
│  └────────┬────────┘                                        │
└───────────┼─────────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────────┐
│                     ERC1967 Proxy                            │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                 MarketV1 (UUPS)                        │  │
│  │  • Collateral Management  • Borrowing  • Repayment    │  │
│  │  • Liquidations  • Health Checks  • Emergency Pause   │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
         │              │              │              │
         ▼              ▼              ▼              ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│    Vault     │ │ PriceOracle  │ │ InterestRate │ │   Strategy   │
│  (ERC-4626)  │ │  (Chainlink) │ │    Model     │ │  (ERC-4626)  │
└──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘
```

### Key Components

| Contract              | Purpose                                                    | Lines  | Test Coverage |
| --------------------- | ---------------------------------------------------------- | ------ | ------------- |
| **MarketV1**          | UUPS upgradeable core lending logic with governance        | ~1,050 | 44 tests      |
| **Vault**             | ERC-4626 vault, liquidity management, strategy integration | ~470   | 23 tests      |
| **PriceOracle**       | Chainlink price feeds, staleness checks, decimal handling  | ~260   | Covered       |
| **InterestRateModel** | Jump rate model, dynamic interest calculation              | ~310   | Covered       |
| **MarketTimelock**    | TimelockController for delayed governance actions          | ~20    | 12 tests      |
| **MarketStorageV1**   | Separated storage layout for upgrade safety                | ~140   | Covered       |

### Governance Architecture

| Role       | Capabilities                                          | Delay     |
| ---------- | ----------------------------------------------------- | --------- |
| **Owner**  | Upgrade contract, set parameters, add collateral      | 2 days    |
| **Guardian** | Pause borrowing only (emergency)                    | Instant   |
| **Timelock** | Holds ownership, enforces delay on all owner actions | 2 days    |
| **Multisig** | Proposes and executes timelock operations           | -         |

### Data Flow Diagrams

#### Deposit & Borrow Flow

```
1. User deposits collateral → Market
2. Market normalizes decimals (6/8/18 → 18)
3. User borrows → Market checks health factor
4. Market borrows from Vault
5. Vault deploys to Strategy
6. Interest accrues via global index
```

#### Repayment Flow

```
1. User calls getRepayAmount() → Gets exact amount
2. User repays → Market receives tokens
3. Market calculates interest + protocol fee
4. Market sends principal + interest to Vault
5. Market sends protocol fee to Treasury
6. Vault deploys to Strategy
7. User's debt updated in storage
```

#### Liquidation Flow

```
1. Price drops → Position becomes unhealthy (HF < 1)
2. Liquidator calls liquidate()
3. Market calculates debt + 5% liquidation bonus
4. Market seizes collateral from borrower
5. Collateral transferred to liquidator
6. Debt repaid to Vault
7. Bad debt (if any) recorded and sent to Bad Debt Address
```

---

## 📜 Smart Contracts

### Core Contracts

#### MarketV1.sol (Upgradeable)

**Purpose**: UUPS upgradeable core lending market with governance
**Key Functions**:

- `initialize(...)` - One-time initialization (replaces constructor)
- `depositCollateral(token, amount)` - Deposit collateral tokens
- `withdrawCollateral(token, amount)` - Withdraw collateral (if healthy)
- `borrow(amount)` - Borrow loan assets against collateral
- `repay(amount)` - Repay borrowed amount with interest
- `liquidate(borrower)` - Liquidate unhealthy positions
- `getRepayAmount(borrower)` - Calculate exact repayment amount (handles rounding)
- `setBorrowingPaused(bool)` - Emergency pause (owner or guardian)
- `setGuardian(address)` - Set emergency guardian (owner only)
- `upgradeToAndCall(newImpl, data)` - Upgrade to new implementation (owner only)

**Key Features**:

- **UUPS Proxy Pattern**: Upgradeable via OpenZeppelin's ERC1967 proxy
- **Emergency Pause**: Guardian can pause borrowing instantly; other operations remain functional
- **Governance Integration**: Owner is TimelockController for delayed upgrades
- Multi-collateral support with individual pause controls
- Decimal normalization for 6, 8, and 18 decimal tokens
- Health factor calculation with liquidation penalty buffer (85% LLTV + 5% buffer)
- Bad debt tracking and management
- Global borrow index for compounding interest accrual

#### MarketStorageV1.sol

**Purpose**: Separated storage layout for upgrade-safe state management
**Storage Layout**:

```
Slot 0:     owner
Slot 1:     protocolTreasury
Slot 2:     badDebtAddress
Slot 3:     vaultContract
Slot 4:     priceOracle
Slot 5:     interestRateModel
Slot 6:     loanAsset
Slot 7-9:   marketParams (3 uint256s)
Slot 10:    totalBorrows
Slot 11:    globalBorrowIndex
Slot 12:    lastAccrualTimestamp
Slot 13:    paused + guardian (packed)
Slot 14-21: mappings
Slot 22-70: __gap (49 slots reserved for upgrades)
```

#### Vault.sol

**Purpose**: ERC-4626 compliant liquidity vault  
**Key Functions**:

- `deposit(assets, receiver)` / `mint(shares, receiver)` - Deposit assets for shares
- `withdraw(assets, receiver, owner)` / `redeem(shares, receiver, owner)` - Withdraw assets
- `adminBorrow(amount)` - Market borrows from vault (only Market)
- `adminRepay(amount)` - Market repays to vault (only Market)
- `changeStrategy(newStrategy)` - Migrate to new yield strategy

**Key Features**:

- Full ERC-4626 compliance with standard interfaces
- Strategy integration for yield generation
- Market-controlled liquidity management
- Available liquidity tracking
- Share price calculation with interest accrual

#### PriceOracle.sol

**Purpose**: Chainlink price feed management  
**Key Functions**:

- `addPriceFeed(asset, feed)` - Register new price feed
- `getLatestPrice(asset)` - Get current price with staleness check
- `updatePriceFeed(asset, newFeed)` - Update existing price feed
- `transferOwnership(newOwner)` - Transfer oracle control (typically to Market)

**Key Features**:

- Chainlink-compatible AggregatorV3Interface
- Staleness validation (default: 1 hour max age)
- Decimal normalization to 18 decimals
- Multiple price feed support per deployment

#### InterestRateModel.sol

**Purpose**: Dynamic interest rate calculation using Jump Rate Model

**Formula**:

```solidity
if (utilization < optimal):
    rate = baseRate + (utilization * slope1)
else:
    rate = baseRate + (optimal * slope1) + ((utilization - optimal) * slope2)
```

**Default Parameters**:

- Base Rate: 2% APR (minimum rate at 0% utilization)
- Optimal Utilization: 80% (target utilization)
- Slope 1: 4% (gradual increase before optimal)
- Slope 2: 60% (steep increase after optimal)

**Example Rates**:

- 10% utilization → 2.5% APR
- 50% utilization → 4.5% APR
- 80% utilization → 5.2% APR
- 90% utilization → 11.2% APR (steep to discourage over-utilization)

---

## 🚀 Installation

### Prerequisites

- [Git](https://git-scm.com/)
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 16+ (optional, for scripts)

### Quick Start

```bash
# Clone repository
git clone https://github.com/yourusername/defi-lending-platform.git
cd defi-lending-platform

# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test

# Run tests with gas report
forge test --gas-report
```

### Project Structure

```
lending-platform-v2/
├── src/
│   ├── core/
│   │   ├── MarketV1.sol            # UUPS upgradeable lending market
│   │   ├── MarketStorageV1.sol     # Separated storage layout
│   │   ├── Market.sol              # Non-upgradeable version (legacy)
│   │   ├── Vault.sol               # ERC-4626 vault
│   │   ├── PriceOracle.sol         # Chainlink integration
│   │   └── InterestRateModel.sol   # Jump rate model
│   ├── governance/
│   │   └── GovernanceSetup.sol     # Timelock & Guardian contracts
│   ├── libraries/
│   │   ├── DataTypes.sol           # Struct definitions
│   │   ├── Events.sol              # Event definitions
│   │   └── Errors.sol              # Custom errors
│   └── interfaces/
│       ├── IMarket.sol
│       ├── IVault.sol
│       ├── IPriceOracle.sol
│       └── IInterestRateModel.sol
├── test/
│   ├── Mocks.sol                   # Shared mock contracts
│   ├── unit/
│   │   ├── MarketTest.t.sol        # Market unit tests (24 tests)
│   │   ├── MarketV1Test.t.sol      # Proxy & upgrade tests (20 tests)
│   │   ├── VaultTest.t.sol         # Vault unit tests (23 tests)
│   │   └── GovernanceTest.t.sol    # Timelock & guardian tests (12 tests)
│   └── integration/
│       ├── IntegrationTest.t.sol   # E2E scenarios (7 tests)
│       └── UpgradeSimulationTest.t.sol # Upgrade simulation (5 tests)
├── script/
│   ├── Deploy.s.sol                # Non-upgradeable deployment
│   ├── DeployUpgradeable.s.sol     # Upgradeable deployment + governance
│   ├── DeployUpgradeableMarket.s.sol # Full stack deployment
│   └── scenarios/
│       ├── Scenario_HappyPath.s.sol    # Full lending cycle demo
│       ├── Scenario_Liquidation.s.sol  # Price crash liquidation
│       └── Scenario_BadDebt.s.sol      # Black swan bad debt
├── foundry.toml                    # Foundry configuration
└── README.md                       # This file
```

---

## 🧪 Testing

### Test Suite Overview

| Test File                      | Tests  | Focus                              |
| ------------------------------ | ------ | ---------------------------------- |
| **MarketTest.t.sol**           | 24     | Core lending functionality         |
| **MarketV1Test.t.sol**         | 20     | Proxy, initialization, upgrades    |
| **VaultTest.t.sol**            | 23     | Vault & ERC-4626 compliance        |
| **GovernanceTest.t.sol**       | 12     | Timelock & guardian functionality  |
| **IntegrationTest.t.sol**      | 7      | End-to-end scenarios               |
| **UpgradeSimulationTest.t.sol**| 5      | Upgrade with active positions      |
| **Total**                      | **91** | **Complete coverage**              |

### Running Tests

```bash
# All tests
forge test

# Specific test file
forge test --match-path test/unit/MarketTest.t.sol

# Specific test
forge test --match-test testBorrow

# With console logs (scenarios)
forge test --match-path test/integration/IntegrationTest.t.sol -vv

# With detailed traces
forge test -vvvv

# With gas report
forge test --gas-report

# Coverage report
forge coverage
```

### Test Coverage

#### Market Tests (24)

✅ Collateral Management

- Deposit single/multiple collaterals
- Withdraw collateral (healthy check)
- Pause/resume collateral deposits
- Decimal normalization (6, 8, 18)

✅ Borrowing & Repayment

- Borrow with collateral validation
- Repay with interest accrual
- Partial payments
- `getRepayAmount()` helper

✅ Liquidations

- Liquidate unhealthy positions
- Cannot liquidate healthy positions
- Bad debt handling

✅ Health Factors

- Health factor calculations
- Liquidation penalty buffer
- Multi-collateral scenarios

✅ Admin Functions

- Access control (onlyOwner)
- Parameter updates
- Add/remove collateral tokens

#### Vault Tests (26)

✅ ERC-4626 Compliance

- `deposit()` / `mint()`
- `withdraw()` / `redeem()`
- Share price calculations
- Preview functions

✅ Strategy Integration

- Asset deployment to strategy
- Strategy migration
- Asset preservation during migration

✅ Market Integration

- `adminBorrow()` / `adminRepay()`
- Available liquidity tracking
- Total assets with borrows

✅ Access Control

- Only market can borrow/repay
- Only market owner can change strategy

#### Integration Tests (7 Scenarios)

1. **Basic Lending Cycle**: Deposit → Borrow → Interest → Repay → Withdraw
2. **Multiple Collaterals**: Mixed WETH + WBTC positions
3. **Liquidation Event**: Price crash → Liquidation → Bad debt
4. **Interest Rate Dynamics**: Rate changes from 10% to 90% utilization
5. **Vault Operations**: Multiple depositors earning yield
6. **Bad Debt Scenario**: Underwater position handling
7. **Strategy Migration**: Live migration with active borrows

#### Upgrade & Governance Tests (37 tests)

✅ Proxy & Initialization (MarketV1Test)
- Proxy delegates to implementation
- Cannot initialize twice
- Implementation cannot be initialized directly
- Only owner can upgrade

✅ Emergency Pause (MarketV1Test)
- Guardian can pause borrowing
- Pause allows deposits, withdrawals, repayments, liquidations
- Non-guardian cannot pause

✅ Timelock & Guardian (GovernanceTest)
- Timelock enforces 2-day delay
- Guardian can pause without delay
- Full governance flow (schedule → wait → execute)
- Timelock can perform upgrades

✅ Upgrade Simulation (UpgradeSimulationTest)
- Upgrade preserves user positions
- Upgrade during pause preserves pause state
- Liquidation works after upgrade
- Multiple sequential upgrades maintain state
- Storage layout verification

---

## 🚀 Deployment

### Upgradeable Deployment (Recommended)

The upgradeable deployment uses UUPS proxy pattern with TimelockController governance.

#### Deployment Order

1. Deploy PriceOracle
2. Deploy Vault (ERC-4626)
3. Deploy InterestRateModel
4. Deploy MarketV1 Implementation
5. Deploy ERC1967Proxy with initialization data
6. Link contracts (Vault ↔ Market, IRM ↔ Market)
7. Add price feeds and collateral tokens
8. Deploy TimelockController
9. Set Guardian address
10. Transfer ownership to Timelock

#### Deployment Script

```bash
# Set up environment variables in .env:
# PRIVATE_KEY, SEPOLIA_RPC_URL, ETHERSCAN_API_KEY
# LOAN_ASSET_ADDRESS, PROTOCOL_TREASURY, BAD_DEBT_ADDRESS
# STRATEGY_ADDRESS, GUARDIAN_ADDRESS, MULTISIG_ADDRESS
# WETH_ADDRESS, WETH_FEED, WBTC_ADDRESS, WBTC_FEED, LOAN_ASSET_FEED

# Deploy upgradeable Market with governance
forge script script/DeployUpgradeableMarket.s.sol:DeployUpgradeableMarket \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

### Performing an Upgrade

```solidity
// 1. Deploy new implementation
MarketV2 newImpl = new MarketV2();

// 2. Schedule upgrade through Timelock (as multisig)
bytes memory upgradeData = abi.encodeWithSelector(
    UUPSUpgradeable.upgradeToAndCall.selector,
    address(newImpl),
    "" // or initialization data for V2
);
timelock.schedule(
    address(marketProxy),
    0,
    upgradeData,
    bytes32(0),
    keccak256("upgrade-v2"),
    2 days
);

// 3. Wait 2 days...

// 4. Execute upgrade (as multisig)
timelock.execute(
    address(marketProxy),
    0,
    upgradeData,
    bytes32(0),
    keccak256("upgrade-v2")
);
```

### Emergency Pause (No Timelock Needed)

```solidity
// Guardian can pause borrowing instantly
market.setBorrowingPaused(true);

// Users can still:
// - Deposit collateral
// - Withdraw collateral
// - Repay debt
// - Get liquidated

// Unpause requires owner (through timelock) or guardian
market.setBorrowingPaused(false);
```

### Post-Deployment Checklist

- [ ] Verify all contracts on Etherscan
- [ ] Verify proxy points to correct implementation
- [ ] Test basic operations (deposit, borrow, repay)
- [ ] Verify Timelock owns Market
- [ ] Verify Guardian can pause
- [ ] Test upgrade flow on testnet
- [ ] Set up monitoring and alerts
- [ ] Configure multisig with appropriate signers
- [ ] Document upgrade procedures for team

---

## 💡 Usage Examples

### For Lenders (Liquidity Providers)

```solidity
// 1. Approve USDC
IERC20(usdc).approve(address(vault), 10_000e6);

// 2. Deposit to vault (receive shares)
uint256 shares = vault.deposit(10_000e6, msg.sender);
// Shares represent your claim on vault assets + interest

// 3. Check your balance
uint256 yourAssets = vault.convertToAssets(shares);
// This increases as borrowers pay interest

// 4. Later: Withdraw with earned interest
uint256 assets = vault.redeem(shares, msg.sender, msg.sender);
// Receive original deposit + interest earned
```

### For Borrowers

```solidity
// 1. Approve collateral (e.g., 2 WETH)
IERC20(weth).approve(address(market), 2e18);

// 2. Deposit collateral
market.depositCollateral(address(weth), 2e18);
// 2 WETH at $2,000 = $4,000 collateral

// 3. Check borrowing power
// Max borrow = $4,000 * 85% LLTV = $3,400

// 4. Borrow USDC (stay under limit for safety)
market.borrow(3_000e6); // Borrow $3,000

// 5. Later: Check debt (includes interest)
uint256 debt = market.getUserTotalDebt(msg.sender);

// 6. Repay debt (use helper for exact amount)
uint256 repayAmount = market.getRepayAmount(msg.sender);
IERC20(usdc).approve(address(market), repayAmount);
market.repay(repayAmount);

// 7. Withdraw collateral (now that debt is paid)
market.withdrawCollateral(address(weth), 2e18);
```

### For Liquidators

```solidity
// 1. Monitor positions
bool isHealthy = market.isHealthy(borrower);
UserPosition memory position = market.getUserPosition(borrower);

// 2. If unhealthy (health factor < 1), liquidate
if (!isHealthy) {
    // Approve loan asset (USDC)
    IERC20(usdc).approve(address(market), type(uint256).max);

    // Liquidate
    market.liquidate(borrower);

    // Receive collateral + 5% liquidation bonus
    // If debt was $1,000, collateral seized = $1,000 * 1.05 = $1,050
}
```

---

## 🔒 Security

### Security Features

1. **ReentrancyGuard**: All state-changing functions protected against reentrancy
2. **UUPS Proxy**: Upgrade authorization in implementation prevents unauthorized upgrades
3. **TimelockController**: 2-day delay on all governance actions allows community review
4. **Emergency Guardian**: Can pause borrowing instantly without timelock delay
5. **Borrow-Only Pause**: Pause only affects borrowing; users can always repay/withdraw
6. **Storage Gaps**: 49-slot gap prevents storage collisions during upgrades
7. **Price Validation**: Staleness checks prevent stale price exploitation
8. **Decimal Safety**: Comprehensive normalization prevents overflow/underflow
9. **Health Factor Buffer**: 5% liquidation penalty creates safety margin before bad debt
10. **Bad Debt Isolation**: Underwater positions tracked separately, don't affect others
11. **Oracle Ownership**: Market controls oracle to prevent price manipulation
12. **Custom Errors**: Gas-efficient, descriptive error messages

### Security Best Practices Implemented

```solidity
// ✅ Check-Effects-Interactions pattern
function borrow(uint256 amount) external {
    // Checks
    if (amount == 0) revert InvalidAmount();
    if (!_isHealthy(msg.sender)) revert PositionUnhealthy();

    // Effects
    userTotalDebt[msg.sender] += normalizedAmount;
    totalBorrows += normalizedAmount;

    // Interactions
    vaultContract.adminBorrow(amount);
    loanAsset.transfer(msg.sender, amount);
}

// ✅ Return value validation
bool success = loanAsset.transfer(user, amount);
if (!success) revert TransferFailed();

// ✅ Input validation
if (user == address(0)) revert ZeroAddress();
if (token == badDebtAddress) revert SystemAddressRestricted();

// ✅ Overflow protection (Solidity 0.8.x)
// Built-in overflow/underflow checks
```

### Known Limitations & Mitigations

| Risk             | Impact                 | Mitigation                                          |
| ---------------- | ---------------------- | --------------------------------------------------- |
| Oracle failure   | Price manipulation     | Multiple price feed support, staleness checks       |
| Strategy loss    | Vault value decrease   | Conservative strategy selection, strategy audits    |
| Bank run         | Liquidity shortage     | High utilization → high rates discourages borrowing |
| Flash crashes    | Liquidation cascade    | 5% penalty buffer, gradual liquidation              |
| Gas price spikes | Expensive liquidations | Off-chain bots monitor 24/7                         |

### Audit Recommendations

**Critical**:

- [ ] Formal verification of interest rate calculations
- [ ] Fuzzing for edge cases (extreme prices, utilization)
- [ ] Economic modeling under various market conditions

**High**:

- [ ] Access control review (all admin functions)
- [ ] Strategy integration security review
- [ ] Oracle failure scenario testing

**Medium**:

- [ ] Gas optimization analysis
- [ ] Event emission completeness
- [ ] Documentation accuracy

---

## ⚡ Gas Optimization

### Gas Benchmarks

| Operation                       | Gas Cost | Notes                        |
| ------------------------------- | -------- | ---------------------------- |
| Deposit Collateral (first)      | ~142k    | Includes storage allocation  |
| Deposit Collateral (subsequent) | ~60k     | Storage update only          |
| Withdraw Collateral             | ~62k     | Standard withdrawal          |
| Borrow                          | ~251k    | Includes vault interaction   |
| Repay                           | ~181k    | With interest calculation    |
| Liquidate                       | ~432k    | Complex multi-step operation |
| Vault Deposit (first)           | ~123k    | ERC-4626 deposit + strategy  |
| Vault Withdraw                  | ~91k     | ERC-4626 withdrawal          |

### Optimization Techniques

1. **Storage Packing**: Minimize storage slots
2. **Immutable Variables**: `owner`, `vaultContract` (saves SLOAD)
3. **Custom Errors**: ~20 gas vs string errors
4. **View Functions**: Extensive use for off-chain queries
5. **Batch Operations**: `addCollateralToken` combines steps

---

## 🔧 Configuration

### Market Parameters

```solidity
// Recommended configuration
LLTV = 85% (0.85e18)              // Max loan-to-value ratio
Liquidation Penalty = 5% (0.05e18) // Liquidator bonus
Protocol Fee = 10% (0.10e18)       // Platform revenue from interest
```

### Interest Rate Model

```solidity
Base Rate = 2% APR (0.02e18)      // Minimum rate at 0% utilization
Optimal Utilization = 80% (0.8e18) // Target utilization rate
Slope 1 = 4% (0.04e18)            // Gradual increase before optimal
Slope 2 = 60% (0.60e18)           // Steep increase after optimal
```

### Supported Token Examples

| Token | Decimals | Use Case   | Price Feed         |
| ----- | -------- | ---------- | ------------------ |
| USDC  | 6        | Loan Asset | Chainlink USDC/USD |
| USDT  | 6        | Loan Asset | Chainlink USDT/USD |
| DAI   | 18       | Loan Asset | Chainlink DAI/USD  |
| WETH  | 18       | Collateral | Chainlink ETH/USD  |
| WBTC  | 8        | Collateral | Chainlink BTC/USD  |

---

## 🤝 Contributing

Contributions welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`forge test`)
5. Format code (`forge fmt`)
6. Commit changes (`git commit -m 'Add amazing feature'`)
7. Push to branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

---

## 📄 License

This project is licensed under the MIT License.

---

## 📞 Contact

- **GitHub Issues**: [Report bugs or request features](https://github.com/Enricrypto/defi-lending-platform/issues)

---

## 🙏 Acknowledgments

- **OpenZeppelin**: Security libraries, UUPS proxy pattern, and TimelockController
- **Foundry**: Development framework
- **Chainlink**: Decentralized oracle network
- **Compound Finance**: Interest rate model inspiration
- **Aave**: Liquidation mechanism design patterns

---
