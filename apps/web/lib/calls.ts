import { createServiceClient } from "./supabase/server";
import type { Database } from "@resona/db";

const DEMO_ORG = "00000000-0000-0000-0000-0000000000b0";
type CallRow = Database["public"]["Tables"]["calls"]["Row"];
type TranscriptRow = Database["public"]["Tables"]["transcripts"]["Row"];
type AnalysisRow = Database["public"]["Tables"]["analyses"]["Row"];

export async function listCalls(orgId: string = DEMO_ORG): Promise<CallRow[]> {
  const db = createServiceClient();
  const { data, error } = await db
    .from("calls")
    .select("*")
    .eq("org_id", orgId)
    .order("started_at", { ascending: false });
  if (error) throw new Error(error.message);
  return data ?? [];
}

export async function searchCalls(
  query: string,
  orgId: string = DEMO_ORG,
): Promise<CallRow[]> {
  const db = createServiceClient();
  // Match transcripts via the generated tsvector, then load the parent calls.
  const { data: hits, error } = await db
    .from("transcripts")
    .select("call_id")
    .eq("org_id", orgId)
    .textSearch("fts", query, { type: "websearch", config: "english" });
  if (error) throw new Error(error.message);
  const ids = (hits ?? []).map((h) => h.call_id);
  if (ids.length === 0) return [];
  const { data, error: callErr } = await db
    .from("calls")
    .select("*")
    .in("id", ids)
    .order("started_at", { ascending: false });
  if (callErr) throw new Error(callErr.message);
  return data ?? [];
}

export type CallDetail = {
  call: CallRow | null;
  transcript: TranscriptRow | null;
  analysis: AnalysisRow | null;
};

export async function getCallDetail(id: string): Promise<CallDetail> {
  const db = createServiceClient();
  const [call, transcript, analysis] = await Promise.all([
    db.from("calls").select("*").eq("id", id).maybeSingle(),
    db.from("transcripts").select("*").eq("call_id", id).maybeSingle(),
    db.from("analyses").select("*").eq("call_id", id).maybeSingle(),
  ]);
  return {
    call: call.data,
    transcript: transcript.data,
    analysis: analysis.data,
  };
}
