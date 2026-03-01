"use client"

import { useState, useCallback } from "react"
import { Header } from "@/components/Header"
import { apiBase } from "@/lib/apiUrl"
import { formatRate } from "@/lib/irm"
import { Lock, RefreshCw, CheckCircle, AlertTriangle, Save } from "lucide-react"

// ── Types ─────────────────────────────────────────────────────────────────────

interface MarketParamsData {
  baseRate:           number
  slope1:             number
  slope2:             number
  optimalUtilization: number
  lltv:               number
  liquidationPenalty: number
  protocolFee:        number
  updatedAt:          string
  updatedBy:          string
}

interface MarketRow {
  marketId:      string
  marketAddress: string
  vaultAddress:  string
  label:         string
  symbol:        string
  params:        MarketParamsData | null
}

// ── Auth gate ─────────────────────────────────────────────────────────────────

function AuthGate({ onAuth }: { onAuth: (token: string) => void }) {
  const [input, setInput] = useState("")
  const [error, setError] = useState(false)

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (!input.trim()) return
    setError(false)
    onAuth(input.trim())
  }

  return (
    <div className="flex flex-col items-center justify-center min-h-[60vh] px-4">
      <div className="glass-panel rounded-2xl p-8 w-full max-w-sm">
        <div className="flex items-center gap-3 mb-6">
          <div className="w-10 h-10 rounded-xl bg-indigo-500/10 flex items-center justify-center">
            <Lock className="w-5 h-5 text-indigo-400" />
          </div>
          <div>
            <h2 className="text-base font-semibold text-white">Admin Access</h2>
            <p className="text-xs text-slate-500">Enter ADMIN_SECRET to continue</p>
          </div>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          <input
            type="password"
            placeholder="Bearer token…"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            className="w-full bg-midnight-900 border border-midnight-700/50 rounded-xl px-4 py-3 text-sm text-white placeholder-slate-600 outline-none focus:border-indigo-500/50"
          />
          {error && (
            <p className="text-xs text-red-400 flex items-center gap-1">
              <AlertTriangle className="w-3 h-3" /> Invalid token
            </p>
          )}
          <button
            type="submit"
            className="w-full py-3 bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-medium rounded-xl transition-all"
          >
            Unlock Admin
          </button>
        </form>
      </div>
    </div>
  )
}

// ── Market param editor ───────────────────────────────────────────────────────

interface ParamEditorProps {
  market: MarketRow
  token:  string
  onSaved: () => void
}

