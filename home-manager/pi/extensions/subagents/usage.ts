// A finished task's tokens and cost as a `Usage`, so its calls reach the main session's totals. What its own model
// wrote goes as `output` and the rest as `input`; the cache split is not something a task records per direction.

import type { Usage } from "@earendil-works/pi-ai";

export function usageFrom(tokens: number, cost: number, generated = 0): Usage {
  const output = Math.min(Math.max(0, generated), tokens);
  return {
    input: tokens - output,
    output,
    cacheRead: 0,
    cacheWrite: 0,
    totalTokens: tokens,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: cost },
  };
}
