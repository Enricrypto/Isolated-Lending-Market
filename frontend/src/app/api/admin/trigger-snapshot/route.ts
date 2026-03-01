/**
 * Next.js proxy route for /admin/trigger-snapshot
 * -------------------------------------------------
 * Forwards POST to the Express backend.
 * Used as dev fallback when NEXT_PUBLIC_API_URL is not set.
 */

import { NextRequest, NextResponse } from "next/server"

function backendUrl() {
  const base = process.env.BACKEND_URL ?? process.env.NEXT_PUBLIC_API_URL ?? ""
  return base.replace(/\/$/, "")
}

export async function POST(req: NextRequest) {
  const base = backendUrl()
  if (!base) {
    return NextResponse.json(
      { error: "BACKEND_URL is not configured" },
      { status: 503 }
    )
  }

  const auth = req.headers.get("authorization") ?? ""
  const body = await req.text()

  const res = await fetch(`${base}/admin/trigger-snapshot`, {
    method:  "POST",
    headers: {
      Authorization:  auth,
      "Content-Type": "application/json",
    },
    body,
  })

  const data = await res.json()
  return NextResponse.json(data, { status: res.status })
}
