import { describe, it, expect } from "vitest";
import { listCalls, getCallDetail, searchCalls } from "../calls";

const CALL_A = "00000000-0000-0000-0000-00000000ca01";

describe("calls", () => {
  it("lists seeded calls", async () => {
    const calls = await listCalls();
    expect(calls.length).toBe(2);
    expect(calls.map((c) => c.id)).toContain(CALL_A);
  });

  it("full-text searches transcripts", async () => {
    const hits = await searchCalls("refund");
    expect(hits.length).toBe(1);
    expect(hits[0].id).toBe(CALL_A);
  });

  it("returns call detail with transcript and analysis", async () => {
    const detail = await getCallDetail(CALL_A);
    expect(detail.call?.id).toBe(CALL_A);
    expect(detail.transcript?.content).toContain("refund");
    expect(detail.analysis?.summary).toBeTruthy();
    expect(detail.analysis?.topics).toContain("refund");
  });
});
