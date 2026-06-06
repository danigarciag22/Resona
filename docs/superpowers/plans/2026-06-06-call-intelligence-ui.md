# Call Intelligence UI (Plan 4b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the conversation-intelligence UI — a searchable CallLibrary and a CallPlayer (transcript + insights + WaveSurfer audio) — over seeded sample calls/transcripts/analyses, with Postgres full-text search, all verified by Vitest.

**Architecture:** Extends `apps/web` (Plan 4a). New typed data functions (`lib/calls.ts`) read calls/transcripts/analyses through the existing service-role Supabase client. CallLibrary and CallPlayer are RSC pages; the waveform is a small `"use client"` WaveSurfer component. Sample data is added to `supabase/seed.sql` (including a generated 8 kHz WAV so the player actually plays audio). Cookie auth, LiveCallMonitor, and semantic (vector) search stay deferred — semantic search needs the Voyage embedder from Plan 2b/3.

**Tech Stack:** Next.js (App Router) + shadcn/ui (Plan 4a), `wavesurfer.js`, Supabase FTS (`websearch_to_tsquery`), Vitest.

> **Prereq:** local Supabase running (`make start`). Seed changes apply via `npm run db:reset`.

---

## File Structure

```
supabase/seed.sql                        # MODIFY: 2 calls + transcripts + analyses
apps/web/public/sample-call.wav          # GENERATED: 8 kHz demo tone for CallPlayer
apps/web/lib/calls.ts                     # listCalls, getCallDetail, searchCalls (FTS)
apps/web/lib/__tests__/calls.test.ts
apps/web/lib/__tests__/stats.test.ts      # MODIFY: counts now reflect seeded calls
apps/web/components/waveform.tsx          # "use client" WaveSurfer player
apps/web/components/app-shell.tsx         # MODIFY: add Calls nav link
apps/web/app/calls/page.tsx               # CallLibrary (list + FTS search)
apps/web/app/calls/[id]/page.tsx          # CallPlayer (transcript + insights + audio)
```

---

## Task 1: Seed sample calls + generate demo audio; fix stats test

**Files:**
- Modify: `supabase/seed.sql`
- Generate: `apps/web/public/sample-call.wav`
- Modify: `apps/web/lib/__tests__/stats.test.ts`

- [ ] **Step 1: Append sample intelligence data to `supabase/seed.sql`**

Append to `supabase/seed.sql`:
```sql
-- Sample calls + transcripts + analyses for the Call Intelligence UI (Plan 4b).
insert into public.calls (id, org_id, agent_id, direction, status, handled_by,
                          from_e164, to_e164, recording_uri, duration_ms, started_at, ended_at)
values
  ('00000000-0000-0000-0000-00000000ca01','00000000-0000-0000-0000-0000000000b0',
   '00000000-0000-0000-0000-0000000000d0','inbound','completed','ai',
   '+15551110001','+15555550100','/sample-call.wav', 184000,
   '2026-06-05 15:00:00+00','2026-06-05 15:03:04+00'),
  ('00000000-0000-0000-0000-00000000ca02','00000000-0000-0000-0000-0000000000b0',
   '00000000-0000-0000-0000-0000000000d0','inbound','completed','ai',
   '+15551110002','+15555550100', null, 92000,
   '2026-06-05 16:30:00+00','2026-06-05 16:31:32+00')
on conflict (id) do nothing;

insert into public.transcripts (call_id, org_id, segments, content)
values
  ('00000000-0000-0000-0000-00000000ca01','00000000-0000-0000-0000-0000000000b0',
   '[{"speaker":"agent","start_ms":0,"end_ms":3000,"text":"Thanks for calling Acme, how can I help?"},
     {"speaker":"customer","start_ms":3200,"end_ms":8000,"text":"I want to know about pricing and a refund for the annual plan."},
     {"speaker":"agent","start_ms":8200,"end_ms":12000,"text":"Happy to help with pricing and your refund."}]'::jsonb,
   'Thanks for calling Acme, how can I help? I want to know about pricing and a refund for the annual plan. Happy to help with pricing and your refund.'),
  ('00000000-0000-0000-0000-00000000ca02','00000000-0000-0000-0000-0000000000b0',
   '[{"speaker":"agent","start_ms":0,"end_ms":2500,"text":"Acme scheduling, how can I help?"},
     {"speaker":"customer","start_ms":2700,"end_ms":7000,"text":"I would like to schedule a cleaning next Tuesday morning."}]'::jsonb,
   'Acme scheduling, how can I help? I would like to schedule a cleaning next Tuesday morning.')
on conflict do nothing;

insert into public.analyses (call_id, org_id, sentiment, topics, objections, summary, action_items, model)
values
  ('00000000-0000-0000-0000-00000000ca01','00000000-0000-0000-0000-0000000000b0',
   0.35, '["pricing","refund","annual plan"]'::jsonb, '["price too high"]'::jsonb,
   'Customer asked about pricing and requested a refund on the annual plan. Agent agreed to help.',
   '["Process annual-plan refund","Send pricing breakdown"]'::jsonb, 'claude-sonnet-4-6'),
  ('00000000-0000-0000-0000-00000000ca02','00000000-0000-0000-0000-0000000000b0',
   0.80, '["scheduling","cleaning"]'::jsonb, '[]'::jsonb,
   'Customer requested a cleaning appointment for Tuesday morning.',
   '["Book cleaning for Tuesday AM"]'::jsonb, 'claude-sonnet-4-6')
on conflict do nothing;
```

