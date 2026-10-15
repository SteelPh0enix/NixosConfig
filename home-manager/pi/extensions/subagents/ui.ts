// Rendering, live status emission, and completion notifications for the
// subagents tools. Rendering uses pi-tui's Text + theme colors; the live
// status is pushed on pi.events for whatever widget wants to show it, and a
// finished task injects its report into the session so the main agent can be
// woken with the result instead of blocking in `subagent_wait`.
// Details types are shared with index.ts.

import { Text } from "@earendil-works/pi-tui";
import type {
  AgentToolResult,
  ExtensionAPI,
  ExtensionToolContext,
  ToolRenderResultOptions,
  Theme,
  ThemeColor,
} from "@earendil-works/pi-coding-agent";
import { IDLE_AFTER_MS, toSummary, type TaskRecord, type TaskState, type TaskSummary } from "./task-record.ts";
import type { TaskRegistry } from "./task-registry.ts";
import { activityLine, formatElapsed, formatTokenStats, oneLine, toolBreadcrumb } from "./format.ts";

// ---- details shapes (matched by renderResult) -----------------------------

export interface SpawnDetails {
  id: string | null;
  name: string;
  model: string;
  /** True when the spawn was refused: the card is on another model, or this model's slots are all taken. */
  blocked?: boolean;
  /** The slot label handed to a spawned task, when its model has more than one slot. */
  slot?: { index: number; total: number };
}

export interface StatusDetails {
  id?: string;
  count: number;
  /** Summaries of the reported tasks, for the expanded detail view. */
  tasks: TaskSummary[];
}

export interface WaitDetails {
  count: number;
  /** Summaries of the finished tasks, for the result view. */
  tasks: TaskSummary[];
}

export interface ResultDetails {
  id: string;
  truncated: boolean;
  fullPath?: string;
}

export interface KillDetails {
  id: string;
  state: TaskState;
}

// ---- rendering ------------------------------------------------------------

function stateColor(state: TaskState): ThemeColor {
  switch (state) {
    case "running":
      return "accent";
    case "done":
      return "success";
    case "failed":
      return "error";
    case "killed":
      return "muted";
    default:
      return "dim";
  }
}

function stateLabel(state: TaskState, theme: Theme): string {
  return theme.fg(stateColor(state), state.toUpperCase());
}

function text(content: string): Text {
  return new Text(content, 0, 0);
}

/** Columns an expanded view is laid out in; `renderResult` is never told how wide the terminal is. */
const DETAIL_WIDTH = 120;

// ---- live status (pi.events) -----------------------------------------------

/**
 * Snapshot of the running tasks on `pi.events` (channel: `subagents:status`).
 * A task reports from the background, so pi may have replaced the session this extension was loaded for;
 * emitting into a replaced session throws, and a task must not take pi down when it reports.
 */
export function emitStatus(pi: ExtensionAPI, registry: TaskRegistry): void {
  const tasks = registry
    .all()
    .filter((r) => r.state === "running")
    .map((r) => toSummary(r));
  try {
    pi.events.emit("subagents:status", { tasks });
  } catch {
    // Nobody is listening any more.
  }
}

// ---- rendering: calls ------------------------------------------------------

export function renderSpawnCall(args: { name: string }, theme: Theme): Text {
  return text(theme.fg("toolTitle", theme.bold("subagent_spawn ")) + theme.fg("accent", args.name));
}

export function renderStatusCall(args: { id?: string }, theme: Theme): Text {
  return text(theme.fg("toolTitle", theme.bold("subagent_status")) + (args.id ? theme.fg("accent", ` ${args.id}`) : ""));
}

export function renderWaitCall(args: { ids?: string[]; timeout_s?: number }, theme: Theme): Text {
  const target = args.ids && args.ids.length ? theme.fg("accent", ` ${args.ids.join(", ")}`) : theme.fg("muted", " (all)");
  const timeout = args.timeout_s ? theme.fg("muted", ` [${args.timeout_s}s]`) : "";
  return text(theme.fg("toolTitle", theme.bold("subagent_wait")) + target + timeout);
}

export function renderResultCall(args: { id: string }, theme: Theme): Text {
  return text(theme.fg("toolTitle", theme.bold("subagent_result ")) + theme.fg("accent", args.id));
}

export function renderKillCall(args: { id: string }, theme: Theme): Text {
  return text(theme.fg("toolTitle", theme.bold("subagent_kill ")) + theme.fg("error", args.id));
}

