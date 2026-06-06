"use server";

import { revalidatePath } from "next/cache";
import { createAgent } from "@/lib/agents";

export async function createAgentAction(formData: FormData) {
  const name = String(formData.get("name") ?? "").trim();
  if (!name) return;
  await createAgent({
    name,
    personaPrompt: String(formData.get("persona") ?? ""),
  });
  revalidatePath("/agents");
}
