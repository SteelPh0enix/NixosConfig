// In-memory registry of subagent tasks and the completion queue that
// `subagent_wait` drains. One registry per extension instance (each session
// gets its own), so a subagent's tasks are never visible to the main agent.

import type { SubagentConfig } from "./config.ts";

export type TaskState = "running" | "done" | "failed" | "killed";

export interface TaskRecord {
  id: string;
  name: string;
  provider: string;
  model: string;
  description?: string;
  taskText: string;
  state: TaskState;
  startedAt: number;
  finishedAt?: number;
  /** Last thing the subagent did, for the status bar and `/subagents <id>`. */
  lastActivity: string;
  lastActivityAt: number;
  /** Last assistant message text seen so far (streaming progress + final report). */
  lastText: string;
  /** Final assistant text (the report). */
  output: string;
  /** Accumulated model usage so the main session's token totals stay accurate. */
  usage: { tokens: number; cost: number };
  error?: string;
  /** Last ~2000 chars of output, for the `/subagents <id>` detail view. */
  recentOutput: string;
  /** Groups this task holds a lease in (empty when the subagent is untracked). */
  groups: string[];
  /** Whether `subagent_wait` has already delivered this task to the main agent. */
  claimed: boolean;
  /** Live only: the runner driving this task. */
  runner?: unknown;
}

/** The compact shape emitted on `pi.events` and rendered in the status bar. */
export interface StatusTask {
  id: string;
  name: string;
  model: string;
  state: TaskState;
  elapsed: number;
  lastActivity: string;
}

function elapsed(record: TaskRecord, now = Date.now()): number {
  const end = record.finishedAt ?? record.startedAt;
  return Math.max(0, now - end);
}

export function toStatus(record: TaskRecord): StatusTask {
  return {
    id: record.id,
    name: record.name,
    model: record.model,
    state: record.state,
    elapsed: elapsed(record),
    lastActivity: record.lastActivity,
  };
}

/**
 * Completion queue for `subagent_wait`.
 *
 * - `claimFinished()` returns every finished-but-unclaimed task and marks them
 *   claimed, so the main agent sees each result exactly once.
 * - `waitForCompletion()` resolves as soon as a task finishes, or rejects the
 *   wait after a timeout (returning whether anything is actually available).
 */
export class TaskRegistry {
  private tasks = new Map<string, TaskRecord>();
  private finished: string[] = [];
  private waiters: Array<(hasWork: boolean) => void> = [];
  private counter = 0;

  /** Generate a unique id for a new task (e.g. "task-1"). */
  nextId(): string {
    this.counter += 1;
    return `task-${this.counter}`;
  }

  add(record: TaskRecord): void {
    this.tasks.set(record.id, record);
  }

  get(id: string): TaskRecord | undefined {
    return this.tasks.get(id);
  }

  all(): TaskRecord[] {
    return [...this.tasks.values()];
  }

  /** Mark a task finished and wake any waiters. */
  markFinished(id: string): void {
    const record = this.tasks.get(id);
    if (record && record.state === "running") {
      record.state = "done";
      record.finishedAt = Date.now();
    }
    if (!this.finished.includes(id)) this.finished.push(id);
    this.notify(true);
  }

  /** Mark a task as killed (still counts as finished for waiters). */
  markKilled(id: string): void {
    const record = this.tasks.get(id);
    if (record && record.state === "running") {
      record.state = "killed";
      record.finishedAt = Date.now();
      this.finished.push(id);
      this.notify(true);
    }
  }

  /** All finished tasks not yet handed to `subagent_wait`, marked claimed. */
  claimFinished(): TaskRecord[] {
    const ids = this.finished;
    this.finished = [];
    const result: TaskRecord[] = [];
    for (const id of ids) {
      const record = this.tasks.get(id);
      if (record) {
        record.claimed = true;
        result.push(record);
      }
    }
    return result;
  }

  /**
   * Resolve once a task finishes, or after `timeoutMs`.
   * Returns true if work is available to claim.
   */
  waitForCompletion(timeoutMs: number): Promise<boolean> {
    if (this.finished.length > 0) return Promise.resolve(true);
    return new Promise<boolean>((resolve) => {
      let settled = false;
      const onWork = () => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        resolve(this.finished.length > 0);
      };
      const timer = setTimeout(() => {
        if (settled) return;
        settled = true;
        this.waiters = this.waiters.filter((w) => w !== onWork);
        resolve(false);
      }, timeoutMs);
      this.waiters.push(onWork);
    });
  }

  private notify(hasWork: boolean): void {
    const waiters = this.waiters;
    this.waiters = [];
    for (const w of waiters) w(hasWork);
  }
}
