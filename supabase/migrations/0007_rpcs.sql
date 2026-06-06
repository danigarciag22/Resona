-- Retrieval RPCs. SECURITY INVOKER (default) => caller RLS applies.

create or replace function public.match_knowledge_chunks(
  query_embedding vector(1024),
  p_kb            uuid,
  match_count     int default 5
)
returns table (id uuid, content text, similarity float)
language sql
stable
as $$
  select kc.id,
         kc.content,
         1 - (kc.embedding <=> query_embedding) as similarity
  from public.knowledge_chunks kc
  join public.knowledge_documents kd on kd.id = kc.document_id
  where kd.kb_id = p_kb
    and kc.embedding is not null
  order by kc.embedding <=> query_embedding
  limit match_count;
$$;

create or replace function public.match_calls(
  query_embedding vector(1024),
  p_org           uuid,
  match_count     int default 10
)
returns table (call_id uuid, similarity float)
language sql
stable
as $$
  select ce.call_id,
         1 - (ce.embedding <=> query_embedding) as similarity
  from public.call_embeddings ce
  where ce.org_id = p_org
    and ce.embedding is not null
  order by ce.embedding <=> query_embedding
  limit match_count;
$$;

grant execute on function public.match_knowledge_chunks(vector, uuid, int) to authenticated;
grant execute on function public.match_calls(vector, uuid, int) to authenticated;
