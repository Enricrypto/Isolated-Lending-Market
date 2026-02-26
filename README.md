# Isolated Lending Market

A decentralized isolated lending protocol built with Solidity 0.8.30, Foundry, and a full-stack TypeScript platform. Features **UUPS upgradeable contracts**, **multi-sig governance with Timelock**, a Jump Rate interest model, health factor-based liquidations, ERC-4626 vault integration, and a **deterministic block-based indexer** backed by Supabase PostgreSQL.

[![Solidity](https://img.shields.io/badge/Solidity-0.8.30-blue)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Foundry-Latest-orange)](https://book.getfoundry.sh/)
[![Next.js](https://img.shields.io/badge/Next.js-15-black)](https://nextjs.org/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Upgradeable](https://img.shields.io/badge/UUPS-Upgradeable-purple)](https://docs.openzeppelin.com/contracts/5.x/api/proxy)

---

## Table of Contents

- [Architecture](#architecture)
- [Smart Contracts](#smart-contracts)
- [Backend Service](#backend-service)
- [Frontend](#frontend)
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
         |  MarketV1 (UUPS) |                    |  Dashboard + Charts  |
         |  Vault (ERC-4626)|                    |  Deposit / Withdraw  |
         |  OracleRouter    |                    |  Monitoring Pages    |
         |  InterestRateModel                    +----------+-----------+
         +-----------------+                               |
                    |                                       |
                    | getLogs (per block)                   | REST API
                    v                                       v
         +---------------------+                 +--------------------+
         |  Backend Service     |  writes ------> | Supabase PostgreSQL|
         |  (Railway/Node.js)   |                 |                    |
         |                      |                 | Market             |
         |  Block-based Indexer |                 | MarketSnapshot     |
         |  Express REST API    |                 | UserPositionSnapshot|
         |  node-cron Jobs      |                 | LiquidationEvent   |
         |  Pino Logging        |                 | SyncState          |
         +---------------------+                 | IndexedBlock       |
                                                  +--------------------+
```

### Key Design Decisions

- **Isolated markets** — Each market is a standalone `MarketV1` + `Vault` pair with its own oracle and interest rate model. Risk is fully isolated per market — a WBTC liquidation cascade cannot affect the USDC market.
- **Deterministic block-based indexer** — Processes `getLogs` per confirmed block (tip − 12 confirmations) in strict block/log order. Survives restarts via `SyncState` cursor. Detects and rolls back reorgs using a 20-block `IndexedBlock` hash window.
- **Separated backend service** — The indexer and data API run as a persistent Node.js/Express process on Railway, decoupled from the Next.js frontend. Vercel serverless functions cannot run persistent event listeners.
- **Severity system** — Each metric dimension (liquidity depth, APR convexity, oracle confidence) has its own 0–3 severity level. A composite maximum drives dashboard alerts and colour coding.
- **Jump Rate Model** — Interest rates rise gradually up to 80% utilization (the "kink"), then spike steeply above it to incentivise repayment and protect lender liquidity.

---

## Smart Contracts

### Core Contracts

| Contract | Purpose | Key Features |
|----------|---------|--------------|
| **MarketV1** | UUPS upgradeable lending market | Multi-collateral, health factor, liquidations, emergency pause |
| **Vault** | ERC-4626 liquidity vault | Standard-compliant shares, market-controlled borrows |
| **OracleRouter** | Price feed aggregation | Chainlink + TWAP, staleness checks, confidence scoring |
| **InterestRateModel** | Jump Rate Model | Dynamic rates based on utilization (2%–17.2% APR range) |
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
| **Multisig** | Proposes and executes timelock operations | — |

### Deployed Contracts (Sepolia)

| Contract | Address |
|----------|---------|
| **MarketV1 (Proxy)** | [`0xC223...E907`](https://sepolia.etherscan.io/address/0xC223C0634c6312Cb3Bf23e847f1C21Ae9ee9E907) |
| **Vault** | [`0xE554...D3B`](https://sepolia.etherscan.io/address/0xE5543F72AF9411936497Dc7816eB4131bB705D3B) |
| **OracleRouter** | [`0xaA6B...8bD7`](https://sepolia.etherscan.io/address/0xaA6B38118a2581fe6659aFEA79cBF3829b848bD7) |
| **InterestRateModel** | [`0x9997...7E0`](https://sepolia.etherscan.io/address/0x9997ACfd06004a2073B46A974258a9EC1066D7E0) |
| **MarketTimelock** | [`0xF36B...D838`](https://sepolia.etherscan.io/address/0xF36B006869bF22c11B1746a7207A250f2ab0D838) |

### Interest Rate Model Parameters

```
Base Rate        = 2%    — minimum borrow rate at 0% utilization
Optimal (kink)   = 80%   — target utilization
Slope 1          = 4%    — gradual rate increase below kink
Slope 2          = 60%   — steep rate increase above kink
Protocol Fee     = 10%   — share of interest taken by treasury

util=0%  → borrow 2.00%,  supply 0.00%
util=40% → borrow 3.60%,  supply 1.30%
util=80% → borrow 5.20%,  supply 3.74%  ← kink
util=90% → borrow 11.20%, supply 9.07%
util=100%→ borrow 17.20%, supply 15.48%
```

---

## Backend Service

The backend (`backend/`) is a standalone Node.js + Express service that runs persistently on Railway. It owns the indexer and serves all data API endpoints.

### Block-Based Deterministic Indexer

```
watchBlockNumber (HTTP polling — chain tip)
        │
        ▼
confirmed = tip - CONFIRMATIONS (12)
        │
        ▼
getLogs(fromBlock=lastProcessed+1, toBlock=confirmed)
        │
        ├─ Reorg check: block.parentHash vs IndexedBlock[N-1].blockHash
        │   └─ On mismatch → rollbackFrom(N - REORG_BUFFER) → replay
        │
        ├─ Sort logs: blockNumber ASC, logIndex ASC
        │
        ├─ For each log: processEventLog(log, market)
        │   ├─ CollateralDeposited / Withdrawn → updateUserPosition
        │   ├─ Borrowed / Repaid             → updateUserPosition
        │   ├─ Liquidated                    → storeLiquidation + updateUserPosition
        │   └─ GlobalBorrowIndexUpdated      → computeAndSaveMarketSnapshot
        │
        ├─ Upsert SyncState { lastProcessedBlock, lastProcessedHash }
        └─ Upsert IndexedBlock; prune blocks older than REORG_BUFFER
```

**On startup recovery** — reads `SyncState.lastProcessedBlock`, calls `processBlockRange(lastProcessed+1, safeHead)` to catch up any blocks missed during downtime, then resumes live polling. No events are silently skipped across restarts.

### Cron Jobs

| Schedule | Job |
|----------|-----|
| Every 1 min | Market snapshot for all active markets (TVL, utilization, rates, oracle, severity) |
| Every 10 min | Recompute health factors for recently-active user positions |
| Daily midnight | Analytics aggregation |

### Internal Endpoints

| Endpoint | Auth | Purpose |
|----------|------|---------|
| `POST /internal/resync` | `ADMIN_SECRET` | Replay from `lastProcessedBlock − REORG_BUFFER` to catch up |
| `POST /internal/recompute-markets` | `CRON_SECRET` | Force market snapshot recomputation (called by GitHub Actions) |
| `GET /health` | None | DB + RPC connectivity check + `lastIndexedBlock` |

---

## Frontend

The frontend (`frontend/`) is a Next.js 15 app deployed on Vercel. It reads all data from the backend REST API via `NEXT_PUBLIC_API_URL`.

### Pages

| Page | Route | Description |
|------|-------|-------------|
| **Landing** | `/` | Marketing page with protocol overview |
| **Dashboard** | `/dashboard` | Market table, protocol metrics, clickable market sidebar with interest rate curve graph and deposit/withdraw form |
| **Deposit** | `/deposit` | Full deposit/withdraw flow with market selector |
| **Monitoring** | `/monitoring` | Real-time charts — liquidity, utilization, borrow rates, oracle confidence |
| **Positions** | `/positions` | Per-user position tracking with health factors |
| **Liquidations** | `/liquidations` | Recent liquidation event feed |
| **Strategy** | `/strategy` | Coming soon |
| **Risk Engine** | `/risk-engine` | Coming soon |

### Key UI Components

| Component | Purpose |
|-----------|---------|
| **MarketUtilizationGraph** | Pure SVG Jump Rate curve — two-tone (green/amber at kink), interactive hover tooltip showing Borrow APR + Supply APY, compact mode for table rows |
| **DepositForm** | Approve + deposit / withdraw flow with loading spinner, sonner toast on confirmation, auto-reset after success |
| **TransactionStepper** | Visual approve → deposit step tracker |
| **VaultTable** | Clickable market rows — selecting a row opens the sidebar panel; active row highlighted with indigo border |
| **Monitoring charts** | Recharts time-series for all signal types |

### Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Next.js 15 (App Router) |
| Styling | Tailwind CSS |
| State | Zustand |
| Web3 | wagmi v2 + viem |
| Notifications | Sonner |
| Charts | Recharts |
| Deployment | Vercel |

---

## API Reference

All endpoints are served by the Express backend on port 4000. The frontend calls them via `NEXT_PUBLIC_API_URL`.

| Endpoint | Method | Description |
|----------|--------|-------------|
| `GET /markets` | GET | All markets with latest snapshot (TVL, utilization, rates, severity) |
| `GET /metrics?vault=<addr>` | GET | Current metrics for a specific market |
| `GET /history?signal=<type>&range=<range>&vault=<addr>` | GET | Time-series data. Signals: `liquidity`, `utilization`, `borrowRate`, `oracle`. Ranges: `24h`, `7d`, `30d`, `90d` |
| `GET /positions?user=<addr>` | GET | User positions across all markets (latest per market) |
| `GET /liquidations?limit=<n>` | GET | Recent liquidation events (default 20, max 100) |
| `GET /indexer` | GET | Indexer running status |
| `POST /indexer` | POST | Start/stop indexer `{"action": "start"\|"stop"}` |
| `GET /health` | GET | Service health: DB, RPC, last indexed block |
| `POST /internal/resync` | POST | Manual resync (requires `ADMIN_SECRET`) |
| `POST /internal/recompute-markets` | POST | Force recompute snapshots (requires `CRON_SECRET`) |

---

## Database Schema

Prisma models backed by Supabase PostgreSQL:

| Model | Purpose |
|-------|---------|
| **Market** | Static registry of isolated markets (vault address, market address, IRM, oracle, token metadata) |
| **MarketSnapshot** | Periodic market state (supply, borrows, rates, oracle confidence, severity scores). ~1 row per market per minute |
| **UserPositionSnapshot** | Per-user position state (collateral value, debt, health factor, borrowing power). Updated on each user event |
| **LiquidationEvent** | On-chain liquidation records (borrower, liquidator, amounts, tx hash, log index). Idempotent upsert. |
| **SyncState** | Indexer cursor — one row per chain. Stores `lastProcessedBlock` + `lastProcessedHash` for restart recovery |
| **IndexedBlock** | Rolling 20-block window of block hashes for reorg detection. Auto-pruned. |

---

## Installation

### Prerequisites

- [Git](https://git-scm.com/)
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 22+
- npm

### Smart Contracts

```bash
git clone https://github.com/Enricrypto/Isolated-Lending-Market.git
cd Isolated-Lending-Market

# Install Foundry dependencies
forge install

# Build contracts
forge build

# Run tests
forge test
```

### Backend Setup

```bash
cd backend

# Install dependencies
npm install

# Set up environment variables
cp .env.example .env
# Edit .env with your DATABASE_URL, RPC_URL, DEPLOYMENT_BLOCK, secrets

# Generate Prisma client
npx prisma generate

# Push schema to database (run once, or after schema changes)
npx prisma db push

# Start dev server
npx tsx src/app.ts

# Or build and run
npm run build && node dist/app.js
```

### Frontend Setup

```bash
cd frontend

# Install dependencies
npm install

# Set up environment variables
cp .env.example .env
# Edit .env — set NEXT_PUBLIC_API_URL to your backend URL

# Start dev server (reads data from backend)
npm run dev
```

### Project Structure

```
lending-platform-v2/
├── src/                              # Solidity contracts
│   ├── core/
│   │   ├── MarketV1.sol              # UUPS upgradeable lending market
│   │   ├── MarketStorageV1.sol       # Separated storage layout
│   │   ├── Vault.sol                 # ERC-4626 vault
│   │   ├── OracleRouter.sol          # Price feed aggregation
│   │   ├── InterestRateModel.sol     # Jump rate model
│   │   └── RiskEngine.sol            # On-chain risk assessment
│   ├── adapters/
│   │   ├── AaveV3Adapter.sol
│   │   └── CompoundV2Adapter.sol
│   ├── governance/
│   │   ├── GovernanceSetup.sol
│   │   └── RiskProposer.sol
│   ├── libraries/
│   │   ├── Events.sol
│   │   └── Errors.sol
│   └── Interfaces/
├── test/
│   ├── unit/
│   ├── integration/
│   └── governance/
├── script/
│   ├── DeployAll.s.sol
│   └── DeployMarkets.s.sol
│
├── backend/                          # Standalone Node.js/Express service
│   ├── prisma/
│   │   └── schema.prisma             # Database models (Market, Snapshot, SyncState, …)
│   ├── src/
│   │   ├── app.ts                    # Express entry point + /health
│   │   ├── indexer/
│   │   │   ├── block-processor.ts    # Deterministic getLogs loop + reorg handling
│   │   │   ├── listener.ts           # processEventLog — routes events to handlers
│   │   │   ├── snapshot.ts           # Market snapshot generator (multicall)
│   │   │   ├── position.ts           # User position tracker
│   │   │   ├── liquidation.ts        # Liquidation recorder (idempotent)
│   │   │   ├── events.ts             # MarketV1 event ABIs
│   │   │   └── index.ts              # startIndexer / stopIndexer
│   │   ├── routes/
│   │   │   ├── markets.ts            # GET /markets
│   │   │   ├── metrics.ts            # GET /metrics
│   │   │   ├── history.ts            # GET /history
│   │   │   ├── positions.ts          # GET /positions
│   │   │   ├── liquidations.ts       # GET /liquidations
│   │   │   ├── indexer.ts            # GET+POST /indexer
│   │   │   └── internal.ts           # POST /internal/resync, /recompute-markets
│   │   ├── jobs/
│   │   │   └── index.ts              # node-cron: snapshot, health factor, analytics
│   │   └── lib/
│   │       ├── db.ts                 # Prisma client
│   │       ├── rpc.ts                # viem client + CONFIRMATIONS, REORG_BUFFER constants
│   │       ├── contracts.ts          # Contract ABIs
│   │       ├── severity.ts           # Severity computation (0-3 scale)
│   │       └── logger.ts             # Pino structured logger
│   └── package.json
│
├── frontend/                         # Next.js 15 app
│   ├── src/
│   │   ├── app/
│   │   │   ├── (app)/
│   │   │   │   ├── dashboard/        # Market table + sidebar with IRM curve + DepositForm
│   │   │   │   ├── deposit/          # Full deposit/withdraw page
│   │   │   │   ├── monitoring/       # Liquidity, rates, utilization, oracle sub-pages
│   │   │   │   ├── positions/
│   │   │   │   ├── liquidations/
│   │   │   │   ├── strategy/         # Coming soon
│   │   │   │   └── risk-engine/      # Coming soon
│   │   │   └── (marketing)/          # Landing page
│   │   ├── components/
│   │   │   ├── MarketUtilizationGraph.tsx  # SVG Jump Rate curve
│   │   │   ├── DepositForm.tsx        # Approve + deposit/withdraw + toasts
│   │   │   ├── VaultTable.tsx         # Clickable market rows
│   │   │   └── TransactionStepper.tsx
│   │   ├── hooks/
│   │   │   ├── useVaults.ts           # Fetches /markets from backend
│   │   │   └── useMetrics.ts
│   │   ├── lib/
│   │   │   ├── irm.ts                 # Jump Rate Model JS mirror
│   │   │   ├── contracts.ts           # Contract ABIs (frontend copy)
│   │   │   └── vault-registry.ts      # Static market registry
│   │   ├── store/
│   │   │   └── useAppStore.ts         # Zustand (selectedVault, refreshKey)
│   │   └── types/
│   └── package.json
│
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

### Backend (Railway)

1. Create a new Railway project and link the repo
2. Set the root directory to `backend/`
3. Set environment variables (see `backend/.env.example`):
   - `DATABASE_URL` — Supabase connection string
   - `RPC_URL` — Sepolia RPC endpoint
   - `DEPLOYMENT_BLOCK` — Block number your contracts were deployed at
   - `ADMIN_SECRET`, `CRON_SECRET` — Internal endpoint secrets
4. Railway auto-deploys on push to `main`

```bash
# After first deploy: run DB migration
railway run npx prisma db push

# Seed the Market table with your deployed contract addresses
railway run npx tsx prisma/seed.ts
```

### Frontend (Vercel)

```bash
cd frontend
vercel --prod
```

Required Vercel environment variables:

| Variable | Description |
|----------|-------------|
| `NEXT_PUBLIC_API_URL` | Backend Railway URL (e.g. `https://your-backend.railway.app`) |
| `NEXT_PUBLIC_RPC_URL` | Sepolia RPC for on-chain reads in the browser |

---

## Usage Examples

### For Lenders

```solidity
// Approve and deposit USDC into vault
IERC20(usdc).approve(address(vault), 10_000e6);
uint256 shares = vault.deposit(10_000e6, msg.sender);

// Later: withdraw principal + earned interest
uint256 assets = vault.redeem(shares, msg.sender, msg.sender);
```

### For Borrowers

```solidity
// Deposit WETH collateral
IERC20(weth).approve(address(market), 2e18);
market.depositCollateral(address(weth), 2e18);

// Borrow USDC against collateral (up to 85% LTV)
market.borrow(3_000e6);

// Repay debt
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
- **TimelockController** with 2-day delay on all governance actions
- **Emergency Guardian** for instant borrow pause (deposits/withdrawals/repayments unaffected)
- **Storage Gaps** (49 slots) for safe future upgrades
- **Oracle staleness checks** prevent stale price exploitation
- **Decimal normalization** handles 6/8/18 decimal tokens safely
- **Health factor buffer** — 5% liquidation penalty creates a safety margin before bad debt
- **Bad debt isolation** — underwater positions tracked separately, do not contaminate healthy accounts

### Known Limitations

| Risk | Mitigation |
|------|-----------|
| Oracle failure | Multi-source routing, staleness checks, confidence scoring |
| Bank run | High utilization spikes rates, discouraging further borrowing |
| Flash crashes | 5% liquidation buffer, block-by-block liquidation |
| Strategy loss | Adapter integration behind "Coming Soon" gate |

---

## Configuration

### Market Parameters

```
LLTV                = 85%   — max loan-to-value ratio
Liquidation Penalty = 5%    — liquidator bonus on seized collateral
Protocol Fee        = 10%   — platform share of borrower interest
```

### Interest Rate Model

```
Base Rate   = 2%    — minimum rate at 0% utilization
Kink        = 80%   — optimal target utilization
Slope 1     = 4%    — gradual increase below kink
Slope 2     = 60%   — steep increase above kink
```

### Indexer

```
CONFIRMATIONS    = 12  — blocks to wait before processing (finality buffer)
REORG_BUFFER     = 20  — blocks to retain for reorg detection
DEPLOYMENT_BLOCK = ?   — first block to index from (set to contract deploy block)
```

---

## License

This project is licensed under the MIT License.

---

## Acknowledgments

- **OpenZeppelin** — Security libraries, UUPS proxy, TimelockController
- **Foundry** — Solidity development and testing framework
- **Chainlink** — Decentralized oracle network
- **Compound Finance** — Jump Rate Model inspiration
- **Aave** — Liquidation mechanism design patterns
- **Supabase** — Managed PostgreSQL
- **Railway** — Backend hosting
- **Vercel** — Frontend deployment
