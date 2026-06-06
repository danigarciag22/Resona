import { createServiceClient } from "./supabase/server";
import type { Database } from "@resona/db";

const DEMO_ORG = "00000000-0000-0000-0000-0000000000b0";
type AgentRow = Database["public"]["Tables"]["agents"]["Row"];

export async function listAgents(orgId: string = DEMO_ORG): Promise<AgentRow[]> {
  const db = createServiceClient();
  const { data, error } = await db
    .from("agents")
    .select("*")
    .eq("org_id", orgId)
    .order("created_at", { ascending: false });
  if (error) throw new Error(error.message);
  return data ?? [];
}

export async function createAgent(input: {
  name: string;
  personaPrompt?: string;
  orgId?: string;
}): Promise<AgentRow> {
  const db = createServiceClient();
  const { data, error } = await db
    .from("agents")
    .insert({
      org_id: input.orgId ?? DEMO_ORG,
      name: input.name,
      persona_prompt: input.personaPrompt ?? "",
    })
    .select()
    .single();
  if (error) throw new Error(error.message);
  return data;
}
