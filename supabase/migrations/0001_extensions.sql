-- Required extensions for Resona's data layer.
create extension if not exists vector;      -- semantic search (embeddings)
create extension if not exists pgtap;       -- database unit tests
-- gen_random_uuid() is provided by pgcrypto, preinstalled on Supabase.