function ParamEditor({ market, token, onSaved }: ParamEditorProps) {
  const p = market.params
  const [baseRate,           setBaseRate]           = useState(String(((p?.baseRate           ?? 0.02) * 100).toFixed(2)))
  const [slope1,             setSlope1]             = useState(String(((p?.slope1             ?? 0.04) * 100).toFixed(2)))
  const [slope2,             setSlope2]             = useState(String(((p?.slope2             ?? 0.60) * 100).toFixed(2)))
  const [optimalUtilization, setOptimalUtilization] = useState(String(((p?.optimalUtilization ?? 0.80) * 100).toFixed(0)))
  const [lltv,               setLltv]               = useState(String(((p?.lltv               ?? 0.85) * 100).toFixed(0)))
  const [liquidationPenalty, setLiquidationPenalty] = useState(String(((p?.liquidationPenalty ?? 0.05) * 100).toFixed(2)))
  const [protocolFee,        setProtocolFee]        = useState(String(((p?.protocolFee        ?? 0.10) * 100).toFixed(2)))

  const [saving,   setSaving]   = useState(false)
  const [saved,    setSaved]    = useState(false)
  const [errMsg,   setErrMsg]   = useState<string | null>(null)

  const handleSave = async () => {
    setSaving(true)
    setSaved(false)
    setErrMsg(null)

    try {
      const base = apiBase()
      const url  = base ? `${base}/admin/market-params` : "/api/admin/market-params"

      const body = {
        marketAddress:      market.marketAddress,
        baseRate:           parseFloat(baseRate)           / 100,
        slope1:             parseFloat(slope1)             / 100,
        slope2:             parseFloat(slope2)             / 100,
        optimalUtilization: parseFloat(optimalUtilization) / 100,
        lltv:               parseFloat(lltv)               / 100,
        liquidationPenalty: parseFloat(liquidationPenalty) / 100,
        protocolFee:        parseFloat(protocolFee)        / 100,
      }

      const res = await fetch(url, {
        method:  "POST",
        headers: {
          "Content-Type":  "application/json",
          Authorization:   `Bearer ${token}`,
        },
        body: JSON.stringify(body),
      })

      if (!res.ok) {
        const data = await res.json()
        throw new Error(data.error ?? `HTTP ${res.status}`)
      }

      setSaved(true)
      onSaved()
      setTimeout(() => setSaved(false), 3000)
    } catch (err) {
      setErrMsg(err instanceof Error ? err.message : "Unknown error")
    } finally {
      setSaving(false)
    }
  }

  const Field = ({
    label, value, onChange, unit = "%", hint,
  }: {
    label: string; value: string; onChange: (v: string) => void;
    unit?: string; hint?: string;
  }) => (
    <div>
      <label className="text-[10px] text-slate-500 uppercase tracking-wider block mb-1.5">
        {label}
        {hint && <span className="text-slate-600 normal-case ml-1">({hint})</span>}
      </label>
      <div className="flex items-center gap-2 bg-midnight-900 border border-midnight-700/50 rounded-xl px-4 py-2.5 focus-within:border-indigo-500/50 transition-colors">
        <input
          type="number"
          step="0.01"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          className="flex-1 min-w-0 bg-transparent text-white text-sm font-mono outline-none"
        />
        <span className="text-xs text-slate-500 flex-shrink-0">{unit}</span>
      </div>
    </div>
  )

  return (
    <div className="glass-panel rounded-2xl overflow-hidden">
      {/* Header */}
      <div className="px-6 py-4 border-b border-midnight-700/50 bg-white/5 flex items-center justify-between">
        <div>
          <h3 className="text-sm font-semibold text-white">{market.symbol} Market</h3>
          <p className="text-[10px] text-slate-500 font-mono mt-0.5">
            {market.marketAddress.slice(0, 14)}…{market.marketAddress.slice(-8)}
          </p>
        </div>
        {p && (
          <div className="text-right">
            <span className="text-[10px] text-slate-600">Last updated by</span>
            <p className="text-[10px] font-medium text-indigo-400">{p.updatedBy}</p>
          </div>
        )}
      </div>

      <div className="p-6 space-y-5">
        {/* IRM params */}
        <div>
          <p className="text-[10px] font-bold text-indigo-400 uppercase tracking-wider mb-3">
            Interest Rate Model
          </p>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <Field label="Base Rate"           value={baseRate}           onChange={setBaseRate}           hint="min rate at 0% util" />
            <Field label="Optimal Utilization" value={optimalUtilization} onChange={setOptimalUtilization} hint="kink point" />
            <Field label="Slope 1 (below kink)" value={slope1}           onChange={setSlope1}             hint="gradual" />
            <Field label="Slope 2 (above kink)" value={slope2}           onChange={setSlope2}             hint="steep" />
          </div>

          {/* Live preview */}
          <div className="mt-3 p-3 bg-midnight-900/50 rounded-lg border border-midnight-700/20 flex flex-wrap gap-4 text-[10px]">
            {(() => {
              const base = parseFloat(baseRate)   / 100
              const s1   = parseFloat(slope1)     / 100
              const s2   = parseFloat(slope2)     / 100
              const opt  = parseFloat(optimalUtilization) / 100
              const atKink = base + opt * s1
              const atMax  = atKink + (1 - opt) * s2
              return (
                <>
                  <span className="text-slate-500">At 0%: <span className="text-white font-mono">{formatRate(base)}</span></span>
                  <span className="text-slate-500">At kink ({optimalUtilization}%): <span className="text-amber-400 font-mono">{formatRate(atKink)}</span></span>
                  <span className="text-slate-500">At 100%: <span className="text-red-400 font-mono">{formatRate(atMax)}</span></span>
                </>
              )
            })()}
          </div>
        </div>

        {/* Risk params */}
        <div>
          <p className="text-[10px] font-bold text-indigo-400 uppercase tracking-wider mb-3">
            Risk Parameters
          </p>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <Field label="LLTV"               value={lltv}               onChange={setLltv}               hint="liquidation LTV" />
            <Field label="Liquidation Penalty" value={liquidationPenalty} onChange={setLiquidationPenalty} />
            <Field label="Protocol Fee"        value={protocolFee}        onChange={setProtocolFee}         hint="of interest" />
          </div>
        </div>

        {/* Actions */}
        <div className="flex items-center gap-3 pt-1">
          <button
            onClick={handleSave}
            disabled={saving}
            className="flex items-center gap-2 px-5 py-2.5 bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 text-white text-xs font-semibold rounded-xl transition-all"
          >
            {saving ? (
              <RefreshCw className="w-3.5 h-3.5 animate-spin" />
            ) : saved ? (
              <CheckCircle className="w-3.5 h-3.5 text-emerald-300" />
            ) : (
              <Save className="w-3.5 h-3.5" />
            )}
            {saving ? "Saving…" : saved ? "Saved!" : "Save Changes"}
          </button>
          {errMsg && (
            <span className="text-xs text-red-400 flex items-center gap-1">
              <AlertTriangle className="w-3 h-3" /> {errMsg}
            </span>
          )}
        </div>
      </div>
    </div>
  )
}

// ── Snapshot trigger ──────────────────────────────────────────────────────────

