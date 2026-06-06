# Resona Web

Next.js (App Router) frontend for Resona. Reads the local Supabase data layer.

## Dev

1. Start the data layer (repo root): `make start`
2. Copy `.env.example` to `.env.local` and paste the `service_role key` from `npx supabase status`.
3. `npm run dev --workspace apps/web` → http://localhost:3000

## Test

`npm run test --workspace apps/web` — Vitest integration tests. Requires the local Supabase stack running (`make start`). Files run serially (shared Postgres).

## Routes

- `/dashboard` — command center; live counts from the DB (dynamic).
- `/agents` — AgentBuilder; list + create agents via a Server Action.
- `/` — redirects to `/dashboard`.

## Notes

- `lib/supabase/server.ts` uses the service-role key (server-only, bypasses RLS) for this foundation slice. Cookie-scoped end-user auth lands in Plan 4b, along with CallLibrary, CallPlayer, and the LiveCallMonitor (Supabase Realtime).
