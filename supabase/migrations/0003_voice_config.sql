-- Voice agent configuration, phone numbers, and RAG knowledge base.

create table public.knowledge_bases (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  name        text not null,
  created_at  timestamptz not null default now()
);

create table public.knowledge_documents (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  kb_id       uuid not null references public.knowledge_bases(id) on delete cascade,
  source_uri  text,
  title       text,
  status      text not null default 'pending'
              check (status in ('pending','processing','ready','error')),
  created_at  timestamptz not null default now()
);

create table public.knowledge_chunks (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  document_id uuid not null references public.knowledge_documents(id) on delete cascade,
  content     text not null,
  token_count int,
  embedding   vector(1024),
  created_at  timestamptz not null default now()
);
create index knowledge_chunks_doc_idx on public.knowledge_chunks(document_id);
create index knowledge_chunks_embedding_idx
  on public.knowledge_chunks using hnsw (embedding vector_cosine_ops);

create table public.agents (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid not null references public.organizations(id) on delete cascade,
  name              text not null,
  voice_id          text,                          -- Cartesia voice id
  persona_prompt    text not null default '',
  llm_model         text not null default 'claude-haiku-4-5',
  tools             jsonb not null default '[]'::jsonb,
  knowledge_base_id uuid references public.knowledge_bases(id) on delete set null,
  guardrails        jsonb not null default '{}'::jsonb,
  created_at        timestamptz not null default now()
);
create index agents_org_idx on public.agents(org_id);

create table public.phone_numbers (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null references public.organizations(id) on delete cascade,
  provider      text not null default 'twilio',
  e164          text not null unique,
  agent_id      uuid references public.agents(id) on delete set null,
  capabilities  jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now()
);

-- RLS
alter table public.knowledge_bases     enable row level security;
alter table public.knowledge_documents enable row level security;
alter table public.knowledge_chunks    enable row level security;
alter table public.agents              enable row level security;
alter table public.phone_numbers       enable row level security;

create policy "kb_select"   on public.knowledge_bases     for select using (public.is_member_of(org_id));
create policy "kb_modify"   on public.knowledge_bases     for all    using (public.is_member_of(org_id)) with check (public.is_member_of(org_id));
create policy "kd_select"   on public.knowledge_documents for select using (public.is_member_of(org_id));
create policy "kd_modify"   on public.knowledge_documents for all    using (public.is_member_of(org_id)) with check (public.is_member_of(org_id));
create policy "kc_select"   on public.knowledge_chunks    for select using (public.is_member_of(org_id));
create policy "kc_modify"   on public.knowledge_chunks    for all    using (public.is_member_of(org_id)) with check (public.is_member_of(org_id));
create policy "agents_select" on public.agents            for select using (public.is_member_of(org_id));
create policy "agents_modify" on public.agents            for all    using (public.is_member_of(org_id)) with check (public.is_member_of(org_id));
create policy "phones_select" on public.phone_numbers     for select using (public.is_member_of(org_id));
create policy "phones_modify" on public.phone_numbers     for all    using (public.is_member_of(org_id)) with check (public.is_member_of(org_id));