function SnapshotTrigger({ token }: { token: string }) {
  const [running, setRunning] = useState(false)
  const [result,  setResult]  = useState<string | null>(null)

  const trigger = async () => {
    setRunning(true)
    setResult(null)
    try {
      const base = apiBase()
      const url  = base ? `${base}/admin/trigger-snapshot` : "/api/admin/trigger-snapshot"
      const res  = await fetch(url, {
        method:  "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body:    JSON.stringify({}),
      })
      const data = await res.json()
      setResult(res.ok ? `Recomputed ${data.recomputed} market(s)` : data.error ?? "Error")
    } catch (err) {
      setResult(err instanceof Error ? err.message : "Unknown error")
    } finally {
      setRunning(false)
    }
  }

  return (
    <div className="glass-panel rounded-2xl p-5 flex items-center justify-between">
      <div>
        <p className="text-xs font-semibold text-white">Force Snapshot Recompute</p>
        <p className="text-[10px] text-slate-500 mt-0.5">
          Triggers an on-chain multicall for all active markets and updates DB snapshots immediately.
        </p>
      </div>
      <div className="flex items-center gap-3 ml-6 flex-shrink-0">
        {result && (
          <span className="text-[10px] text-emerald-400">{result}</span>
        )}
        <button
          onClick={trigger}
          disabled={running}
          className="flex items-center gap-2 px-4 py-2 bg-midnight-800 border border-midnight-700/50 hover:border-indigo-500/30 text-slate-300 text-xs font-medium rounded-xl transition-all disabled:opacity-50"
        >
          <RefreshCw className={`w-3.5 h-3.5 ${running ? "animate-spin" : ""}`} />
          {running ? "Running…" : "Recompute"}
        </button>
      </div>
    </div>
  )
}

// ── Main page ─────────────────────────────────────────────────────────────────

export default function AdminPage() {
  const [token,   setToken]   = useState<string | null>(null)
  const [markets, setMarkets] = useState<MarketRow[]>([])
  const [loading, setLoading] = useState(false)
  const [errMsg,  setErrMsg]  = useState<string | null>(null)

  const fetchMarkets = useCallback(async (t: string) => {
    setLoading(true)
    setErrMsg(null)
    try {
      const base = apiBase()
      const url  = base ? `${base}/admin/market-params` : "/api/admin/market-params"
      const res  = await fetch(url, {
        headers: { Authorization: `Bearer ${t}` },
      })
      if (res.status === 401) {
        setToken(null)
        setErrMsg("Invalid token — please re-authenticate.")
        return
      }
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const data = await res.json()
      setMarkets(data.markets ?? [])
    } catch (err) {
      setErrMsg(err instanceof Error ? err.message : "Unknown error")
    } finally {
      setLoading(false)
    }
  }, [])

  const handleAuth = (t: string) => {
    setToken(t)
    fetchMarkets(t)
  }

  if (!token) {
    return (
      <>
        <Header title="Market Admin" breadcrumb="Admin" showModeToggle={false} />
        <AuthGate onAuth={handleAuth} />
      </>
    )
  }

  return (
    <>
      <Header title="Market Admin" breadcrumb="Admin" showModeToggle={false} />

      <div className="p-6 sm:p-8 lg:p-10 space-y-8">
        {/* Hero */}
        <div className="relative">
          <div className="text-[10px] font-bold text-indigo-400 uppercase tracking-[0.2em] mb-2">
            Governance Controls
          </div>
          <h1 className="text-3xl font-display font-black text-white mb-2 tracking-tighter leading-[1.1]">
            Market Parameters
          </h1>
          <p className="text-slate-400 text-sm max-w-2xl font-light leading-relaxed">
            Update IRM constants and risk parameters. Changes propagate to the DB immediately
            and reflect in all frontend analytics within the next snapshot cycle.
          </p>
          <div className="absolute -top-20 -left-20 w-64 h-64 bg-indigo-600/10 rounded-full blur-[80px] pointer-events-none mix-blend-screen" />
        </div>

        {/* Force snapshot */}
        <SnapshotTrigger token={token} />

        {/* Error */}
        {errMsg && (
          <div className="flex items-center gap-2 text-sm text-red-400 px-4 py-3 bg-red-500/5 border border-red-500/20 rounded-xl">
            <AlertTriangle className="w-4 h-4 flex-shrink-0" />
            {errMsg}
          </div>
        )}

        {/* Loading */}
        {loading && (
          <div className="flex items-center gap-3 text-slate-500 text-sm">
            <RefreshCw className="w-4 h-4 animate-spin" />
            Loading market parameters…
          </div>
        )}

        {/* Market editors */}
        {!loading && markets.length > 0 && (
          <div className="space-y-6">
            {markets.map((market) => (
              <ParamEditor
                key={market.marketId}
                market={market}
                token={token}
                onSaved={() => fetchMarkets(token)}
              />
            ))}
          </div>
        )}

        {!loading && markets.length === 0 && !errMsg && (
          <div className="text-slate-500 text-sm">
            No active markets found. Start the indexer first.
          </div>
        )}
      </div>
    </>
  )
}
