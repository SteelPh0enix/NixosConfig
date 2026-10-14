// Theme-free formatting: time, tokens, tool activity and the plain-text task lines that the tools' `content`
// and the `/subagents` command speak in. Rendering to themed `Text` stays in ui.ts; nothing here touches pi or
// pi-tui, so it stays alongside the node-only task model.

import { IDLE_AFTER_MS, toSummary, type TaskRecord, type TaskSummary } from "./task-record.ts";

/** Collapse to one line and cut to `limit`, for activity text, errors and rendered output. */
export function oneLine(value: string, limit: number): string {
  const text = value.replace(/\s+/g, " ").trim();
  return text.length > limit ? `${text.slice(0, limit - 1).trimEnd()}…` : text;
}

/**
 * A tool's own duration, as `0.3s` / `4.2s` / `1m02s`. `formatElapsed` floors to whole seconds, which loses every
 * sub-second tool call.
 */
export function formatDuration(ms: number): string {
  const seconds = Math.max(0, ms) / 1000;
  if (seconds < 60) return `${seconds < 10 ? seconds.toFixed(1) : Math.round(seconds)}s`;
  return `${Math.floor(seconds / 60)}m${String(Math.round(seconds % 60)).padStart(2, "0")}s`;
}

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

/** How many lines of a running subagent's own text the wait widget shows. */
const LIVE_TAIL_LINES = 3;

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

/** The running tool with its live timer, or whatever the task last did. */
export function activityLine(task: TaskSummary): string {
  if (!task.tool) return task.lastActivity;
  const what = task.tool.summary ? `${task.tool.name}: ${task.tool.summary}` : task.tool.name;
  return `${what} (${formatDuration(task.tool.elapsed)})`;
}

/** `read 0.3s · bash 4.2s`, newest last; a failed call carries a `✗`. */
export function toolBreadcrumb(task: TaskSummary): string {
  return task.recentTools.map((call) => `${call.isError ? "✗" : ""}${call.name} ${formatDuration(call.durationMs)}`).join(" · ");
}

// ---- plain-text task lines (tool `content`, `/subagents`) -----------------

export function formatStatusLine(record: TaskRecord): string {
  const summary = toSummary(record);
  const idle = summary.idle !== undefined && summary.idle >= IDLE_AFTER_MS ? ` (idle ${formatElapsed(summary.idle)})` : "";
  const slot = summary.slot && summary.slot.total > 1 ? ` (slot ${summary.slot.index}/${summary.slot.total})` : "";
  const doing = activityLine(summary);
  const activity = doing ? ` — ${doing}${slot}${idle}` : "";
  const err = summary.error ? ` — ${summary.error}` : "";
  return `${record.id} · ${record.name} (${record.model}) · ${summary.state} · ${formatElapsed(summary.elapsed)}${activity}${err}`;
}

/** `/subagents <id>`: the status line, what the task has cost so far, and its recent assistant output. */
export function formatDetail(record: TaskRecord): string {
  const summary = toSummary(record);
  const stats = [`${summary.turns} turn(s)`, `${summary.tokens} tokens`, formatTokenStats(summary), summary.retry ? `retry ${summary.retry}` : ""]
    .filter(Boolean)
    .join(" · ");
  const crumb = toolBreadcrumb(summary);
  const head = `${formatStatusLine(record)}\n${stats}${crumb ? `\n${crumb}` : ""}`;
  const text = (record.lastText || record.output || "").trim();
  const preview = text.length > 500 ? `${text.slice(0, 499).trimEnd()}…` : text;
  return preview ? `${head}\n\n${preview}` : head;
}

/** The status line plus what the task's model cost and how full its context window is. */
export function formatReportLine(record: TaskRecord): string {
  const stats = formatTokenStats(toSummary(record));
  const line = formatStatusLine(record);
  return stats ? `${line} · ${stats}` : line;
}
