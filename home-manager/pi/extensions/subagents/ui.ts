// Rendering, live status emission, and completion notifications for the
// subagents tools. Rendering uses pi-tui's Text + theme colors; the live
// status is pushed on pi.events so llama-dx (and the setStatus fallback) can
// render it. Details types are shared with index.ts.

import { Text } from "@earendil-works/pi-tui";
import type {
  AgentToolResult,
  ExtensionAPI,
  ExtensionContext,
  ExtensionToolContext,
  ToolRenderResultOptions,
  Theme,
  ThemeColor,
} from "@earendil-works/pi-coding-agent";
import type { TaskRegistry, TaskRecord, StatusTask } from "./state.ts";
import { toStatus } from "./state.ts";

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
  /** Full task records, for the expanded detail view. */
  tasks: TaskRecord[];
}

export interface WaitDetails {
  count: number;
  /** Finished task records, for the result view. */
  tasks: TaskRecord[];
}

export interface ResultDetails {
  id: string;
  truncated: boolean;
  fullPath?: string;
}

export interface KillDetails {
  id: string;
  state: TaskRecord["state"];
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

function stateColor(state: TaskRecord["state"]): ThemeColor {
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

function stateLabel(state: TaskRecord["state"], theme: Theme): Text {
  return new Text(theme.fg(stateColor(state), state.toUpperCase()), 0, 0);
}

function text(content: string): Text {
  return new Text(content, 0, 0);
}

// ---- live status (pi.events + setStatus fallback) -------------------------

/** Push the set of running tasks so llama-dx renders the bar segment. */
export function emitStatus(pi: ExtensionAPI, registry: TaskRegistry): void {
  const tasks = registry
    .all()
    .filter((r) => r.state === "running")
    .map(toStatus);
  pi.events.emit("subagents:status", { tasks });
}

/** Compact string for the status-bar fallback when llama-dx is not present. */
export function formatStatusText(registry: TaskRegistry): string {
  const running = registry
    .all()
    .filter((r) => r.state === "running")
    .sort((a, b) => a.startedAt - b.startedAt)
    .slice(0, 2);
  if (running.length === 0) return "";
  const body = running.map((r) => `${r.name} ${formatElapsed(Date.now() - r.startedAt)}`).join(" · ");
  const extra = registry.all().filter((r) => r.state === "running").length - running.length;
  return `⚙ ${body}${extra > 0 ? ` · +${extra}` : ""}`;
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

function taskBlock(record: TaskRecord, theme: Theme, options: { expanded?: boolean } = {}): Text {
  const header = `${record.id} ${theme.fg("dim", "· ")}${theme.fg("accent", record.name)} ${theme.fg("dim", "· ")}${theme.fg("muted", record.model)}`;
  const state = stateLabel(record.state, theme);
  const elapsed = theme.fg("dim", ` ${formatElapsed(Date.now() - record.startedAt)}`);
  const lines = [`${header} ${state}${elapsed}`];
  if (record.error) lines.push(theme.fg("error", `  ${record.error}`));
  if (record.lastActivity) lines.push(theme.fg("muted", `  ▸ ${record.lastActivity}`));
  if (options.expanded) {
    const output = (record.recentOutput || record.output).trim();
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
  if (d.count === 0) {
    return text(opts.isPartial ? theme.fg("muted", "subagent_wait: timed out, nothing finished") : theme.fg("muted", "subagent_wait: no tasks finished"));
  }
  const blocks = d.tasks.map((r) => taskBlock(r, theme, { expanded: opts.expanded }));
  const header = theme.fg("toolTitle", theme.bold(`subagent_wait · ${d.count} finished`));
  return text(`${header}\n${blocks.map((b) => b.render(120).join("\n")).join("\n\n")}`);
}

export function renderResultResult(
  result: AgentToolResult<ResultDetails>,
  opts: ToolRenderResultOptions,
  theme: Theme,
  ctx: { isError: boolean },
): Text {
  const d = result.details;
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
  return text(theme.fg("toolTitle", theme.bold("subagent_kill ")) + theme.fg("accent", d.id) + theme.fg("muted", ` · ${d.state}`));
}

// ---- notifications ---------------------------------------------------------

/** Toast the user when a subagent finishes (called when results are collected). */
export function notifyCompletion(ctx: ExtensionToolContext, record: TaskRecord): void {
  if (record.state === "running") return;
  ctx.ui.notify(
    `subagent ${record.name} (${record.id}) finished: ${record.state}` + (record.error ? ` — ${record.error}` : ""),
    record.state === "failed" ? "error" : record.state === "killed" ? "warning" : "info",
  );
}
