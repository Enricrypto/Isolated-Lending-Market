"use client";

import { createConfig, http } from "wagmi";
import { sepolia } from "wagmi/chains";
import { injected, walletConnect } from "wagmi/connectors";

// WalletConnect project ID - get one at https://cloud.walletconnect.com
const projectId = process.env.NEXT_PUBLIC_WC_PROJECT_ID || "demo-project-id";

export const config = createConfig({
  chains: [sepolia],
  connectors: [
    injected(),
    walletConnect({
      projectId,
      metadata: {
        name: "LendCore Protocol",
        description: "Lending Protocol Dashboard",
        url: "https://lendcore.fi",
        icons: ["https://lendcore.fi/icon.png"],
      },
    }),
  ],
  transports: {
    [sepolia.id]: http(
      process.env.NEXT_PUBLIC_RPC_URL ||
        "https://eth-sepolia.g.alchemy.com/v2/demo"
    ),
  },
  ssr: true,
});
