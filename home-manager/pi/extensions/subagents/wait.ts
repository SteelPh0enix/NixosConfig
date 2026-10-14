// The `subagent_wait` handler: blocks until a claimable task finishes, streams what the running ones are doing,
// and delivers each finished task exactly once (with its cost counted once).

import type { AgentToolResult, AgentToolUpdateCallback } from "@earendil-works/pi-coding-agent";
import type { SubagentContext } from "./context.ts";
import { activityLine, formatElapsed, formatReportLine, formatTokenStats, tailLines } from "./format.ts";
import { toSummary, type TaskRecord } from "./state.ts";
import { usageFrom } from "./usage.ts";
import type { WaitDetails } from "./ui.ts";

export const DEFAULT_WAIT_TIMEOUT_S = 300;

export interface WaitParams {
  ids?: string[];
  timeout_s?: number;
}

/**
 * Why a wait had nothing to deliver: nothing exists at all, the ids name no task, or the tasks it was given have
 * already reported. `delivered` is what a wait that ran out of time says about the last case, which it cannot tell
 * apart from a task that never entered the queue.
 */
function nothingMessage(registry: SubagentContext["registry"], ids: string[] | undefined, delivered: boolean): string {
  if (!ids || ids.length === 0) return "subagent_wait: no tasks to wait for";
  const unknown = ids.filter((id) => !registry.get(id));
  if (unknown.length === ids.length) return `subagent_wait: no such subagent tasks: ${unknown.join(", ")}`;
  if (unknown.length > 0) return `subagent_wait: nothing new — no such subagent tasks: ${unknown.join(", ")}`;
  // Every id names a task that exists, which is all that is left to say about it.
  const known = registry.all().filter((r) => ids.includes(r.id)).map((r) => `${r.id} (${r.state})`).join(", ");
  return delivered ? `subagent_wait: nothing new — already delivered: ${known}` : `subagent_wait: nothing new — ${known}`;
}

export async function executeWait(
  deps: SubagentContext,
  params: WaitParams,
  signal: AbortSignal | undefined,
  onUpdate: AgentToolUpdateCallback<WaitDetails> | undefined,
): Promise<AgentToolResult<WaitDetails>> {
  const { registry } = deps;
  const ids = params.ids?.length ? params.ids : undefined;
  const matches = (record: TaskRecord) => !ids || ids.includes(record.id);
  const running = () => registry.all().filter((r) => matches(r) && r.state === "running");
  const timeoutS = params.timeout_s ?? DEFAULT_WAIT_TIMEOUT_S;
  let finished = registry.claimFinished(ids);
  // Nothing running and nothing queued means there is nothing this wait could ever deliver, so waiting for
  // `timeout_s` of it would just be standing still: say so at once. An already-aborted request says that instead.
  if (!signal?.aborted && finished.length === 0 && running().length === 0) {
    return { content: [{ type: "text", text: nothingMessage(registry, ids, false) }], details: { count: 0, tasks: [] } };
  }
  const deadline = Date.now() + timeoutS * 1000;

  const interval = setInterval(() => {
    const pending = running();
    if (!pending.length) return;
    // The session can be replaced while this blocks, and a dead renderer must not end the wait or take pi down.
    try {
      const views = pending.map((r) => {
        const summary = toSummary(r);
        const stats = formatTokenStats(summary);
        return {
          summary: { ...summary, preview: tailLines(r.lastText) },
          line: `${r.id}: ${activityLine(summary) || "running"} (${formatElapsed(summary.elapsed)})${stats ? ` ${stats}` : ""}`,
        };
      });
      onUpdate?.({
        content: [{ type: "text", text: views.map((v) => v.line).join("\n") }],
        details: { count: pending.length, tasks: views.map((v) => v.summary) },
      });
    } catch {
      // The next tick reports again.
    }
  }, 1000);
  try {
    while (finished.length === 0 && !signal?.aborted) {
      const remaining = Math.max(0, deadline - Date.now());
      if (remaining <= 0) break;
      if (!(await registry.waitForCompletion(remaining, ids, signal))) break;
      finished.push(...registry.claimFinished(ids));
    }
  } finally {
    clearInterval(interval);
  }

  if (finished.length === 0) {
    const pending = running();
    const stillRunning = pending.map((r) => `${r.id} (${r.name})`).join(", ");
    // Tasks that were already delivered stay in the registry, so "no such task" would be a lie: say what happened.
    const text = signal?.aborted
      ? `subagent_wait: interrupted${pending.length ? ` — still running: ${stillRunning}` : ""}`
      : pending.length !== 0
        ? `subagent_wait: timed out — still running: ${stillRunning}`
        : nothingMessage(registry, ids, true);
    return { content: [{ type: "text", text }], details: { count: 0, tasks: pending.map((r) => toSummary(r)) } };
  }

  const total = (pick: (record: TaskRecord) => number) => finished.reduce((sum, r) => sum + pick(r), 0);
  return {
    content: [{ type: "text", text: finished.map(formatReportLine).join("\n") }],
    details: { count: finished.length, tasks: finished.map((r) => toSummary(r)) },
    usage: usageFrom(total((r) => r.usage.tokens), total((r) => r.usage.cost), total((r) => r.usage.generated)),
  };
}
