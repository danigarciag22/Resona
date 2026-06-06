-- Conversation intelligence: analysis, call-level embeddings, compliance, scorecards.

create table public.analyses (
  id                 uuid primary key default gen_random_uuid(),
  call_id            uuid not null references public.calls(id) on delete cascade,
  org_id             uuid not null references public.organizations(id) on delete cascade,
  sentiment          numeric,                       -- -1..1 overall
  sentiment_timeline jsonb not null default '[]'::jsonb,
  topics             jsonb not null default '[]'::jsonb,
  objections         jsonb not null default '[]'::jsonb,
  summary            text,
  action_items       jsonb not null default '[]'::jsonb,
  model              text,
  created_at         timestamptz not null default now()
);
create unique index analyses_call_idx on public.analyses(call_id);

create table public.call_embeddings (
  id        uuid primary key default gen_random_uuid(),
  call_id   uuid not null references public.calls(id) on delete cascade,
  org_id    uuid not null references public.organizations(id) on delete cascade,
  embedding vector(1024)
);
create index call_embeddings_idx
  on public.call_embeddings using hnsw (embedding vector_cosine_ops);

create table public.compliance_flags (
  id        uuid primary key default gen_random_uuid(),
  call_id   uuid not null references public.calls(id) on delete cascade,
  org_id    uuid not null references public.organizations(id) on delete cascade,
  rule      text not null,
  severity  text not null default 'low' check (severity in ('low','medium','high','critical')),
  excerpt   text,
  ts_ms     int,
  resolved  boolean not null default false,
  created_at timestamptz not null default now()
);
create index compliance_flags_call_idx on public.compliance_flags(call_id);

create table public.scorecards (
  id            uuid primary key default gen_random_uuid(),
  call_id       uuid not null references public.calls(id) on delete cascade,
  org_id        uuid not null references public.organizations(id) on delete cascade,
  rep_id        uuid references auth.users(id) on delete set null,
  scores        jsonb not null default '{}'::jsonb,
  coaching_notes text,
  model         text,
  created_at    timestamptz not null default now()
);

-- RLS
alter table public.analyses         enable row level security;
alter table public.call_embeddings  enable row level security;
alter table public.compliance_flags enable row level security;
alter table public.scorecards       enable row level security;

create policy "analyses_select"   on public.analyses         for select using (public.is_member_of(org_id));
create policy "analyses_modify"   on public.analyses         for all    using (public.is_member_of(org_id)) with check (public.is_member_of(org_id));
create policy "callemb_select"    on public.call_embeddings  for select using (public.is_member_of(org_id));
create policy "callemb_modify"    on public.call_embeddings  for all    using (public.is_member_of(org_id)) with check (public.is_member_of(org_id));
create policy "flags_select"      on public.compliance_flags for select using (public.is_member_of(org_id));
create policy "flags_modify"      on public.compliance_flags for all    using (public.is_member_of(org_id)) with check (public.is_member_of(org_id));
create policy "scorecards_select" on public.scorecards       for select using (public.is_member_of(org_id));
create policy "scorecards_modify" on public.scorecards       for all    using (public.is_member_of(org_id)) with check (public.is_member_of(org_id));
