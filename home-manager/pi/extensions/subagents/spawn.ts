// The `subagent_spawn` handler: validation, model resolution, group/slot leasing, and starting the task's SDK
// session. Planning (`planSpawn`) is pure and happens before anything is touched, so a refusal creates nothing;
// a failure after the lease is taken hands it back.

import { existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import {
  SessionManager,
  getAgentDir,
  type AgentToolResult,
  type ExtensionToolContext,
} from "@earendil-works/pi-coding-agent";
import { resolveTools, type ResolvedTools, type SubagentConfig } from "./config.ts";
import type { SubagentContext } from "./context.ts";
import type { TaskRecord } from "./task-record.ts";
import { SubagentTask } from "./task.ts";
import type { AcquireResult, LeaseRequest } from "./store.ts";
import { emitStatus, notifyCompletion, type SpawnDetails } from "./ui.ts";

/** Directory (under the main working directory) for saved subagent sessions. */
const SUBAGENT_SESSION_DIR = join(".pi", "subagents", "sessions");

export interface SpawnParams {
  name: string;
  task: string;
  session: string;
  workdir?: boolean;
}

/** Everything the spawn needs before it resolves a model or takes a lease. */
export interface SpawnPlan {
  config: SubagentConfig;
  /** "provider/model", the key a lease and the `slots` map use. */
  providerModel: string;
  /** That model's slot count; a model nobody listed has one. */
  capacity: number;
  /** One request per group the subagent names, each carrying that group's limit. */
  requests: LeaseRequest[];
}

/**
 * Validate a spawn and turn its config into a lease plan. Pure: throws on an unknown subagent, a missing or
 * non-kebab-case session, or a group nobody gave a limit to, all before any store or session exists.
 */
export function planSpawn(deps: SubagentContext, params: SpawnParams): SpawnPlan {
  const config = deps.configs.get(params.name);
  if (!config) {
    throw new Error(`unknown subagent "${params.name}". Configured: ${deps.names.join(", ") || "(none)"}`);
  }
  if (!params.session) {
    throw new Error("a session name is required (kebab-case, e.g. repo-scan)");
  }
  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(params.session)) {
    throw new Error(`invalid session name "${params.session}" (use kebab-case, e.g. repo-scan)`);
  }

  const providerModel = `${config.provider}/${config.model}`;
  const capacity = deps.slots.get(providerModel) ?? 1;
  // Hold a slot in each of this subagent's groups; a group nobody limited cannot be enforced, so it is an error.
  const requests: LeaseRequest[] = [];
  for (const group of config.groups ?? []) {
    const limit = deps.groups.get(group);
    if (limit === undefined) {
      throw new Error(`subagent "${params.name}" names group "${group}", which no config gives a limit`);
    }
    requests.push({ group, limit });
  }
  return { config, providerModel, capacity, requests };
}

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

export async function executeSpawn(
  deps: SubagentContext,
  params: SpawnParams,
  toolCtx: ExtensionToolContext,
): Promise<AgentToolResult<SpawnDetails>> {
  const { registry, getStore, pi } = deps;
  const { config, providerModel, capacity, requests } = planSpawn(deps, params);

  // llama-compat fills a llama.cpp model's context size from the server, and --fit can answer differently from one
  // load to the next, so ask the provider for its live figures before resolving. A server that is not answering is
  // not the subagent's problem: pi keeps the catalog it already has and the spawn goes ahead.
  await toolCtx.modelRegistry.refresh({ providers: [config.provider], force: true }).catch(() => {});
  const model = toolCtx.modelRegistry.find(config.provider, config.model);
  if (!model) {
    throw new Error(`unknown model "${config.provider}/${config.model}"`);
  }

  // A group's limit counts distinct models; within a model the capacity is that model's own slot count. Every group
  // this spawn takes shares one claim, so it counts once toward capacity. An untracked subagent never opens the store.
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

  // Only now is it safe to lay down the session directory: a blocked spawn creates nothing. Anything below can
  // still fail, and a failure has to hand its group slot back instead of holding it until the process exits.
  try {
    const sessionDir = makeSessionDir(toolCtx.cwd, params.session);
    const effectiveCwd = params.workdir ? sessionDir : toolCtx.cwd;
    const sessionManager = SessionManager.create(effectiveCwd, sessionDir);
    // A subagent without an exact allowlist inherits what the main agent has right now.
    const resolvedTools: ResolvedTools = resolveTools(config, pi.getActiveTools());

    const id = registry.nextId();
    const record: TaskRecord = {
      id,
      name: params.name,
      provider: config.provider,
      model: config.model,
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
      mainSessionPath: toolCtx.sessionManager.getSessionFile(),
      onStatus: () => emitStatus(pi, registry),
      onFinish: (finished) => {
        notifyCompletion(toolCtx, finished);
        emitStatus(pi, registry);
      },
    });
    void runner.start().catch(() => {});
    emitStatus(pi, registry);

    return {
      content: [{ type: "text", text: `spawned ${record.name} as ${id}` }],
      details: { id, name: params.name, model: config.model, slot: record.slot },
    };
  } catch (err) {
    for (const leaseId of lease.ids) leaseStore?.release(leaseId);
    throw err;
  }
}
