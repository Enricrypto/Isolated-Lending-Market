// Sepolia Testnet Contract Addresses
// Deployed via DeployAll.s.sol

export const SEPOLIA_ADDRESSES = {
  // Core Protocol Contracts
  market: "0xC223C0634c6312Cb3Bf23e847f1C21Ae9ee9E907" as const,
  marketImplementation: "0xE28e6ac00d12Dd34c81E608299bFDdd53efDA2c8" as const,
  vault: "0xE5543F72AF9411936497Dc7816eB4131bB705D3B" as const,
  oracleRouter: "0xaA6B38118a2581fe6659aFEA79cBF3829b848bD7" as const,
  irm: "0x9997ACfd06004a2073B46A974258a9EC1066D7E0" as const,
  strategy: "0xB6c036875b7c36b2863FC40F61f019Df0b57CCBD" as const,
  timelock: "0xF36B006869bF22c11B1746a7207A250f2ab0D838" as const,

  // Test Tokens (Sepolia)
  usdc: "0x4d3922e731023cd5fba64f495e547D5f1B931128" as const,
  weth: "0x8d952c27aC46B1A0360144c6094Ea6159a991A95" as const,
  wbtc: "0x662CAA602Ec32c9a5c67f971208DAeaBd255AB6D" as const,

  // Chainlink Price Feeds (Sepolia)
  usdcFeed: "0xBF13bB9B959F6a7178252E7F1E73C0c36494bf22" as const,
  wethFeed: "0x83Cc67c3C80A9335D4a1478E190B7735c75AdFa9" as const,
  wbtcFeed: "0x333f90Ae64850EDa4B2C7EF7CA05D1D118fb4b7F" as const,

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
