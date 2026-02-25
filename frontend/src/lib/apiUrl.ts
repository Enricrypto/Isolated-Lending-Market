/**
 * API base URL helper.
 * - Dev (NEXT_PUBLIC_API_URL not set): returns "" — relative URLs hit Next.js routes
 * - Prod (NEXT_PUBLIC_API_URL set): returns the backend URL, e.g. "https://api.lendcore.xyz"
 */
export const apiBase = (): string =>
  (process.env.NEXT_PUBLIC_API_URL ?? "").replace(/\/$/, "")