- [ ] **Step 2: Generate the demo WAV (8 kHz mono, matches telephony narrowband)**

Run from repo root:
```bash
python3 - <<'PY'
import wave, struct, math, os
os.makedirs('apps/web/public', exist_ok=True)
sr, dur, freq = 8000, 2.0, 440.0
w = wave.open('apps/web/public/sample-call.wav', 'w')
w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
for i in range(int(sr*dur)):
    w.writeframesraw(struct.pack('<h', int(3000*math.sin(2*math.pi*freq*i/sr))))
w.close()
print('wrote apps/web/public/sample-call.wav')
PY
```
Expected: prints the path; file is ~32 KB.

- [ ] **Step 3: Apply the seed**

Run: `npm run db:reset`
Expected: migrations + seed apply cleanly (no errors on the new inserts).

- [ ] **Step 4: Update `stats.test.ts` for the new seed counts**

Replace the count assertions in `apps/web/lib/__tests__/stats.test.ts`:
```ts
import { describe, it, expect } from "vitest";
import { getDashboardStats } from "../stats";

describe("getDashboardStats", () => {
  it("returns seeded counts", async () => {
    const stats = await getDashboardStats();
    expect(stats.agents).toBe(1);
    expect(stats.phoneNumbers).toBe(1);
    expect(stats.calls).toBe(2); // seed now has 2 sample calls
    expect(stats.completedCalls).toBe(2);
  });
});
```

- [ ] **Step 5: Verify stats test passes**

Run: `npm run test --workspace apps/web`
Expected: PASS (stats now expects 2 calls; agents test unaffected).

- [ ] **Step 6: Commit**

```bash
git add supabase/seed.sql apps/web/public/sample-call.wav apps/web/lib/__tests__/stats.test.ts
git commit -m "feat(db,web): seed sample calls/transcripts/analyses and demo audio"
```

---

## Task 2: Call data functions (TDD)

**Files:**
- Create: `apps/web/lib/calls.ts`, `apps/web/lib/__tests__/calls.test.ts`

- [ ] **Step 1: Write the failing test**

`apps/web/lib/__tests__/calls.test.ts`:
```ts
import { describe, it, expect } from "vitest";
import { listCalls, getCallDetail, searchCalls } from "../calls";

const CALL_A = "00000000-0000-0000-0000-00000000ca01";

describe("calls", () => {
  it("lists seeded calls", async () => {
    const calls = await listCalls();
    expect(calls.length).toBe(2);
    expect(calls.map((c) => c.id)).toContain(CALL_A);
  });

  it("full-text searches transcripts", async () => {
    const hits = await searchCalls("refund");
    expect(hits.length).toBe(1);
    expect(hits[0].id).toBe(CALL_A);
  });

  it("returns call detail with transcript and analysis", async () => {
    const detail = await getCallDetail(CALL_A);
    expect(detail.call?.id).toBe(CALL_A);
    expect(detail.transcript?.content).toContain("refund");
    expect(detail.analysis?.summary).toBeTruthy();
    expect(detail.analysis?.topics).toContain("refund");
  });
});
```

