import { test, expect } from "@playwright/test"
import { injectMockWallet, mockApiRoutes } from "./utils/mockWallet"

test.describe("Monitoring & Analytics", () => {
  test.beforeEach(async ({ page }) => {
    await injectMockWallet(page)
    await mockApiRoutes(page)
    await page.goto("/monitoring")
  })

  test("renders monitoring page", async ({ page }) => {
    await expect(page.getByText(/Monitoring|Analytics/i).first()).toBeVisible()
  })

  test("shows market selector", async ({ page }) => {
    // The monitoring page has a vault/market selector
    await expect(page.getByText("USDC").first()).toBeVisible()
  })

  test("shows severity/status indicators", async ({ page }) => {
    // Monitoring page should show severity levels
    await expect(
      page.getByText(/Normal|Elevated|Critical|Emergency|Severity/i).first()
    ).toBeVisible()
  })

  test("shows signal panels", async ({ page }) => {
    // Monitoring has Liquidity Depth, APR Convexity, Oracle signals
    await expect(
      page.getByText(/Liquidity|APR|Oracle|Utilization/i).first()
    ).toBeVisible()
  })
})

test.describe("Monitoring — Data display", () => {
  test.beforeEach(async ({ page }) => {
    await injectMockWallet(page)
    await mockApiRoutes(page)
    await page.goto("/monitoring")
  })

  test("shows utilization value from mocked metrics", async ({ page }) => {
    // Mock returns aprConvexity.utilization: 0.65 → rendered as 65% or 0.65
    await expect(page.getByText(/65|0\.65/).first()).toBeVisible()
  })

  test("shows oracle confidence from mocked metrics", async ({ page }) => {
    // Mock returns oracle.confidence: 99
    await expect(page.getByText(/99/).first()).toBeVisible()
  })
})
