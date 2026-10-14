// The `subagent_result` handler: a finished task's full report, its cost, and a temp file when it overflows.

import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { randomBytes } from "node:crypto";
import type { AgentToolResult, ExtensionToolContext } from "@earendil-works/pi-coding-agent";
import type { SubagentContext } from "./context.ts";
import { formatTokenStats } from "./format.ts";
import { toSummary } from "./task-record.ts";
import { usageFrom } from "./usage.ts";
import { notifyCompletion, type ResultDetails } from "./ui.ts";

const OUTPUT_LIMIT = 20000;

export interface ResultParams {
  id: string;
}

function writeTempFile(name: string, content: string): string {
  const dir = join(tmpdir(), "pi-subagents");
  mkdirSync(dir, { recursive: true });
  const path = join(dir, `${name.replace(/[^a-z0-9-]/gi, "-")}-${randomBytes(4).toString("hex")}.txt`);
  writeFileSync(path, content);
  return path;
}

export async function executeResult(
  deps: SubagentContext,
  params: ResultParams,
  toolCtx: ExtensionToolContext,
): Promise<AgentToolResult<ResultDetails>> {
  const { registry } = deps;
  const record = registry.get(params.id);
  if (!record) throw new Error(`no such subagent task "${params.id}"`);
  if (record.state === "running") throw new Error(`task ${record.id} is still running`);

  notifyCompletion(toolCtx, record);
  // Reading the report counts as collecting the task, so a later `subagent_wait` does not deliver it a second time.
  registry.delivered(record.id);
  const output = record.output;
  const truncated = output.length > OUTPUT_LIMIT;
  // A task can settle with nothing to show (killed before it spoke, cut off mid tool call), and one that failed
  // before the model answered has only its error. Say which, rather than hand back an empty block.
  const content = !output
    ? `task ${record.id} (${record.name}) ended as ${record.state} with no report text${record.error ? `: ${record.error}` : ""}`
    : truncated
      ? `${output.slice(0, OUTPUT_LIMIT)}\n\n… (truncated — full copy saved to temp file)`
      : output;
  let fullPath: string | undefined;
  if (truncated) fullPath = writeTempFile(`${record.id}.txt`, output);
  // Report what the subagent cost once, whoever collects it first: pi adds up every tool result's usage.
  const reportUsage = !record.usageReported;
  record.usageReported = true;

  // What the task cost, said once next to its report rather than only in the tool metadata.
  const stats = formatTokenStats(toSummary(record));
  return {
    content: [{ type: "text", text: stats ? `${content}\n\n[${stats}]` : content }],
    details: { id: record.id, truncated, fullPath },
    ...(reportUsage ? { usage: usageFrom(record.usage.tokens, record.usage.cost, record.usage.generated) } : {}),
  };
}
