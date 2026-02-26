/**
 * Prisma 7 configuration
 * ----------------------
 * Configures the database connection for Prisma CLI commands
 * (db push, migrate, studio). Runtime queries use the PrismaPg
 * adapter in src/lib/db.ts — this file is CLI-only.
 *
 * For migrations, pass the direct/session-pooler URL:
 *   DATABASE_URL=$DIRECT_URL npx prisma db push
 *
 * For Railway:
 *   railway run --env DATABASE_URL=$DIRECT_URL npx prisma db push
 */
import path from "node:path"
import { defineConfig, env } from "prisma/config"

export default defineConfig({
  schema: path.join(__dirname, "prisma", "schema.prisma"),
  datasource: {
    url: env("DATABASE_URL"),
  },
})
