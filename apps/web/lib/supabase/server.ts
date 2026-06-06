import { createClient } from "@supabase/supabase-js";
import type { Database } from "@resona/db";

/**
 * Server-only Supabase client using the service-role key.
 * Bypasses RLS — never import this into a Client Component.
 * Plan 4b replaces dashboard reads with cookie-scoped user sessions.
 */
export function createServiceClient() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
  return createClient<Database>(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
