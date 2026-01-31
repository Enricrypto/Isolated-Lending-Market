"use client";

import { useAccount, useConnect, useDisconnect } from "wagmi";
import { Wallet, LogOut, ChevronDown } from "lucide-react";
import { useState } from "react";

export function ConnectWallet() {
  const { address, isConnected, connector } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const [showDropdown, setShowDropdown] = useState(false);

  // Format address for display
  const formatAddress = (addr: string) => {
    return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
  };

  if (isConnected && address) {
    return (
      <div className="relative">
        <button
          onClick={() => setShowDropdown(!showDropdown)}
          className="flex items-center gap-2 px-3 py-1.5 bg-indigo-500/10 border border-indigo-500/20 rounded-lg hover:bg-indigo-500/20 transition-all"
        >
          <div className="w-5 h-5 rounded-full bg-gradient-to-br from-indigo-400 to-purple-500" />
          <span className="text-xs font-medium text-indigo-300">
            {formatAddress(address)}
          </span>
          <ChevronDown className="w-3.5 h-3.5 text-indigo-400" />
        </button>

        {/* Dropdown */}
        {showDropdown && (
          <>
            {/* Backdrop */}
            <div
              className="fixed inset-0 z-40"
              onClick={() => setShowDropdown(false)}
            />

            <div className="absolute right-0 mt-2 w-48 bg-midnight-900 border border-midnight-700/50 rounded-lg shadow-xl z-50 overflow-hidden">
              <div className="p-3 border-b border-midnight-700/50">
                <div className="text-xs text-slate-500 mb-1">Connected with</div>
                <div className="text-sm font-medium text-slate-200">
                  {connector?.name || "Wallet"}
                </div>
              </div>

              <div className="p-2">
                <button
                  onClick={() => {
                    disconnect();
                    setShowDropdown(false);
                  }}
                  className="w-full flex items-center gap-2 px-3 py-2 text-sm text-red-400 hover:bg-red-500/10 rounded-md transition-colors"
                >
                  <LogOut className="w-4 h-4" />
                  Disconnect
                </button>
              </div>
            </div>
          </>
        )}
      </div>
    );
  }

  return (
    <div className="relative">
      <button
        onClick={() => setShowDropdown(!showDropdown)}
        disabled={isPending}
        className="flex items-center gap-2 px-4 py-1.5 bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-medium rounded-lg transition-all disabled:opacity-50"
      >
        <Wallet className="w-4 h-4" />
        {isPending ? "Connecting..." : "Connect Wallet"}
      </button>

      {/* Connector Selection Dropdown */}
      {showDropdown && !isPending && (
        <>
          {/* Backdrop */}
          <div
            className="fixed inset-0 z-40"
            onClick={() => setShowDropdown(false)}
          />

          <div className="absolute right-0 mt-2 w-56 bg-midnight-900 border border-midnight-700/50 rounded-lg shadow-xl z-50 overflow-hidden">
            <div className="p-3 border-b border-midnight-700/50">
              <div className="text-sm font-medium text-slate-200">
                Connect a Wallet
              </div>
              <div className="text-xs text-slate-500 mt-1">
                Select a wallet provider
              </div>
            </div>

            <div className="p-2">
              {connectors.map((connector) => (
                <button
                  key={connector.uid}
                  onClick={() => {
                    connect({ connector });
                    setShowDropdown(false);
                  }}
                  className="w-full flex items-center gap-3 px-3 py-2.5 text-sm text-slate-300 hover:bg-midnight-800 rounded-md transition-colors"
                >
                  <div className="w-8 h-8 rounded-lg bg-midnight-800 flex items-center justify-center">
                    {connector.name === "MetaMask" && (
                      <span className="text-lg">🦊</span>
                    )}
                    {connector.name === "WalletConnect" && (
                      <span className="text-lg">🔗</span>
                    )}
                    {connector.name === "Injected" && (
                      <Wallet className="w-4 h-4 text-slate-400" />
                    )}
                  </div>
                  <span className="font-medium">{connector.name}</span>
                </button>
              ))}
            </div>
          </div>
        </>
      )}
    </div>
  );
}
