// Runs one subagent task in its own in-memory SDK agent session and reports
// progress back to the registry. The subagent gets the main agent's tool set
// (minus the subagent tools) and a read-only view of the main transcript.

import { createAgentSession, SessionManager, type AgentSession, type AgentSessionEvent } from "@earendil-works/pi-coding-agent";
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
      this.session = (await createAgentSession({
        cwd,
        agentDir,
        model,
        sessionManager,
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

  /** Free this task's group leases (called on every terminal path). */
  private releaseLeases(): void {
    const { store, leases } = this.options;
    if (!store || !leases) return;
    for (const id of leases) store.release(id);
  }

  private subscribe(): void {
    if (!this.session) return;
    this.unsubscribe = this.session.subscribe((event) => this.onEvent(event));
  }

  private onEvent(event: AgentSessionEvent): void {
    const { record } = this.options;
    if (event.type === "message_end" && event.message.role === "assistant") {
      this.lastAssistant = event.message;
      record.lastText = extractText(event.message);
      const usage = event.message.usage;
      if (usage) {
        record.usage.tokens += usage.totalTokens;
        record.usage.cost += usage.cost?.total ?? 0;
      }
      record.lastActivity = "writing…";
      record.lastActivityAt = Date.now();
    } else if (event.type === "tool_execution_start") {
      const summary = summarizeArgs(event.toolName, event.args);
      record.lastActivity = summary ? `${event.toolName}: ${summary}` : event.toolName;
      record.lastActivityAt = Date.now();
    }
    const now = Date.now();
    if (now - this.lastStatusEmit >= STATUS_THROTTLE_MS) {
      this.lastStatusEmit = now;
      this.options.onStatus(this.options.record);
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
    record.output = assistant ? extractText(assistant) : (this.session?.getLastAssistantText() ?? "");
    record.recentOutput = record.output.slice(-RECENT_OUTPUT_LIMIT);
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
