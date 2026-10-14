// The task model: what a task is, what a compact view of it looks like, and the derived fields a status line needs.
// Node-only, so the offline suite can load it directly.

export type TaskState = "running" | "done" | "failed" | "killed";

/** One finished tool call, for the `read 0.3s · edit 1.1s` breadcrumb. */
export interface ToolCall {
  name: string;
  /** One-line argument summary (the path, the command); empty when there is nothing worth quoting. */
  summary: string;
  durationMs: number;
  isError: boolean;
}

export interface TaskRecord {
  id: string;
  name: string;
  provider: string;
  model: string;
  taskText: string;
  state: TaskState;
  startedAt: number;
  finishedAt?: number;
  /** Last thing the subagent did, for the status bar and `/subagents <id>`. */
  lastActivity: string;
  lastActivityAt: number;
  /** The tool call running right now, if any, with when it started so its timer can climb. */
  currentTool?: { name: string; summary: string; startedAt: number };
  /** The last few finished tool calls, newest last, for the breadcrumb. */
  recentTools?: ToolCall[];
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
  /**
   * The slot label this task was handed on its model: `index` among the model's live slots, `total` the model's slot
   * count. A label, not a reservation — it shifts as other tasks on the same model finish.
   */
  slot?: { index: number; total: number };
  /** Whether this task's tokens and cost have already been reported to the main session (they must be once). */
  usageReported?: boolean;
  /** Whether the completion toast has already fired. */
  notified?: boolean;
  /** Live only: the runner driving this task (its SubagentTask). */
  runner?: TaskRunner;
}

/** What a task's runner offers to whoever wants it stopped. */
interface TaskRunner {
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
  /** The tool running right now, with how long it has been running; only while one is. */
  tool?: { name: string; summary: string; elapsed: number };
  /** The last few finished tool calls, newest last. */
  recentTools: ToolCall[];
  retry?: string;
  error?: string;
  /** Tail of the output, for the `/subagents <id>` detail view and result blocks. */
  recentOutput: string;
  /** The slot label this task is showing, when its model has more than one slot. */
  slot?: { index: number; total: number };
  /**
   * Last lines of the task's own text, for the live `subagent_wait` widget. Only set by that widget's progress
   * updates, so it never reaches the session file and never carries a finished task's report.
   */
  preview?: string;
}

const SUMMARY_OUTPUT_LIMIT = 1000;
/** How much of a task's own text `recentOutput` carries: the tail of its report, or of what it said when it never wrote one. */
export const RECENT_OUTPUT_LIMIT = 2000;

/** Idle a running task may sit silent for before the status line says so. */
export const IDLE_AFTER_MS = 15_000;

/** How many finished tool calls the breadcrumb keeps. */
export const RECENT_TOOLS_LIMIT = 4;

/** Tokens of the turn being decoded right now, counted off the stream; 0 once the turn has ended. */
function liveGenerated(record: TaskRecord): number {
  return record.state === "running" ? (record.usage.streaming ?? 0) : 0;
}

/** Hand a task that never wrote a report the last thing it said, so there is something to read instead of nothing. */
export function keepSaidText(record: TaskRecord): void {
  if (record.output || !record.lastText.trim()) return;
  record.output = record.lastText.trim();
  record.recentOutput = record.output.slice(-RECENT_OUTPUT_LIMIT);
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
    tool: record.currentTool
      ? { name: record.currentTool.name, summary: record.currentTool.summary, elapsed: Math.max(0, now - record.currentTool.startedAt) }
      : undefined,
    recentTools: record.recentTools ?? [],
    retry: record.retry,
    error: record.error,
    recentOutput: record.recentOutput.slice(-SUMMARY_OUTPUT_LIMIT),
    slot: record.slot,
  };
}
