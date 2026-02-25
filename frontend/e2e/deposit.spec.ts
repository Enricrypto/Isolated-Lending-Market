import { test, expect } from "@playwright/test"
import { injectMockWallet, mockApiRoutes } from "./utils/mockWallet"

test.describe("Token Management — Deposit/Withdraw UI", () => {
  test.beforeEach(async ({ page }) => {
    await injectMockWallet(page)
    await mockApiRoutes(page)
    await page.goto("/deposit")
  })

  test("renders page with correct title", async ({ page }) => {
    await expect(page.getByRole("heading", { name: /Deposit & Withdraw/i })).toBeVisible()
  })

  test("shows market selector with 3 tokens", async ({ page }) => {
    await expect(page.getByRole("heading", { name: /Select Market/i })).toBeVisible()
    await expect(page.getByText("USDC").first()).toBeVisible()
    await expect(page.getByText("WETH").first()).toBeVisible()
    await expect(page.getByText("WBTC").first()).toBeVisible()
  })

  test("USDC market is selected by default", async ({ page }) => {
    // The panel header should show USDC Market
    await expect(page.getByText(/USDC Market/).first()).toBeVisible()
  })

  test("switching to WETH market updates the form header", async ({ page }) => {
    await page.getByText("WETH").first().click()
    await expect(page.getByText(/WETH Market/).first()).toBeVisible()
  })

  test("switching to WBTC market updates the form header", async ({ page }) => {
    await page.getByText("WBTC").first().click()
    await expect(page.getByText(/WBTC Market/).first()).toBeVisible()
  })

  test("shows 'How it works' steps", async ({ page }) => {
    await expect(page.getByText("1. Approve Token")).toBeVisible()
    await expect(page.getByText("2. Deposit")).toBeVisible()
    await expect(page.getByText("3. Earn Yield")).toBeVisible()
  })
})

test.describe("Token Management — Wallet connection", () => {
  test("shows connect wallet prompt when not connected", async ({ page }) => {
    await mockApiRoutes(page)
    await page.goto("/deposit")
    // Without wallet connected, DepositForm shows "Connect Your Wallet"
    await expect(page.getByText("Connect Your Wallet")).toBeVisible()
  })
})
