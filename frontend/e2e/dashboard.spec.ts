import { test, expect } from "@playwright/test"
import { injectMockWallet, mockApiRoutes } from "./utils/mockWallet"

test.describe("Dashboard — Market Overview", () => {
  test.beforeEach(async ({ page }) => {
    await injectMockWallet(page)
    await mockApiRoutes(page)
    await page.goto("/dashboard")
  })

  test("renders Market Overview table", async ({ page }) => {
    await expect(page.getByText("Market Overview")).toBeVisible()
  })

  test("shows USDC market from backend data", async ({ page }) => {
    await expect(page.getByText("USDC").first()).toBeVisible()
    await expect(page.getByText("USDC Isolated Market").first()).toBeVisible()
  })

  test("shows utilization from backend", async ({ page }) => {
    // 0.65 utilization → 65.0%
    await expect(page.getByText("65.0%").first()).toBeVisible()
  })

  test("shows TVL from backend", async ({ page }) => {
    // totalSupply=8400000 USDC → $8,400,000
    await expect(page.getByText(/\$8,400,000/).first()).toBeVisible()
  })

  test("'View All' routes to monitoring page", async ({ page }) => {
    await page.getByRole("link", { name: /View All/i }).click()
    await expect(page).toHaveURL(/\/monitoring/)
  })

  test("'Manage' button routes to deposit page", async ({ page }) => {
    await page.getByRole("link", { name: /Manage/i }).click()
    await expect(page).toHaveURL(/\/deposit/)
  })

  test("shows Low Risk health status for severity 0", async ({ page }) => {
    await expect(page.getByText("Low Risk")).toBeVisible()
  })

  test("shows protocol stats in header", async ({ page }) => {
    // The dashboard page should show total TVL
    await expect(page.getByText(/TVL/i).first()).toBeVisible()
  })
})

test.describe("Dashboard — Wallet connection", () => {
  test("shows 'Not Connected' when wallet not injected", async ({ page }) => {
    await mockApiRoutes(page)
    await page.goto("/dashboard")
    await expect(page.getByText("Not Connected")).toBeVisible()
  })
})
