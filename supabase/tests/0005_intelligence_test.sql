begin;
select plan(5);

select has_table('public', 'analyses',         'analyses table exists');
select has_table('public', 'call_embeddings',  'call_embeddings table exists');
select has_table('public', 'compliance_flags', 'compliance_flags table exists');
select has_table('public', 'scorecards',       'scorecards table exists');
select col_type_is('public', 'call_embeddings', 'embedding', 'vector(1024)',
                   'call_embeddings.embedding is vector(1024)');

select * from finish();
rollback;