// ---- rendering: results ----------------------------------------------------

function taskBlock(task: TaskSummary, theme: Theme, options: { expanded?: boolean } = {}): Text {
  const header = `${task.id} ${theme.fg("dim", "· ")}${theme.fg("accent", task.name)} ${theme.fg("dim", "· ")}${theme.fg("muted", task.model)}`;
  const idle = task.idle !== undefined && task.idle >= IDLE_AFTER_MS ? theme.fg("warning", ` idle ${formatElapsed(task.idle)}`) : "";
  const slot = task.slot && task.slot.total > 1 ? theme.fg("muted", ` slot ${task.slot.index}/${task.slot.total}`) : "";
  const lines = [`${header} ${stateLabel(task.state, theme)} ${theme.fg("dim", formatElapsed(task.elapsed))}${slot}${idle}`];
  if (task.error) lines.push(theme.fg("error", `  ${task.error}`));
  if (task.retry) lines.push(theme.fg("warning", `  retrying ${task.retry}`));
  // What it is doing goes on its own line; a settled task only shows its stats when the view is expanded.
  const stats = [`${task.turns} turn(s)`, formatTokenStats(task)].filter(Boolean).join(" · ");
  const doing = activityLine(task);
  const activity = [doing && `▸ ${doing}`, stats].filter(Boolean).join(" · ");
  if (doing || options.expanded) lines.push(theme.fg("muted", `  ${activity}`));
  if (task.preview) lines.push(...task.preview.split("\n").map((line) => theme.fg("dim", `  │ ${line}`)));
  if (options.expanded) {
    const crumb = toolBreadcrumb(task);
    if (crumb) lines.push(theme.fg("dim", `  ${crumb}`));
    const output = task.recentOutput.trim();
    if (output) lines.push("", theme.fg("dim", oneLine(output, 800)));
  }
  return text(lines.join("\n"));
}

export function renderSpawnResult(
  result: AgentToolResult<SpawnDetails>,
  _opts: ToolRenderResultOptions,
  theme: Theme,
): Text {
  const d = result.details;
  if (!d) return text(theme.fg("muted", "spawned"));
  if (d.blocked) {
    const message = result.content.find((c) => c.type === "text")?.text ?? "blocked";
    return text(theme.fg("toolTitle", theme.bold("subagent_spawn ")) + theme.fg("error", ` blocked — ${message}`));
  }
  return text(
    theme.fg("toolTitle", theme.bold("subagent_spawn ")) +
      theme.fg("accent", `${d.id} ← ${d.name}`) +
      theme.fg("dim", ` (${d.model})`) +
      (d.slot && d.slot.total > 1 ? theme.fg("muted", ` · slot ${d.slot.index}/${d.slot.total}`) : "") +
      theme.fg("muted", " · running"),
  );
}

export function renderStatusResult(
  result: AgentToolResult<StatusDetails>,
  opts: ToolRenderResultOptions,
  theme: Theme,
): Text {
  const d = result.details;
  if (!d) return text(theme.fg("muted", "subagent_status"));
  const title = d.id ? theme.fg("toolTitle", theme.bold("subagent_status")) : theme.fg("toolTitle", theme.bold("subagent_status (all)"));
  if (!opts.expanded) {
    const running = d.tasks.filter((t) => t.state === "running").length;
    return text(`${title} ${theme.fg("dim", `— ${d.count} task(s), ${running} running`)}`);
  }
  const blocks = d.tasks.map((r) => taskBlock(r, theme, { expanded: true }));
  return text(`${title}\n${blocks.map((b) => b.render(DETAIL_WIDTH).join("\n")).join("\n")}`);
}

export function renderWaitResult(
  result: AgentToolResult<WaitDetails>,
  opts: ToolRenderResultOptions,
  theme: Theme,
): Text {
  const d = result.details;
  if (!d) return text(theme.fg("muted", "subagent_wait"));
  const blocks = d.tasks.map((r) => taskBlock(r, theme, { expanded: opts.expanded }));
  if (d.count === 0) {
    // The tool says which case this is (interrupted, nothing to wait for, timed out); show it with whatever is left.
    const message = theme.fg("muted", oneLine(result.content.find((c) => c.type === "text")?.text ?? "subagent_wait: nothing finished", 200));
    return text(blocks.length ? `${message}\n${blocks.map((b) => b.render(DETAIL_WIDTH).join("\n")).join("\n\n")}` : message);
  }
  const header = theme.fg("toolTitle", theme.bold(`subagent_wait · ${d.count} ${opts.isPartial ? "still running" : "finished"}`));
  return text(`${header}\n${blocks.map((b) => b.render(DETAIL_WIDTH).join("\n")).join("\n\n")}`);
}

