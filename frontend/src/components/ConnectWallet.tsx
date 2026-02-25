"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";

export function ConnectWallet() {
  return (
    <ConnectButton
      showBalance={false}
      chainStatus="none"
      accountStatus="address"
    />
  );
}
