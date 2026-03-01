import { ImageResponse } from "next/og"

export const size = { width: 180, height: 180 }
export const contentType = "image/png"

export default function AppleIcon() {
  // Four overlapping circles — scaled up for 180×180 iOS icon
  const r = 76
  const gap = 38
  const total = 3 * gap + r // = 190px — slight bleed intentional for padding effect
  const x0 = Math.round((180 - total) / 2) // ≈ -5 → outer circles bleed a little, looks natural
  const y = (180 - r) / 2

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
          width: 180,
          height: 180,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          background: "#0d1117",
          borderRadius: 40,
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
