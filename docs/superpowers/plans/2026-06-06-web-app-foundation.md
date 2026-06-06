# Web App Foundation (Plan 4a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the Resona Next.js web app wired to the local Supabase data layer — a dashboard showing real seeded counts and an AgentBuilder that lists and creates agents — with Vitest integration tests proving the DB→UI pipe.

**Architecture:** An `apps/web` Next.js App Router app inside an npm-workspaces monorepo (root already holds `supabase/` and `packages/db`). Server-side data access goes through a typed `@supabase/supabase-js` client using the **service-role** key (server-only, local dev), importing the generated `Database` types from `@resona/db`. UI uses Tailwind + shadcn/ui. Cookie-based end-user auth is intentionally deferred to Plan 4b; this slice proves data flow end-to-end against the running local stack.

**Tech Stack:** Next.js (App Router, TypeScript), Tailwind v4, shadcn/ui, `@supabase/supabase-js`, Vitest, dotenv, npm workspaces.

> **Prereq:** the local Supabase stack from Plan 1 must be running (`make start` / `npx supabase start`). The service-role key + API URL come from `npx supabase status`.

> **Execution note (interactive scaffolders):** `create-next-app` and `shadcn init` may show prompts despite flags, depending on version. If a prompt appears, accept the documented default (TypeScript yes, App Router yes, Turbopack yes, import alias `@/*`, shadcn New York / Zinc). These are tool prompts, not code decisions.

---

## File Structure

```
resona/
  package.json                       # MODIFY: add "workspaces": ["apps/*","packages/*"]
  apps/web/
    package.json                     # next app + deps (scaffolded, then edited)
    next.config.ts                   # transpile @resona/db
    tsconfig.json                    # scaffolded
    components.json                  # shadcn config
    vitest.config.ts                 # node env, loads .env.local
    .env.local                       # gitignored: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
    .env.example                     # committed template
    app/
      layout.tsx                     # MODIFY: wrap in AppShell
      page.tsx                       # MODIFY: redirect -> /dashboard
      globals.css                    # scaffolded (Tailwind v4)
      dashboard/page.tsx             # server component: getDashboardStats()
      agents/page.tsx                # server component: listAgents() + create form
      agents/actions.ts              # "use server" createAgentAction
    components/
      app-shell.tsx                  # sidebar nav layout
      ui/                            # shadcn components (button, card, table, input, label)
    lib/
      supabase/server.ts             # createServiceClient()
      stats.ts                       # getDashboardStats()
      agents.ts                      # listAgents(), createAgent()
      __tests__/
        stats.test.ts
        agents.test.ts
```

---

## Task 1: Monorepo workspaces + Next.js scaffold

**Files:**
- Modify: `package.json` (root)
- Create: `apps/web/**` (via scaffolder)

- [ ] **Step 1: Make the root a workspace**

Edit root `package.json` to add a `workspaces` field (keep existing `scripts`/`devDependencies`):
```json
{
  "name": "resona",
  "private": true,
  "version": "0.0.0",
  "workspaces": ["apps/*", "packages/*"],
  "scripts": {
    "db:start": "supabase start",
    "db:stop": "supabase stop",
    "db:reset": "supabase db reset",
    "db:test": "supabase test db",
    "db:types": "supabase gen types typescript --local > packages/db/types.ts",
    "db:status": "supabase status",
    "web:dev": "npm run dev --workspace apps/web",
    "web:build": "npm run build --workspace apps/web",
    "web:test": "npm run test --workspace apps/web"
  },
  "devDependencies": {
    "supabase": "^2"
  }
}
```

- [ ] **Step 2: Scaffold the Next.js app**

