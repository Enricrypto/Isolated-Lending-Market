import { ImageResponse } from "next/og"

export const size = { width: 32, height: 32 }
export const contentType = "image/png"

export default function Icon() {
  // Four overlapping circles — matches the Sidebar logo
  // At 32px: each circle is 14px, offset 7px between starts, centred vertically
  const r = 14
  const gap = 7
  const total = 3 * gap + r // = 35px
  const x0 = Math.round((32 - total) / 2) // ≈ -1 → clip is fine, use 0
  const y = (32 - r) / 2

  const circles = [
    { left: x0,           top: y, bg: "linear-gradient(135deg,#fb923c,#ef4444)" },
    { left: x0 + gap,     top: y, bg: "linear-gradient(135deg,#fcd34d,#eab308)" },
    { left: x0 + gap * 2, top: y, bg: "linear-gradient(135deg,#67e8f9,#2dd4bf)" },
    { left: x0 + gap * 3, top: y, bg: "linear-gradient(135deg,#60a5fa,#6366f1)" },
  ]

  return new ImageResponse(
    (
      <div
        style={{
          width: 32,
          height: 32,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          background: "#0d1117",
          borderRadius: 8,
          overflow: "hidden",
          position: "relative",
        }}
      >
        {circles.map((c, i) => (
          <div
            key={i}
            style={{
              position: "absolute",
              left: c.left,
              top: c.top,
              width: r,
              height: r,
              borderRadius: "50%",
              background: c.bg,
              opacity: i === 0 ? 1 : 0.88,
            }}
          />
        ))}
      </div>
    ),
    { ...size }
  )
}
