import { createServiceClient } from "./supabase/server";

export type DashboardStats = {
  agents: number;
  phoneNumbers: number;
  calls: number;
  completedCalls: number;
};

export async function getDashboardStats(): Promise<DashboardStats> {
  const db = createServiceClient();
  const head = { count: "exact" as const, head: true };
  const [agents, phones, calls, completed] = await Promise.all([
    db.from("agents").select("*", head),
    db.from("phone_numbers").select("*", head),
    db.from("calls").select("*", head),
    db.from("calls").select("*", head).eq("status", "completed"),
  ]);
  return {
    agents: agents.count ?? 0,
    phoneNumbers: phones.count ?? 0,
    calls: calls.count ?? 0,
    completedCalls: completed.count ?? 0,
  };
}
