# Isolated Lending Market

A decentralized isolated lending protocol built with Solidity 0.8.30, Foundry, and a Next.js monitoring frontend. Features **UUPS upgradeable contracts**, **multi-sig governance with Timelock**, dynamic interest rates, health factor-based liquidations, ERC-4626 vault integration, and a real-time **event-driven indexer** backed by Supabase.

[![Solidity](https://img.shields.io/badge/Solidity-0.8.30-blue)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Foundry-Latest-orange)](https://book.getfoundry.sh/)
[![Next.js](https://img.shields.io/badge/Next.js-16-black)](https://nextjs.org/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Upgradeable](https://img.shields.io/badge/UUPS-Upgradeable-purple)](https://docs.openzeppelin.com/contracts/5.x/api/proxy)

---

## Table of Contents

- [Architecture](#architecture)
- [Smart Contracts](#smart-contracts)
- [Frontend & Monitoring](#frontend--monitoring)
- [Event-Driven Indexer](#event-driven-indexer)
- [API Reference](#api-reference)
- [Database Schema](#database-schema)
- [Installation](#installation)
- [Testing](#testing)
- [Deployment](#deployment)
- [Usage Examples](#usage-examples)
- [Security](#security)
- [Configuration](#configuration)
- [License](#license)

---

## Architecture

### System Overview

```
                         Users (Lenders / Borrowers / Liquidators)
                                        |
                    +-------------------+-------------------+
                    |                                       |
                    v                                       v
         +-----------------+                    +----------------------+
         |  Smart Contracts |                    |  Next.js Frontend    |
         |  (Sepolia)       |                    |  (Vercel)            |
         |                  |                    |                      |
         |  MarketV1 (UUPS) |<--- events -----  |  Monitoring Dashboard|
         |  Vault (ERC-4626)|                    |  Deposit / Borrow UI |
         |  OracleRouter    |                    |  Position Tracking   |
         |  InterestRateModel|                   +----------+-----------+
         +-----------------+                               |
                    |                                       |
                    | events + reads                        | REST API
                    v                                       v
         +---------------------+                 +--------------------+
         | Indexer Service      |  writes ------> | Supabase PostgreSQL|
         | (Event Listener +   |                  |                    |
         |  Snapshot Generator) |                  | Market             |
         |                     |                  | MarketSnapshot     |
         +---------------------+                  | UserPositionSnapshot|
                                                  | LiquidationEvent   |
                                                  +--------------------+
```

### Key Design Decisions

- **Isolated markets**: Each market is a standalone `MarketV1` + `Vault` pair with its own oracle and interest rate model. Risk is isolated per market.
- **Event-driven indexer**: On-chain events (deposits, borrows, liquidations) trigger real-time snapshot updates via viem polling. Periodic snapshots every 60s provide time-series data.
- **Zero-downtime frontend rebinding**: API response shapes are stable — switching from legacy `MetricSnapshot` to new `MarketSnapshot` required zero frontend hook changes.
- **Severity system**: Each metric dimension (liquidity, APR convexity, oracle) has its own 0-3 severity level. An overall composite severity drives dashboard alerts.

---

## Smart Contracts

### Core Contracts

| Contract | Purpose | Key Features |
|----------|---------|--------------|
| **MarketV1** | UUPS upgradeable lending market | Multi-collateral, health factor, liquidations, emergency pause |
| **Vault** | ERC-4626 liquidity vault | Standard-compliant shares, market-controlled borrows |
| **OracleRouter** | Price feed aggregation | Chainlink + TWAP, staleness checks, confidence scoring |
| **InterestRateModel** | Jump rate model | Dynamic rates based on utilization (2%-60% APR range) |
| **RiskEngine** | On-chain risk assessment | Severity scoring, parameter bounds (coming soon) |
| **RiskProposer** | Governance risk proposals | Role-based parameter change proposals (coming soon) |

### Adapters (Coming Soon)

| Contract | Purpose |
|----------|---------|
| **AaveV3Adapter** | Yield strategy via Aave V3 lending pools |
| **CompoundV2Adapter** | Yield strategy via Compound V2 cTokens |

### Governance

| Role | Capabilities | Delay |
|------|-------------|-------|
| **Owner** | Upgrade contract, set parameters, add collateral | 2 days |
| **Guardian** | Pause borrowing only (emergency) | Instant |
| **Timelock** | Holds ownership, enforces delay on all owner actions | 2 days |
| **Multisig** | Proposes and executes timelock operations | - |

### Deployed Contracts (Sepolia)

| Contract | Address |
|----------|---------|
| **MarketV1 (Proxy)** | [`0xC223...E907`](https://sepolia.etherscan.io/address/0xC223C0634c6312Cb3Bf23e847f1C21Ae9ee9E907) |
| **Vault** | [`0xE554...D3B`](https://sepolia.etherscan.io/address/0xE5543F72AF9411936497Dc7816eB4131bB705D3B) |
| **OracleRouter** | [`0xaA6B...8bD7`](https://sepolia.etherscan.io/address/0xaA6B38118a2581fe6659aFEA79cBF3829b848bD7) |
| **InterestRateModel** | [`0x9997...7E0`](https://sepolia.etherscan.io/address/0x9997ACfd06004a2073B46A974258a9EC1066D7E0) |
| **MarketTimelock** | [`0xF36B...D838`](https://sepolia.etherscan.io/address/0xF36B006869bF22c11B1746a7207A250f2ab0D838) |

---

## Frontend & Monitoring

The frontend is a Next.js 16 app deployed on Vercel. It provides:

- **Dashboard** — Market overview with TVL, total borrows, and per-market severity indicators
- **Deposit / Borrow UI** — Select a market, deposit collateral, borrow against it
- **Monitoring** — Real-time charts for liquidity depth, utilization, borrow rates, and oracle confidence
  - Sub-pages: `/monitoring/liquidity`, `/monitoring/utilization`, `/monitoring/rates`, `/monitoring/oracle`
- **Positions** — Per-user position tracking with health factors (via `/api/positions`)
- **Liquidation Feed** — Recent liquidation events (via `/api/liquidations`)
- **Strategy** — Coming soon
- **Risk Engine** — Coming soon

### Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Next.js 16 (App Router, Turbopack) |
| Styling | Tailwind CSS |
| State | Zustand + React Query |
| Web3 | wagmi + viem |
| Database | Prisma 7 + Supabase PostgreSQL |
| Charts | Recharts |
| Deployment | Vercel |

---

## Event-Driven Indexer

The indexer (`frontend/src/lib/indexer/`) is the data pipeline that bridges on-chain state to the database.

### How It Works

1. **Event Listener** (`listener.ts`) — Polls MarketV1 contract events via `viem.watchContractEvent` (15s interval):
   - `CollateralDeposited`, `CollateralWithdrawn`, `Borrowed`, `Repaid`, `Liquidated`, `GlobalBorrowIndexUpdated`

2. **Snapshot Generator** (`snapshot.ts`) — On each event or periodic tick:
   - Multicall reads: `availableLiquidity`, `totalAssets`, `totalBorrows`, `utilizationRate`, `borrowRate`, `optimalUtilization`, `lendingRate`, `globalBorrowIndex`, oracle `evaluate`
   - Computes derived metrics: `liquidityDepthRatio`, `distanceToKink`, severity levels
   - Writes `MarketSnapshot` to database

3. **Position Tracker** (`position.ts`) — On user events:
   - Calls `getUserPosition(user)` on MarketV1
   - Writes `UserPositionSnapshot` with collateral value, debt, health factor, borrowing power

4. **Liquidation Recorder** (`liquidation.ts`) — On `Liquidated` events:
   - Stores `LiquidationEvent` with idempotent upsert on `(txHash, logIndex)`

### Control

```bash
# Start indexer
curl -X POST http://localhost:3000/api/indexer -d '{"action":"start"}'

# Check status
curl http://localhost:3000/api/indexer

# Stop indexer
curl -X POST http://localhost:3000/api/indexer -d '{"action":"stop"}'
```

---

## API Reference

All endpoints are Next.js API routes under `frontend/src/app/api/`.

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/vaults` | GET | List all markets with latest snapshot (TVL, utilization, severity) |
| `/api/metrics?vault=<addr>` | GET | Current metrics for a specific market |
| `/api/history?signal=<type>&range=<range>&vault=<addr>` | GET | Time-series data. Signals: `liquidity`, `utilization`, `borrowRate`, `oracle`. Ranges: `24h`, `7d`, `30d`, `90d` |
| `/api/positions?user=<addr>` | GET | User positions across all markets (latest per market) |
| `/api/liquidations?limit=<n>` | GET | Recent liquidation events (default 20, max 100) |
| `/api/indexer` | GET | Indexer status |
| `/api/indexer` | POST | Start/stop indexer (`{"action": "start"\|"stop"}`) |
| `/api/poll` | POST | Legacy polling endpoint (to be retired) |

---

## Database Schema

Prisma models backed by Supabase PostgreSQL:

| Model | Purpose |
|-------|---------|
| **Market** | Static registry of isolated markets (vault address, market address, IRM, oracle, metadata) |
| **MarketSnapshot** | Periodic market state (supply, borrows, rates, oracle, severities). ~1 row per market per 60s |
| **UserPositionSnapshot** | Per-user position state (collateral, debt, health factor). Updated on each user event |
| **LiquidationEvent** | On-chain liquidation records (borrower, liquidator, amounts, tx hash) |
| **MetricSnapshot** | Legacy polling-based snapshots (to be retired) |

---

## Installation

### Prerequisites

- [Git](https://git-scm.com/)
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 22+ (required for Prisma 7)
- npm

### Quick Start

```bash
# Clone repository
git clone https://github.com/Enricrypto/Isolated-Lending-Market.git
cd Isolated-Lending-Market

# Install Foundry dependencies
forge install

# Build contracts
forge build

# Run tests
forge test
```

### Frontend Setup

```bash
cd frontend

# Install dependencies
npm install

# Set up environment variables
cp .env.example .env
# Edit .env with your Supabase and RPC credentials

# Generate Prisma client
npx prisma generate

# Push schema to database
npx prisma db push

# Seed the Market table
npx tsx prisma/seed.ts

# Start dev server
npm run dev
```

### Project Structure

```
lending-platform-v2/
├── src/
│   ├── core/
│   │   ├── MarketV1.sol              # UUPS upgradeable lending market
│   │   ├── MarketStorageV1.sol       # Separated storage layout
│   │   ├── Vault.sol                 # ERC-4626 vault
│   │   ├── OracleRouter.sol          # Price feed aggregation
│   │   ├── InterestRateModel.sol     # Jump rate model
│   │   └── RiskEngine.sol            # On-chain risk assessment
│   ├── adapters/
│   │   ├── AaveV3Adapter.sol         # Aave V3 yield strategy
│   │   └── CompoundV2Adapter.sol     # Compound V2 yield strategy
│   ├── governance/
│   │   ├── GovernanceSetup.sol       # Timelock & Guardian
│   │   └── RiskProposer.sol          # Risk parameter proposals
│   ├── libraries/
│   │   ├── Events.sol
│   │   └── Errors.sol
│   └── Interfaces/
│       ├── IOracleRouter.sol
│       ├── IRiskEngine.sol
│       ├── IStrategy.sol
│       ├── ITWAPOracle.sol
│       └── IWETH.sol
├── test/
│   ├── unit/                         # Unit tests
│   ├── integration/                  # E2E + upgrade simulation tests
│   └── governance/                   # Access control + risk proposer tests
├── script/
│   ├── DeployAll.s.sol               # Full deployment script
│   ├── DeployRiskEngine.s.sol
│   ├── DeployAdapters.s.sol
│   └── legacy/
├── frontend/
│   ├── prisma/
│   │   └── schema.prisma             # Database models
│   ├── src/
│   │   ├── app/
│   │   │   ├── (app)/                # Authenticated pages
│   │   │   │   ├── dashboard/
│   │   │   │   ├── deposit/
│   │   │   │   ├── monitoring/       # Liquidity, rates, utilization, oracle
│   │   │   │   ├── strategy/         # Coming soon
│   │   │   │   └── risk-engine/      # Coming soon
│   │   │   ├── (marketing)/          # Landing page
│   │   │   └── api/                  # REST API routes
│   │   │       ├── vaults/
│   │   │       ├── metrics/
│   │   │       ├── history/
│   │   │       ├── positions/
│   │   │       ├── liquidations/
│   │   │       └── indexer/
│   │   ├── components/               # Shared UI components
│   │   ├── hooks/                    # React hooks
│   │   ├── lib/
│   │   │   ├── indexer/              # Event-driven data pipeline
│   │   │   │   ├── events.ts         # MarketV1 event ABI
│   │   │   │   ├── listener.ts       # Event subscriptions
│   │   │   │   ├── snapshot.ts       # Market snapshot generator
│   │   │   │   ├── position.ts       # User position tracker
│   │   │   │   ├── liquidation.ts    # Liquidation recorder
│   │   │   │   └── index.ts          # Orchestrator
│   │   │   ├── agents/               # Legacy polling agents
│   │   │   ├── db.ts                 # Prisma client + helpers
│   │   │   ├── contracts.ts          # Contract ABIs
│   │   │   ├── rpc.ts               # Viem client setup
│   │   │   └── severity.ts          # Severity computation
│   │   ├── store/                    # Zustand state
│   │   └── types/                    # TypeScript types
│   └── package.json
├── foundry.toml
└── README.md
```

---

## Testing

### Foundry Tests

```bash
# All tests
forge test

# Specific test file
forge test --match-path test/unit/RiskEngineTest.t.sol

# With gas report
forge test --gas-report

# Verbose traces
forge test -vvvv
```

### Test Coverage

| Area | Focus |
|------|-------|
| **Market** | Collateral, borrowing, repayment, liquidations, health factors, emergency pause |
| **Vault** | ERC-4626 compliance, market-controlled borrows, share pricing |
| **Oracle** | Price feed management, staleness checks, decimal normalization |
| **Governance** | Timelock delays, guardian pause, role-based access, risk proposals |
| **Integration** | Full lending cycles, price crash liquidation, bad debt, upgrade simulation |

---

## Deployment

### Smart Contracts

```bash
# Set up .env with PRIVATE_KEY, SEPOLIA_RPC_URL, ETHERSCAN_API_KEY
forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast \
  --verify
```

### Frontend (Vercel)

The frontend auto-deploys on push to `main` via Vercel, or manually:

```bash
cd frontend
vercel --prod
```

Required Vercel environment variables:
- `DATABASE_URL` — Supabase connection string (transaction pooler, port 6543)
- `DIRECT_URL` — Supabase connection string (session pooler, port 5432)
- `NEXT_PUBLIC_RPC_URL` — Sepolia RPC endpoint

---

## Usage Examples

### For Lenders

```solidity
// Approve and deposit USDC into vault
IERC20(usdc).approve(address(vault), 10_000e6);
uint256 shares = vault.deposit(10_000e6, msg.sender);

// Later: withdraw with earned interest
uint256 assets = vault.redeem(shares, msg.sender, msg.sender);
```

### For Borrowers

```solidity
// Deposit collateral
IERC20(weth).approve(address(market), 2e18);
market.depositCollateral(address(weth), 2e18);

// Borrow against collateral
market.borrow(3_000e6);

// Repay debt
uint256 repayAmount = market.getRepayAmount(msg.sender);
IERC20(usdc).approve(address(market), repayAmount);
market.repay(repayAmount);

// Withdraw collateral
market.withdrawCollateral(address(weth), 2e18);
```

### For Liquidators

```solidity
if (!market.isHealthy(borrower)) {
    IERC20(usdc).approve(address(market), type(uint256).max);
    market.liquidate(borrower);
    // Receive collateral + 5% liquidation bonus
}
```

---

## Security

### Features

- **ReentrancyGuard** on all state-changing functions
- **UUPS Proxy** with upgrade authorization in implementation
- **TimelockController** with 2-day delay on governance actions
- **Emergency Guardian** for instant borrow pause (deposits/withdrawals/repayments unaffected)
- **Storage Gaps** (49 slots) for safe future upgrades
- **Oracle staleness checks** prevent stale price exploitation
- **Decimal normalization** handles 6/8/18 decimal tokens safely
- **Health factor buffer** (5% liquidation penalty) creates safety margin
- **Bad debt isolation** — underwater positions tracked separately

### Known Limitations

| Risk | Mitigation |
|------|-----------|
| Oracle failure | Multiple feed support, staleness checks, confidence scoring |
| Bank run | High utilization drives rates up, discouraging further borrowing |
| Flash crashes | 5% liquidation penalty buffer, gradual liquidation |
| Strategy loss | Adapter integration is isolated and behind "Coming Soon" gate |

---

## Configuration

### Market Parameters

```
LLTV = 85%               # Max loan-to-value ratio
Liquidation Penalty = 5%  # Liquidator bonus
Protocol Fee = 10%        # Platform revenue from interest
```

### Interest Rate Model

```
Base Rate = 2% APR        # Minimum rate at 0% utilization
Optimal Utilization = 80% # Target utilization
Slope 1 = 4%              # Gradual increase before kink
Slope 2 = 60%             # Steep increase after kink
```

---

## License

This project is licensed under the MIT License.

---

## Acknowledgments

- **OpenZeppelin** — Security libraries, UUPS proxy, TimelockController
- **Foundry** — Development framework
- **Chainlink** — Decentralized oracle network
- **Compound Finance** — Interest rate model inspiration
- **Aave** — Liquidation mechanism design patterns
- **Supabase** — Managed PostgreSQL
- **Vercel** — Frontend deployment
