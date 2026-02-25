"use client";

import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { sepolia } from "wagmi/chains";

export const config = getDefaultConfig({
  appName: "LendCore",
  projectId: process.env.NEXT_PUBLIC_WC_PROJECT_ID || "",
  chains: [sepolia],
  ssr: true,
});
