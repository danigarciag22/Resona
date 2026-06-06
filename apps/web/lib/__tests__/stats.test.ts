import { describe, it, expect } from "vitest";
import { getDashboardStats } from "../stats";

describe("getDashboardStats", () => {
  it("returns seeded counts", async () => {
    const stats = await getDashboardStats();
    expect(stats.agents).toBe(1); // seed: Acme Scheduler
    expect(stats.phoneNumbers).toBe(1); // seed: +15555550100
    expect(stats.calls).toBe(2); // seed now has 2 sample calls
    expect(stats.completedCalls).toBe(2);
  });
});
