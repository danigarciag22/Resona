-- Demo tenant for local development. Applied automatically by `supabase db reset`.
insert into auth.users (id, email, aud, role)
values ('00000000-0000-0000-0000-0000000000aa','demo@resona.dev','authenticated','authenticated')
on conflict (id) do nothing;

insert into public.organizations (id, name)
values ('00000000-0000-0000-0000-0000000000b0','Acme Demo')
on conflict (id) do nothing;

insert into public.memberships (org_id, user_id, role)
values ('00000000-0000-0000-0000-0000000000b0','00000000-0000-0000-0000-0000000000aa','owner')
on conflict do nothing;

insert into public.knowledge_bases (id, org_id, name)
values ('00000000-0000-0000-0000-0000000000c0','00000000-0000-0000-0000-0000000000b0','Acme FAQ')
on conflict (id) do nothing;

insert into public.agents (id, org_id, name, voice_id, persona_prompt, knowledge_base_id, tools)
values ('00000000-0000-0000-0000-0000000000d0','00000000-0000-0000-0000-0000000000b0',
        'Acme Scheduler', 'cartesia-default',
        'You are Acme''s friendly scheduling assistant. Be concise and warm.',
        '00000000-0000-0000-0000-0000000000c0',
        '["book_appointment","search_knowledge_base"]'::jsonb)
on conflict (id) do nothing;

insert into public.phone_numbers (id, org_id, e164, agent_id)
values ('00000000-0000-0000-0000-0000000000e0','00000000-0000-0000-0000-0000000000b0',
        '+15555550100','00000000-0000-0000-0000-0000000000d0')
on conflict (id) do nothing;

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
