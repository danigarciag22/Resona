import Link from "next/link";

export function AppShell({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen">
      <aside className="w-56 border-r bg-muted/30 p-4">
        <div className="mb-6 text-lg font-semibold">Resona</div>
        <nav className="flex flex-col gap-1 text-sm">
          <Link className="rounded px-2 py-1.5 hover:bg-muted" href="/dashboard">
            Dashboard
          </Link>
          <Link className="rounded px-2 py-1.5 hover:bg-muted" href="/agents">
            Agents
          </Link>
          <Link className="rounded px-2 py-1.5 hover:bg-muted" href="/calls">
            Calls
          </Link>
        </nav>
      </aside>
      <main className="flex-1 p-8">{children}</main>
    </div>
  );
}
