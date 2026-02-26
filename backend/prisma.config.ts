/**
 * Prisma 7 configuration
 * ----------------------
 * Configures the database connection for Prisma CLI commands
 * (db push, migrate, studio). Runtime queries use the PrismaPg
 * adapter in src/lib/db.ts — this file is CLI-only.
 *
 * env var used: DATABASE_URL (session-mode pooler, port 5432)
 */
import { defineConfig } from "prisma/config"

export default defineConfig({
  schema: "./prisma/schema.prisma",
  datasource: {
    url: process.env.DATABASE_URL,
  },
})
