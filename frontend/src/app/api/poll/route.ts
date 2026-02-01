import { NextRequest, NextResponse } from "next/server"
import { pollAndStore } from "@/lib/agents"
import { cleanupOldSnapshots } from "@/lib/db"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"
export const maxDuration = 60 // Allow up to 60 seconds for RPC calls

// Secret key for cron job authentication (optional)
const CRON_SECRET = process.env.CRON_SECRET

export async function POST(request: NextRequest) {
  try {
    // Optional: Verify cron secret if configured
    if (CRON_SECRET && process.env.NODE_ENV !== "development") {
      const authHeader = request.headers.get("authorization")
      if (authHeader !== `Bearer ${CRON_SECRET}`) {
        return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
      }
    }

    // Run the poll for all registered vaults
    const snapshots = await pollAndStore()

    if (!snapshots) {
      return NextResponse.json({
        skipped: true,
        reason: "Poll already in flight"
      })
    }

    // Cleanup old snapshots (keep last 90 days)
    const deletedCount = await cleanupOldSnapshots()

    return NextResponse.json({
      success: true,
      vaultsPolled: snapshots.length,
      snapshots: snapshots.map((s) => ({
        id: s.id,
        vaultAddress: s.vaultAddress,
        timestamp: s.timestamp.toISOString(),
        overallSeverity: s.overallSeverity,
      })),
      deletedOldSnapshots: deletedCount
    })
  } catch (error) {
    console.error("Poll error:", error)
    return NextResponse.json(
      {
        error: "Failed to poll metrics",
        details: error instanceof Error ? error.message : "Unknown error"
      },
      { status: 500 }
    )
  }
}

// Also allow GET for manual testing in browser
export async function GET(request: NextRequest) {
  // In development, allow GET requests for easy testing
  if (process.env.NODE_ENV === "development") {
    return POST(request)
  }

  return NextResponse.json(
    { error: "Use POST method for polling" },
    { status: 405 }
  )
}