- [ ] **Step 2: Run test, expect fail**

Run: `npm run test --workspace apps/web`
Expected: FAIL — `../calls` missing.

- [ ] **Step 3: Implement `lib/calls.ts`**

`apps/web/lib/calls.ts`:
```ts
import { createServiceClient } from "./supabase/server";
import type { Database } from "@resona/db";

const DEMO_ORG = "00000000-0000-0000-0000-0000000000b0";
type CallRow = Database["public"]["Tables"]["calls"]["Row"];
type TranscriptRow = Database["public"]["Tables"]["transcripts"]["Row"];
type AnalysisRow = Database["public"]["Tables"]["analyses"]["Row"];

export async function listCalls(orgId: string = DEMO_ORG): Promise<CallRow[]> {
  const db = createServiceClient();
  const { data, error } = await db
    .from("calls")
    .select("*")
    .eq("org_id", orgId)
    .order("started_at", { ascending: false });
  if (error) throw new Error(error.message);
  return data ?? [];
}

export async function searchCalls(
  query: string,
  orgId: string = DEMO_ORG,
): Promise<CallRow[]> {
  const db = createServiceClient();
  // Match transcripts via the generated tsvector, then load the parent calls.
  const { data: hits, error } = await db
    .from("transcripts")
    .select("call_id")
    .eq("org_id", orgId)
    .textSearch("fts", query, { type: "websearch", config: "english" });
  if (error) throw new Error(error.message);
  const ids = (hits ?? []).map((h) => h.call_id);
  if (ids.length === 0) return [];
  const { data, error: callErr } = await db
    .from("calls")
    .select("*")
    .in("id", ids)
    .order("started_at", { ascending: false });
  if (callErr) throw new Error(callErr.message);
  return data ?? [];
}

export type CallDetail = {
  call: CallRow | null;
  transcript: TranscriptRow | null;
  analysis: AnalysisRow | null;
};

export async function getCallDetail(id: string): Promise<CallDetail> {
  const db = createServiceClient();
  const [call, transcript, analysis] = await Promise.all([
    db.from("calls").select("*").eq("id", id).maybeSingle(),
    db.from("transcripts").select("*").eq("call_id", id).maybeSingle(),
    db.from("analyses").select("*").eq("call_id", id).maybeSingle(),
  ]);
  return {
    call: call.data,
    transcript: transcript.data,
    analysis: analysis.data,
  };
}
```

- [ ] **Step 4: Run test, expect pass**

Run: `npm run test --workspace apps/web`
Expected: PASS (stats + agents + 3 calls tests).

- [ ] **Step 5: Commit**

```bash
git add apps/web/lib/calls.ts apps/web/lib/__tests__/calls.test.ts
git commit -m "feat(web): call data functions with full-text search"
```

---

## Task 3: CallLibrary page + nav

**Files:**
- Create: `apps/web/app/calls/page.tsx`
- Modify: `apps/web/components/app-shell.tsx`

- [ ] **Step 1: Add the Calls nav link**

In `apps/web/components/app-shell.tsx`, add a link after the Agents link:
```tsx
          <Link className="rounded px-2 py-1.5 hover:bg-muted" href="/calls">
            Calls
          </Link>
```

- [ ] **Step 2: Create the CallLibrary page**

`apps/web/app/calls/page.tsx`:
```tsx
import Link from "next/link";
import { listCalls, searchCalls } from "@/lib/calls";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";

export const dynamic = "force-dynamic";

export default async function CallsPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>;
}) {
  const { q } = await searchParams;
  const query = (q ?? "").trim();
  const calls = query ? await searchCalls(query) : await listCalls();

  return (
    <div className="max-w-4xl">
      <h1 className="mb-6 text-2xl font-bold">Call Library</h1>

      <form action="/calls" method="get" className="mb-6 flex gap-2">
        <Input
          name="q"
          defaultValue={query}
          placeholder="Search transcripts (e.g. refund)"
        />
        <Button type="submit">Search</Button>
      </form>

      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Direction</TableHead>
            <TableHead>Status</TableHead>
            <TableHead>Duration</TableHead>
            <TableHead>Started</TableHead>
            <TableHead></TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {calls.map((c) => (
            <TableRow key={c.id}>
              <TableCell className="capitalize">{c.direction}</TableCell>
              <TableCell className="capitalize">{c.status}</TableCell>
              <TableCell>
                {c.duration_ms ? `${Math.round(c.duration_ms / 1000)}s` : "—"}
              </TableCell>
              <TableCell>
                {c.started_at ? new Date(c.started_at).toLocaleString() : "—"}
              </TableCell>
              <TableCell>
                <Link className="text-sky-600 hover:underline" href={`/calls/${c.id}`}>
                  Open
                </Link>
              </TableCell>
            </TableRow>
          ))}
          {calls.length === 0 && (
            <TableRow>
              <TableCell colSpan={5} className="text-muted-foreground">
                No calls{query ? ` matching “${query}”` : ""}.
              </TableCell>
            </TableRow>
          )}
        </TableBody>
      </Table>
    </div>
  );
}
```

