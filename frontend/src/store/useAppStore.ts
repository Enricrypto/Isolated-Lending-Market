import { create } from "zustand";

type VaultId = "usdc" | "weth" | "wbtc" | null;

interface AppStore {
  // Selected vault for right panel
  selectedVault: VaultId;
  setSelectedVault: (vault: VaultId) => void;

  // Refresh trigger for data
  refreshKey: number;
  triggerRefresh: () => void;

  // UI state
  isSidebarCollapsed: boolean;
  toggleSidebar: () => void;

  // Mobile nav
  mobileMenuOpen: boolean;
  openMobileMenu: () => void;
  closeMobileMenu: () => void;
}

export const useAppStore = create<AppStore>((set) => ({
  // Vault selection
  selectedVault: "usdc", // Default to USDC vault
  setSelectedVault: (vault) => set({ selectedVault: vault }),

  // Refresh state
  refreshKey: 0,
  triggerRefresh: () => set((state) => ({ refreshKey: state.refreshKey + 1 })),

  // Sidebar state
  isSidebarCollapsed: false,
  toggleSidebar: () =>
    set((state) => ({ isSidebarCollapsed: !state.isSidebarCollapsed })),

  // Mobile nav
  mobileMenuOpen: false,
  openMobileMenu: () => set({ mobileMenuOpen: true }),
  closeMobileMenu: () => set({ mobileMenuOpen: false }),
}));
