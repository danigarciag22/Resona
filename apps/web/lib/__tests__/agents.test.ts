import { describe, it, expect, afterEach } from "vitest";
import { listAgents, createAgent } from "../agents";
import { createServiceClient } from "../supabase/server";

const created: string[] = [];

afterEach(async () => {
  if (created.length) {
    const db = createServiceClient();
    await db.from("agents").delete().in("id", created);
    created.length = 0;
  }
});

describe("agents", () => {
  it("creates an agent and lists it", async () => {
    const agent = await createAgent({
      name: "Test Agent",
      personaPrompt: "be brief",
    });
    created.push(agent.id);
    expect(agent.name).toBe("Test Agent");

    const agents = await listAgents();
    expect(agents.some((a) => a.id === agent.id)).toBe(true);
  });
});
