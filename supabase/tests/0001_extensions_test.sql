begin;
select plan(2);

select has_extension('vector', 'pgvector extension is installed');
select has_extension('pgtap',  'pgtap extension is installed');

select * from finish();
rollback;
