"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  LayoutDashboard,
  TrendingUp,
  Wallet,
  Settings,
  ShieldAlert,
  ChevronDown,
  FlaskConical,
  Banknote,
} from "lucide-react";
import { ConnectButton } from "@rainbow-me/rainbowkit";

const coreNavigation = [
  { name: "Dashboard", href: "/dashboard", icon: LayoutDashboard },
  { name: "Monitoring & Analytics", href: "/monitoring", icon: TrendingUp },
  { name: "Token Management", href: "/deposit", icon: Wallet },
  { name: "Borrow & Repay", href: "/borrow", icon: Banknote },
];

const adminNavigation = [
  { name: "Strategy", href: "/strategy", icon: Settings, comingSoon: true },
  { name: "Risk Engine", href: "/risk-engine", icon: ShieldAlert, comingSoon: true },
];

export function Sidebar() {
  const pathname = usePathname();

  return (
    <aside className="fixed top-0 left-0 w-72 h-screen border-r border-midnight-700/50 flex-col bg-midnight-950/80 backdrop-blur-xl hidden md:flex z-50">
      {/* Logo */}
      <div className="h-20 flex items-center px-6 border-b border-midnight-700/50 flex-shrink-0">
        <div className="flex items-center gap-3">
          {/* Custom LendCore Logo - 4 overlapping circles */}
          <div className="flex items-center -space-x-2.5">
            <div className="w-5 h-5 rounded-full bg-gradient-to-br from-orange-400 to-red-500 shadow-[0_0_10px_rgba(239,68,68,0.4)] z-10 border border-white/10" />
            <div className="w-5 h-5 rounded-full bg-gradient-to-br from-amber-300 to-yellow-500 shadow-[0_0_10px_rgba(245,158,11,0.4)] z-20 mix-blend-screen border border-white/10" />
            <div className="w-5 h-5 rounded-full bg-gradient-to-br from-cyan-300 to-teal-400 shadow-[0_0_10px_rgba(34,211,238,0.4)] z-30 mix-blend-screen border border-white/10" />
            <div className="w-5 h-5 rounded-full bg-gradient-to-br from-blue-400 to-indigo-500 shadow-[0_0_10px_rgba(59,130,246,0.4)] z-40 mix-blend-screen border border-white/10" />
          </div>
          <span className="font-brand font-bold text-2xl text-white tracking-tight">
            LendCore
          </span>
        </div>
      </div>

      {/* Navigation */}
      <nav className="flex-1 px-4 py-6 space-y-1.5 overflow-y-auto">
        <div className="px-3 mb-3 text-[10px] font-bold text-indigo-400/80 uppercase tracking-[0.2em]">
          Core Modules
        </div>

        {coreNavigation.map((item) => {
          const isActive = pathname === item.href ||
            (item.href === "/monitoring" && pathname.startsWith("/monitoring")) ||
            (item.href === "/dashboard" && pathname === "/dashboard");
          const Icon = item.icon;

          return (
            <Link
              key={item.name}
              href={item.href}
              className={`flex items-center gap-3 px-3 py-2.5 text-sm font-medium rounded-lg transition-all group ${
                isActive
                  ? "nav-item-active"
                  : "text-slate-400 hover:text-white hover:bg-white/5"
              }`}
            >
              <Icon
                className={`w-4 h-4 ${
                  isActive
                    ? "text-indigo-400"
                    : "text-slate-500 group-hover:text-indigo-300"
                } transition-colors`}
              />
              {item.name}
            </Link>
          );
        })}

        <div className="px-3 mt-8 mb-3 text-[10px] font-bold text-indigo-400/80 uppercase tracking-[0.2em]">
          Admin
        </div>

        {adminNavigation.map((item) => {
          const isActive = pathname === item.href;
          const Icon = item.icon;

          return (
            <Link
              key={item.name}
              href={item.href}
              className={`flex items-center gap-3 px-3 py-2.5 text-sm font-medium rounded-lg transition-all group ${
                isActive
                  ? "nav-item-active"
                  : "text-slate-400 hover:text-white hover:bg-white/5"
              }`}
            >
              <Icon
                className={`w-4 h-4 ${
                  isActive
                    ? "text-indigo-400"
                    : "text-slate-500 group-hover:text-indigo-300"
                } transition-colors`}
              />
              {item.name}
              {item.comingSoon && (
                <span className="ml-auto text-[9px] px-1.5 py-0.5 bg-slate-700/50 text-slate-500 rounded border border-slate-600/30 uppercase tracking-wider font-bold">
                  Soon
                </span>
              )}
            </Link>
          );
        })}
      </nav>

      {/* Testnet Banner */}
      <div className="mx-4 mb-3 px-3 py-2.5 rounded-lg bg-amber-500/5 border border-amber-500/20 flex items-start gap-2.5 flex-shrink-0">
        <FlaskConical className="w-3.5 h-3.5 text-amber-400 mt-0.5 flex-shrink-0" />
        <div>
          <p className="text-[10px] font-bold text-amber-400 uppercase tracking-wider">Testnet Only</p>
          <p className="text-[10px] text-slate-500 mt-0.5 leading-relaxed">
            This protocol runs on Sepolia. No real funds.
          </p>
        </div>
      </div>

      {/* Wallet — RainbowKit Custom Button */}
      <div className="p-4 border-t border-midnight-700/50 flex-shrink-0">
        <ConnectButton.Custom>
          {({ account, chain, openAccountModal, openConnectModal, mounted }) => {
            const connected = mounted && account && chain;
            return (
              <button
                onClick={connected ? openAccountModal : openConnectModal}
                className="w-full flex items-center justify-between p-2 rounded-lg bg-midnight-900 border border-midnight-700/50 hover:border-indigo-500/30 transition-all group"
              >
                <div className="flex items-center gap-3">
                  <div className="w-6 h-6 rounded-full bg-indigo-500/20 text-indigo-400 flex items-center justify-center overflow-hidden">
                    {connected && account.ensAvatar ? (
                      <img src={account.ensAvatar} alt="avatar" className="w-full h-full object-cover rounded-full" />
                    ) : (
                      <Wallet className="w-3.5 h-3.5" />
                    )}
                  </div>
                  <div className="flex flex-col items-start">
                    <span className="text-xs font-medium text-slate-200">
                      {connected ? account.displayName : "Not Connected"}
                    </span>
                    <span className="text-[10px] text-emerald-500 flex items-center gap-1">
                      <span className="w-1.5 h-1.5 rounded-full bg-emerald-500" />
                      Sepolia
                    </span>
                  </div>
                </div>
                <ChevronDown className="w-4 h-4 text-slate-500 group-hover:text-slate-300" />
              </button>
            );
          }}
        </ConnectButton.Custom>
      </div>
    </aside>
  );
}
