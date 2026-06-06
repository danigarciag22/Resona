begin;
select plan(6);

select has_table('public', 'agents',              'agents table exists');
select has_table('public', 'phone_numbers',       'phone_numbers table exists');
select has_table('public', 'knowledge_bases',     'knowledge_bases table exists');
select has_table('public', 'knowledge_documents', 'knowledge_documents table exists');
select has_table('public', 'knowledge_chunks',    'knowledge_chunks table exists');
select col_type_is('public', 'knowledge_chunks', 'embedding', 'vector(1024)',
                   'knowledge_chunks.embedding is vector(1024)');

select * from finish();
rollback;