Run:
```bash
npx create-next-app@latest apps/web \
  --typescript --tailwind --eslint --app \
  --no-src-dir --turbopack --import-alias "@/*" --use-npm --yes
```
Expected: creates `apps/web` with App Router, Tailwind v4, TypeScript. (If it warns the directory is in a workspace, that's fine.)

- [ ] **Step 3: Boot the dev server to verify scaffold**

Run: `npm run dev --workspace apps/web -- --port 3000 &` then after ~4s `curl -sS -o /dev/null -w "%{http_code}\n" http://localhost:3000`
Expected: `200`. Then kill the dev server (`kill %1` or `pkill -f "next dev"`).

- [ ] **Step 4: Commit**

```bash
git add package.json package-lock.json apps/web
git commit -m "feat(web): scaffold Next.js app in npm workspace"
```

---

## Task 2: shadcn/ui + base components

**Files:**
- Create: `apps/web/components.json`, `apps/web/components/ui/*`

- [ ] **Step 1: Initialize shadcn**

Run (from repo root):
```bash
cd apps/web && npx shadcn@latest init -d -y ; cd -
```
Expected: creates `components.json`, sets up `components/ui`, `lib/utils.ts`, and CSS variables in `globals.css`. (`-d` = defaults: New York style, Zinc. If it still prompts, accept defaults.)

- [ ] **Step 2: Add the components this slice uses**

Run:
```bash
cd apps/web && npx shadcn@latest add button card table input label -y ; cd -
```
Expected: creates `components/ui/{button,card,table,input,label}.tsx`.

- [ ] **Step 3: Verify the app still builds**

Run: `npm run build --workspace apps/web`
Expected: build succeeds (no type errors).

- [ ] **Step 4: Commit**

```bash
git add apps/web
git commit -m "feat(web): add shadcn/ui and base components"
```

---

## Task 3: Typed Supabase service client + Vitest harness

**Files:**
- Create: `apps/web/lib/supabase/server.ts`
- Create: `apps/web/.env.local`, `apps/web/.env.example`
- Create: `apps/web/vitest.config.ts`
- Modify: `apps/web/package.json` (deps + test script), `apps/web/next.config.ts`

- [ ] **Step 1: Install runtime + test deps**

Run:
```bash
npm install --workspace apps/web @supabase/supabase-js @resona/db
npm install --workspace apps/web -D vitest dotenv
```
Expected: adds `@supabase/supabase-js` and the workspace `@resona/db` to `apps/web` dependencies, `vitest`+`dotenv` to devDeps.

- [ ] **Step 2: Write env files**

Get values: `npx supabase status` prints `API URL` (http://127.0.0.1:54321) and `service_role key`.

`apps/web/.env.example` (committed):
```
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_SERVICE_ROLE_KEY=replace-with-local-service-role-key
```

`apps/web/.env.local` (gitignored — fill the real local key from `supabase status`):
```
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_SERVICE_ROLE_KEY=<paste service_role key from `npx supabase status`>
```

- [ ] **Step 3: Transpile the workspace types package**

`apps/web/next.config.ts`:
```ts
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  transpilePackages: ["@resona/db"],
};

export default nextConfig;
```

- [ ] **Step 4: Write the service client**

`apps/web/lib/supabase/server.ts`:
```ts
import { createClient } from "@supabase/supabase-js";
import type { Database } from "@resona/db";

/**
 * Server-only Supabase client using the service-role key.
 * Bypasses RLS — never import this into a Client Component.
 * Plan 4b replaces dashboard reads with cookie-scoped user sessions.
 */
export function createServiceClient() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
  return createClient<Database>(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
```

- [ ] **Step 5: Add Vitest config + test script**

`apps/web/vitest.config.ts`:
```ts
import { defineConfig } from "vitest/config";
import { config } from "dotenv";

config({ path: ".env.local" });

export default defineConfig({
  test: {
    environment: "node",
    include: ["lib/**/*.test.ts"],
  },
});
```

Edit `apps/web/package.json` scripts — add:
```json
"test": "vitest run"
```

- [ ] **Step 6: Smoke-test the client wiring**

`apps/web/lib/__tests__/stats.test.ts` (temporary smoke assertion, replaced in Task 4):
```ts
import { describe, it, expect } from "vitest";
import { createServiceClient } from "../supabase/server";

describe("supabase service client", () => {
  it("connects and reads the seeded org", async () => {
    const db = createServiceClient();
    const { data, error } = await db
      .from("organizations")
      .select("name")
      .eq("id", "00000000-0000-0000-0000-0000000000b0")
      .single();
    expect(error).toBeNull();
    expect(data?.name).toBe("Acme Demo");
  });
});
```

Run: `npm run test --workspace apps/web`
Expected: PASS (reads the seeded "Acme Demo" org).

- [ ] **Step 7: Commit**

```bash
git add apps/web/lib apps/web/vitest.config.ts apps/web/next.config.ts apps/web/.env.example apps/web/package.json package-lock.json
git commit -m "feat(web): typed Supabase service client and Vitest harness"
```

---

## Task 4: Dashboard — real seeded counts (TDD)

**Files:**
- Create: `apps/web/lib/stats.ts`, `apps/web/lib/__tests__/stats.test.ts` (replace smoke test)
- Create: `apps/web/app/dashboard/page.tsx`, `apps/web/components/app-shell.tsx`
- Modify: `apps/web/app/layout.tsx`, `apps/web/app/page.tsx`

- [ ] **Step 1: Write the failing test**

Replace `apps/web/lib/__tests__/stats.test.ts`:
```ts
import { describe, it, expect } from "vitest";
import { getDashboardStats } from "../stats";

describe("getDashboardStats", () => {
  it("returns seeded counts", async () => {
    const stats = await getDashboardStats();
    expect(stats.agents).toBe(1);        // seed: Acme Scheduler
    expect(stats.phoneNumbers).toBe(1);  // seed: +15555550100
    expect(stats.calls).toBe(0);         // seed has no calls
    expect(stats.completedCalls).toBe(0);
  });
});
```

- [ ] **Step 2: Run test, expect failure**

Run: `npm run test --workspace apps/web`
Expected: FAIL — `getDashboardStats` not found / `../stats` missing.

- [ ] **Step 3: Implement the data function**

`apps/web/lib/stats.ts`:
```ts
import { createServiceClient } from "./supabase/server";

export type DashboardStats = {
  agents: number;
  phoneNumbers: number;
  calls: number;
  completedCalls: number;
};

export async function getDashboardStats(): Promise<DashboardStats> {
  const db = createServiceClient();
  const head = { count: "exact" as const, head: true };
  const [agents, phones, calls, completed] = await Promise.all([
    db.from("agents").select("*", head),
    db.from("phone_numbers").select("*", head),
    db.from("calls").select("*", head),
    db.from("calls").select("*", head).eq("status", "completed"),
  ]);
  return {
    agents: agents.count ?? 0,
    phoneNumbers: phones.count ?? 0,
    calls: calls.count ?? 0,
    completedCalls: completed.count ?? 0,
  };
}
```

- [ ] **Step 4: Run test, expect pass**

Run: `npm run test --workspace apps/web`
Expected: PASS.

- [ ] **Step 5: Build the app shell**

`apps/web/components/app-shell.tsx`:
```tsx
import Link from "next/link";

export function AppShell({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen">
      <aside className="w-56 border-r bg-muted/30 p-4">
        <div className="mb-6 text-lg font-semibold">Resona</div>
        <nav className="flex flex-col gap-1 text-sm">
          <Link className="rounded px-2 py-1.5 hover:bg-muted" href="/dashboard">Dashboard</Link>
          <Link className="rounded px-2 py-1.5 hover:bg-muted" href="/agents">Agents</Link>
        </nav>
      </aside>
      <main className="flex-1 p-8">{children}</main>
    </div>
  );
}
```

- [ ] **Step 6: Render the dashboard**

`apps/web/app/dashboard/page.tsx`:
```tsx
import { getDashboardStats } from "@/lib/stats";
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card";

export const dynamic = "force-dynamic";

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <Card>
      <CardHeader><CardTitle className="text-sm text-muted-foreground">{label}</CardTitle></CardHeader>
      <CardContent className="text-3xl font-bold">{value}</CardContent>
    </Card>
  );
}

export default async function DashboardPage() {
  const stats = await getDashboardStats();
  return (
    <div>
      <h1 className="mb-6 text-2xl font-bold">Command Center</h1>
      <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
        <Stat label="Agents" value={stats.agents} />
        <Stat label="Phone Numbers" value={stats.phoneNumbers} />
        <Stat label="Calls" value={stats.calls} />
        <Stat label="Completed" value={stats.completedCalls} />
      </div>
    </div>
  );
}
```

- [ ] **Step 7: Wire layout + root redirect**

`apps/web/app/layout.tsx` — wrap `{children}` in `<AppShell>` (keep the scaffolded `<html>`/`<body>` and font setup):
```tsx
import { AppShell } from "@/components/app-shell";
// ...keep existing imports, metadata, fonts...
// inside <body ...>:
//   <AppShell>{children}</AppShell>
```

`apps/web/app/page.tsx` (replace entire file):
```tsx
import { redirect } from "next/navigation";

export default function Home() {
  redirect("/dashboard");
}
```

- [ ] **Step 8: Build to verify pages compile**

Run: `npm run build --workspace apps/web`
Expected: build succeeds; `/dashboard` compiles as a dynamic route.

- [ ] **Step 9: Commit**

```bash
git add apps/web/lib apps/web/app apps/web/components
git commit -m "feat(web): dashboard with real seeded counts"
```

---

## Task 5: AgentBuilder — list + create (TDD)

**Files:**
- Create: `apps/web/lib/agents.ts`, `apps/web/lib/__tests__/agents.test.ts`
- Create: `apps/web/app/agents/page.tsx`, `apps/web/app/agents/actions.ts`

- [ ] **Step 1: Write the failing test**

`apps/web/lib/__tests__/agents.test.ts`:
```ts
import { describe, it, expect, afterEach } from "vitest";
import { listAgents, createAgent } from "../agents";
import { createServiceClient } from "../supabase/server";

const created: string[] = [];

afterEach(async () => {
  if (created.length) {
    const db = createServiceClient();
    await db.from("agents").delete().in("id", created);
    created.length = 0;
  }
});

describe("agents", () => {
  it("creates an agent and lists it", async () => {
    const agent = await createAgent({ name: "Test Agent", personaPrompt: "be brief" });
    created.push(agent.id);
    expect(agent.name).toBe("Test Agent");

    const agents = await listAgents();
    expect(agents.some((a) => a.id === agent.id)).toBe(true);
  });
});
```

- [ ] **Step 2: Run test, expect failure**

Run: `npm run test --workspace apps/web`
Expected: FAIL — `../agents` missing.

- [ ] **Step 3: Implement the data functions**

`apps/web/lib/agents.ts`:
```ts
import { createServiceClient } from "./supabase/server";
import type { Database } from "@resona/db";

const DEMO_ORG = "00000000-0000-0000-0000-0000000000b0";
type AgentRow = Database["public"]["Tables"]["agents"]["Row"];

export async function listAgents(orgId: string = DEMO_ORG): Promise<AgentRow[]> {
  const db = createServiceClient();
  const { data, error } = await db
    .from("agents")
    .select("*")
    .eq("org_id", orgId)
    .order("created_at", { ascending: false });
  if (error) throw new Error(error.message);
  return data ?? [];
}

export async function createAgent(input: {
  name: string;
  personaPrompt?: string;
  orgId?: string;
}): Promise<AgentRow> {
  const db = createServiceClient();
  const { data, error } = await db
    .from("agents")
    .insert({
      org_id: input.orgId ?? DEMO_ORG,
      name: input.name,
      persona_prompt: input.personaPrompt ?? "",
    })
    .select()
    .single();
  if (error) throw new Error(error.message);
  return data;
}
```

- [ ] **Step 4: Run test, expect pass**

Run: `npm run test --workspace apps/web`
Expected: PASS (both stats and agents tests green).

- [ ] **Step 5: Server Action**

`apps/web/app/agents/actions.ts`:
```ts
"use server";

import { revalidatePath } from "next/cache";
import { createAgent } from "@/lib/agents";

export async function createAgentAction(formData: FormData) {
  const name = String(formData.get("name") ?? "").trim();
  if (!name) return;
  await createAgent({
    name,
    personaPrompt: String(formData.get("persona") ?? ""),
  });
  revalidatePath("/agents");
}
```

- [ ] **Step 6: Agents page (list + create form)**

`apps/web/app/agents/page.tsx`:
```tsx
import { listAgents } from "@/lib/agents";
import { createAgentAction } from "./actions";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";

export const dynamic = "force-dynamic";

export default async function AgentsPage() {
  const agents = await listAgents();
  return (
    <div className="max-w-3xl">
      <h1 className="mb-6 text-2xl font-bold">Agents</h1>

      <form action={createAgentAction} className="mb-8 flex items-end gap-3">
        <div className="flex flex-col gap-1.5">
          <Label htmlFor="name">Name</Label>
          <Input id="name" name="name" placeholder="Clinic Scheduler" required />
        </div>
        <div className="flex flex-1 flex-col gap-1.5">
          <Label htmlFor="persona">Persona</Label>
          <Input id="persona" name="persona" placeholder="Friendly, concise" />
        </div>
        <Button type="submit">Create</Button>
      </form>

      <Table>
        <TableHeader>
          <TableRow><TableHead>Name</TableHead><TableHead>Model</TableHead><TableHead>Created</TableHead></TableRow>
        </TableHeader>
        <TableBody>
          {agents.map((a) => (
            <TableRow key={a.id}>
              <TableCell className="font-medium">{a.name}</TableCell>
              <TableCell>{a.llm_model}</TableCell>
              <TableCell>{new Date(a.created_at).toLocaleDateString()}</TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}
```

- [ ] **Step 7: Build to verify**

Run: `npm run build --workspace apps/web`
Expected: build succeeds.

- [ ] **Step 8: Commit**

```bash
git add apps/web/lib apps/web/app
git commit -m "feat(web): AgentBuilder list and create via Server Action"
```

---

## Task 6: Manual verification + web README

**Files:**
- Create: `apps/web/README.md`

- [ ] **Step 1: Run the full web test suite**

Run: `npm run test --workspace apps/web`
Expected: all tests pass (stats + agents).

- [ ] **Step 2: Manually verify the running app**

Run: `npm run dev --workspace apps/web &` then:
```bash
sleep 4
curl -sS -o /dev/null -w "dashboard %{http_code}\n" http://localhost:3000/dashboard
curl -sS -o /dev/null -w "agents %{http_code}\n" http://localhost:3000/agents
```
Expected: both `200`. Confirm the dashboard shows Agents=1, Phone Numbers=1. Kill the dev server afterward.

- [ ] **Step 3: Write the web README**

`apps/web/README.md`:
```markdown
# Resona Web

Next.js (App Router) frontend for Resona. Reads the local Supabase data layer.

## Dev

1. Start the data layer (repo root): `make start`
2. Copy `.env.example` to `.env.local` and paste the `service_role key` from `npx supabase status`.
3. `npm run dev --workspace apps/web` → http://localhost:3000

## Test

`npm run test --workspace apps/web` (Vitest integration tests; requires the local stack running).

## Notes

- `lib/supabase/server.ts` uses the service-role key (server-only, bypasses RLS) for this foundation slice. Cookie-scoped end-user auth lands in Plan 4b.
```

- [ ] **Step 4: Commit**

```bash
git add apps/web/README.md
git commit -m "docs(web): dev and test instructions"
```

---

## Self-Review

**Spec coverage** (design doc §4/§7 web surfaces):
- Next.js App Router + TS + Tailwind + shadcn/ui → Tasks 1–2 ✓
- RSC data-heavy views (dashboard, agents) → Tasks 4–5 (server components, `force-dynamic`) ✓
- Command center (volume/agents counts) → Task 4 ✓ (subset; sentiment/objection charts deferred to 4b with real call data)
- AgentBuilder (persona, create) → Task 5 ✓ (voice/tools/guardrails fields deferred to 4b)
- Typed DB access from `@resona/db` → Task 3 ✓
- **Deferred to 4b (documented):** cookie auth, CallLibrary, CallPlayer (WaveSurfer), LiveCallMonitor (Supabase Realtime — pairs with the voice service), analytics charts.

**Placeholder scan:** no TBD/TODO; every code step has complete code. The only non-code variability is the service-role key value (pasted from `supabase status`) and possible interactive scaffolder prompts (noted up top).

**Type consistency:** `createServiceClient()` defined in Task 3, used identically in Tasks 4–5. `Database["public"]["Tables"]["agents"]["Row"]` used for `AgentRow`. `getDashboardStats(): DashboardStats` matches its test. `createAgentAction(formData: FormData)` matches the form `action`.

**Open risk:** `create-next-app` / `shadcn` are version-sensitive (Tailwind v4, React 19); accept documented defaults on any prompt. Vitest integration tests require the local Supabase stack running (same model as Plan 1's pgTAP).
