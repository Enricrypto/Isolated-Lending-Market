"use client"

import { useSearchParams, useRouter, usePathname } from "next/navigation"
import { DEFAULT_VAULT, getVaultConfig } from "@/lib/vault-registry"

export function useSelectedVault() {
  const searchParams = useSearchParams()
  const router = useRouter()
  const pathname = usePathname()

  const vaultAddress = searchParams.get("vault") || DEFAULT_VAULT.vaultAddress
  const config = getVaultConfig(vaultAddress) || DEFAULT_VAULT

  const setVault = (address: string) => {
    const params = new URLSearchParams(searchParams.toString())
    params.set("vault", address)
    router.push(`${pathname}?${params.toString()}`)
  }

  return { vaultAddress, config, setVault }
}
