// The `subagent_kill` handler and the shared kill helper the `/subagents kill` command uses too.

import type { AgentToolResult } from "@earendil-works/pi-coding-agent";
import type { SubagentContext } from "./context.ts";
import { killRecord } from "./task-outcome.ts";
import type { TaskRecord } from "./task-record.ts";
import { emitStatus, type KillDetails } from "./ui.ts";

/**
 * How long a kill waits for the task to actually wind down. Nothing in this extension may block the main agent for
 * longer than it says it will, and a task stuck inside a session that is still starting up never settles on its own.
 */
export const DEFAULT_KILL_TIMEOUT_S = 10;

export interface KillParams {
  id: string;
  timeout_s?: number;
}

/** Abort a task without ever waiting on it longer than `timeoutS` (see `killRecord`). */
export function killTask(deps: SubagentContext, record: TaskRecord, timeoutS = DEFAULT_KILL_TIMEOUT_S): Promise<boolean> {
  return killRecord(record, timeoutS * 1000, deps.registry);
}

export async function executeKill(
  deps: SubagentContext,
  params: KillParams,
): Promise<AgentToolResult<KillDetails>> {
  const record = deps.registry.get(params.id);
  if (!record) throw new Error(`no such subagent task "${params.id}"`);
  const timeoutS = params.timeout_s ?? DEFAULT_KILL_TIMEOUT_S;
  const settled = await killTask(deps, record, timeoutS);
  emitStatus(deps.pi, deps.registry);
  return {
    content: [
      {
        type: "text",
        text: `subagent task ${record.id} (${record.name}) → ${record.state}${
          settled
            ? ""
            : ` (its own cleanup was still running after ${timeoutS}s; it is marked killed and its group slots are free — the abandoned runner finishes on its own)`
        }`,
      },
    ],
    details: { id: record.id, state: record.state },
  };
}
