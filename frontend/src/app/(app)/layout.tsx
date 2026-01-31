import { Sidebar } from "@/components/Sidebar";

export default function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <>
      <Sidebar />
      <main className="md:ml-72 flex flex-col min-h-screen relative z-10">
        {children}
      </main>
    </>
  );
}
