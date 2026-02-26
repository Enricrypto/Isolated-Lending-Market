"use client"

import { Icon } from "@iconify/react"

// Mapping of token/protocol symbols to icon names
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
  morpho: "token-branded:morpho"
}

// Semantic size options
type TokenIconSize = "sm" | "md" | "lg"

interface TokenIconProps {
  symbol: string
  size?: TokenIconSize
  className?: string
}

// Map semantic sizes to pixels
const SIZE_MAP: Record<TokenIconSize, number> = {
  sm: 20,
  md: 28,
  lg: 36
}

export function TokenIcon({ symbol, size = "md", className }: TokenIconProps) {
  const iconName = TOKEN_ICONS[symbol.toLowerCase()]
  const pixelSize = SIZE_MAP[size] // Always a number

  if (!iconName) {
    // Fallback: first letter in a circle
    return (
      <span
        className={`inline-flex items-center justify-center font-bold text-slate-400 ${className ?? ""}`}
        style={{
          width: pixelSize,
          height: pixelSize,
          fontSize: pixelSize * 0.45,
          borderRadius: "50%",
          backgroundColor: "rgba(100,100,100,0.1)" // optional subtle background
        }}
      >
        {symbol.charAt(0).toUpperCase()}
      </span>
    )
  }

  return (
    <Icon
      icon={iconName}
      width={pixelSize}
      height={pixelSize}
      className={className}
    />
  )
}