- [ ] **Step 3: Build**

Run: `npm run build --workspace apps/web`
Expected: build succeeds; `/calls` compiles.

- [ ] **Step 4: Commit**

```bash
git add apps/web/app/calls/page.tsx apps/web/components/app-shell.tsx
git commit -m "feat(web): CallLibrary page with transcript search"
```

---

## Task 4: CallPlayer page + WaveSurfer

**Files:**
- Create: `apps/web/components/waveform.tsx`
- Create: `apps/web/app/calls/[id]/page.tsx`
- Modify: `apps/web/package.json` (add wavesurfer.js)

- [ ] **Step 1: Install WaveSurfer**

Run: `npm install --workspace apps/web wavesurfer.js`
Expected: adds `wavesurfer.js` to `apps/web` dependencies.

- [ ] **Step 2: Create the client waveform component**

`apps/web/components/waveform.tsx`:
```tsx
"use client";

import { useEffect, useRef, useState } from "react";
import WaveSurfer from "wavesurfer.js";
import { Button } from "@/components/ui/button";

export function Waveform({ url }: { url: string }) {
  const containerRef = useRef<HTMLDivElement>(null);
  const wsRef = useRef<WaveSurfer | null>(null);
  const [playing, setPlaying] = useState(false);

  useEffect(() => {
    if (!containerRef.current) return;
    const ws = WaveSurfer.create({
      container: containerRef.current,
      url,
      height: 64,
      waveColor: "#94a3b8",
      progressColor: "#0ea5e9",
      cursorColor: "#0ea5e9",
    });
    ws.on("play", () => setPlaying(true));
    ws.on("pause", () => setPlaying(false));
    ws.on("finish", () => setPlaying(false));
    wsRef.current = ws;
    return () => {
      ws.destroy();
      wsRef.current = null;
    };
  }, [url]);

  return (
    <div className="space-y-2">
      <div ref={containerRef} className="rounded border bg-muted/30 p-2" />
      <Button type="button" variant="outline" onClick={() => wsRef.current?.playPause()}>
        {playing ? "Pause" : "Play"}
      </Button>
    </div>
  );
}
```

- [ ] **Step 3: Create the CallPlayer page**

