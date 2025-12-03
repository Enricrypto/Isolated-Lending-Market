# 🏦 DeFi Lending Platform V2

A comprehensive, production-ready decentralized lending protocol built with Solidity 0.8.30 and Foundry. Supports multi-collateral borrowing with dynamic interest rates, health factor-based liquidations, and ERC-4626 vault integration.

[![Solidity](https://img.shields.io/badge/Solidity-0.8.30-blue)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Foundry-Latest-orange)](https://book.getfoundry.sh/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/Tests-58%20Passing-brightgreen)](test/)

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

### Advanced Features

- **Strategy Integration**: Deployable yield strategies for idle capital optimization
- **Bad Debt Management**: Systematic tracking and handling of underwater positions
- **Protocol Fees**: 10% of interest revenue to protocol treasury
- **Pause Controls**: Emergency pause for individual collateral types
- **Price Oracle Integration**: Chainlink-compatible price feeds with staleness checks
- **Precision Accounting**: 18-decimal internal accounting prevents cumulative rounding errors

### Developer Experience

- **Comprehensive Tests**: 58 unit, integration, and scenario tests with 100% core coverage
- **Gas Optimized**: Efficient storage patterns and minimal external calls (~140k gas per operation)
- **Detailed Events**: Complete event coverage for off-chain indexing and monitoring
- **Custom Errors**: Gas-efficient error handling with descriptive messages
- **NatSpec Documentation**: Thorough inline documentation for all public functions

---

---

## 🌐 Deployed Contracts

### Sepolia Testnet

The protocol is currently deployed and operational on Sepolia testnet:

**Core Contracts:**

- **Market**: [`0xB44d...6daF`](https://sepolia.etherscan.io/address/0xB44dA96f11c429A89EA75BF820255d8698b86daF)
- **Vault**: [`0x6104...D27F`](https://sepolia.etherscan.io/address/0x61048f410a148cfd999C078315e430925D45D27F)
- **PriceOracle**: [`0x931C...Ce76`](https://sepolia.etherscan.io/address/0x931C0e524c51518fC0B46B0c941996f6E612Ce76)
- **InterestRateModel**: [`0xaD00...D650`](https://sepolia.etherscan.io/address/0xaD00C98eEDfb769e1ae4c41c55a8B06178F2D650)

**Test Assets:**

- **USDC (Mock)**: `0x4949E3c0fBA71d2A0031D9a648A17632E65ae495`
- **WETH (Mock)**: `0x4F61DeD7391d6F7EbEb8002481aFEc2ebd1D535c`
- **WBTC (Mock)**: `0x773269dE75Ec35Bd786337407af9E725e0E32dD5`

**Try it out:**

```bash
# Get testnet ETH: https://sepoliafaucet.com/
# Mint test tokens and interact with the protocol!
```

### Mainnet

_Coming soon after security audit_

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
│                      Market Contract                         │
│  • Collateral Management  • Borrowing  • Repayment          │
│  • Liquidations          • Health Checks                     │
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
| **Market**            | Core lending logic, collateral management, liquidations    | ~1,130 | 24 tests      |
| **Vault**             | ERC-4626 vault, liquidity management, strategy integration | ~470   | 26 tests      |
| **PriceOracle**       | Chainlink price feeds, staleness checks, decimal handling  | ~260   | Covered       |
| **InterestRateModel** | Jump rate model, dynamic interest calculation              | ~310   | Covered       |

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

#### Market.sol

**Purpose**: Core lending market contract  
**Key Functions**:

- `depositCollateral(token, amount)` - Deposit collateral tokens
- `withdrawCollateral(token, amount)` - Withdraw collateral (if healthy)
- `borrow(amount)` - Borrow loan assets against collateral
- `repay(amount)` - Repay borrowed amount with interest
- `liquidate(borrower)` - Liquidate unhealthy positions
- `getRepayAmount(borrower)` - Calculate exact repayment amount (handles rounding)

**Key Features**:

- Multi-collateral support with individual pause controls
- Decimal normalization for 6, 8, and 18 decimal tokens
- Health factor calculation with liquidation penalty buffer (85% LLTV + 5% buffer)
- Bad debt tracking and management
- Global borrow index for compounding interest accrual

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
defi-lending-platform/
├── src/
│   ├── core/
│   │   ├── Market.sol              # Core lending market
│   │   ├── Vault.sol               # ERC-4626 vault
│   │   ├── PriceOracle.sol         # Chainlink integration
│   │   └── InterestRateModel.sol   # Jump rate model
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
│   │   ├── MarketTest.t.sol        # Market unit tests
│   │   ├── VaultTest.t.sol         # Vault unit tests
│   │   └── DiagnosticTest.t.sol    # Setup verification
│   └── integration/
│       └── IntegrationTest.t.sol   # E2E scenarios
├── script/
│   └── Deploy.s.sol                # Deployment script
├── foundry.toml                    # Foundry configuration
└── README.md                       # This file
```

---

## 🧪 Testing

### Test Suite Overview

| Test File                 | Tests  | Focus                       | Lines      |
| ------------------------- | ------ | --------------------------- | ---------- |
| **MarketTest.t.sol**      | 24     | Market core functionality   | ~640       |
| **VaultTest.t.sol**       | 26     | Vault & ERC-4626 compliance | ~470       |
| **IntegrationTest.t.sol** | 7      | End-to-end scenarios        | ~570       |
| **DiagnosticTest.t.sol**  | 1      | Setup verification          | ~100       |
| **Total**                 | **58** | **Complete coverage**       | **~1,780** |

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

---

## 🚀 Deployment

### Deployment Order

1. Deploy MockERC20 tokens (or use real tokens)
2. Deploy MockPriceFeed (or use Chainlink feeds)
3. Deploy Strategy (ERC-4626 yield strategy)
4. Deploy PriceOracle with deployer as owner
5. Deploy Vault with Strategy
6. Deploy InterestRateModel with Vault
7. Deploy Market with all dependencies
8. Link contracts:
   ```solidity
   vault.setMarket(address(market));
   irm.setMarketContract(address(market));
   oracle.transferOwnership(address(market));
   ```
9. Configure Market:
   ```solidity
   market.setMarketParameters(0.85e18, 0.05e18, 0.10e18);
   market.addCollateralToken(weth, wethFeed);
   market.addCollateralToken(wbtc, wbtcFeed);
   ```
10. Fund Vault with initial liquidity

### Deployment Script

```bash
# Local (Anvil)
anvil  # Start local node
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

# Sepolia Testnet
forge script script/Deploy.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY

# Mainnet
forge script script/Deploy.s.sol \
  --rpc-url $MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

### Post-Deployment Checklist

- [ ] Verify all contracts on Etherscan
- [ ] Transfer oracle ownership to Market
- [ ] Configure market parameters (LLTV = 85%, penalty = 5%, fee = 10%)
- [ ] Add all collateral tokens with Chainlink price feeds
- [ ] Fund vault with initial liquidity (e.g., 100,000 USDC)
- [ ] Test deposit/borrow/repay on testnet
- [ ] Set up monitoring and alerts
- [ ] Conduct security audit
- [ ] Transfer admin roles to multisig

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
2. **Access Control**: Strict role-based permissions (owner, market, liquidator)
3. **Pausable**: Emergency pause capability for individual collateral types
4. **Price Validation**: Staleness checks prevent stale price exploitation
5. **Decimal Safety**: Comprehensive normalization prevents overflow/underflow
6. **Health Factor Buffer**: 5% liquidation penalty creates safety margin before bad debt
7. **Bad Debt Isolation**: Underwater positions tracked separately, don't affect others
8. **Oracle Ownership**: Market controls oracle to prevent price manipulation
9. **Vault Approval**: Market pre-approves Vault for seamless repayments
10. **Custom Errors**: Gas-efficient, descriptive error messages

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

- **GitHub Issues**: [Report bugs or request features](https://github.com/yourusername/defi-lending-platform/issues)
- **Documentation**: Coming soon at docs.yourproject.com
- **Security**: security@yourproject.com

---

## 🙏 Acknowledgments

- **OpenZeppelin**: Security libraries and standards
- **Foundry**: Development framework
- **Chainlink**: Decentralized oracle network
- **Compound Finance**: Interest rate model inspiration
- **Aave**: Liquidation mechanism design patterns

---
