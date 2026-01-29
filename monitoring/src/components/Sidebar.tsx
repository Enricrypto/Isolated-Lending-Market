"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  LayoutDashboard,
  Droplets,
  TrendingUp,
  Eye,
  Zap,
  Settings,
  FileText,
} from "lucide-react";

const riskNavigation = [
  { name: "Overview", href: "/", icon: LayoutDashboard },
  { name: "Liquidity Depth", href: "/liquidity", icon: Droplets },
  { name: "Rates & Convexity", href: "/rates", icon: TrendingUp },
  { name: "Oracle Health", href: "/oracle", icon: Eye },
  { name: "Utilization Velocity", href: "/utilization", icon: Zap },
];

const systemNavigation = [
  { name: "Settings", href: "/settings", icon: Settings },
  { name: "Logs", href: "/logs", icon: FileText },
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
          Risk Management
        </div>

        {riskNavigation.map((item) => {
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
            </Link>
          );
        })}

        <div className="px-3 mt-8 mb-3 text-[10px] font-bold text-indigo-400/80 uppercase tracking-[0.2em]">
          System
        </div>

        {systemNavigation.map((item) => {
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
            </Link>
          );
        })}
      </nav>

      {/* Footer */}
      <div className="p-4 border-t border-midnight-700/50 flex-shrink-0">
        <div className="flex items-center gap-3 p-2 rounded-lg bg-indigo-500/10 border border-indigo-500/20">
          <div className="w-9 h-9 rounded-md bg-gradient-to-br from-indigo-500 to-purple-600 flex items-center justify-center text-white font-bold text-xs shadow-lg shadow-indigo-500/20">
            A
          </div>
          <div className="flex flex-col">
            <span className="text-sm font-medium text-white">Admin</span>
            <span className="text-[10px] text-indigo-300/70">
              monitoring@lendcore.fi
            </span>
          </div>
        </div>
      </div>
    </aside>
  );
}
