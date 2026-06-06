-- Calls, per-call event log, and transcripts with full-text search.

create table public.calls (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid not null references public.organizations(id) on delete cascade,
  agent_id        uuid references public.agents(id) on delete set null,
  phone_number_id uuid references public.phone_numbers(id) on delete set null,
  direction       text not null check (direction in ('inbound','outbound')),
  from_e164       text,
  to_e164         text,
  status          text not null default 'in_progress'
                  check (status in ('in_progress','completed','failed','no_answer')),
  handled_by      text not null default 'ai' check (handled_by in ('ai','human')),
  disposition     text,
  recording_uri   text,
  started_at      timestamptz not null default now(),
  ended_at        timestamptz,
  duration_ms     int
);
create index calls_org_started_idx on public.calls(org_id, started_at desc);
create index calls_agent_idx       on public.calls(agent_id);

-- Append-only event log: tool calls, barge-ins, transfers, per-turn latency spans.
create table public.call_events (
  id        uuid primary key default gen_random_uuid(),
  call_id   uuid not null references public.calls(id) on delete cascade,
  org_id    uuid not null references public.organizations(id) on delete cascade,
  ts        timestamptz not null default now(),
  type      text not null,                 -- 'tool_call' | 'barge_in' | 'transfer' | 'latency_span' | ...
  payload   jsonb not null default '{}'::jsonb
);
create index call_events_call_idx on public.call_events(call_id, ts);

create table public.transcripts (
  id        uuid primary key default gen_random_uuid(),
  call_id   uuid not null references public.calls(id) on delete cascade,
  org_id    uuid not null references public.organizations(id) on delete cascade,
  segments  jsonb not null default '[]'::jsonb,   -- [{speaker,start_ms,end_ms,text}]
  content   text not null default '',             -- flattened transcript for FTS
  fts       tsvector generated always as (to_tsvector('english', coalesce(content,''))) stored,
  created_at timestamptz not null default now()
);
create index transcripts_call_idx on public.transcripts(call_id);
create index transcripts_fts_idx  on public.transcripts using gin (fts);

-- RLS
alter table public.calls       enable row level security;
alter table public.call_events enable row level security;
alter table public.transcripts enable row level security;

create policy "calls_select"  on public.calls       for select using (public.is_member_of(org_id));
create policy "calls_modify"  on public.calls       for all    using (public.is_member_of(org_id)) with check (public.is_member_of(org_id));
create policy "events_select" on public.call_events for select using (public.is_member_of(org_id));
create policy "events_modify" on public.call_events for all    using (public.is_member_of(org_id)) with check (public.is_member_of(org_id));
create policy "trans_select"  on public.transcripts for select using (public.is_member_of(org_id));
create policy "trans_modify"  on public.transcripts for all    using (public.is_member_of(org_id)) with check (public.is_member_of(org_id));
