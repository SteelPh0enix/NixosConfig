// The row of running subagents, above the two llama.cpp ones.
//
// The subagents extension broadcasts a snapshot of its running tasks on pi's event bus (channel `subagents:status`)
// whenever one of them starts, moves or finishes. This keeps the last snapshot and composes the row out of it. Like
// layout.ts it imports nothing at runtime, so test-utils/preview.mjs can render it without pi.

import { cut, fmtMs, load, metricsLine, short, type Cell, type Group, type Load, type Segment, type Tone } from "./layout.ts";

/** What `subagents:status` reports for one task — only the fields this row shows. */
export type Agent = {
  id: string;
  name: string;
  state: string;
  /** Milliseconds it has run, as of the snapshot. */
  elapsed: number;
  /** Milliseconds since its last event, only while it runs. */
  idle?: number;
  /** What it is doing right now, already one line. */
  lastActivity?: string;
  /** Set while its model call is being retried, e.g. `2/5 after 40s`. */
  retry?: string;
  error?: string;
  slot?: { index: number; total: number };
  /** The tool it is on right now, and how long it had been on it when the snapshot was taken. */
  tool?: { name: string; summary: string; elapsed: number };
  /** Tokens its model produced; `generatedLive` while the turn is still decoding and the figure is an estimate. */
  generated?: number;
  generatedLive?: boolean;
  /** pi's estimate of what the task's model holds, its window, and the percentage. */
  contextTokens?: number | null;
  contextWindow?: number;
  contextPercent?: number | null;
};

/** Silence this long gets a colour of its own: the model of that task has stopped answering. */
const IDLE_MS = 15_000;
/** What a task is doing is told in this many columns; the row never spends more on it than that. */
const ACTIVITY_COLS = 34;

/** The context cell's colour, the same thresholds the llama.cpp bar holds to. */
const CTX_TONE: Record<Load, Tone> = { normal: "dim", warn: "warn", error: "error" };

let snapshot: { tasks: Agent[]; at: number } | undefined;

const isAgent = (value: unknown): value is Agent => {
  const task = value as Agent;
  return typeof task?.id === "string" && typeof task?.name === "string" && typeof task?.elapsed === "number";
};

/** Remember the newest `subagents:status` snapshot. Nothing arrives when no subagent runs, and that is the same thing as none. */
export function noteAgents(data: unknown): void {
  const tasks = (data as { tasks?: unknown })?.tasks;
  const running = Array.isArray(tasks) ? tasks.filter(isAgent) : [];
  snapshot = running.length > 0 ? { tasks: running, at: Date.now() } : undefined;
}

/** A task's age: `12s`, `3m12s`, `1h05m`. */
const age = (ms: number): string => {
  const s = Math.max(0, Math.floor(ms / 1000));
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  return m < 60 ? `${m}m${String(s % 60).padStart(2, "0")}s` : `${Math.floor(m / 60)}h${String(m % 60).padStart(2, "0")}m`;
};

/** What the task is on: the tool it runs right now with a live timer, else what it last did, else its state. */
const nowCell = (task: Agent, since: number): Cell => {
  if (task.state !== "running") return [{ text: task.state.toLowerCase(), tone: "dim" }];
  if (task.error) return [{ text: cut(task.error, ACTIVITY_COLS), tone: "error" }];
  if (task.retry) return [{ text: `retrying ${task.retry}`, tone: "warn" }];
  if (task.tool) {
    const what = task.tool.summary ? `${task.tool.name}: ${task.tool.summary}` : task.tool.name;
    return [{ text: cut(what, ACTIVITY_COLS), tone: "dim" }, { text: ` (${fmtMs(task.tool.elapsed + since)})`, tone: "live" }];
  }
  return task.lastActivity ? [{ text: cut(task.lastActivity, ACTIVITY_COLS), tone: "dim" }] : [];
};

/** What its model produced, with `~` while that figure is the in-flight estimate rather than the model's own. */
const outCell = (task: Agent): Cell =>
  task.generated
    ? [{ text: "out", tone: "label" }, { text: `${task.generatedLive ? " ~" : " "}${short(task.generated)}`, tone: task.generatedLive ? "live" : "value" }]
    : [];

/** How full the task's own context is: `ctx 41k/262k`, `ctx ?/262k` before pi can estimate it. */
const ctxCell = (task: Agent): Cell => {
  if (!task.contextWindow) return [];
  const used = task.contextTokens;
  const known = used !== null && used !== undefined;
  return [{ text: "ctx", tone: "label" }, { text: ` ${known ? `${short(used)}/${short(task.contextWindow)}` : `?/${short(task.contextWindow)}`}`, tone: known ? CTX_TONE[load(used, task.contextWindow)] : "dim" }];
};

/** One task: who it is, how long it has run, what it is busy with, and what its model has done with its context. */
const agentCells = (task: Agent, since: number): Cell[] => {
  const idle = task.idle === undefined ? undefined : task.idle + since;
  const who: Cell = [{ text: task.id, tone: "ident" }, { text: ` ${task.name}`, tone: "value" }];
  if (task.slot && task.slot.total > 1) who.push({ text: ` ${task.slot.index}/${task.slot.total}`, tone: "dim" });
  const running = task.state === "running";
  const timing: Cell = [{ text: age(task.elapsed + since), tone: running ? "live" : "dim" }];
  if (idle !== undefined && idle >= IDLE_MS) timing.push({ text: ` idle ${age(idle)}`, tone: "warn" });
  return [who, timing, nowCell(task, since), outCell(task), ctxCell(task)].filter((cell) => cell.length > 0);
};

/**
 * The row, or nothing while no subagent runs. Tasks drop from the right as the terminal narrows, so the count in
 * front always says how many there are and a dropped task is never mistaken for the whole picture. A snapshot only
 * arrives when something changed, so the ages keep counting from the moment it was taken.
 */
export function agentsRow(width: number): Segment[] | undefined {
  if (!snapshot) return undefined;
  const since = Date.now() - snapshot.at;
  const groups: Group[] = [
    { name: "subagents", cells: [[{ text: "subagents", tone: "label" }, { text: ` ${snapshot.tasks.length}`, tone: "live" }]] },
    ...snapshot.tasks.map((task) => ({ name: task.id, cells: agentCells(task, since) })),
  ];
  return metricsLine(groups, width);
}
