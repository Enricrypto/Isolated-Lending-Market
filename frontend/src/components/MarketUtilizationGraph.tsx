"use client"

import { useMemo, useState, useCallback, useId, useRef, useEffect } from "react"
import { computeBorrowAPR, computeSupplyAPY, formatRate, IRM } from "@/lib/irm"

// ─── Types ────────────────────────────────────────────────────────────────────

export interface MarketUtilizationGraphProps {
  /** Current utilization ratio 0–1 (e.g. 0.65 = 65%) */
  utilization: number
  /** Kink point where slope jumps. Defaults to IRM.OPTIMAL (0.80) */
  kink?: number
  /**
   * Optional pre-computed curve [{x: utilization, y: rate}].
   * If omitted the component computes the curve from the on-chain IRM formula.
   */
  interestCurve?: { x: number; y: number }[]
  width?: number
  height?: number
  /**
   * When true the Y-axis shows Supply APY instead of Borrow APR.
   * The hover tooltip always shows both values regardless of this flag.
   */
  showSupplyAPY?: boolean
  className?: string
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

const CURVE_N = 120 // number of sample points for the curve

function buildCurve(
  showSupply: boolean,
  custom?: { x: number; y: number }[]
): { x: number; y: number }[] {
  if (custom) return custom
  return Array.from({ length: CURVE_N + 1 }, (_, i) => {
    const x = i / CURVE_N
    return { x, y: showSupply ? computeSupplyAPY(x) : computeBorrowAPR(x) }
  })
}

// ─── Component ────────────────────────────────────────────────────────────────

export function MarketUtilizationGraph({
  utilization,
  kink = IRM.OPTIMAL,
  interestCurve,
  width: externalWidth,
  height = 100,
  showSupplyAPY = false,
  className = "",
}: MarketUtilizationGraphProps) {
  // Unique prefix for SVG def IDs — prevents conflicts when rendered multiple times
  const uid = useId().replace(/[^a-zA-Z0-9]/g, "")

  // Fluid width: fill container when no explicit width is provided
  const containerRef = useRef<HTMLDivElement>(null)
  const [width, setWidth] = useState(externalWidth ?? 280)
  useEffect(() => {
    if (externalWidth !== undefined) return
    const el = containerRef.current
    if (!el) return
    const ro = new ResizeObserver((entries) => {
      const w = entries[0]?.contentRect.width
      if (w > 0) setWidth(w)
    })
    ro.observe(el)
    return () => ro.disconnect()
  }, [externalWidth])

  const [hover, setHover] = useState<{ svgX: number; u: number } | null>(null)

  // ── Layout ─────────────────────────────────────────────────────────────────
  const compact = height < 70
  const pT = compact ? 4 : 10  // pad top
  const pB = compact ? 14 : 26 // pad bottom (space for x-axis labels)
  const pL = 0
  const pR = compact ? 8 : 12  // pad right
  const plotW = width - pL - pR
  const plotH = height - pT - pB
  const bottom = pT + plotH   // y-coordinate of the baseline

  // ── Curve paths ────────────────────────────────────────────────────────────
  // Memoize heavy work — only recomputes when curve data or layout changes,
  // NOT on every hover state update.
  const { curvePath, fillPath, kinkX } = useMemo(() => {
    const pts = buildCurve(showSupplyAPY, interestCurve)
    const maxRate = pts.reduce((m, p) => Math.max(m, p.y), 0)
    const yMax = maxRate > 0 ? maxRate * 1.18 : 0.20  // 18% headroom

    const tx = (u: number) => pL + u * plotW
    const ty = (r: number) => pT + plotH * (1 - r / yMax)
    const bl = pT + plotH

    const pathStr = pts
      .map((p, i) => `${i === 0 ? "M" : "L"}${tx(p.x).toFixed(2)},${ty(p.y).toFixed(2)}`)
      .join(" ")

    const fillStr =
      `${pathStr} ` +
      `L${tx(1).toFixed(2)},${bl.toFixed(2)} ` +
      `L${tx(0).toFixed(2)},${bl.toFixed(2)} Z`

    return { curvePath: pathStr, fillPath: fillStr, kinkX: tx(kink) }
  }, [interestCurve, showSupplyAPY, kink, plotW, plotH, pL, pT])

  // ── Current utilization marker ─────────────────────────────────────────────
  const { dotX, dotY, isAboveKink } = useMemo(() => {
    // Reuse the same yMax calculation independently for the dot position
    const pts = buildCurve(showSupplyAPY, interestCurve)
    const maxRate = pts.reduce((m, p) => Math.max(m, p.y), 0)
    const yMax = maxRate > 0 ? maxRate * 1.18 : 0.20

    const tx = (u: number) => pL + u * plotW
    const ty = (r: number) => pT + plotH * (1 - r / yMax)
    const rate = showSupplyAPY ? computeSupplyAPY(utilization) : computeBorrowAPR(utilization)

    return {
      dotX: tx(utilization),
      dotY: ty(rate),
      isAboveKink: utilization > kink,
    }
  }, [utilization, kink, showSupplyAPY, interestCurve, plotW, plotH, pL, pT])

  // ── Hover ──────────────────────────────────────────────────────────────────
  const handleMouseMove = useCallback(
    (e: React.MouseEvent<SVGRectElement>) => {
      const rect = e.currentTarget.getBoundingClientRect()
      const mouseX = e.clientX - rect.left        // 0 → plotW
      const u = Math.max(0, Math.min(1, mouseX / plotW))
      setHover({ svgX: pL + mouseX, u })
    },
    [pL, plotW]
  )

  const hoverBorrow = hover !== null ? computeBorrowAPR(hover.u) : null
  const hoverSupply = hover !== null ? computeSupplyAPY(hover.u) : null

  // ── Visual constants ────────────────────────────────────────────────────────
  const markerColor = isAboveKink ? "#f59e0b" : "#10b981"
  const dotR        = compact ? 2.5 : 3.5
  const glowR       = compact ? 5 : 7
  const fontSize    = compact ? 7 : 9
  const strokeW     = compact ? 1.5 : 2

  // ── Render ─────────────────────────────────────────────────────────────────
  return (
    <div
      ref={containerRef}
      className={`relative select-none ${className}`}
      style={{ width: externalWidth !== undefined ? width : "100%", height }}
    >
      <svg
        width={width}
        height={height}
        viewBox={`0 0 ${width} ${height}`}
        aria-label="Interest rate curve"
      >
        <defs>
          {/* Area-fill gradients */}
          <linearGradient id={`gb-${uid}`} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%"   stopColor="#10b981" stopOpacity="0.20" />
            <stop offset="100%" stopColor="#10b981" stopOpacity="0.02" />
          </linearGradient>
          <linearGradient id={`ga-${uid}`} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%"   stopColor="#f59e0b" stopOpacity="0.20" />
            <stop offset="100%" stopColor="#f59e0b" stopOpacity="0.02" />
          </linearGradient>

          {/* Clip paths for two-tone curve (below / above kink) */}
          <clipPath id={`cb-${uid}`}>
            <rect x={0} y={0} width={kinkX} height={height} />
          </clipPath>
          <clipPath id={`ca-${uid}`}>
            <rect x={kinkX} y={0} width={width} height={height} />
          </clipPath>
        </defs>

        {/* ── Area fills ─────────────────────────────────────────────────── */}
        <path d={fillPath} fill={`url(#gb-${uid})`} clipPath={`url(#cb-${uid})`} />
        <path d={fillPath} fill={`url(#ga-${uid})`} clipPath={`url(#ca-${uid})`} />

        {/* ── Rate curve — green below kink, amber above ─────────────────── */}
        <path
          d={curvePath}
          fill="none"
          stroke="#10b981"
          strokeWidth={strokeW}
          clipPath={`url(#cb-${uid})`}
        />
        <path
          d={curvePath}
          fill="none"
          stroke="#f59e0b"
          strokeWidth={strokeW}
          clipPath={`url(#ca-${uid})`}
        />

        {/* ── Baseline ───────────────────────────────────────────────────── */}
        <line
          x1={pL} y1={bottom}
          x2={width - pR} y2={bottom}
          stroke="#1e293b" strokeWidth="1"
        />

        {/* ── Kink dashed vertical line ──────────────────────────────────── */}
        <line
          x1={kinkX} y1={pT}
          x2={kinkX} y2={bottom}
          stroke="#818cf8" strokeWidth="1" strokeDasharray="3,2" opacity="0.55"
        />

        {/* ── Current utilization marker ─────────────────────────────────── */}
        {utilization > 0 && (
          <>
            {/* Vertical guide */}
            <line
              x1={dotX} y1={pT}
              x2={dotX} y2={bottom}
              stroke={markerColor} strokeWidth="1" opacity="0.3"
            />
            {/* Glow ring */}
            <circle cx={dotX} cy={dotY} r={glowR}
              fill={markerColor} opacity="0.08" />
            {/* Dot */}
            <circle cx={dotX} cy={dotY} r={dotR}
              fill={markerColor} stroke="#0f172a" strokeWidth="1.5" />
          </>
        )}

        {/* ── Hover crosshair ────────────────────────────────────────────── */}
        {hover && (
          <line
            x1={hover.svgX} y1={pT}
            x2={hover.svgX} y2={bottom}
            stroke="#475569" strokeWidth="1" strokeDasharray="2,2"
          />
        )}

        {/* ── X-axis labels ──────────────────────────────────────────────── */}
        <text
          x={pL + 2}
          y={height - (compact ? 2 : 7)}
          fontSize={fontSize}
          fill="#475569"
        >
          0%
        </text>
        <text
          x={kinkX}
          y={height - (compact ? 2 : 7)}
          fontSize={fontSize}
          fill="#818cf8"
          textAnchor="middle"
        >
          {Math.round(kink * 100)}%
        </text>
        <text
          x={width - pR - 2}
          y={height - (compact ? 2 : 7)}
          fontSize={fontSize}
          fill="#475569"
          textAnchor="end"
        >
          100%
        </text>

        {/* ── Invisible hover-capture overlay ────────────────────────────── */}
        <rect
          x={pL} y={pT}
          width={plotW} height={plotH}
          fill="transparent"
          style={{ cursor: "crosshair" }}
          onMouseMove={handleMouseMove}
          onMouseLeave={() => setHover(null)}
        />
      </svg>

      {/* ── Tooltip ───────────────────────────────────────────────────────── */}
      {hover && hoverBorrow !== null && hoverSupply !== null && (
        <div
          className="absolute pointer-events-none z-50 bg-[#0c1118] border border-indigo-500/20 rounded-lg px-2.5 py-2 shadow-xl whitespace-nowrap"
          style={{
            left: hover.svgX + 8,
            top: pT,
            // Flip to left side when near the right edge
            transform:
              hover.svgX > width * 0.65
                ? "translateX(calc(-100% - 16px))"
                : undefined,
          }}
        >
          <p className="text-[10px] font-mono text-slate-500 leading-relaxed">
            Util&nbsp;
            <span className="text-white">{(hover.u * 100).toFixed(1)}%</span>
          </p>
          <p className="text-[10px] font-mono text-slate-500 leading-relaxed">
            Borrow&nbsp;
            <span className="text-amber-400">{formatRate(hoverBorrow)}</span>
          </p>
          <p className="text-[10px] font-mono text-slate-500 leading-relaxed">
            Supply&nbsp;
            <span className="text-emerald-400">{formatRate(hoverSupply)}</span>
          </p>
        </div>
      )}
    </div>
  )
}
