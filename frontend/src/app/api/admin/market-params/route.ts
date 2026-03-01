/**
 * Next.js proxy routes for /admin/market-params
 * ------------------------------------------------
 * Forwards GET and POST to the Express backend.
 * Used as dev fallback when NEXT_PUBLIC_API_URL is not set.
 *
 * Server-side env var: BACKEND_URL (e.g. http://localhost:4000)
 * Falls back to NEXT_PUBLIC_API_URL if BACKEND_URL is absent.
 */

import { NextRequest, NextResponse } from "next/server"

function backendUrl() {
  const base = process.env.BACKEND_URL ?? process.env.NEXT_PUBLIC_API_URL ?? ""
  return base.replace(/\/$/, "")
}

export async function GET(req: NextRequest) {
  const base = backendUrl()
  if (!base) {
    return NextResponse.json(
      { error: "BACKEND_URL is not configured" },
      { status: 503 }
    )
  }

  const auth = req.headers.get("authorization") ?? ""
  const res = await fetch(`${base}/admin/market-params`, {
    headers: { Authorization: auth },
  })

  const data = await res.json()
  return NextResponse.json(data, { status: res.status })
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

  const res = await fetch(`${base}/admin/market-params`, {
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
