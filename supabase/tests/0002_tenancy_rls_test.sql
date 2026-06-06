begin;
select plan(5);

select has_table('public', 'organizations', 'organizations table exists');
select has_table('public', 'memberships',   'memberships table exists');
select has_function('public', 'is_member_of', array['uuid'], 'is_member_of(uuid) exists');

-- Seed two tenants as superuser (RLS bypassed during setup).
insert into auth.users (id, email, aud, role)
values ('11111111-1111-1111-1111-111111111111','a@test.com','authenticated','authenticated'),
       ('22222222-2222-2222-2222-222222222222','b@test.com','authenticated','authenticated');

insert into public.organizations (id, name)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Org A'),
       ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Org B');

insert into public.memberships (org_id, user_id, role)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111','owner'),
       ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','22222222-2222-2222-2222-222222222222','owner');

-- Act as user A (RLS now applies).
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"11111111-1111-1111-1111-111111111111"}';

select is((select count(*)::int from public.organizations), 1,
          'user A sees exactly one organization (their own)');
select is((select count(*)::int from public.organizations
           where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), 0,
          'user A cannot see Org B');

reset role;
select * from finish();
rollback;
