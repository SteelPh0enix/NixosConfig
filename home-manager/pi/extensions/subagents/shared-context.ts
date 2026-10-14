// Fair sharing of a --kv-unified llama.cpp pool. llama-compat registers the per-slot safe window (`pool / slots`)
// so the main session can never overrun it; a subagent, though, can be told how many peers are actually running and
// take an equal slice of the whole pool instead, so one task runs at the full window and N tasks split it.
// Node-only: the check loads it directly.

import type { LlamaShared, TaskRecord } from "./task-record.ts";

/** The pool metadata llama-compat attaches to a unified model; absent for anything else. */
export function llamaShared(model: unknown): LlamaShared | undefined {
  const value = (model as { llamaShared?: Partial<LlamaShared> } | undefined)?.llamaShared;
  const { pool, slots } = value ?? {};
  return typeof pool === "number" && pool > 0 && typeof slots === "number" && slots > 1 ? { pool, slots } : undefined;
}

/** One task's equal slice of a pool with `active` tasks on it; undefined when no sharing applies. */
export function sharedWindow(shared: LlamaShared | undefined, active: number): number | undefined {
  return shared && active >= 1 ? Math.floor(shared.pool / active) : undefined;
}

/** Running tasks bound to one provider/model; the peers a slice is split across. */
export function runningOn(records: Iterable<TaskRecord>, provider: string, model: string): TaskRecord[] {
  return [...records].filter((record) => record.state === "running" && record.provider === provider && record.model === model);
}

/**
 * Recompute the slice for every running task on one model and hand it to each runner. `shared` is a pool just
 * learned (a cold preset that has now loaded); otherwise the pool a running peer already recorded is reused.
 */
export function rebalanceShared(records: Iterable<TaskRecord>, provider: string, model: string, shared?: LlamaShared): void {
  const running = runningOn(records, provider, model);
  const pool = shared ?? running.find((record) => record.shared)?.shared;
  if (!pool) return;
  const window = sharedWindow(pool, running.length);
  if (window === undefined) return;
  for (const record of running) {
    record.shared = pool;
    void record.runner?.setContextWindow?.(window);
  }
}
