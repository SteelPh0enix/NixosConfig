// In-memory registry of subagent tasks and the completion queue that
// `subagent_wait` drains. One registry per extension instance (each session
// gets its own), so a subagent's tasks are never visible to the main agent.

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
  /** Assistant turns finished so far: 0 with a long elapsed time means it never got an answer. */
  turns: number;
  /** Set while pi is retrying a failed model call, e.g. "2/5 after 40s". */
  retry?: string;
  /** Last assistant message text seen so far (streaming progress + final report). */
  lastText: string;
  /** Final assistant text (the report). Only ever handed out by `subagent_result`. */
  output: string;
  /** Accumulated model usage so the main session's token totals stay accurate. */
  usage: { tokens: number; cost: number };
  error?: string;
  /** Tail of the output, for the `/subagents <id>` detail view and result blocks. */
  recentOutput: string;
  /** Groups this task holds a lease in (empty when the subagent is untracked). */
  groups: string[];
  /** Whether `subagent_wait` has already delivered this task to the main agent. */
  claimed: boolean;
  /** Live only: the runner driving this task. */
  runner?: unknown;
}

/**
 * Compact view of a task for tool `details` and status events. Tool details are
 * persisted into the session file, so they never carry the full report.
 */
export interface TaskSummary {
  id: string;
  name: string;
  model: string;
  state: TaskState;
  /** Milliseconds the task ran (or has been running, measured at call time). */
  elapsed: number;
  /** Milliseconds since its last event; only while it runs. Silence means the model call is not answering. */
  idle?: number;
  turns: number;
  tokens: number;
  lastActivity: string;
  retry?: string;
  error?: string;
  recentOutput: string;
}

const SUMMARY_OUTPUT_LIMIT = 1000;

/** Idle a running task may sit silent for before the status line says so. */
export const IDLE_AFTER_MS = 15_000;

export function toSummary(record: TaskRecord, now = Date.now()): TaskSummary {
  return {
    id: record.id,
    name: record.name,
    model: record.model,
    state: record.state,
    elapsed: Math.max(0, now - (record.finishedAt ?? record.startedAt)),
    idle: record.state === "running" ? Math.max(0, now - record.lastActivityAt) : undefined,
    turns: record.turns,
    tokens: record.usage.tokens,
    lastActivity: record.lastActivity,
    retry: record.retry,
    error: record.error,
    recentOutput: record.recentOutput.slice(-SUMMARY_OUTPUT_LIMIT),
  };
}

/**
 * Completion queue for `subagent_wait`.
 *
 * - `claimFinished(ids)` hands out finished-but-unclaimed tasks and marks them
 *   claimed, so the main agent sees each result exactly once. When `ids` is
 *   given, only those tasks are claimed; the rest stay queued for later.
 * - `waitForCompletion(timeoutMs, ids, signal)` resolves true as soon as a
 *   claimable task finishes, and false on timeout or abort.
 */
export class TaskRegistry {
  private tasks = new Map<string, TaskRecord>();
  private finished: string[] = [];
  private waiters: Array<() => void> = [];
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

  /** Mark a task finished (whatever the outcome) and wake any waiters. */
  markFinished(id: string): void {
    const record = this.tasks.get(id);
    if (record && record.state === "running") {
      record.state = "done";
      record.finishedAt = Date.now();
    }
    if (!this.finished.includes(id)) this.finished.push(id);
    this.notify();
  }

  claimFinished(ids?: string[]): TaskRecord[] {
    const claimed: TaskRecord[] = [];
    const queued: string[] = [];
    for (const id of this.finished) {
      const record = this.tasks.get(id);
      if (!record) continue;
      if (ids && !ids.includes(id)) {
        queued.push(id);
        continue;
      }
      record.claimed = true;
      claimed.push(record);
    }
    this.finished = queued;
    return claimed;
  }

  /** Resolve true on claimable work, false after `timeoutMs` or on abort. */
  waitForCompletion(timeoutMs: number, ids?: string[], signal?: AbortSignal): Promise<boolean> {
    if (this.hasClaimable(ids)) return Promise.resolve(true);
    if (signal?.aborted) return Promise.resolve(false);
    return new Promise<boolean>((resolve) => {
      let settled = false;
      const settle = (value: boolean) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        signal?.removeEventListener("abort", onAbort);
        this.waiters = this.waiters.filter((w) => w !== onWork);
        resolve(value);
      };
      // A finish outside `ids` must keep the wait going, so re-check on every wake.
      const onWork = () => {
        if (this.hasClaimable(ids)) settle(true);
      };
      const onAbort = () => settle(false);
      const timer = setTimeout(() => settle(false), timeoutMs);
      signal?.addEventListener("abort", onAbort, { once: true });
      this.waiters.push(onWork);
    });
  }

  private hasClaimable(ids?: string[]): boolean {
    return this.finished.some((id) => this.tasks.has(id) && (!ids || ids.includes(id)));
  }

  private notify(): void {
    const waiters = this.waiters;
    this.waiters = [];
    for (const waiter of waiters) waiter();
  }
}
