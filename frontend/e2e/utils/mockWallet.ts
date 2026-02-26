import type { Page } from "@playwright/test"

export const TEST_ADDRESS = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
export const SEPOLIA_CHAIN_ID = "0xaa36a7" // 11155111

/**
 * Injects a mock window.ethereum provider into the page.
 * Responds to MetaMask-style RPC calls so wagmi connects without a real wallet.
 */
export async function injectMockWallet(page: Page) {
  await page.addInitScript(
    ({ address, chainId }: { address: string; chainId: string }) => {
      const mockProvider = {
        isMetaMask: true,
        selectedAddress: address,
        chainId,
        networkVersion: "11155111",

        request: async ({ method }: { method: string }) => {
          switch (method) {
            case "eth_requestAccounts":
            case "eth_accounts":
              return [address]
            case "eth_chainId":
              return chainId
            case "net_version":
              return "11155111"
            case "wallet_switchEthereumChain":
              return null
            default:
              throw new Error(`Mock wallet: unhandled method ${method}`)
          }
        },

        on: () => {},
        removeListener: () => {},
        removeAllListeners: () => {},
      }

      // @ts-ignore
      window.ethereum = mockProvider
    },
    { address: TEST_ADDRESS, chainId: SEPOLIA_CHAIN_ID }
  )
}

/**
 * Mocks all backend API calls with fixture data.
 * Call before page.goto() to ensure intercepts are in place.
 */
export async function mockApiRoutes(page: Page) {
  const marketsFixture = require("../fixtures/markets.json")
  const metricsFixture = require("../fixtures/metrics.json")

  // Mock backend routes
  await page.route("**/markets", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(marketsFixture) })
  )
  await page.route("**/metrics**", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(metricsFixture) })
  )
  await page.route("**/history**", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ signal: "utilization", range: "24h", data: [] }) })
  )
  await page.route("**/positions**", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ positions: [] }) })
  )
  await page.route("**/liquidations**", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ liquidations: [] }) })
  )
  await page.route("**/health", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ status: "ok" }) })
  )

  // Mock Next.js API fallbacks
  await page.route("**/api/vaults", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(marketsFixture) })
  )
  await page.route("**/api/metrics**", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(metricsFixture) })
  )
  await page.route("**/api/history**", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ signal: "utilization", range: "24h", data: [] }) })
  )
  await page.route("**/api/positions**", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ positions: [] }) })
  )
  await page.route("**/api/liquidations**", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ liquidations: [] }) })
  )

  // Mock all Ethereum JSON-RPC calls (viem/wagmi readContract calls)
  await page.route("https://eth-sepolia.g.alchemy.com/**", (route) => {
    const body = route.request().postDataJSON()
    const method = body?.method ?? ""

    const responses: Record<string, unknown> = {
      eth_chainId: "0xaa36a7",
      eth_blockNumber: "0x1234567",
      eth_call: "0x0000000000000000000000000000000000000000000000000000000000000000",
      eth_getBalance: "0x0",
      eth_estimateGas: "0x5208",
    }

    const result = responses[method] ?? null
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ jsonrpc: "2.0", id: body?.id ?? 1, result }),
    })
  })
}
