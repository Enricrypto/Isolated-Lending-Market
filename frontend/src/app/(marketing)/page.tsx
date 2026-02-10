import Link from "next/link";
import { BookOpen, PlayCircle } from "lucide-react";
import { TokenIcon } from "@/components/TokenIcon";

export default function LandingPage() {
  return (
    <div className="relative overflow-x-hidden antialiased">
      {/* Background Noise */}
      <div className="fixed inset-0 z-0 pointer-events-none">
        <div className="absolute top-[-20%] left-[20%] w-[60rem] h-[60rem] bg-indigo-900/10 rounded-full blur-[120px]" />
      </div>

      {/* Navigation */}
      <nav className="fixed top-0 w-full z-50 border-b border-white/5 bg-[#020410]/80 backdrop-blur-md">
        <div className="max-w-7xl mx-auto px-6 h-20 flex items-center justify-between">
          <Link href="/" className="flex items-center gap-3 group">
            <div className="flex items-center -space-x-2.5">
              <div className="w-5 h-5 rounded-full bg-gradient-to-br from-orange-400 to-red-500 shadow-[0_0_10px_rgba(239,68,68,0.4)] z-10 border border-white/10" />
              <div className="w-5 h-5 rounded-full bg-gradient-to-br from-amber-300 to-yellow-500 shadow-[0_0_10px_rgba(245,158,11,0.4)] z-20 mix-blend-screen border border-white/10" />
              <div className="w-5 h-5 rounded-full bg-gradient-to-br from-cyan-300 to-teal-400 shadow-[0_0_10px_rgba(34,211,238,0.4)] z-30 mix-blend-screen border border-white/10" />
              <div className="w-5 h-5 rounded-full bg-gradient-to-br from-blue-400 to-indigo-500 shadow-[0_0_10px_rgba(59,130,246,0.4)] z-40 mix-blend-screen border border-white/10" />
            </div>
            <span className="font-brand font-bold text-2xl text-white tracking-tight">
              LendCore
            </span>
          </Link>
          <div className="hidden md:flex items-center gap-8 text-sm font-medium text-slate-400">
            <a href="#features" className="hover:text-white transition-colors">
              Features
            </a>
            <a href="#markets" className="hover:text-white transition-colors">
              Markets
            </a>
            <a
              href="#governance"
              className="hover:text-white transition-colors"
            >
              Governance
            </a>
            <a href="#docs" className="hover:text-white transition-colors">
              Docs
            </a>
          </div>
          <div className="flex items-center gap-4">
            <a
              href="#docs"
              className="hidden md:flex items-center gap-2 text-sm font-medium text-slate-400 hover:text-white transition-colors"
            >
              <BookOpen className="w-4 h-4" />
              Docs
            </a>
            <Link
              href="/dashboard"
              className="bg-[#4F46E5] hover:bg-[#4338ca] text-white px-5 py-2 rounded-lg text-sm font-medium transition-all shadow-[0_0_15px_rgba(79,70,229,0.2)] hover:shadow-[0_0_25px_rgba(79,70,229,0.4)] flex items-center gap-2"
            >
              Launch App
            </Link>
          </div>
        </div>
      </nav>

      {/* Hero Section */}
      <header className="relative pt-32 pb-20 lg:pt-48 lg:pb-32 px-6">
        <div className="glow" />
        <div className="max-w-5xl mx-auto text-center relative z-10">
          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-indigo-500/5 border border-indigo-500/20 text-indigo-300 text-xs font-medium mb-8 uppercase tracking-wider">
            <span className="w-1.5 h-1.5 rounded-full bg-indigo-400 animate-pulse" />
            Protocol V2 Live
          </div>

          <h1 className="text-5xl md:text-7xl font-semibold text-white tracking-tight mb-8 leading-[1.05]">
            Isolated Lending <br />
            <span className="text-gradient">No Intermediaries</span>
          </h1>

          <p className="text-lg md:text-xl text-slate-400 max-w-2xl mx-auto mb-10 leading-relaxed font-light">
            Maximize capital efficiency with isolated risk markets.
            Permissionless infrastructure built for the next generation of DeFi
            yield.
          </p>

          <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
            <Link
              href="/dashboard"
              className="w-full sm:w-auto bg-white text-slate-950 px-8 py-3.5 rounded-lg text-sm font-semibold hover:bg-slate-200 transition-colors flex items-center justify-center gap-2"
            >
              Start Earning
            </Link>
            <button className="w-full sm:w-auto bg-white/5 border border-white/10 text-white px-8 py-3.5 rounded-lg text-sm font-medium hover:bg-white/10 transition-colors flex items-center justify-center gap-2">
              <PlayCircle className="w-4 h-4 text-slate-400" />
              How it works
            </button>
          </div>
        </div>
      </header>

      {/* Features Section */}
      <section id="features" className="py-12 px-6 relative z-10">
        <div className="max-w-6xl mx-auto">
          <div className="mb-12">
            <h2 className="text-2xl font-semibold text-white tracking-tight mb-2">
              Core Infrastructure
            </h2>
            <p className="text-slate-400 text-sm">
              Engineered for solvency, speed, and composability.
            </p>
          </div>

          {/* Bento Grid */}
          <div className="bento-grid grid-cols-1 md:grid-cols-4 rounded-3xl overflow-hidden shadow-2xl shadow-black/50">
            {/* 1. Architecture */}
            <div className="bento-card col-span-1 md:col-span-2 h-64 md:h-72 group relative">
              <div className="absolute inset-0 bg-gradient-to-r from-blue-900/10 to-transparent opacity-50" />
              <div className="absolute inset-0 overflow-hidden">
                <svg
                  className="w-full h-full opacity-40 group-hover:opacity-60 transition-opacity duration-700"
                  preserveAspectRatio="none"
                >
                  <path
                    d="M0,200 C150,200 150,50 400,50"
                    stroke="url(#lineGrad1)"
                    strokeWidth="1"
                    fill="none"
                  />
                  <path
                    d="M0,220 C180,220 180,80 450,80"
                    stroke="url(#lineGrad2)"
                    strokeWidth="1"
                    fill="none"
                    opacity="0.7"
                  />
                  <path
                    d="M0,240 C210,240 210,110 500,110"
                    stroke="url(#lineGrad1)"
                    strokeWidth="1"
                    fill="none"
                    opacity="0.4"
                  />
                  <defs>
                    <linearGradient
                      id="lineGrad1"
                      x1="0%"
                      y1="0%"
                      x2="100%"
                      y2="0%"
                    >
                      <stop
                        offset="0%"
                        style={{ stopColor: "#3b82f6", stopOpacity: 0 }}
                      />
                      <stop
                        offset="50%"
                        style={{ stopColor: "#3b82f6", stopOpacity: 1 }}
                      />
                      <stop
                        offset="100%"
                        style={{ stopColor: "#06b6d4", stopOpacity: 0 }}
                      />
                    </linearGradient>
                    <linearGradient
                      id="lineGrad2"
                      x1="0%"
                      y1="0%"
                      x2="100%"
                      y2="0%"
                    >
                      <stop
                        offset="0%"
                        style={{ stopColor: "#6366f1", stopOpacity: 0 }}
                      />
                      <stop
                        offset="50%"
                        style={{ stopColor: "#6366f1", stopOpacity: 1 }}
                      />
                      <stop
                        offset="100%"
                        style={{ stopColor: "#8b5cf6", stopOpacity: 0 }}
                      />
                    </linearGradient>
                  </defs>
                </svg>
              </div>
              <div className="absolute bottom-8 left-8 z-10">
                <h3 className="text-[10px] font-bold tracking-[0.2em] text-slate-500 uppercase mb-2">
                  Architecture
                </h3>
                <p className="text-2xl font-medium text-white tracking-tight">
                  Onchain Composability
                </p>
              </div>
            </div>

            {/* 2. Liquidity */}
            <div className="bento-card col-span-1 md:col-span-2 h-64 md:h-72 relative overflow-hidden">
              <div className="absolute inset-0 bg-gradient-to-l from-purple-900/10 to-transparent" />
              <div className="absolute right-0 top-0 bottom-0 w-1/2 overflow-hidden pointer-events-none">
                <div className="absolute right-[-20%] top-[-10%] w-full h-[120%] bg-indigo-600/20 blur-[60px]" />
                <svg
                  className="absolute right-0 top-0 h-full w-full"
                  preserveAspectRatio="none"
                >
                  <defs>
                    <linearGradient
                      id="prismGrad"
                      x1="0%"
                      y1="0%"
                      x2="100%"
                      y2="100%"
                    >
                      <stop
                        offset="0%"
                        stopColor="rgba(139, 92, 246, 0.6)"
                      />
                      <stop
                        offset="100%"
                        stopColor="rgba(79, 70, 229, 0.1)"
                      />
                    </linearGradient>
                  </defs>
                  <path
                    d="M200 0 L400 300 L100 300 Z"
                    fill="url(#prismGrad)"
                    className="opacity-80"
                    transform="translate(100, 0)"
                  />
                  <line
                    x1="300"
                    y1="0"
                    x2="200"
                    y2="300"
                    stroke="rgba(255,255,255,0.2)"
                    strokeWidth="1"
                  />
                </svg>
              </div>
              <div className="absolute bottom-8 left-8 z-10">
                <h3 className="text-[10px] font-bold tracking-[0.2em] text-slate-500 uppercase mb-2">
                  Liquidity
                </h3>
                <p className="text-2xl font-medium text-white tracking-tight">
                  Just-in-Time
                </p>
                <p className="text-2xl font-medium text-white/40 tracking-tight">
                  Provisioning
                </p>
              </div>
            </div>

            {/* 3. Dollar Icon */}
            <div className="bento-card col-span-1 h-48 md:h-56 relative flex items-center justify-center overflow-hidden">
              <div className="absolute inset-0 flex items-center justify-center opacity-20">
                <svg
                  viewBox="0 0 200 200"
                  className="w-[180%] h-[180%] animate-[spin_60s_linear_infinite]"
                >
                  <g stroke="#4F46E5" strokeWidth="0.5">
                    <line x1="100" y1="100" x2="100" y2="0" />
                    <line x1="100" y1="100" x2="170" y2="30" />
                    <line x1="100" y1="100" x2="200" y2="100" />
                    <line x1="100" y1="100" x2="170" y2="170" />
                    <line x1="100" y1="100" x2="100" y2="200" />
                    <line x1="100" y1="100" x2="30" y2="170" />
                    <line x1="100" y1="100" x2="0" y2="100" />
                    <line x1="100" y1="100" x2="30" y2="30" />
                  </g>
                </svg>
              </div>
              <div className="relative z-10 w-14 h-14 rounded-full border border-indigo-500/20 bg-indigo-500/10 backdrop-blur-sm flex items-center justify-center shadow-lg shadow-indigo-500/20">
                <svg
                  width="24"
                  height="24"
                  viewBox="0 0 24 24"
                  fill="none"
                  xmlns="http://www.w3.org/2000/svg"
                >
                  <path
                    d="M12 2v2m0 16v2M17 8c0-1.657-2.239-3-5-3S7 6.343 7 8s2.239 3 5 3 5 1.343 5 3-2.239 3-5 3-5-1.343-5-3"
                    stroke="#818CF8"
                    strokeWidth="2"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  />
                </svg>
              </div>
            </div>

            {/* 4. Max Leverage */}
            <div className="bento-card col-span-1 md:col-span-2 h-48 md:h-56 relative flex flex-col justify-center pl-10 md:pl-16 overflow-hidden">
              <div className="absolute inset-0 checkerboard" />
              <div className="absolute right-0 top-0 h-full w-32 bg-gradient-to-l from-[#050714] to-transparent" />
              <div className="relative z-10">
                <h3 className="text-[10px] font-bold tracking-[0.2em] text-slate-500 uppercase mb-1">
                  Max Leverage
                </h3>
                <div className="flex items-baseline">
                  <span className="text-7xl md:text-8xl font-medium text-white tracking-tighter">
                    20
                  </span>
                  <span className="text-5xl md:text-6xl font-medium text-slate-700 tracking-tighter ml-1">
                    X
                  </span>
                </div>
              </div>
            </div>

            {/* 5. Collateral */}
            <div className="bento-card col-span-1 h-48 md:h-56 relative overflow-hidden group">
              <div
                className="absolute inset-0 opacity-20"
                style={{
                  backgroundImage:
                    "linear-gradient(rgba(16, 185, 129, 0.3) 1px, transparent 1px), linear-gradient(90deg, rgba(16, 185, 129, 0.3) 1px, transparent 1px)",
                  backgroundSize: "24px 24px",
                }}
              />
              <div className="absolute inset-0 bg-gradient-to-t from-emerald-950/50 to-transparent" />
              <div className="absolute bottom-8 left-8 z-10">
                <h3 className="text-[10px] font-bold tracking-[0.2em] text-slate-500 uppercase mb-2">
                  Collateral
                </h3>
                <p className="text-xl font-medium text-white tracking-tight">
                  USDC &amp; ETH
                </p>
              </div>
              <div className="absolute top-8 right-8 w-2 h-2 rounded-full bg-emerald-500 shadow-[0_0_10px_rgba(16,185,129,0.5)]" />
            </div>
          </div>
        </div>
      </section>

      {/* Protocol Stats */}
      <section
        id="markets"
        className="border-y border-white/5 bg-white/[0.01]"
      >
        <div className="max-w-7xl mx-auto px-6 py-12">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-8 md:gap-12">
            <div className="text-center">
              <p className="text-xs text-slate-500 mb-1 font-medium uppercase tracking-wider">
                Total Value Locked
              </p>
              <p className="text-3xl font-semibold text-white tracking-tight">
                $8.4M+
              </p>
            </div>
            <div className="text-center">
              <p className="text-xs text-slate-500 mb-1 font-medium uppercase tracking-wider">
                Active Markets
              </p>
              <p className="text-3xl font-semibold text-white tracking-tight">
                12
              </p>
            </div>
            <div className="text-center">
              <p className="text-xs text-slate-500 mb-1 font-medium uppercase tracking-wider">
                Total Supplied
              </p>
              <p className="text-3xl font-semibold text-white tracking-tight">
                $14.2M
              </p>
            </div>
            <div className="text-center">
              <p className="text-xs text-slate-500 mb-1 font-medium uppercase tracking-wider">
                Protocol Users
              </p>
              <p className="text-3xl font-semibold text-white tracking-tight">
                2,400+
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* How It Works */}
      <section className="py-24 px-6 relative overflow-hidden">
        <div className="max-w-7xl mx-auto flex flex-col lg:flex-row gap-16 lg:gap-24 items-center">
          {/* Left Content */}
          <div className="lg:w-1/2 space-y-8">
            <h2 className="text-4xl md:text-5xl font-semibold text-white tracking-tight leading-[1.1]">
              Designed for <br />
              <span className="text-indigo-400">Simplicity &amp; Control</span>
            </h2>
            <p className="text-lg text-slate-400 font-light leading-relaxed max-w-md">
              Navigate the DeFi landscape with an intuitive dashboard. Monitor
              health factors and manage collateral effortlessly.
            </p>

            <div className="space-y-6 pt-2">
              {["Connect Wallet", "Deposit Collateral", "Earn Yield"].map(
                (step, i) => (
                  <div key={step} className="flex items-center gap-4 group">
                    <div className="w-8 h-8 rounded-full bg-slate-800/60 border border-white/5 flex items-center justify-center text-sm font-medium text-slate-300 group-hover:bg-indigo-500 group-hover:text-white transition-all duration-300">
                      {i + 1}
                    </div>
                    <span className="text-slate-300 font-medium group-hover:text-white transition-colors">
                      {step}
                    </span>
                  </div>
                )
              )}
            </div>
          </div>

          {/* Right Visual */}
          <div className="lg:w-1/2 w-full flex justify-center lg:justify-end">
            <div className="relative w-full max-w-lg bg-[#080a14] border border-white/5 rounded-2xl p-6 md:p-8 shadow-2xl shadow-black/80">
              <div className="absolute -top-px left-0 right-0 h-px bg-gradient-to-r from-transparent via-indigo-500/50 to-transparent" />

              <div className="flex justify-between items-center mb-6">
                <div className="flex items-center gap-3">
                  <span className="text-slate-500 font-medium text-sm">Net APY</span>
                  <span className="text-emerald-400 font-semibold">5.24%</span>
                </div>
                <div className="flex items-center gap-1.5 px-2.5 py-1 rounded-md bg-emerald-500/10 border border-emerald-500/20">
                  <span className="w-1.5 h-1.5 rounded-full bg-emerald-400" />
                  <span className="text-emerald-400 text-xs font-medium">Active</span>
                </div>
              </div>

              <div className="space-y-3">
                {/* USDC Market Row */}
                <div className="flex items-center justify-between p-4 rounded-lg bg-[#0e111a] border border-white/5 hover:border-white/10 transition-colors duration-500">
                  <div className="flex items-center gap-3">
                    <div className="w-8 h-8 rounded-xl bg-blue-500/15 border border-blue-500/20 flex items-center justify-center"><TokenIcon symbol="usdc" size={18} /></div>
                    <div>
                      <p className="text-sm font-medium text-white">USDC Market</p>
                      <p className="text-xs text-slate-500">Isolated Lending</p>
                    </div>
                  </div>
                  <div className="text-right">
                    <p className="text-sm font-medium text-white">$8.4M</p>
                    <p className="text-xs text-emerald-400">+5.24% APY</p>
                  </div>
                </div>

                {/* WETH Market Row */}
                <div className="flex items-center justify-between p-4 rounded-lg bg-[#0e111a] border border-white/5 hover:border-white/10 transition-colors duration-500">
                  <div className="flex items-center gap-3">
                    <div className="w-8 h-8 rounded-xl bg-indigo-500/15 border border-indigo-500/20 flex items-center justify-center"><TokenIcon symbol="weth" size={18} /></div>
                    <div>
                      <p className="text-sm font-medium text-white">WETH Market</p>
                      <p className="text-xs text-slate-500">Isolated Lending</p>
                    </div>
                  </div>
                  <div className="text-right">
                    <p className="text-sm font-medium text-white">1,204 &#926;</p>
                    <p className="text-xs text-emerald-400">+3.42% APY</p>
                  </div>
                </div>

                {/* WBTC Market Row */}
                <div className="flex items-center justify-between p-4 rounded-lg bg-[#0e111a] border border-white/5 hover:border-white/10 transition-colors duration-500">
                  <div className="flex items-center gap-3">
                    <div className="w-8 h-8 rounded-xl bg-amber-500/15 border border-amber-500/20 flex items-center justify-center"><TokenIcon symbol="wbtc" size={18} /></div>
                    <div>
                      <p className="text-sm font-medium text-white">WBTC Market</p>
                      <p className="text-xs text-slate-500">Isolated Lending</p>
                    </div>
                  </div>
                  <div className="text-right">
                    <p className="text-sm font-medium text-white">12.5 &#8383;</p>
                    <p className="text-xs text-slate-500">0.00% APY</p>
                  </div>
                </div>
              </div>

              <div className="absolute -inset-1 bg-indigo-500/10 rounded-2xl blur-2xl -z-10 opacity-50" />
            </div>
          </div>
        </div>
      </section>

      {/* Governance Section */}
      <section id="governance" className="py-24 px-6 relative z-10">
        <div className="max-w-5xl mx-auto text-center">
          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-indigo-500/5 border border-indigo-500/20 text-indigo-300 text-xs font-medium mb-6 uppercase tracking-wider">
            Governance
          </div>
          <h2 className="text-3xl md:text-4xl font-semibold text-white tracking-tight mb-4">
            Secured by Timelock Governance
          </h2>
          <p className="text-slate-400 text-lg max-w-2xl mx-auto mb-10 font-light">
            All protocol parameter changes go through a 48-hour timelock with
            multisig oversight. Emergency guardians can pause instantly to
            protect user funds.
          </p>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6 max-w-3xl mx-auto">
            {[
              {
                label: "Timelock Delay",
                value: "48h",
                desc: "All changes are delayed",
              },
              {
                label: "Risk Engine",
                value: "24/7",
                desc: "Automated risk monitoring",
              },
              {
                label: "Emergency Pause",
                value: "Instant",
                desc: "Guardian-protected",
              },
            ].map((item) => (
              <div
                key={item.label}
                className="glass-panel rounded-xl p-6 text-center"
              >
                <p className="text-2xl font-semibold text-white mb-1">
                  {item.value}
                </p>
                <p className="text-xs text-slate-500 uppercase tracking-wider font-medium mb-1">
                  {item.label}
                </p>
                <p className="text-xs text-slate-600">{item.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* CTA */}
      <section className="py-20 px-6">
        <div className="max-w-3xl mx-auto text-center">
          <h2 className="text-3xl md:text-4xl font-semibold text-white tracking-tight mb-4">
            Ready to start?
          </h2>
          <p className="text-slate-400 mb-8 font-light">
            Connect your wallet and start earning yield on Sepolia testnet.
          </p>
          <Link
            href="/dashboard"
            className="inline-flex bg-[#4F46E5] hover:bg-[#4338ca] text-white px-8 py-3.5 rounded-lg text-sm font-semibold transition-all shadow-[0_0_15px_rgba(79,70,229,0.2)] hover:shadow-[0_0_25px_rgba(79,70,229,0.4)]"
          >
            Launch App
          </Link>
        </div>
      </section>

      {/* Footer */}
      <footer
        id="docs"
        className="border-t border-white/5 py-12 px-6 bg-[#020410]"
      >
        <div className="max-w-7xl mx-auto flex flex-col md:flex-row justify-between items-center gap-6">
          <div className="flex items-center gap-3">
            <div className="flex items-center -space-x-2">
              <div className="w-3.5 h-3.5 rounded-full bg-gradient-to-br from-orange-400 to-red-500 z-10 border border-white/10" />
              <div className="w-3.5 h-3.5 rounded-full bg-gradient-to-br from-amber-300 to-yellow-500 z-20 mix-blend-screen border border-white/10" />
              <div className="w-3.5 h-3.5 rounded-full bg-gradient-to-br from-cyan-300 to-teal-400 z-30 mix-blend-screen border border-white/10" />
              <div className="w-3.5 h-3.5 rounded-full bg-gradient-to-br from-blue-400 to-indigo-500 z-40 mix-blend-screen border border-white/10" />
            </div>
            <span className="text-white font-semibold">LendCore</span>
          </div>
          <p className="text-slate-600 text-sm">
            &copy; 2026 LendCore Protocol.
          </p>
        </div>
      </footer>
    </div>
  );
}
