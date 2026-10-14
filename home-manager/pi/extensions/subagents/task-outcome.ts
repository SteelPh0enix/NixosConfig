// The terminal-outcome state machine: the one place a task's state, finish time, output and error are written.
// `settle` is idempotent, so a kill that outruns its runner cannot resurrect a task, and `killRecord` never blocks
// the caller longer than it was told to. Node-only.

import { keepSaidText, RECENT_OUTPUT_LIMIT, type TaskRecord, type TaskState } from "./task-record.ts";
import type { TaskRegistry } from "./task-registry.ts";

/** How a running task ended; the values `TaskState` takes once it is no longer running. */
export type TaskOutcome = Exclude<TaskState, "running">;

/** Resolve true once `pending` settles, false after `ms`. Never rejects, and never takes longer than `ms`. */
export function withTimeout(pending: Promise<unknown>, ms: number): Promise<boolean> {
  return new Promise<boolean>((resolve) => {
    const timer = setTimeout(() => resolve(false), Math.max(0, ms));
    const settle = () => {
      clearTimeout(timer);
      resolve(true);
    };
    pending.then(settle, settle);
  });
}

/**
 * End a running task exactly once, writing every terminal field together.
 *
 * A settled task is not running a tool and is not writing: `currentTool` goes and the streaming token estimate is
 * zeroed. `output` is replaced when given, so a runner can hand over the report it read; `error` is only ever added,
 * never cleared, because a task that failed before the model answered must keep that reason. A task that never wrote
 * a report keeps the last thing it said. Only a killed task keeps its activity line - where it stopped is the point -
 * a finished one has no "right now".
 */
export function settle(record: TaskRecord, outcome: TaskOutcome, opts: { error?: string; output?: string } = {}): void {
  if (record.state !== "running") return;
  record.state = outcome;
  record.finishedAt = Date.now();
  record.usage.streaming = 0;
  record.currentTool = undefined;
  if (opts.output !== undefined) {
    record.output = opts.output;
    record.recentOutput = record.output.slice(-RECENT_OUTPUT_LIMIT);
  }
  if (opts.error) record.error = opts.error;
  keepSaidText(record);
  if (outcome !== "killed") record.lastActivity = "";
}

/**
 * Abort a task and report whether it wound down inside `timeoutMs`. Nothing here may block the caller for longer than
 * it was told to: a task whose session is still being created has nothing to abort and no deadline of its own, and
 * the main agent must not end up waiting for it. A task that does not settle is marked killed anyway and hands its
 * group slots back, so the abandoned runner cannot hold a group while it finishes on its own. A record with no
 * runner is marked killed the same way: a task nothing drives any more is not a running task.
 *
 * A task that settles is queued by its own runner; one that does not has nobody else to do it, so the kill queues it
 * through `registry` (when one is given). Otherwise a timed-out kill leaves a task that `subagent_wait` can never
 * deliver — exactly the case the timeout exists for.
 */
export async function killRecord(record: TaskRecord, timeoutMs: number, registry?: TaskRegistry): Promise<boolean> {
  if (record.state !== "running") return true;
  const runner = record.runner;
  if (!runner) {
    settle(record, "killed");
    registry?.markFinished(record.id);
    return true;
  }
  // A failed abort is not worth an error of its own: the timeout still ends the kill and the lease TTL frees the group.
  void runner.abort().catch(() => {});
  const settled = await withTimeout(runner.done(), timeoutMs);
  settle(record, "killed");
  if (!settled) {
    runner.releaseLeases();
    registry?.markFinished(record.id);
  }
  return settled;
}
