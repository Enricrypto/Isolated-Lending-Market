import type { Metadata } from "next";
import "./globals.css";
import { Providers } from "@/components/Providers";
import { Toaster } from "sonner";

export const metadata: Metadata = {
  title: "LendCore | Decentralized Isolated Lending",
  description: "Maximize capital efficiency with isolated risk markets. Permissionless infrastructure built for DeFi yield.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="dark scroll-smooth">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        <link
          href="https://fonts.googleapis.com/css2?family=Archivo:wght@700;800;900&family=Inter:wght@300;400;500;600&family=Space+Grotesk:wght@500;700&display=swap"
          rel="stylesheet"
        />
      </head>
      <body className="bg-midnight-950 text-slate-300 min-h-screen selection:bg-accent-blue/30 relative overflow-x-hidden">
        {/* Background Effects */}
        <div className="fixed inset-0 z-0 bg-cosmic-gradient pointer-events-none" />
        <div className="fixed inset-0 z-0 bg-grid-pattern pointer-events-none opacity-40" />

        <Providers>
          {children}
          <Toaster
            position="bottom-right"
            theme="dark"
            toastOptions={{
              style: {
                background: "#0d1117",
                border: "1px solid rgba(99,102,241,0.2)",
                color: "#e2e8f0",
                fontFamily: "var(--font-inter, sans-serif)",
                fontSize: "13px",
              },
            }}
          />
        </Providers>
      </body>
    </html>
  );
}
