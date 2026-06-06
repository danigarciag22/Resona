-- Third-party integrations (CRM, calendar) and an audit trail.
-- token_ref points to a secret in the app's secrets manager; never store raw tokens.

create table public.integrations (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid not null references public.organizations(id) on delete cascade,
  provider   text not null,                  -- 'hubspot' | 'salesforce' | 'google_calendar' | 'cal_com' | ...
  status     text not null default 'disconnected'
             check (status in ('disconnected','connected','error')),
  token_ref  text,
  created_at timestamptz not null default now(),
  unique (org_id, provider)
);

create table public.audit_log (
  id        uuid primary key default gen_random_uuid(),
  org_id    uuid not null references public.organizations(id) on delete cascade,
  actor     uuid references auth.users(id) on delete set null,
  action    text not null,
  target    text,
  ts        timestamptz not null default now(),
  metadata  jsonb not null default '{}'::jsonb
);
create index audit_log_org_ts_idx on public.audit_log(org_id, ts desc);

-- RLS
alter table public.integrations enable row level security;
alter table public.audit_log    enable row level security;

create policy "integrations_select" on public.integrations for select using (public.is_member_of(org_id));
create policy "integrations_modify" on public.integrations for all    using (public.is_member_of(org_id)) with check (public.is_member_of(org_id));
-- Audit log is read-only to org members; writes happen via service role only.
create policy "audit_select" on public.audit_log for select using (public.is_member_of(org_id));
