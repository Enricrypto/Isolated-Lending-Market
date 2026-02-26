import { test, expect } from "@playwright/test"
import { injectMockWallet, mockApiRoutes } from "./utils/mockWallet"

test.describe("Navigation", () => {
  test.beforeEach(async ({ page }) => {
    await injectMockWallet(page)
    await mockApiRoutes(page)
  })

  test("landing page loads with correct headline", async ({ page }) => {
    await page.goto("/")
    await expect(page.getByRole("heading", { name: /Isolated Lending/i })).toBeVisible()
    await expect(page.getByRole("link", { name: /Launch App/i }).first()).toBeVisible()
  })

  test("landing page has working Launch App button", async ({ page }) => {
    await page.goto("/")
    await page.getByRole("link", { name: /Launch App/i }).first().click()
    await expect(page).toHaveURL(/\/dashboard/)
  })

  test("sidebar shows core navigation items", async ({ page }) => {
    await page.goto("/dashboard")
    await expect(page.getByRole("link", { name: /Dashboard/i })).toBeVisible()
    await expect(page.getByRole("link", { name: /Monitoring/i })).toBeVisible()
    await expect(page.getByRole("link", { name: /Token Management/i })).toBeVisible()
  })

  test("sidebar shows testnet banner", async ({ page }) => {
    await page.goto("/dashboard")
    await expect(page.locator("text=Testnet Only")).toBeVisible()
    await expect(page.getByText("No real funds.", { exact: false })).toBeVisible()
  })

  test("admin links show 'Soon' badge", async ({ page }) => {
    await page.goto("/dashboard")
    await expect(page.getByText("Soon").first()).toBeVisible()
  })

  test("navigates to monitoring page", async ({ page }) => {
    await page.goto("/dashboard")
    await page.getByRole("link", { name: /Monitoring/i }).click()
    await expect(page).toHaveURL(/\/monitoring/)
  })

  test("navigates to deposit page", async ({ page }) => {
    await page.goto("/dashboard")
    await page.getByRole("link", { name: /Token Management/i }).click()
    await expect(page).toHaveURL(/\/deposit/)
  })
})
