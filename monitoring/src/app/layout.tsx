import type { Metadata } from "next";
import "./globals.css";
import { Sidebar } from "@/components/Sidebar";
import { Providers } from "@/components/Providers";

export const metadata: Metadata = {
  title: "LendCore | Protocol Dashboard",
  description: "Lending Protocol Dashboard - Manage vaults, monitor risk, and interact with the protocol",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="dark">
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
          <Sidebar />
          <main className="md:ml-72 flex flex-col min-h-screen relative z-10">
            {children}
          </main>
        </Providers>
      </body>
    </html>
  );
}
