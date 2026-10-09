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
import { IDLE_AFTER_MS, killRecord, TaskRegistry, toSummary, type TaskRecord } from "./state.ts";
import { SubagentTask } from "./task.ts";
import { LeaseStore, type LeaseRequest, type AcquireResult } from "./store.ts";
import { SlotResolver } from "./slots.ts";
import {
  emitStatus,
  formatElapsed,
  formatTokenStats,
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
  tailLines,
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
/**
 * How long a kill waits for the task to actually wind down. Nothing in this extension may block the main agent for
 * longer than it says it will, and a task stuck inside a session that is still starting up never settles on its own.
 */
const DEFAULT_KILL_TIMEOUT_S = 10;

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
  const { subagents: configs, groups, slots, errors } = loadSubagentConfigs(process.cwd(), getAgentDir());
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

  // One slot resolver per provider, so its short cache outlives a spawn: each provider is asked for its slot counts
  // about every 30 s rather than on every spawn.
  const resolvers = new Map<string, SlotResolver>();
  async function slotsFor(provider: string, providerModel: string, baseUrl: string): Promise<number> {
    const resolver = resolvers.get(provider) ?? new SlotResolver(baseUrl, provider);
    resolvers.set(provider, resolver);
    return resolver.slotsFor(providerModel, slots.get(providerModel));
  }

  // ---- helpers -------------------------------------------------------------

  /** Create `.pi/subagents/sessions/<session>-<YYYY-MM-DD>-<HHMMSS>/` and return it. */
  function makeSessionDir(cwd: string, session: string): string {
    const now = new Date().toISOString();
    const stamp = `${now.slice(0, 10)}-${now.slice(11, 19).replace(/:/g, "")}`;
    const base = join(cwd, SUBAGENT_SESSION_DIR, `${session}-${stamp}`);
    let path = base;
    for (let i = 2; existsSync(path); i += 1) path = `${base}-${i}`;
    mkdirSync(path, { recursive: true });
    return path;
  }

  /**
   * A `Usage` for a finished task, so its calls reach the main session's totals. What its own model wrote goes as
   * `output` and the rest as `input`; the cache split is not something a task records per direction.
   */
  function usageFrom(tokens: number, cost: number, generated = 0): Usage {
    const output = Math.min(Math.max(0, generated), tokens);
    return {
      input: tokens - output,
      output,
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
    const slot = summary.slot && summary.slot.total > 1 ? ` (slot ${summary.slot.index}/${summary.slot.total})` : "";
    const activity = summary.lastActivity ? ` — ${summary.lastActivity}${slot}${idle}` : "";
    const err = summary.error ? ` — ${summary.error}` : "";
    return `${record.id} · ${record.name} (${record.model}) · ${summary.state} · ${formatElapsed(summary.elapsed)}${activity}${err}`;
  }

  // `/subagents <id>`: the status line, what the task has cost so far, and its recent assistant output.
  function formatDetail(record: TaskRecord): string {
    const summary = toSummary(record);
    const stats = [`${summary.turns} turn(s)`, `${summary.tokens} tokens`, formatTokenStats(summary), summary.retry ? `retry ${summary.retry}` : ""]
      .filter(Boolean)
      .join(" · ");
    const text = (record.lastText || record.output || "").trim();
    const preview = text.length > 500 ? `${text.slice(0, 499).trimEnd()}…` : text;
    return preview
      ? `${formatStatusLine(record)}\n${stats}\n\n${preview}`
      : `${formatStatusLine(record)}\n${stats}`;
  }

  /** The status line plus what the task's model cost and how full its context window is. */
  function formatReportLine(record: TaskRecord): string {
    const stats = formatTokenStats(toSummary(record));
    const line = formatStatusLine(record);
    return stats ? `${line} · ${stats}` : line;
  }

  /** Abort a task without ever waiting on it longer than `timeoutS` (see `killRecord`). */
  function killTask(record: TaskRecord, timeoutS = DEFAULT_KILL_TIMEOUT_S): Promise<boolean> {
    return killRecord(record, timeoutS * 1000);
  }

  /**
   * Why a wait had nothing to deliver: nothing exists at all, the ids name no task, or the tasks it was given have
   * already reported. `delivered` is what a wait that ran out of time says about the last case, which it cannot tell
   * apart from a task that never entered the queue.
   */
  function nothingMessage(ids: string[] | undefined, delivered: boolean): string {
    if (!ids || ids.length === 0) return "subagent_wait: no tasks to wait for";
    const unknown = ids.filter((id) => !registry.get(id));
    if (unknown.length === ids.length) return `subagent_wait: no such subagent tasks: ${unknown.join(", ")}`;
    if (unknown.length > 0) return `subagent_wait: nothing new — no such subagent tasks: ${unknown.join(", ")}`;
    const known = ids
      .map((id) => registry.get(id))
      .filter((r): r is TaskRecord => r !== undefined)
      .map((r) => `${r.id} (${r.state})`)
      .join(", ");
    return delivered ? `subagent_wait: nothing new — already delivered: ${known}` : `subagent_wait: nothing new — ${known}`;
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
        return `${l.grp} (${l.resKey}) · ${l.subagent} · pid ${l.pid} · expires ${when} (+${secsLeft}s)`;
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

      // llama-compat fills a llama.cpp model's context size from the server, and --fit can answer differently from
      // one load to the next, so ask the provider for its live figures before resolving. A server that is not
      // answering is not the subagent's problem: pi keeps the catalog it already has and the spawn goes ahead.
      await ctx.modelRegistry.refresh({ providers: [config.provider], force: true }).catch(() => {});
      const model = ctx.modelRegistry.find(config.provider, config.model);
      if (!model) {
        throw new Error(`unknown model "${config.provider}/${config.model}"`);
      }

      // A group's limit counts distinct models; within a model the capacity is that model's own slot count. Resolve
      // it (config override, then the server's --parallel, then 1) before taking any slot. Discovery reads only
      // /v1/models, so it never loads or swaps the resident model, and a silent server means one slot.
      const providerModel = `${config.provider}/${config.model}`;
      const capacity = await slotsFor(config.provider, providerModel, model.baseUrl);

      // Hold a slot in each of this subagent's groups; reject if another model already holds a group or this model's
      // own slots are gone. Every group this spawn takes shares one claim, so it counts once toward capacity.
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
      const lease: AcquireResult = leaseStore
        ? leaseStore.acquire(params.name, { key: providerModel, capacity, claim: randomUUID() }, requests)
        : { ok: true, ids: [], slot: { index: 1, total: capacity } };
      if (!lease.ok) {
        const modelId = providerModel.slice(providerModel.lastIndexOf("/") + 1);
        const message =
          lease.reason === "resident"
            ? `"${lease.group}" is holding ${lease.at} (limit ${lease.limit} model)`
            : `${modelId} has no free slot (${lease.capacity} slots on ${lease.at})`;
        return {
          content: [{ type: "text", text: `spawn blocked: ${message}` }],
          details: { id: null, name: params.name, model: config.model, blocked: true },
          isError: true,
        };
      }

      // Only now is it safe to lay down a session directory: a blocked spawn creates nothing, and neither does a
      // bare session name, which asks for no transcript and no scratchpad.
      const sessionDir =
        params.session && (params.save_session || params.workdir) ? makeSessionDir(ctx.cwd, params.session) : undefined;
      const effectiveCwd = params.workdir && sessionDir ? sessionDir : ctx.cwd;
      const sessionManager =
        params.save_session && sessionDir
          ? SessionManager.create(effectiveCwd, sessionDir)
          : SessionManager.inMemory(effectiveCwd);
      // A subagent without an exact allowlist inherits what the main agent has right now.
      const resolvedTools: ResolvedTools = resolveTools(config, pi.getActiveTools());

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
        usage: { tokens: 0, cost: 0, generated: 0 },
        groups: config.groups ?? [],
        slot: lease.slot,
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
        leases: lease.ids,
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
        details: { id, name: params.name, model: config.model, slot: record.slot },
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
      const content = tasks.length === 0 ? "no subagent tasks" : tasks.map(formatReportLine).join("\n");
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
      const timeoutS = params.timeout_s ?? DEFAULT_WAIT_TIMEOUT_S;
      let finished = registry.claimFinished(ids);
      // Nothing running and nothing queued means there is nothing this wait could ever deliver, so waiting for
      // `timeout_s` of it would just be standing still: say so at once. An already-aborted request says that instead.
      if (!signal?.aborted && finished.length === 0 && running().length === 0) {
        return { content: [{ type: "text", text: nothingMessage(ids, false) }], details: { count: 0, tasks: [] } };
      }
      const deadline = Date.now() + timeoutS * 1000;

      const interval = setInterval(() => {
        const pending = running();
        if (!pending.length) return;
        // The session can be replaced while this blocks, and a dead renderer must not end the wait or take pi down.
        try {
          const views = pending.map((r) => {
            const summary = toSummary(r);
            const stats = formatTokenStats(summary);
            return {
              summary: { ...summary, preview: tailLines(r.lastText) },
              line: `${r.id}: ${r.lastActivity} (${formatElapsed(summary.elapsed)})${stats ? ` ${stats}` : ""}`,
            };
          });
          onUpdate?.({
            content: [{ type: "text", text: views.map((v) => v.line).join("\n") }],
            details: { count: pending.length, tasks: views.map((v) => v.summary) },
          });
        } catch {
          // The next tick reports again.
        }
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
        // Tasks that were already delivered stay in the registry, so "no such task" would be a lie: say what happened.
        const text = signal?.aborted
          ? `subagent_wait: interrupted${pending.length ? ` — still running: ${stillRunning}` : ""}`
          : pending.length !== 0
            ? `subagent_wait: timed out — still running: ${stillRunning}`
            : nothingMessage(ids, true);
        return { content: [{ type: "text", text }], details: { count: 0, tasks: pending.map((r) => toSummary(r)) } };
      }

      const total = (pick: (record: TaskRecord) => number) => finished.reduce((sum, r) => sum + pick(r), 0);
      return {
        content: [{ type: "text", text: finished.map(formatReportLine).join("\n") }],
        details: { count: finished.length, tasks: finished.map((r) => toSummary(r)) },
        usage: usageFrom(total((r) => r.usage.tokens), total((r) => r.usage.cost), total((r) => r.usage.generated)),
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
      // Reading the report counts as collecting the task, so a later `subagent_wait` does not deliver it a second time.
      registry.delivered(record.id);
      const output = record.output;
      const truncated = output.length > OUTPUT_LIMIT;
      // A task can settle with nothing to show (killed before it spoke, cut off mid tool call), and one that failed
      // before the model answered has only its error. Say which, rather than hand back an empty block.
      const content = !output
        ? `task ${record.id} (${record.name}) ended as ${record.state} with no report text${record.error ? `: ${record.error}` : ""}`
        : truncated
          ? `${output.slice(0, OUTPUT_LIMIT)}\n\n… (truncated — full copy saved to temp file)`
          : output;
      let fullPath: string | undefined;
      if (truncated) fullPath = writeTempFile(`${record.id}.txt`, output);
      // Report what the subagent cost once, whoever collects it first: pi adds up every tool result's usage.
      const reportUsage = !record.usageReported;
      record.usageReported = true;

      // What the task cost, said once next to its report rather than only in the tool metadata.
      const stats = formatTokenStats(toSummary(record));
      return {
        content: [{ type: "text", text: stats ? `${content}\n\n[${stats}]` : content }],
        details: { id: record.id, truncated, fullPath },
        ...(reportUsage ? { usage: usageFrom(record.usage.tokens, record.usage.cost, record.usage.generated) } : {}),
      };
    },
    renderCall: (args, theme) => renderResultCall(args, theme),
    renderResult: (result, opts, theme, context) => renderResultResult(result, opts, theme, context),
  });

  pi.registerTool({
    name: "subagent_kill",
    label: "Abort a subagent task",
    description: "Abort a running subagent task and record the outcome as killed.",
    parameters: Type.Object({
      id: idParam,
      timeout_s: Type.Optional(
        Type.Number({ description: `How long to wait for the task to wind down before marking it killed anyway. Default ${DEFAULT_KILL_TIMEOUT_S}.` }),
      ),
    }),
    execute: async (_id, params: { id: string; timeout_s?: number }, _signal, _onUpdate, _ctx): Promise<AgentToolResult<KillDetails>> => {
      const record = registry.get(params.id);
      if (!record) throw new Error(`no such subagent task "${params.id}"`);
      const timeoutS = params.timeout_s ?? DEFAULT_KILL_TIMEOUT_S;
      const settled = await killTask(record, timeoutS);
      emitStatus(pi, registry);
      return {
        content: [
          {
            type: "text",
            text: `subagent task ${record.id} (${record.name}) → ${record.state}${
              settled
                ? ""
                : ` (its own cleanup was still running after ${timeoutS}s; it is marked killed and its group slots are free — the abandoned runner finishes on its own)`
            }`,
          },
        ],
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
        const settled = await killTask(record);
        ctx.ui.notify(
          `subagents: ${record.id} (${record.name}) → ${record.state}${settled ? "" : " (its cleanup is still winding down; the group slots were freed)"}`,
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

  pi.on("session_start", (_event, ctx) => {
    // Load-time complaints go to stderr with everything else at startup; repeating them here means the user actually
    // sees them in the TUI, where a missing or half-broken subagent list otherwise just looks like an empty one.
    if (errors.length > 0) {
      ctx.ui.notify(
        errors.length === 1 ? `subagents: ${errors[0]}` : `subagents: ${errors.length} problems in subagents.json — ${errors[0]}`,
        "warning",
      );
    }
    emitStatus(pi, registry);
  });

  pi.on("session_shutdown", () => {
    for (const record of registry.all()) {
      // Fire-and-forget by necessity (pi does not wait for us), and nothing may reject unhandled here. The kill is
      // given no time at all: on the way out we free the record and let the shared lease TTL clear the group.
      void killRecord(record, 0).catch(() => {});
    }
    // This instance's slots are freed right away instead of expiring after the TTL.
    store?.close();
  });
}
