import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./src/pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/components/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  darkMode: "class",
  theme: {
    extend: {
      fontFamily: {
        sans: ["Inter", "sans-serif"],
        display: ["Archivo", "sans-serif"],
        brand: ["Space Grotesk", "sans-serif"],
      },
      colors: {
        midnight: {
          950: "#020410",
          900: "#05071A",
          800: "#0F112A",
          700: "#1A1D42",
        },
        accent: {
          blue: "#4F46E5",
          purple: "#7C3AED",
          cyan: "#22D3EE",
        },
        severity: {
          normal: "#22c55e",
          elevated: "#eab308",
          critical: "#f97316",
          emergency: "#ef4444",
        },
      },
      backgroundImage: {
        "cosmic-gradient": "radial-gradient(circle at 50% 0%, #1e1b4b 0%, #020410 60%)",
        "glass-gradient": "linear-gradient(180deg, rgba(15, 17, 42, 0.6) 0%, rgba(5, 7, 26, 0.6) 100%)",
        "btn-primary": "linear-gradient(90deg, #3730A3 0%, #4F46E5 100%)",
      },
    },
  },
  plugins: [],
};

export default config;
