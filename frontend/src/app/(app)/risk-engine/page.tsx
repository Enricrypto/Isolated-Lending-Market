"use client";

import { Header } from "@/components/Header";
import { ShieldAlert } from "lucide-react";
import Link from "next/link";

export default function RiskEnginePage() {
  return (
    <>
      <Header title="Risk Engine" breadcrumb="Risk Engine" />

      <div className="p-6 sm:p-8 lg:p-10 flex items-center justify-center min-h-[60vh]">
        <div className="glass-panel rounded-2xl p-12 max-w-lg text-center relative overflow-hidden">
          <div className="absolute -top-20 -right-20 w-64 h-64 bg-indigo-600/10 rounded-full blur-[80px] pointer-events-none" />

          <div className="w-16 h-16 rounded-2xl bg-indigo-500/10 border border-indigo-500/20 flex items-center justify-center mx-auto mb-6">
            <ShieldAlert className="w-8 h-8 text-indigo-400" />
          </div>

          <h2 className="text-2xl font-display font-bold text-white mb-3 tracking-tight">
            Risk Engine
          </h2>

          <p className="text-slate-400 text-sm leading-relaxed mb-8">
            Automated on-chain risk assessment will be available in a future
            release. Risk monitoring is currently available via the Monitoring
            &amp; Analytics dashboard.
          </p>

          <Link
            href="/monitoring"
            className="inline-flex items-center gap-2 px-6 py-2.5 bg-btn-primary text-white text-sm font-medium rounded-lg shadow-[0_0_20px_rgba(79,70,229,0.3)] hover:shadow-[0_0_30px_rgba(79,70,229,0.5)] transition-all border border-white/10"
          >
            Go to Monitoring
          </Link>
        </div>
      </div>
    </>
  );
}
