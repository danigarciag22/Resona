begin;
select plan(2);

select has_function('public', 'match_knowledge_chunks',
       array['vector','uuid','integer'],
       'match_knowledge_chunks(vector, uuid, int) exists');

-- Build unit vectors with a 1.0 at index i (others 0) for deterministic ranking.
create function pg_temp.unit_vec(i int) returns vector(1024)
language sql as $$
  select ('[' || string_agg(case when g = i then '1' else '0' end, ',') || ']')::vector(1024)
  from generate_series(1, 1024) g;
$$;

-- Seed a KB with two chunks pointing in different directions.
insert into auth.users (id, email, aud, role)
values ('44444444-4444-4444-4444-444444444444','d@test.com','authenticated','authenticated');
insert into public.organizations (id, name) values ('dddddddd-dddd-dddd-dddd-dddddddddddd','Org D');
insert into public.memberships (org_id, user_id, role)
values ('dddddddd-dddd-dddd-dddd-dddddddddddd','44444444-4444-4444-4444-444444444444','owner');
insert into public.knowledge_bases (id, org_id, name)
values ('dbdbdbdb-0000-0000-0000-000000000000','dddddddd-dddd-dddd-dddd-dddddddddddd','KB D');
insert into public.knowledge_documents (id, org_id, kb_id, title, status)
values ('ddd0c000-0000-0000-0000-000000000000','dddddddd-dddd-dddd-dddd-dddddddddddd','dbdbdbdb-0000-0000-0000-000000000000','Doc','ready');
insert into public.knowledge_chunks (org_id, document_id, content, embedding)
values ('dddddddd-dddd-dddd-dddd-dddddddddddd','ddd0c000-0000-0000-0000-000000000000','about pricing', pg_temp.unit_vec(1)),
       ('dddddddd-dddd-dddd-dddd-dddddddddddd','ddd0c000-0000-0000-0000-000000000000','about refunds', pg_temp.unit_vec(2));

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"44444444-4444-4444-4444-444444444444"}';

-- Query closest to unit_vec(1) -> 'about pricing' must rank first.
select is(
  (select content from public.match_knowledge_chunks(pg_temp.unit_vec(1),
          'dbdbdbdb-0000-0000-0000-000000000000', 1)),
  'about pricing',
  'match_knowledge_chunks returns the nearest chunk first'
);

reset role;
select * from finish();
rollback;
