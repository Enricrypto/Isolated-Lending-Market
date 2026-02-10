import { NextRequest, NextResponse } from "next/server"
import { startIndexer, stopIndexer, getIndexerStatus } from "@/lib/indexer"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

/** GET /api/indexer — Returns indexer status */
export async function GET() {
  return NextResponse.json(getIndexerStatus())
}

/** POST /api/indexer — Start or stop the indexer */
export async function POST(request: NextRequest) {
  try {
    const body = await request.json().catch(() => ({}))
    const action = (body as { action?: string }).action ?? "start"

    if (action === "start") {
      const result = await startIndexer()
      return NextResponse.json(result)
    }

    if (action === "stop") {
      const result = stopIndexer()
      return NextResponse.json(result)
    }

    return NextResponse.json({ error: `Unknown action: ${action}. Use "start" or "stop".` }, { status: 400 })
  } catch (error) {
    console.error("[api/indexer] Error:", error)
    return NextResponse.json(
      { error: "Indexer operation failed", details: error instanceof Error ? error.message : "Unknown" },
      { status: 500 }
    )
  }
}
