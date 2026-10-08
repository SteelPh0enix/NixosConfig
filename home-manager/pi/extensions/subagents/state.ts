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
  /**
   * Accumulated model usage so the main session's token totals stay accurate. `generated` is what its own model
   * wrote; `streaming` is the running estimate for the turn being decoded right now, corrected at `message_end`.
   */
  usage: { tokens: number; cost: number; generated: number; streaming?: number };
  /**
   * What the subagent's model is holding right now, straight from pi: `tokens` out of `contextWindow`, and the
   * percentage. `tokens` is null when pi cannot estimate it yet (a task that has not been answered, or one that has
   * just compacted). Refreshed with every status emit, so a blocked wait shows it moving.
   */
  context?: { tokens: number | null; contextWindow: number; percent: number | null };
  error?: string;
  /** Tail of the output, for the `/subagents <id>` detail view and result blocks. */
  recentOutput: string;
  /** Groups this task holds a lease in (empty when the subagent is untracked). */
  groups: string[];
  /** Whether `subagent_wait` has already delivered this task to the main agent. */
  claimed: boolean;
  /** Whether this task's tokens and cost have already been reported to the main session (they must be once). */
  usageReported?: boolean;
  /** Whether the completion toast has already fired. */
  notified?: boolean;
  /** Live only: the runner driving this task (its SubagentTask). */
  runner?: TaskRunner;
}

/** What a task's runner offers to whoever wants it stopped. */
export interface TaskRunner {
  abort(): Promise<void>;
  done(): Promise<void>;
  releaseLeases(): void;
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
  /** Tokens the subagent's own model produced, as opposed to everything it read. */
  generated: number;
  /** True while `generated` still counts the in-flight estimate rather than the model's own figure. */
  generatedLive?: boolean;
  /** What its model holds right now: pi's context estimate, its window, and the percentage. */
  contextTokens?: number | null;
  contextWindow?: number;
  contextPercent?: number | null;
  lastActivity: string;
  retry?: string;
  error?: string;
  recentOutput: string;
  /**
   * Last lines of the task's own text, for the live `subagent_wait` widget. Only set by that widget's progress
   * updates, so it never reaches the session file and never carries a finished task's report.
   */
  preview?: string;
}

const SUMMARY_OUTPUT_LIMIT = 1000;

/** Idle a running task may sit silent for before the status line says so. */
export const IDLE_AFTER_MS = 15_000;

/** Tokens of the turn being decoded right now, counted off the stream; 0 once the turn has ended. */
function liveGenerated(record: TaskRecord): number {
  return record.state === "running" ? (record.usage.streaming ?? 0) : 0;
}

/** Resolve true once `pending` settles, false after `ms`. Never rejects, and never takes longer than `ms`. */
export function withTimeout(pending: Promise<unknown>, ms: number): Promise<boolean> {
  return new Promise<boolean>((resolve) => {
    const timer = setTimeout(() => resolve(false), Math.max(0, ms));
    const settle = () => {
      clearTimeout(timer);
      resolve(true);
    };
    pending.then(settle, settle);
  });
}

/**
 * Abort a task and report whether it wound down inside `timeoutMs`. Nothing here may block the caller for longer than
 * it was told to: a task whose session is still being created has nothing to abort and no deadline of its own, and
 * the main agent must not end up waiting for it. A task that does not settle is marked killed anyway and hands its
 * group slots back, so the abandoned runner cannot hold a group while it finishes on its own.
 */
export async function killRecord(record: TaskRecord, timeoutMs: number): Promise<boolean> {
  if (record.state !== "running") return true;
  const runner = record.runner;
  if (!runner) return true;
  // A failed abort is not worth an error of its own: the timeout still ends the kill and the lease TTL frees the group.
  void runner.abort().catch(() => {});
  const settled = await withTimeout(runner.done(), timeoutMs);
  if (record.state === "running") {
    record.state = "killed";
    record.finishedAt = record.finishedAt ?? Date.now();
    // A task stopped between turns still said something; better than reporting nothing.
    if (!record.output && record.lastText.trim()) {
      record.output = record.lastText.trim();
      record.recentOutput = record.output;
    }
  }
  if (!settled) runner.releaseLeases();
  return settled;
}

export function toSummary(record: TaskRecord, now = Date.now()): TaskSummary {
  return {
    id: record.id,
    name: record.name,
    model: record.model,
    state: record.state,
    elapsed: Math.max(0, (record.finishedAt ?? now) - record.startedAt),
    idle: record.state === "running" ? Math.max(0, now - record.lastActivityAt) : undefined,
    turns: record.turns,
    tokens: record.usage.tokens,
    generated: (record.usage.generated ?? 0) + liveGenerated(record),
    generatedLive: liveGenerated(record) > 0,
    contextTokens: record.context?.tokens,
    contextWindow: record.context?.contextWindow,
    contextPercent: record.context?.percent,
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

  /**
   * Note that a task has been reported by some route other than the queue (its report was read directly), so a later
   * `subagent_wait` does not hand the same finished task out a second time.
   */
  delivered(id: string): void {
    this.finished = this.finished.filter((queued) => queued !== id);
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
      // The wait is where the main agent normally collects a task, so that is where its cost gets counted.
      record.usageReported = true;
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
    // Each waiter takes itself off the list once it settles. One that stayed waiting (its ids did not match this
    // finish) has to survive, or the task it does wait for can never wake it and the wait sits out its timeout.
    for (const waiter of [...this.waiters]) waiter();
  }
}
