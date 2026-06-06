import { defineConfig } from "vitest/config";
import { config } from "dotenv";

config({ path: ".env.local" });

export default defineConfig({
  test: {
    environment: "node",
    include: ["lib/**/*.test.ts"],
    // Integration tests share one local Postgres; run files serially so a
    // transient insert in one file can't perturb exact-count asserts in another.
    fileParallelism: false,
  },
});
