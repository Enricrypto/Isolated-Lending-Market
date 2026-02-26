# Multi-stage build for LendCore backend service
# Stage 1: Install production deps only
FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev

# Stage 2: Full build (includes devDeps for prisma generate + tsc)
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
# DATABASE_URL is required by prisma.config.ts at generate time but not used at runtime in this stage
ENV DATABASE_URL=postgresql://x:x@localhost:5432/x
RUN npx prisma generate && npm run build

# Stage 3: Lean production image
FROM node:20-alpine AS runner
WORKDIR /app

# Copy production node_modules
COPY --from=deps /app/node_modules ./node_modules

# Copy compiled output
COPY --from=builder /app/dist ./dist

# Copy generated Prisma client
COPY --from=builder /app/src/generated ./src/generated

# Copy prisma schema (needed for runtime introspection)
COPY --from=builder /app/prisma ./prisma

EXPOSE 4000

CMD ["node", "dist/app.js"]
