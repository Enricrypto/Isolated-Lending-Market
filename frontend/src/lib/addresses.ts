// Sepolia Testnet Contract Addresses
// Deployed via DeployAll.s.sol

export const SEPOLIA_ADDRESSES = {
  // Core Protocol Contracts (Deployed Jan 30, 2026 - Real Chainlink Feeds)
  market: "0x12f8DA89619C40553d9eA50aAce593cEb2f3eFcE" as const,
  marketImplementation: "0x217547Af931896123Df66354Ce285C13bCD379E5" as const,
  vault: "0xE8323c3d293f81C71232023367Bada21137C055E" as const,
  oracle: "0x02dC7cA9865cDbE9D2930A9D50A79fe31BB4377E" as const,
  oracleRouter: "0xf0a440147AAC2FF4349ca623f8bf9BD96EA43843" as const,
  irm: "0x7Eca31bB8e6C9369b34cacf2dF32E815EbdcAdB2" as const,
  strategy: "0x7FC70540Ab332e9Fa74E6808352df88Ffd2Bfe36" as const,
  timelock: "0xE97D8FceEA76Bf5855F33e4aede175EEf79546DF" as const,
  riskEngine: "0x4866A7D31Db0F0eD1bE9e14D8d1E64D9F408359a" as const,
  emergencyGuardian: "0xd6DAe9Bb82f3Aa04584E54AD63146cbB7B0aac94" as const,
  riskProposer: "0x6c6d74e823F7072955fDdf7F53d5425D82fe6075" as const,

  // Mock Tokens (Sepolia)
  usdc: "0xa23575D09B55c709590F7f5507b246043A8cF49b" as const,
  weth: "0x655Af45748C1116B95339d189B1556c92d73ff77" as const,
  wbtc: "0x3bCFE4F6f3b11c8dB62f8302dc53f5CCdb51F9c3" as const,

  // Chainlink Price Feeds (Real Sepolia Feeds)
  usdcFeed: "0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E" as const,
  wethFeed: "0x694AA1769357215DE4FAC081bf1f309aDC325306" as const,
  wbtcFeed: "0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43" as const,

  // Protocol Addresses
  treasury: "0xd0d211ccef07598946bb0df5ecee0bf75caf3ecc" as const,
  badDebt: "0xd0d211ccef07598946bb0df5ecee0bf75caf3ecc" as const,
} as const;

// Token Metadata
export const TOKENS = {
  USDC: {
    address: SEPOLIA_ADDRESSES.usdc,
    symbol: "USDC",
    name: "USD Coin",
    decimals: 6,
    icon: "$",
    color: "#2775CA",
  },
  WETH: {
    address: SEPOLIA_ADDRESSES.weth,
    symbol: "WETH",
    name: "Wrapped Ether",
    decimals: 18,
    icon: "Ξ",
    color: "#627EEA",
  },
  WBTC: {
    address: SEPOLIA_ADDRESSES.wbtc,
    symbol: "WBTC",
    name: "Wrapped Bitcoin",
    decimals: 8,
    icon: "₿",
    color: "#F7931A",
  },
} as const;

// Helper to get token by address
export function getTokenByAddress(address: string) {
  const normalizedAddress = address.toLowerCase();
  return Object.values(TOKENS).find(
    (token) => token.address.toLowerCase() === normalizedAddress
  );
}
