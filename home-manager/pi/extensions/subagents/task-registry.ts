// The task registry and the completion queue that `subagent_wait` drains. One registry per extension instance
// (each session gets its own), so a subagent's tasks are never visible to the main agent. Node-only.

import type { TaskRecord } from "./task-record.ts";

/**
 * Completion queue for `subagent_wait`.
 *
 * - `claimFinished(ids)` takes finished tasks off the queue, so the main agent sees each result exactly once. When
 *   `ids` is given, only those tasks are taken; the rest stay queued for later.
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
    // The safety net for a runner that never settled: a record still marked running is queued as done. It never
    // overwrites a terminal state, so a task killed before its runner noticed stays killed.
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
