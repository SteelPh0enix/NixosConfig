// Runs one subagent task in its own in-memory SDK agent session and reports
// progress back to the registry. The subagent gets the main agent's tool set
// (minus the subagent tools) and a read-only view of the main transcript.

import {
  createAgentSession,
  createCodemodeExtension,
  DefaultResourceLoader,
  SessionManager,
  SettingsManager,
  type AgentSession,
  type AgentSessionEvent,
} from "@earendil-works/pi-coding-agent";
import type { AgentMessage } from "@earendil-works/pi-agent-core";
import type { Model } from "@earendil-works/pi-ai/compat";
import type { SubagentConfig, ResolvedTools } from "./config.ts";
import type { TaskRegistry, TaskRecord } from "./state.ts";
import type { LeaseStore } from "./store.ts";

type TaskCallback = (record: TaskRecord) => void;

export interface StartTaskOptions {
  record: TaskRecord;
  config: SubagentConfig;
  resolvedTools: ResolvedTools;
  /** Working directory for the task (the saved-session dir when `workdir` is set). */
  cwd: string;
  agentDir: string;
  model: Model<any>;
  sessionManager: SessionManager;
  registry: TaskRegistry;
  /** Lease ids acquired for this task's groups; released when the task ends. */
  leases?: number[];
  store?: LeaseStore;
  /** Live main-transcript path, passed to the subagent for read-only reference. */
  mainSessionPath?: string;
  /** Progress callback, throttled by `onEvent`. */
  onStatus: TaskCallback;
  /** Terminal callback: called exactly once, after the outcome is recorded. */
  onFinish: TaskCallback;
}

const RECENT_OUTPUT_LIMIT = 2000;
const STATUS_THROTTLE_MS = 1000;

export class SubagentTask {
  private readonly options: StartTaskOptions;
  private session?: AgentSession;
  private unsubscribe?: () => void;
  private lastAssistant?: AgentMessage;
  private aborted = false;
  private lastStatusEmit = 0;
  private readonly donePromise: Promise<void>;
  private resolveDone!: () => void;

  constructor(options: StartTaskOptions) {
    this.options = options;
    this.donePromise = new Promise<void>((resolve) => {
      this.resolveDone = resolve;
    });
  }

  /** Resolves once the task has settled (so `subagent_kill` can read the outcome). */
  done(): Promise<void> {
    return this.donePromise;
  }

  /** Abort the active prompt; the outcome is recorded once the prompt settles. */
  async abort(): Promise<void> {
    this.aborted = true;
    // Aborts that land before `createAgentSession` resolves are picked up by `start()`.
    await this.session?.abort();
  }

  async start(): Promise<void> {
    const { record, resolvedTools, cwd, agentDir, model, sessionManager, mainSessionPath } = this.options;
    record.runner = this;

    try {
      // pi only loads codemode, tool_search and MCP in the CLI; an SDK session gets none of them
      // unless the resource loader supplies the extension, and then a tool name in `tools` activates it.
      const settingsManager = SettingsManager.create(cwd, agentDir);
      const resourceLoader = new DefaultResourceLoader({
        cwd,
        agentDir,
        settingsManager,
        extensionFactories: [createCodemodeExtension()],
      });
      await resourceLoader.reload();
      this.session = (await createAgentSession({
        cwd,
        agentDir,
        model,
        sessionManager,
        settingsManager,
        resourceLoader,
        tools: resolvedTools.tools,
        excludeTools: resolvedTools.excludeTools,
      })).session;
      if (!this.aborted) {
        this.subscribe();
        await this.session.prompt(this.buildPrompt());
      }
    } catch (err) {
      record.state = "failed";
      record.error = err instanceof Error ? err.message : String(err);
    }

    // The tail always runs: a task that never reports would hang `subagent_wait`.
    try {
      this.applyOutcome();
    } catch (err) {
      record.state = "failed";
      record.error ??= err instanceof Error ? err.message : String(err);
      record.finishedAt ??= Date.now();
    }
    this.unsubscribe?.();
    try {
      this.session?.dispose();
    } catch {
      // A failed cleanup still has to resolve done().
    }
    this.releaseLeases();
    this.options.registry.markFinished(record.id);
    try {
      this.options.onFinish(record);
    } catch {
      // A broken notification must not swallow the outcome.
    }
    this.resolveDone();
  }

  /** Free this task's group leases (called on every terminal path, and by a kill that will not be waited for). */
  releaseLeases(): void {
    const { store, leases } = this.options;
    if (!store || !leases) return;
    for (const id of leases) store.release(id);
  }

  private subscribe(): void {
    if (!this.session) return;
    this.unsubscribe = this.session.subscribe((event) => this.onEvent(event));
  }

  /** What the subagent is doing right now, so a task stuck on a silent server is recognisable. */
  private note(activity: string): void {
    const { record } = this.options;
    record.lastActivity = activity;
    record.lastActivityAt = Date.now();
  }

