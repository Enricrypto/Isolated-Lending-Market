import { NextRequest, NextResponse } from "next/server";
import { pollAndStore } from "@/lib/polling";
import { cleanupOldSnapshots } from "@/lib/db";

export const dynamic = "force-dynamic";
export const maxDuration = 60; // Allow up to 60 seconds for RPC calls

// Secret key for cron job authentication (optional)
const CRON_SECRET = process.env.CRON_SECRET;

export async function POST(request: NextRequest) {
  try {
    // Optional: Verify cron secret if configured
    if (CRON_SECRET) {
      const authHeader = request.headers.get("authorization");
      if (authHeader !== `Bearer ${CRON_SECRET}`) {
        return NextResponse.json(
          { error: "Unauthorized" },
          { status: 401 }
        );
      }
    }

    // Run the poll
    const snapshot = await pollAndStore();

    // Cleanup old snapshots (keep last 30 days)
    const deletedCount = await cleanupOldSnapshots();

    return NextResponse.json({
      success: true,
      snapshotId: snapshot.id,
      timestamp: snapshot.timestamp.toISOString(),
      overallSeverity: snapshot.overallSeverity,
      deletedOldSnapshots: deletedCount,
    });
  } catch (error) {
    console.error("Poll error:", error);
    return NextResponse.json(
      {
        error: "Failed to poll metrics",
        details: error instanceof Error ? error.message : "Unknown error"
      },
      { status: 500 }
    );
  }
}

// Also allow GET for manual testing in browser
export async function GET(request: NextRequest) {
  // In development, allow GET requests for easy testing
  if (process.env.NODE_ENV === "development") {
    return POST(request);
  }

  return NextResponse.json(
    { error: "Use POST method for polling" },
    { status: 405 }
  );
}
