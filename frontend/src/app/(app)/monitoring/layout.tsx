"use client";

import { Suspense } from "react";
import { VaultSelector } from "@/components/VaultSelector";
import { VAULT_REGISTRY } from "@/lib/vault-registry";
import { useSelectedVault } from "@/hooks/useSelectedVault";
import { useVaults } from "@/hooks/useVaults";
import type { SeverityLevel } from "@/types/metrics";

function MonitoringLayoutInner({ children }: { children: React.ReactNode }) {
  const { vaultAddress, setVault } = useSelectedVault();
  const { data } = useVaults();

  const severities = new Map<string, SeverityLevel>();
  if (data) {
    for (const v of data.vaults) {
      severities.set(v.vaultAddress, v.overallSeverity);
    }
  }

  return (
    <div>
      {VAULT_REGISTRY.length > 1 && (
        <div className="px-6 py-3 border-b border-midnight-700/50 flex items-center gap-4">
          <span className="text-xs text-slate-500 uppercase tracking-wider font-medium">
            Market
          </span>
          <VaultSelector
            vaults={VAULT_REGISTRY}
            selected={vaultAddress}
            onSelect={setVault}
            severities={severities}
          />
        </div>
      )}
      {children}
    </div>
  );
}

export default function MonitoringLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <Suspense fallback={null}>
      <MonitoringLayoutInner>{children}</MonitoringLayoutInner>
    </Suspense>
  );
}
