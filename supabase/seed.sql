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