  private onEvent(event: AgentSessionEvent): void {
    const { record } = this.options;
    if (event.type === "turn_start") {
      // An abort also opens the next turn; that one must not overwrite the line the task stopped on.
      if (!this.aborted) this.note("thinking…");
    } else if (event.type === "message_update") {
      const delta = event.assistantMessageEvent?.type;
      if (delta === "text_delta" || delta === "reasoning_delta") {
        this.note("writing…");
        // What the model has produced so far, counted off the partial message: an estimate, corrected exactly when
        // the turn ends and the provider reports its own figure.
        record.usage.streaming = Math.round(generatedChars(event.message) / 4);
      }
      // `event.message` is the partial message, so the report reaches the record while it is still being written.
      if (delta === "text_delta") record.lastText = extractText(event.message);
    } else if (event.type === "message_end" && event.message.role === "assistant") {
      this.lastAssistant = event.message;
      record.turns += 1;
      record.lastText = extractText(event.message);
      record.usage.streaming = 0;
      const usage = event.message.usage;
      if (usage) {
        record.usage.tokens += usage.totalTokens;
        record.usage.generated += usage.output ?? 0;
        record.usage.cost += usage.cost?.total ?? 0;
      }
      // An abort lands here as an assistant error message. Painting "model error: ... aborted" over the tool the
      // subagent was running would make a task we stopped ourselves look like one that crashed.
      if (!this.aborted && event.message.stopReason !== "aborted") {
        this.note(
          event.message.stopReason === "error"
            ? `model error: ${oneLine(event.message.errorMessage ?? "unknown error", 120)}`
            : "writing…",
        );
      }
    } else if (event.type === "tool_execution_start") {
      const summary = summarizeArgs(event.toolName, event.args);
      this.note(summary ? `${event.toolName}: ${summary}` : event.toolName);
    } else if (event.type === "auto_retry_start") {
      record.retry = `${event.attempt}/${event.maxAttempts} after ${Math.ceil(event.delayMs / 1000)}s`;
      this.note(`retrying: ${oneLine(event.errorMessage, 120)}`);
    } else if (event.type === "auto_retry_end") {
      record.retry = undefined;
      this.note(
        event.success
          ? `answered after ${event.attempt} attempt(s)`
          : event.finalError
            ? `gave up: ${oneLine(event.finalError, 120)}`
            : "retry cancelled",
      );
    }
    const now = Date.now();
    if (now - this.lastStatusEmit >= STATUS_THROTTLE_MS) {
      this.lastStatusEmit = now;
      this.readContextUsage();
      this.options.onStatus(this.options.record);
    }
  }

  /** What its model holds right now, for the `ctx used/window (%)` the status and the wait widget report. */
  private readContextUsage(): void {
    const { record } = this.options;
    try {
      const usage = this.session?.getContextUsage();
      if (usage) record.context = { tokens: usage.tokens, contextWindow: usage.contextWindow, percent: usage.percent };
    } catch {
      // A session on its way out has no context to report; the last figure stays.
    }
  }

  private buildPrompt(): string {
    const { record, mainSessionPath } = this.options;
    const parts = [
      "You are a background subagent handling a single delegated task. You cannot spawn or manage other subagents, and you cannot see or affect other subagents.",
    ];
    if (mainSessionPath) {
      parts.push(
        `Read-only reference: the main agent's conversation transcript is at ${mainSessionPath}. ` +
          "It is an append-only JSONL log; read it with the read tool (follow the parentId chain from the latest entry). Do not edit it.",
      );
    }
    parts.push(
      "",
      "When your work is complete, reply with a clear, self-contained report of your findings.",
      "Your task:",
      record.taskText,
    );
    return parts.join("\n");
  }

  private applyOutcome(): void {
    const { record } = this.options;
    const assistant = this.lastAssistant?.role === "assistant" ? this.lastAssistant : undefined;
    if (this.aborted || assistant?.stopReason === "aborted") {
      record.state = "killed";
    } else if (assistant?.stopReason === "error") {
      record.state = "failed";
      record.error = assistant.errorMessage ?? "Model returned an error";
    } else if (record.state !== "failed") {
      // Do not overwrite a failure the prompt() catch already recorded.
      record.state = "done";
      if (assistant?.stopReason === "length") record.error = "report hit the model's output limit";
    }
    record.finishedAt = Date.now();
    record.usage.streaming = 0;
    record.output = assistant ? extractText(assistant) : (this.session?.getLastAssistantText() ?? "");
    record.recentOutput = record.output.slice(-RECENT_OUTPUT_LIMIT);
    // The last figure the task's model reported is the one worth showing next to its totals.
    this.readContextUsage();
    if (!record.output && record.lastText.trim()) {
      // A task killed between turns still said something; better than handing back nothing.
      record.output = record.lastText.trim();
      record.recentOutput = record.output.slice(-RECENT_OUTPUT_LIMIT);
    }
    // A settled task has no "right now", and the last thing it did reads as if it were still going. Where it stopped
    // is worth keeping when it was aborted.
    if (record.state !== "killed") record.lastActivity = "";
  }
}

export function extractText(message: AgentMessage): string {
  if (message.role !== "assistant") return "";
  return message.content
    .filter((c) => c.type === "text")
    .map((c) => c.text)
    .join("\n")
    .trim();
}

/** Everything the model has produced for this message, thinking included, for the token estimate while it writes. */
function generatedChars(message: AgentMessage): number {
  if (message.role !== "assistant") return 0;
  let chars = 0;
  for (const block of message.content) {
    if (block.type === "text") chars += block.text.length;
    else if (block.type === "thinking") chars += block.thinking.length;
  }
  return chars;
}

function oneLine(value: string, limit: number): string {
  const text = value.replace(/\s+/g, " ").trim();
  return text.length > limit ? `${text.slice(0, limit - 1).trimEnd()}…` : text;
}

function summarizeArgs(toolName: string, args: unknown): string {
  if (!args || typeof args !== "object") return "";
  const a = args as Record<string, unknown>;
  const pick = (...keys: string[]): string => {
    for (const k of keys) {
      const v = a[k];
      if (typeof v === "string" && v.trim()) return v.trim().replace(/\s+/g, " ").slice(0, 60);
    }
    return "";
  };
  const s =
    toolName === "bash" || toolName === "powershell" ? pick("command", "cmd") :
    toolName === "web_search" ? pick("query") :
    toolName === "web_fetch" ? pick("url", "uri") :
    pick("path", "file", "filename");
  return s || "";
}
