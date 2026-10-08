// subagents extension entry point.
//
// Loads the subagent configuration once at startup, then registers five tools
// (spawn / status / wait / result / kill) and a `/subagents` command. Each
// spawned task runs in its own in-memory SDK session that inherits the main
// agent's tool set (minus the subagent tools) and a read-only view of the
// main transcript.

import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { randomBytes, randomUUID } from "node:crypto";
import {
  SessionManager,
  getAgentDir,
  type AgentToolResult,
  type ExtensionAPI,
  type ExtensionToolContext,
} from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import type { Usage } from "@earendil-works/pi-ai";
import { loadSubagentConfigs, resolveTools, nameSchema, type ResolvedTools } from "./config.ts";
import { IDLE_AFTER_MS, TaskRegistry, toSummary, type TaskRecord } from "./state.ts";
import { SubagentTask } from "./task.ts";
import { LeaseStore, type LeaseRequest } from "./store.ts";
import {
  emitStatus,
  formatElapsed,
  notifyCompletion,
  renderSpawnCall,
  renderSpawnResult,
  renderStatusCall,
  renderStatusResult,
  renderWaitCall,
  renderWaitResult,
  renderResultCall,
  renderResultResult,
  renderKillCall,
  renderKillResult,
  type SpawnDetails,
  type StatusDetails,
  type WaitDetails,
  type ResultDetails,
  type KillDetails,
} from "./ui.ts";

/** Directory (under the main working directory) for saved subagent sessions. */
const SUBAGENT_SESSION_DIR = join(".pi", "subagents", "sessions");
const OUTPUT_LIMIT = 20000;
const DEFAULT_WAIT_TIMEOUT_S = 300;

/** Minimal view of the command context the lease helpers need. */
type CommandCtx = { ui: { notify: (message: string, type?: "info" | "warning" | "error") => void } };

/** True if a process with this pid currently exists (signal 0 probe). */
function isPidAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (err) {
    // ESRCH: no such process. Anything else (e.g. EPERM) means it is alive.
    return (err as NodeJS.ErrnoException).code === "ESRCH" ? false : true;
  }
}

interface SpawnParams {
  name: string;
  task: string;
  session?: string;
  save_session?: boolean;
  workdir?: boolean;
}