`apps/web/app/calls/[id]/page.tsx`:
```tsx
import { notFound } from "next/navigation";
import { getCallDetail } from "@/lib/calls";
import { Waveform } from "@/components/waveform";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

export const dynamic = "force-dynamic";

type Segment = { speaker: string; start_ms: number; end_ms: number; text: string };

export default async function CallPlayerPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const { call, transcript, analysis } = await getCallDetail(id);
  if (!call) notFound();

  const segments = (transcript?.segments as Segment[] | null) ?? [];
  const topics = (analysis?.topics as string[] | null) ?? [];
  const actionItems = (analysis?.action_items as string[] | null) ?? [];

  return (
    <div className="grid max-w-5xl gap-6 md:grid-cols-[2fr_1fr]">
      <div className="space-y-6">
        <h1 className="text-2xl font-bold">Call {call.id.slice(0, 8)}</h1>

        <Card>
          <CardHeader>
            <CardTitle className="text-sm text-muted-foreground">Recording</CardTitle>
          </CardHeader>
          <CardContent>
            {call.recording_uri ? (
              <Waveform url={call.recording_uri} />
            ) : (
              <p className="text-sm text-muted-foreground">
                No recording (live voice pipeline pending — Plan 2b).
              </p>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-sm text-muted-foreground">Transcript</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            {segments.map((s, i) => (
              <p key={i} className="text-sm">
                <span className="font-semibold capitalize">{s.speaker}: </span>
                {s.text}
              </p>
            ))}
            {segments.length === 0 && (
              <p className="text-sm text-muted-foreground">No transcript.</p>
            )}
          </CardContent>
        </Card>
      </div>

      <div className="space-y-6">
        <Card>
          <CardHeader>
            <CardTitle className="text-sm text-muted-foreground">Insights</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3 text-sm">
            <div>
              <div className="font-semibold">Sentiment</div>
              <div>{analysis?.sentiment ?? "—"}</div>
            </div>
            <div>
              <div className="font-semibold">Topics</div>
              <div>{topics.join(", ") || "—"}</div>
            </div>
            <div>
              <div className="font-semibold">Summary</div>
              <div>{analysis?.summary ?? "—"}</div>
            </div>
            <div>
              <div className="font-semibold">Action items</div>
              <ul className="list-disc pl-5">
                {actionItems.map((a, i) => (
                  <li key={i}>{a}</li>
                ))}
                {actionItems.length === 0 && <li className="list-none">—</li>}
              </ul>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Build**

Run: `npm run build --workspace apps/web`
Expected: build succeeds; `/calls/[id]` compiles (dynamic). WaveSurfer is client-only so it must not break SSR.

- [ ] **Step 5: Commit**

```bash
git add apps/web/components/waveform.tsx apps/web/app/calls apps/web/package.json package-lock.json
git commit -m "feat(web): CallPlayer with WaveSurfer audio, transcript, and insights"
```

---

## Task 5: Verify running app + finish

**Files:** none (verification)

- [ ] **Step 1: Full web test suite**

Run: `npm run test --workspace apps/web`
Expected: all pass (stats, agents, 3 calls).

- [ ] **Step 2: Manual route check**

```bash
cd apps/web && pkill -f "next dev" 2>/dev/null; npm run dev -- --port 3100 > /tmp/web-4b.log 2>&1 &
sleep 0  # use curl --retry instead
BASE=http://localhost:3100
curl -sS --retry 25 --retry-delay 1 --retry-connrefused -o /dev/null -w "calls %{http_code}\n" "$BASE/calls"
curl -sS -o /dev/null -w "search %{http_code}\n" "$BASE/calls?q=refund"
curl -sS -o /dev/null -w "player %{http_code}\n" "$BASE/calls/00000000-0000-0000-0000-00000000ca01"
curl -sS -o /dev/null -w "sample.wav %{http_code}\n" "$BASE/sample-call.wav"
pkill -f "next dev" 2>/dev/null
```
Expected: all `200`.

- [ ] **Step 3: Commit any final touch-ups, then this plan is done.**

(No code change expected; proceed to finishing-a-development-branch.)

---

## Self-Review

**Spec coverage** (design doc §4 components):
- CallLibrary (searchable transcripts) → Tasks 2–3 (FTS via `websearch_to_tsquery`) ✓
- CallPlayer (audio synced to transcript + insight timeline) → Task 4 (WaveSurfer + segments + insights) ✓
- Uses Plan 1 FTS index (`transcripts.fts`) ✓
- **Deferred:** semantic/vector call search (needs Voyage embedder — Plan 2b/3), cookie auth, LiveCallMonitor (Realtime + voice service), analytics charts.

**Placeholder scan:** no TBD/TODO; all code complete. The WAV is generated by a concrete stdlib script.

**Type consistency:** `CallRow`/`TranscriptRow`/`AnalysisRow` from `Database[...]["Row"]` used in `lib/calls.ts` and pages. `getCallDetail` returns `CallDetail` ({call, transcript, analysis}) consumed identically by the player. `searchCalls`/`listCalls` return `CallRow[]` consumed by CallLibrary. Next 16 async `params`/`searchParams` are `Promise<...>` and awaited (per Next 16 docs).

**Open risk:** `wavesurfer.js` is client-only; the `"use client"` boundary on `waveform.tsx` keeps it out of SSR. `textSearch("fts", q, {type:"websearch"})` targets the generated tsvector column — if PostgREST rejects the column name, fall back to an RPC `search_calls_fts(q)`. Seeded call counts (2) are reflected in the updated stats test.
