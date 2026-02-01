import type { VaultConfig } from "@/types/metrics";

export const VAULT_REGISTRY: VaultConfig[] = [
  {
    vaultAddress: "0xE8323c3d293f81C71232023367Bada21137C055E",
    marketAddress: "0x12f8DA89619C40553d9eA50aAce593cEb2f3eFcE",
    irmAddress: "0x7Eca31bB8e6C9369b34cacf2dF32E815EbdcAdB2",
    oracleRouterAddress: "0xf0a440147AAC2FF4349ca623f8bf9BD96EA43843",
    strategyAddress: "0x7FC70540Ab332e9Fa74E6808352df88Ffd2Bfe36",
    loanAsset: "0xa23575D09B55c709590F7f5507b246043A8cF49b",
    label: "USDC Vault",
  },
];

export const DEFAULT_VAULT = VAULT_REGISTRY[0];

export function getVaultConfig(vaultAddress: string): VaultConfig | undefined {
  return VAULT_REGISTRY.find(
    (v) => v.vaultAddress.toLowerCase() === vaultAddress.toLowerCase()
  );
}
