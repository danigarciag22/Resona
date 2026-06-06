begin;
select plan(2);

select has_table('public', 'integrations', 'integrations table exists');
select has_table('public', 'audit_log',    'audit_log table exists');

select * from finish();
rollback;