export default function subagents(pi: ExtensionAPI): void {
  // The project config is read from the process working directory at startup.
  const { subagents: configs, groups, errors } = loadSubagentConfigs(process.cwd(), getAgentDir());
  for (const error of errors) console.warn(`[subagents] ${error}`);
  const names = [...configs.keys()];
  const registry = new TaskRegistry();

  // Shared group-concurrency store, one per process; opened lazily on first spawn.
  let store: LeaseStore | undefined;
  function getStore(): LeaseStore {
    if (!store) {
      store = new LeaseStore(join(getAgentDir(), "subagents", "leases.db"), `${randomUUID()}-${process.pid}`);
      store.start();
    }
    return store;
  }

  // ---- helpers -------------------------------------------------------------

  /** Create `.pi/subagents/sessions/<session>-<YYYY-MM-DD>-<HHMMSS>/` and return it. */
  function makeSessionDir(cwd: string, session: string): string {
    const now = new Date().toISOString();
    const stamp = `${now.slice(0, 10)}-${now.slice(11, 17).replace(/:/g, "")}`;
    const base = join(cwd, SUBAGENT_SESSION_DIR, `${session}-${stamp}`);
    let path = base;
    for (let i = 2; existsSync(path); i += 1) path = `${base}-${i}`;
    mkdirSync(path, { recursive: true });
    return path;
  }

  function usageFrom(tokens: number, cost: number): Usage {
    return {
      input: tokens,
      output: 0,
      cacheRead: 0,
      cacheWrite: 0,
      totalTokens: tokens,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: cost },
    };
  }

  function writeTempFile(name: string, content: string): string {
    const dir = join(tmpdir(), "pi-subagents");
    mkdirSync(dir, { recursive: true });
    const path = join(dir, `${name.replace(/[^a-z0-9-]/gi, "-")}-${randomBytes(4).toString("hex")}.txt`);
    writeFileSync(path, content);
    return path;
  }

  function formatStatusLine(record: TaskRecord): string {
    const summary = toSummary(record);
    const idle = summary.idle !== undefined && summary.idle >= IDLE_AFTER_MS ? ` (idle ${formatElapsed(summary.idle)})` : "";
    const activity = summary.lastActivity ? ` — ${summary.lastActivity}${idle}` : "";
    const err = summary.error ? ` — ${summary.error}` : "";
    return `${record.id} · ${record.name} (${record.model}) · ${summary.state} · ${formatElapsed(summary.elapsed)}${activity}${err}`;
  }

  // `/subagents <id>`: the status line, what the task has cost so far, and its recent assistant output.
  function formatDetail(record: TaskRecord): string {
    const summary = toSummary(record);
    const stats = `${summary.turns} turn(s) · ${summary.tokens} tokens${summary.retry ? ` · retry ${summary.retry}` : ""}`;
    const text = (record.lastText || record.output || "").trim();
    const preview = text.length > 500 ? `${text.slice(0, 499).trimEnd()}…` : text;
    return preview
      ? `${formatStatusLine(record)}\n${stats}\n\n${preview}`
      : `${formatStatusLine(record)}\n${stats}`;
  }

  async function killTask(record: TaskRecord): Promise<void> {
    if (record.state !== "running" || !record.runner) return;
    const runner = record.runner as SubagentTask;
    await runner.abort();
    // `abort()` also covers a task whose session is still being created.
    await runner.done();
    if (record.state === "running") {
      record.state = "killed";
      record.finishedAt = record.finishedAt ?? Date.now();
    }
  }

  // `/subagents leases ...` — inspect and clean up group concurrency leases.
  async function handleLeases(args: string[], ctx: CommandCtx): Promise<void> {
    const leaseStore = getStore();
    const sub = args[0];

    if (!sub || sub === "list") {
      const leases = leaseStore.list();
      if (leases.length === 0) {
        ctx.ui.notify("subagents: no active leases");
        return;
      }
      const now = Date.now();
      const lines = leases.map((l) => {
        const when = new Date(l.expiresAt).toISOString();
        const secsLeft = Math.max(0, Math.round((l.expiresAt - now) / 1000));
        return `${l.grp} · ${l.subagent} · pid ${l.pid} · expires ${when} (+${secsLeft}s)`;
      });
      ctx.ui.notify(`subagents: ${leases.length} active lease(s):\n${lines.join("\n")}`);
      return;
    }

    if (sub === "purge") {
      const expired = leaseStore.reap();
      const now = Date.now();
      let dead = 0;
      for (const l of leaseStore.list()) {
        if (l.expiresAt > now && !isPidAlive(l.pid)) {
          leaseStore.release(l.id);
          dead += 1;
        }
      }
      ctx.ui.notify(`subagents: purged ${expired} expired + ${dead} dead-instance lease(s)`);
      return;
    }

    if (sub === "drop-all") {
      const count = leaseStore.list().length;
      leaseStore.releaseAll();
      ctx.ui.notify(`subagents: dropped ${count} lease(s)`);
      return;
    }

    if (sub.startsWith("drop ")) {
      const group = sub.slice("drop ".length).trim();
      if (!group) {
        ctx.ui.notify("subagents: usage: /subagents leases drop <group>", "error");
        return;
      }
      const removed = leaseStore.dropGroup(group);
      ctx.ui.notify(`subagents: dropped ${removed} lease(s) for group "${group}"`);
      return;
    }

    ctx.ui.notify("subagents leases: list | purge | drop <group> | drop-all", "warning");
  }

  // ---- tool schemas --------------------------------------------------------

  const spawnParameters = Type.Object({
    name: nameSchema(names),
    task: Type.String({
      description: "The task to delegate. Be specific about the goal, constraints, and expected output.",
    }),
    session: Type.Optional(
      Type.String({
        description: "Assign a persistent session (kebab-case id, e.g. 'repo-scan'). Use with save_session or workdir to keep the transcript and files under .pi/subagents/sessions/.",
      }),
    ),
    save_session: Type.Optional(
      Type.Boolean({
        description: "Save the subagent session transcript under .pi/subagents/sessions/ so it can be inspected later.",
      }),
    ),
    workdir: Type.Optional(
      Type.Boolean({
        description: "Run the subagent with its session directory as the working directory (isolated scratchpad).",
      }),
    ),
  });

  const idParam = Type.String({ description: "The subagent task id (e.g. 'task-1')." });

  // ---- register tools ------------------------------------------------------

  pi.registerTool({
    name: "subagent_spawn",
    label: "Spawn a background subagent",
    description: "Delegate a task to a configured subagent, which runs in the background.",
    parameters: spawnParameters,
    execute: async (
      _id,
      params: SpawnParams,
      _signal,
      _onUpdate,
      ctx: ExtensionToolContext,
    ): Promise<AgentToolResult<SpawnDetails>> => {
      const config = configs.get(params.name);
      if (!config) {
        throw new Error(`unknown subagent "${params.name}". Configured: ${names.join(", ") || "(none)"}`);
      }
      if (params.session && !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(params.session)) {
        throw new Error(`invalid session name "${params.session}" (use kebab-case, e.g. repo-scan)`);
      }
      if ((params.save_session || params.workdir) && !params.session) {
        throw new Error("save_session and workdir need a session name to put their directory under");
      }

      const model = ctx.modelRegistry.find(config.provider, config.model);
      if (!model) {
        throw new Error(`unknown model "${config.provider}/${config.model}"`);
      }

      // Hold a slot in each of this subagent's groups; reject the spawn if any is full.
      const requests: LeaseRequest[] = [];
      for (const group of config.groups ?? []) {
        const limit = groups.get(group);
        if (limit === undefined) {
          throw new Error(`subagent "${params.name}" names group "${group}", which no config gives a limit`);
        }
        requests.push({ group, limit });
      }
      // An untracked subagent never opens the store.
      const leaseStore = requests.length ? getStore() : undefined;
      const leaseIds = leaseStore ? leaseStore.acquire(params.name, requests) : [];
      if (leaseIds === null) {
        const atCapacity = requests.map((r) => `${r.group} (limit ${r.limit})`).join(", ");
        return {
          content: [{ type: "text", text: `spawn blocked: ${atCapacity} at capacity` }],
          details: { id: null, name: params.name, model: config.model, blocked: true },
          isError: true,
        };
      }

      // Only now is it safe to lay down a session directory: a blocked spawn creates nothing.
      const sessionDir = params.session ? makeSessionDir(ctx.cwd, params.session) : undefined;
      const effectiveCwd = params.workdir && sessionDir ? sessionDir : ctx.cwd;
      const sessionManager =
        sessionDir && params.save_session
          ? SessionManager.create(effectiveCwd, sessionDir)
          : SessionManager.inMemory(effectiveCwd);
      const resolvedTools: ResolvedTools = resolveTools(config);

      const id = registry.nextId();
      const record: TaskRecord = {
        id,
        name: params.name,
        provider: config.provider,
        model: config.model,
        description: config.description,
        taskText: params.task,
        state: "running",
        startedAt: Date.now(),
        lastActivity: "starting…",
        lastActivityAt: Date.now(),
        turns: 0,
        lastText: "",
        output: "",
        recentOutput: "",
        usage: { tokens: 0, cost: 0 },
        groups: config.groups ?? [],
        claimed: false,
      };
      registry.add(record);

      const runner = new SubagentTask({
        record,
        config,
        resolvedTools,
        cwd: effectiveCwd,
        agentDir: getAgentDir(),
        model,
        sessionManager,
        registry,
        leases: leaseIds,
        store: leaseStore,
        mainSessionPath: ctx.sessionManager.getSessionFile(),
        onStatus: () => emitStatus(pi, registry),
        onFinish: (finished) => {
          notifyCompletion(ctx, finished);
          emitStatus(pi, registry);
        },
      });
      void runner.start();
      emitStatus(pi, registry);

      return {
        content: [{ type: "text", text: `spawned ${record.name} as ${id}` }],
        details: { id, name: params.name, model: config.model },
      };
    },
    renderCall: (args, theme) => renderSpawnCall(args, theme),
    renderResult: (result, opts, theme) => renderSpawnResult(result, opts, theme),
  });

  const statusParameters = Type.Object({
    id: Type.Optional(Type.String({ description: "Only report this task id. Omit to report all tasks." })),
  });

  pi.registerTool({
    name: "subagent_status",
    label: "Show subagent task status",
    description: "Report the status of subagent tasks, or one specific task.",
    parameters: statusParameters,
    execute: async (_id, params: { id?: string }, _signal, _onUpdate, _ctx): Promise<AgentToolResult<StatusDetails>> => {
      const target = params.id ? registry.get(params.id) : undefined;
      if (params.id && !target) throw new Error(`no such subagent task "${params.id}"`);
      const tasks = target ? [target] : registry.all();
      const details: StatusDetails = { id: params.id, count: tasks.length, tasks: tasks.map((t) => toSummary(t)) };
      const content = tasks.length === 0 ? "no subagent tasks" : tasks.map(formatStatusLine).join("\n");
      return { content: [{ type: "text", text: content }], details };
    },
    renderCall: (args, theme) => renderStatusCall(args, theme),
    renderResult: (result, opts, theme) => renderStatusResult(result, opts, theme),
  });

  pi.registerTool({
    name: "subagent_wait",
    label: "Wait for subagent tasks to finish",
    description: "Block until one or more subagent tasks finish, then report their outcomes.",
    parameters: Type.Object({
      ids: Type.Optional(Type.Array(Type.String({ description: "Only wait for these task ids." }))),
      timeout_s: Type.Optional(
        Type.Number({ description: `Seconds to wait before returning partial status. Default ${DEFAULT_WAIT_TIMEOUT_S}.` }),
      ),
    }),
    execute: async (
      _id,
      params: { ids?: string[]; timeout_s?: number },
      signal: AbortSignal | undefined,
      onUpdate,
      _ctx,
    ): Promise<AgentToolResult<WaitDetails>> => {
      const ids = params.ids?.length ? params.ids : undefined;
      const matches = (record: TaskRecord) => !ids || ids.includes(record.id);
      const running = () => registry.all().filter((r) => matches(r) && r.state === "running");
      const deadline = Date.now() + (params.timeout_s ?? DEFAULT_WAIT_TIMEOUT_S) * 1000;
      let finished = registry.claimFinished(ids);

      const interval = setInterval(() => {
        const pending = running();
        if (!pending.length) return;
        onUpdate?.({
          content: [
            {
              type: "text",
              text: pending
                .map((r) => `${r.id}: ${r.lastActivity} (${formatElapsed(Date.now() - r.startedAt)})`)
                .join("\n"),
            },
          ],
          details: { count: pending.length, tasks: pending.map((r) => toSummary(r)) },
        });
      }, 1000);
      try {
        while (finished.length === 0 && !signal?.aborted) {
          const remaining = Math.max(0, deadline - Date.now());
          if (remaining <= 0) break;
          if (!(await registry.waitForCompletion(remaining, ids, signal))) break;
          finished.push(...registry.claimFinished(ids));
        }
      } finally {
        clearInterval(interval);
      }

      if (finished.length === 0) {
        const pending = running();
        const stillRunning = pending.map((r) => `${r.id} (${r.name})`).join(", ");
        const text = signal?.aborted
          ? `subagent_wait: interrupted${pending.length ? ` — still running: ${stillRunning}` : ""}`
          : pending.length === 0
            ? ids
              ? "subagent_wait: no such subagent tasks"
              : "subagent_wait: no tasks to wait for"
            : `subagent_wait: timed out — still running: ${stillRunning}`;
        return { content: [{ type: "text", text }], details: { count: 0, tasks: pending.map((r) => toSummary(r)) } };
      }

      const totalTokens = finished.reduce((sum, r) => sum + r.usage.tokens, 0);
      const totalCost = finished.reduce((sum, r) => sum + r.usage.cost, 0);
      return {
        content: [{ type: "text", text: finished.map(formatStatusLine).join("\n") }],
        details: { count: finished.length, tasks: finished.map((r) => toSummary(r)) },
        usage: usageFrom(totalTokens, totalCost),
      };
    },
    renderCall: (args, theme) => renderWaitCall(args, theme),
    renderResult: (result, opts, theme) => renderWaitResult(result, opts, theme),
  });

  pi.registerTool({
    name: "subagent_result",
    label: "Get a subagent task's report",
    description: "Return the full report of a finished subagent task.",
    parameters: Type.Object({ id: idParam }),
    execute: async (_id, params: { id: string }, _signal, _onUpdate, ctx): Promise<AgentToolResult<ResultDetails>> => {
      const record = registry.get(params.id);
      if (!record) throw new Error(`no such subagent task "${params.id}"`);
      if (record.state === "running") throw new Error(`task ${record.id} is still running`);

      notifyCompletion(ctx, record);
      const output = record.output;
      const truncated = output.length > OUTPUT_LIMIT;
      const content = truncated
        ? `${output.slice(0, OUTPUT_LIMIT)}\n\n… (truncated — full copy saved to temp file)`
        : output;
      let fullPath: string | undefined;
      if (truncated) fullPath = writeTempFile(`${record.id}.txt`, output);

      return {
        content: [{ type: "text", text: content }],
        details: { id: record.id, truncated, fullPath },
        usage: usageFrom(record.usage.tokens, record.usage.cost),
      };
    },
    renderCall: (args, theme) => renderResultCall(args, theme),
    renderResult: (result, opts, theme, context) => renderResultResult(result, opts, theme, context),
  });

  pi.registerTool({
    name: "subagent_kill",
    label: "Abort a subagent task",
    description: "Abort a running subagent task and record the outcome as killed.",
    parameters: Type.Object({ id: idParam }),
    execute: async (_id, params: { id: string }, _signal, _onUpdate, _ctx): Promise<AgentToolResult<KillDetails>> => {
      const record = registry.get(params.id);
      if (!record) throw new Error(`no such subagent task "${params.id}"`);
      await killTask(record);
      emitStatus(pi, registry);
      return {
        content: [{ type: "text", text: `subagent task ${record.id} (${record.name}) → ${record.state}` }],
        details: { id: record.id, state: record.state },
      };
    },
    renderCall: (args, theme) => renderKillCall(args, theme),
    renderResult: (result, opts, theme) => renderKillResult(result, opts, theme),
  });

  // ---- slash command -------------------------------------------------------

  pi.registerCommand("subagents", {
    description:
      "subagents: lists tasks; <id> shows one; kill <id> aborts one; leases lists/purges/drops group concurrency leases",
    getArgumentCompletions: (prefix) => {
      if (prefix.startsWith("kill ")) {
        const rest = prefix.slice("kill ".length);
        return registry
          .all()
          .filter((r) => r.state === "running" && r.id.startsWith(rest))
          .map((r) => ({ value: `kill ${r.id}`, label: `${r.id} (${r.name})` }));
      }
      return ["kill", "leases"]
        .filter((a) => a.startsWith(prefix))
        .map((value) => ({ value, label: value === "kill" ? "kill <id>" : value }));
    },
    handler: async (args, ctx) => {
      const parts = args.trim().split(/\s+/).filter(Boolean);
      if (parts[0] === "leases") {
        await handleLeases(parts.slice(1), ctx);
        return;
      }
      if (parts[0] === "kill") {
        const id = parts[1];
        if (!id) {
          ctx.ui.notify("subagents: usage: /subagents kill <id>", "error");
          return;
        }
        const record = registry.get(id);
        if (!record) {
          ctx.ui.notify(`subagents: no such task "${id}"`, "error");
          return;
        }
        await killTask(record);
        ctx.ui.notify(
          `subagents: ${record.id} (${record.name}) → ${record.state}`,
          record.state === "killed" ? "warning" : "info",
        );
      } else if (parts[0]) {
        const record = registry.get(parts[0]);
        if (!record) {
          ctx.ui.notify(`subagents: no such task "${parts[0]}"`, "error");
          return;
        }
        ctx.ui.notify(formatDetail(record));
      } else {
        const lines = registry.all().map(formatStatusLine);
        ctx.ui.notify(lines.length === 0 ? "subagents: no tasks" : lines.join("\n"));
      }
      emitStatus(pi, registry);
    },
  });

  // ---- lifecycle -----------------------------------------------------------

  pi.on("session_start", () => {
    emitStatus(pi, registry);
  });

  pi.on("session_shutdown", () => {
    for (const record of registry.all()) {
      if (record.state === "running") (record.runner as SubagentTask | undefined)?.abort();
    }
    // This instance's slots are freed right away instead of expiring after the TTL.
    store?.close();
  });
}
