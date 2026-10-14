// The `subagent_status` handler: one task or all of them, as plain-text report lines.

import type { AgentToolResult } from "@earendil-works/pi-coding-agent";
import type { SubagentContext } from "./context.ts";
import { formatReportLine } from "./format.ts";
import { toSummary } from "./state.ts";
import type { StatusDetails } from "./ui.ts";

export interface StatusParams {
  id?: string;
}

export async function executeStatus(
  deps: SubagentContext,
  params: StatusParams,
): Promise<AgentToolResult<StatusDetails>> {
  const { registry } = deps;
  const target = params.id ? registry.get(params.id) : undefined;
  if (params.id && !target) throw new Error(`no such subagent task "${params.id}"`);
  const tasks = target ? [target] : registry.all();
  const details: StatusDetails = { id: params.id, count: tasks.length, tasks: tasks.map((t) => toSummary(t)) };
  const content = tasks.length === 0 ? "no subagent tasks" : tasks.map(formatReportLine).join("\n");
  return { content: [{ type: "text", text: content }], details };
}
