// Rendering, live status emission, and completion notifications for the
// subagents tools. Rendering uses pi-tui's Text + theme colors; the live
// status is pushed on pi.events so llama-dx (and the setStatus fallback) can
// render it. Details types are shared with index.ts.

import { Text } from "@earendil-works/pi-tui";
import type {
  AgentToolResult,
  ExtensionAPI,
  ExtensionToolContext,
  ToolRenderResultOptions,
  Theme,
  ThemeColor,
} from "@earendil-works/pi-coding-agent";
import { IDLE_AFTER_MS, toSummary, type TaskRecord, type TaskRegistry, type TaskState, type TaskSummary } from "./state.ts";

// ---- details shapes (matched by renderResult) -----------------------------

export interface SpawnDetails {
  id: string | null;
  name: string;
  model: string;
  /** True when the spawn was rejected because a group was at capacity. */
  blocked?: boolean;
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

// ---- shared formatting ----------------------------------------------------

export function formatElapsed(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  if (h > 0) return `${h}h${String(m).padStart(2, "0")}m`;
  if (m > 0) return `${m}m${String(s).padStart(2, "0")}s`;
  return `${s}s`;
}

/** Token counts read as `12.3k` above a thousand, plain below it. */
export function formatTokens(value: number): string {
  if (value < 1000) return `${value}`;
  const k = value / 1000;
  return `${k < 100 ? k.toFixed(1).replace(/\.0$/, "") : Math.round(k)}k`;
}

/**
 * `out ~1.2k · ctx 41.2k/262k (16%)` — what the subagent's model produced, and how much of its window it is holding.
 * The generated figure carries `~` while its turn is still decoding, since that number is counted off the stream and
 * the model replaces it with its own when the turn ends. Empty when neither is known yet.
 */
export function formatTokenStats(task: TaskSummary): string {
  const parts: string[] = [];
  if (task.generated > 0) parts.push(`out ${task.generatedLive ? "~" : ""}${formatTokens(task.generated)}`);
  if (task.contextWindow) {
    const used = task.contextTokens;
    parts.push(
      used === null || used === undefined
        ? `ctx ?/${formatTokens(task.contextWindow)}`
        : `ctx ${formatTokens(used)}/${formatTokens(task.contextWindow)} (${Math.round(task.contextPercent ?? (used / task.contextWindow) * 100)}%)`,
    );
  }
  return parts.join(" · ");
}

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

/** How many lines of a running subagent's own text the wait widget shows. */
export const LIVE_TAIL_LINES = 3;

/** Last `count` lines of `value`, each flattened to one line and cut to `width`. */
export function tailLines(value: string, count = LIVE_TAIL_LINES, width = 90): string {
  return value
    .split("\n")
    .map((line) => line.replace(/\s+/g, " ").trim())
    .filter(Boolean)
    .slice(-count)
    .map((line) => (line.length > width ? `${line.slice(0, width - 1).trimEnd()}…` : line))
    .join("\n");
}

// ---- live status (pi.events + setStatus fallback) -------------------------

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
  const lines = [`${header} ${stateLabel(task.state, theme)} ${theme.fg("dim", formatElapsed(task.elapsed))}${idle}`];
  if (task.error) lines.push(theme.fg("error", `  ${task.error}`));
  if (task.retry) lines.push(theme.fg("warning", `  retrying ${task.retry}`));
  // What it is doing goes on its own line; a settled task only shows its stats when the view is expanded.
  const stats = [`${task.turns} turn(s)`, formatTokenStats(task)].filter(Boolean).join(" · ");
  const activity = [task.lastActivity && `▸ ${task.lastActivity}`, stats].filter(Boolean).join(" · ");
  if (task.lastActivity || options.expanded) lines.push(theme.fg("muted", `  ${activity}`));
  if (task.preview) lines.push(...task.preview.split("\n").map((line) => theme.fg("dim", `  │ ${line}`)));
  if (options.expanded) {
    const output = task.recentOutput.trim();
    if (output) lines.push("", theme.fg("dim", truncate(output, 800)));
  }
  return text(lines.join("\n"));
}

function truncate(value: string, limit: number): string {
  const trimmed = value.replace(/\s+/g, " ").trim();
  return trimmed.length > limit ? `${trimmed.slice(0, limit - 1).trimEnd()}…` : trimmed;
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
  return text(`${title}\n${blocks.map((b) => b.render(120).join("\n")).join("\n")}`);
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
    const message = theme.fg("muted", truncate(result.content.find((c) => c.type === "text")?.text ?? "subagent_wait: nothing finished", 200));
    return text(blocks.length ? `${message}\n${blocks.map((b) => b.render(120).join("\n")).join("\n\n")}` : message);
  }
  const header = theme.fg("toolTitle", theme.bold(`subagent_wait · ${d.count} ${opts.isPartial ? "still running" : "finished"}`));
  return text(`${header}\n${blocks.map((b) => b.render(120).join("\n")).join("\n\n")}`);
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
    return text(theme.fg(ctx.isError ? "error" : "muted", truncate(message, 600)));
  }
  const header = theme.fg("toolTitle", theme.bold("subagent_result ")) + theme.fg("accent", d.id);
  if (ctx.isError) {
    const message = result.content.find((c) => c.type === "text")?.text ?? "unknown error";
    return text(`${header}\n${theme.fg("error", truncate(message, 600))}`);
  }
  const first = result.content.find((c) => c.type === "text")?.text ?? "";
  if (!opts.expanded) {
    return text(`${header}\n${theme.fg("dim", truncate(first, 400))}${d.truncated ? theme.fg("muted", "\n(full output saved to temp file)") : ""}`);
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

/** Toast the user once when a subagent finishes; reading its report again must not toast a second time. */
export function notifyCompletion(ctx: ExtensionToolContext, record: TaskRecord): void {
  if (record.state === "running" || record.notified) return;
  record.notified = true;
  ctx.ui.notify(
    `subagent ${record.name} (${record.id}) finished: ${record.state}` + (record.error ? ` — ${record.error}` : ""),
    record.state === "failed" ? "error" : record.state === "killed" ? "warning" : "info",
  );
}