export function renderResultResult(
  result: AgentToolResult<ResultDetails>,
  opts: ToolRenderResultOptions,
  theme: Theme,
  ctx: { isError: boolean },
): Text {
  const d = result.details;
  if (!d) {
    const message = result.content.find((c) => c.type === "text")?.text ?? "subagent_result";
    return text(theme.fg(ctx.isError ? "error" : "muted", oneLine(message, 600)));
  }
  const header = theme.fg("toolTitle", theme.bold("subagent_result ")) + theme.fg("accent", d.id);
  if (ctx.isError) {
    const message = result.content.find((c) => c.type === "text")?.text ?? "unknown error";
    return text(`${header}\n${theme.fg("error", oneLine(message, 600))}`);
  }
  const first = result.content.find((c) => c.type === "text")?.text ?? "";
  if (!opts.expanded) {
    return text(`${header}\n${theme.fg("dim", oneLine(first, 400))}${d.truncated ? theme.fg("muted", "\n(full output saved to temp file)") : ""}`);
  }
  const full = first.trim() || (d.fullPath ? `(full output saved to ${d.fullPath})` : "");
  return text(`${header}\n${theme.fg("dim", full)}`);
}

export function renderKillResult(
  result: AgentToolResult<KillDetails>,
  _opts: ToolRenderResultOptions,
  theme: Theme,
): Text {
  const d = result.details;
  if (!d) return text(theme.fg("muted", "subagent_kill"));
  return text(theme.fg("toolTitle", theme.bold("subagent_kill ")) + theme.fg("accent", d.id) + theme.fg("muted", ` · ${d.state}`));
}

// ---- notifications ---------------------------------------------------------

/** How much of a finished report the completion message carries; the full one stays behind `subagent_result`. */
const INJECTED_REPORT_LIMIT = 8000;

/** Toast the user once when a subagent finishes; reading its report again must not toast a second time. */
export function notifyCompletion(ctx: ExtensionToolContext, record: TaskRecord): void {
  if (record.state === "running" || record.notified) return;
  record.notified = true;
  ctx.ui.notify(
    `subagent ${record.name} (${record.id}) finished: ${record.state}` + (record.error ? ` — ${record.error}` : ""),
    record.state === "failed" ? "error" : record.state === "killed" ? "warning" : "info",
  );
}

/**
 * Wake the main agent when a subagent settles, with the report in the message: it enters the session as a custom
 * message and, when the agent is idle, starts a turn - so the agent can hand control to the user instead of blocking
 * in `subagent_wait`. While the agent is streaming it queues as a follow-up. A message into a session pi has replaced
 * is swallowed, like the status emit.
 */
export function injectCompletion(pi: ExtensionAPI, record: TaskRecord): void {
  if (record.state === "running") return;
  const elapsed = formatElapsed((record.finishedAt ?? Date.now()) - record.startedAt);
  const head =
    record.state === "done"
      ? `Subagent ${record.name} (${record.id}) finished in ${elapsed}.`
      : record.state === "failed"
        ? `Subagent ${record.name} (${record.id}) failed after ${elapsed}${record.error ? `: ${oneLine(record.error, 300)}` : ""}.`
        : `Subagent ${record.name} (${record.id}) was killed after ${elapsed}.`;
  const report = record.output.trim();
  const body = report
    ? report.length > INJECTED_REPORT_LIMIT
      ? `${report.slice(0, INJECTED_REPORT_LIMIT)}\n… (truncated — the full report is behind subagent_result("${record.id}"))`
      : report
    : record.error
      ? `No report: ${oneLine(record.error, 300)}`
      : "No report.";
  const stats = formatTokenStats(toSummary(record));
  try {
    pi.sendMessage(
      {
        customType: "subagent-result",
        content: [head, body, stats && `[${stats}]`].filter(Boolean).join("\n\n"),
        display: true,
        details: { id: record.id, name: record.name, state: record.state, elapsed, error: record.error },
      },
      { triggerTurn: true, deliverAs: "followUp" },
    );
  } catch {
    // The session this extension was loaded for has been replaced; there is nobody to wake.
  }
}
