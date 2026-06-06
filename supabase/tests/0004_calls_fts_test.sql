begin;
select plan(4);

select has_table('public', 'calls',       'calls table exists');
select has_table('public', 'call_events', 'call_events table exists');
select has_table('public', 'transcripts', 'transcripts table exists');

-- Full-text search works on transcripts.content via generated fts column.
insert into auth.users (id, email, aud, role)
values ('33333333-3333-3333-3333-333333333333','c@test.com','authenticated','authenticated');
insert into public.organizations (id, name) values ('cccccccc-cccc-cccc-cccc-cccccccccccc','Org C');
insert into public.agents (id, org_id, name) values ('c1111111-0000-0000-0000-000000000000','cccccccc-cccc-cccc-cccc-cccccccccccc','Agent C');
insert into public.calls (id, org_id, agent_id, direction, status)
values ('ca000000-0000-0000-0000-000000000000','cccccccc-cccc-cccc-cccc-cccccccccccc','c1111111-0000-0000-0000-000000000000','inbound','completed');
insert into public.transcripts (call_id, org_id, content)
values ('ca000000-0000-0000-0000-000000000000','cccccccc-cccc-cccc-cccc-cccccccccccc',
        'customer asked about pricing and requested a refund');

select is(
  (select count(*)::int from public.transcripts
   where fts @@ to_tsquery('english','refund')),
  1,
  'FTS matches the word "refund" in transcript content'
);

select * from finish();
rollback;
