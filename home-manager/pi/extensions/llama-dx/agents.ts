// The row of running subagents, above the two llama.cpp ones.
//
// The subagents extension broadcasts a snapshot of its running tasks on pi's event bus (channel `subagents:status`)
// whenever one of them starts, moves or finishes. This keeps the last snapshot and composes the row out of it. Like
// layout.ts it imports nothing at runtime, so test-utils/preview.mjs can render it without pi.

import { cut, metricsLine, type Cell, type Group, type Segment } from "./layout.ts";

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
};

/** Silence this long gets a colour of its own: the model of that task has stopped answering. */
const IDLE_MS = 15_000;
/** What a task is doing is told in this many columns; the row never spends more on it than that. */
const ACTIVITY_COLS = 34;

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

/** One task: who it is, how long it has run, and what it is busy with. */
const agentCells = (task: Agent, since: number): Cell[] => {
  const idle = task.idle === undefined ? undefined : task.idle + since;
  const who: Cell = [{ text: task.id, tone: "ident" }, { text: ` ${task.name}`, tone: "value" }];
  if (task.slot && task.slot.total > 1) who.push({ text: ` ${task.slot.index}/${task.slot.total}`, tone: "dim" });
  const running = task.state === "running";
  const timing: Cell = [{ text: age(task.elapsed + since), tone: running ? "live" : "dim" }];
  if (idle !== undefined && idle >= IDLE_MS) timing.push({ text: ` idle ${age(idle)}`, tone: "warn" });
  const now: Cell = !running
    ? [{ text: task.state.toLowerCase(), tone: "dim" }]
    : task.error
      ? [{ text: cut(task.error, ACTIVITY_COLS), tone: "error" }]
      : task.retry
        ? [{ text: `retrying ${task.retry}`, tone: "warn" }]
        : task.lastActivity
          ? [{ text: cut(task.lastActivity, ACTIVITY_COLS), tone: "dim" }]
          : [];
  return [who, timing, now].filter((cell) => cell.length > 0);
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
