"use client";

import { Icon } from "@iconify/react";

const TOKEN_ICONS: Record<string, string> = {
  // Tokens
  usdc: "cryptocurrency-color:usdc",
  weth: "cryptocurrency-color:eth",
  wbtc: "cryptocurrency-color:btc",
  eth: "cryptocurrency-color:eth",
  btc: "cryptocurrency-color:btc",
  // Protocols
  aave: "cryptocurrency-color:aave",
  "aave v3": "cryptocurrency-color:aave",
  lido: "cryptocurrency-color:ldo",
  compound: "cryptocurrency-color:comp",
  morpho: "token-branded:morpho",
};

interface TokenIconProps {
  symbol: string;
  size?: number;
  className?: string;
}

export function TokenIcon({ symbol, size = 24, className }: TokenIconProps) {
  const iconName = TOKEN_ICONS[symbol.toLowerCase()];

  if (!iconName) {
    // Fallback: first letter in a circle
    return (
      <span
        className={`inline-flex items-center justify-center font-bold text-slate-400 ${className ?? ""}`}
        style={{ width: size, height: size, fontSize: size * 0.45 }}
      >
        {symbol.charAt(0)}
      </span>
    );
  }

  return (
    <Icon
      icon={iconName}
      width={size}
      height={size}
      className={className}
    />
  );
}
