# Lending Platform Monitoring Dashboard

Real-time monitoring dashboard for the lending protocol. Tracks key risk signals and provides severity-based alerting per the [MONITORING.md](../docs/MONITORING.md) specification.

## Monitored Signals

| Signal | Description | Severity Levels |
|--------|-------------|-----------------|
| **Liquidity Depth** | Available liquidity vs total borrows | 0-2 |
| **APR Convexity** | Distance to interest rate kink | 0-3 |
| **Oracle Deviations** | Price confidence and staleness | 0-3 |
| **Utilization Velocity** | Rate of change per hour | 0-3 |

## Tech Stack

- **Frontend**: Next.js 14 (App Router) + React + TypeScript
- **Styling**: Tailwind CSS
- **Charts**: Recharts
- **Database**: PostgreSQL + Prisma ORM
- **RPC Client**: viem

## Getting Started

### Prerequisites

- Node.js 18+
- PostgreSQL database
- RPC endpoint (Alchemy, Infura, etc.)

### Installation

1. Install dependencies:
   ```bash
   cd monitoring
   npm install
   ```

2. Copy environment variables:
   ```bash
   cp .env.example .env
   ```

3. Edit `.env` with your values:
   - `DATABASE_URL`: PostgreSQL connection string
   - `RPC_URL`: Ethereum RPC endpoint
   - Contract addresses from deployment

4. Set up the database:
   ```bash
   npm run db:push
   ```

5. Start the development server:
   ```bash
   npm run dev
   ```

6. Open [http://localhost:3000](http://localhost:3000)

## Polling Data

The dashboard needs to poll on-chain data periodically. You can trigger a poll:

### Manual Poll (Development)
Visit `http://localhost:3000/api/poll` in your browser (GET requests allowed in development)

### Production Polling
Set up a cron job to POST to `/api/poll` every 5 minutes:

```bash
# Example with curl
curl -X POST https://your-domain.com/api/poll \
  -H "Authorization: Bearer YOUR_CRON_SECRET"
```

For Vercel deployments, use [Vercel Cron Jobs](https://vercel.com/docs/cron-jobs).

## API Routes

| Route | Method | Description |
|-------|--------|-------------|
| `/api/metrics` | GET | Current metrics snapshot |
| `/api/history?signal=<signal>&range=<range>` | GET | Historical data for charts |
| `/api/poll` | POST | Trigger a new poll |

### Query Parameters

- `signal`: `liquidity`, `utilization`, `borrowRate`, `oracle`, `velocity`
- `range`: `24h`, `7d`, `30d`

## Project Structure

```
monitoring/
├── src/
│   ├── app/                    # Next.js pages and API routes
│   │   ├── api/                # API endpoints
│   │   ├── liquidity/          # Liquidity signal page
│   │   ├── rates/              # Interest rates page
│   │   ├── oracle/             # Oracle status page
│   │   ├── utilization/        # Velocity page
│   │   ├── page.tsx            # Dashboard home
│   │   └── layout.tsx          # Root layout
│   ├── components/             # React components
│   ├── lib/                    # Core logic
│   │   ├── contracts.ts        # Contract ABIs
│   │   ├── rpc.ts              # viem client
│   │   ├── db.ts               # Prisma client
│   │   ├── polling.ts          # Polling service
│   │   └── severity.ts         # Severity calculations
│   └── types/                  # TypeScript types
├── prisma/
│   └── schema.prisma           # Database schema
└── package.json
```

## Severity Levels

| Level | Label | Color | Action |
|-------|-------|-------|--------|
| 0 | Normal | Green | Dashboard only |
| 1 | Elevated | Yellow | Monitor closely |
| 2 | Critical | Orange | Review required |
| 3 | Emergency | Red | Immediate attention |

## Data Retention

- Snapshots are stored in PostgreSQL
- Automatic cleanup keeps last 30 days
- Cleanup runs after each poll

## Development

```bash
# Run development server
npm run dev

# Generate Prisma client after schema changes
npm run db:generate

# Push schema changes to database
npm run db:push

# Open Prisma Studio (database GUI)
npm run db:studio

# Build for production
npm run build

# Run production server
npm start
```

## License

MIT
