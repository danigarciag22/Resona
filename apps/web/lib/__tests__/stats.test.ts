import { describe, it, expect } from "vitest";
import { createServiceClient } from "../supabase/server";

describe("supabase service client", () => {
  it("connects and reads the seeded org", async () => {
    const db = createServiceClient();
    const { data, error } = await db
      .from("organizations")
      .select("name")
      .eq("id", "00000000-0000-0000-0000-0000000000b0")
      .single();
    expect(error).toBeNull();
    expect(data?.name).toBe("Acme Demo");
  });
});
