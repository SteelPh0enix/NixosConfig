// subagents extension entry point.
//
// Loads the subagent configuration once at startup and wires it up: the five tools (each handler lives in its own
// module — spawn/wait/status/result/kill), the `/subagents` command, the system prompt section that introduces them
// to a session allowed to spawn, and the lifecycle hooks. Shared state is gathered into one `SubagentContext`.

import { join } from "node:path";
import { randomUUID } from "node:crypto";
import { getAgentDir, type AgentToolResult, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type, type Static } from "typebox";
import { loadSubagentConfigs, nameSchema, SUBAGENT_TOOL_NAMES } from "./config.ts";
import type { SubagentContext } from "./context.ts";
import { commandDefinition } from "./command.ts";
import { executeKill, DEFAULT_KILL_TIMEOUT_S } from "./kill.ts";
import { subagentPromptSection } from "./prompt.ts";
import { executeResult } from "./result.ts";
import { executeSpawn } from "./spawn.ts";
import { executeStatus } from "./status.ts";
import { executeWait, DEFAULT_WAIT_TIMEOUT_S } from "./wait.ts";
import { TaskRegistry, killRecord } from "./state.ts";
import { LeaseStore } from "./store.ts";
import {
  emitStatus,
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

  const deps: SubagentContext = { pi, configs, names, groups, slots, registry, getStore };

  // ---- tool schemas --------------------------------------------------------

  const spawnParameters = Type.Object({
    name: nameSchema(configs),
    task: Type.String({
      description: "The task to delegate. Be specific about the goal, constraints, and expected output.",
    }),
    session: Type.String({
      description: "Required name for this task's session (kebab-case, e.g. 'repo-scan'). Its transcript is always saved under .pi/subagents/sessions/ and can be reopened in pi.",
    }),
    workdir: Type.Optional(
      Type.Boolean({
        description: "Run the subagent with its session directory as the working directory (isolated scratchpad).",
      }),
    ),
  });

  const idParam = Type.String({ description: "The subagent task id (e.g. 'task-1')." });

  const statusParameters = Type.Object({
    id: Type.Optional(Type.String({ description: "Only report this task id. Omit to report all tasks." })),
  });

  const waitParameters = Type.Object({
    ids: Type.Optional(Type.Array(Type.String({ description: "Only wait for these task ids." }))),
    timeout_s: Type.Optional(
      Type.Number({ description: `Seconds to wait before returning partial status. Default ${DEFAULT_WAIT_TIMEOUT_S}.` }),
    ),
  });

  const resultParameters = Type.Object({ id: idParam });

  const killParameters = Type.Object({
    id: idParam,
    timeout_s: Type.Optional(
      Type.Number({ description: `How long to wait for the task to wind down before marking it killed anyway. Default ${DEFAULT_KILL_TIMEOUT_S}.` }),
    ),
  });

  // ---- register tools ------------------------------------------------------

  pi.registerTool({
    name: "subagent_spawn",
    label: "Spawn a background subagent",
    description:
      "Delegate a task to a configured subagent, which runs in the background. A spawn that cannot get a concurrency slot is refused rather than queued, so retry it once the tasks it names have finished.",
    parameters: spawnParameters,
    execute: async (_id, params: Static<typeof spawnParameters>, _signal, _onUpdate, ctx): Promise<AgentToolResult<SpawnDetails>> => executeSpawn(deps, params, ctx),
    renderCall: (args, theme) => renderSpawnCall(args, theme),
    renderResult: (result, opts, theme) => renderSpawnResult(result, opts, theme),
  });

  pi.registerTool({
    name: "subagent_status",
    label: "Show subagent task status",
    description: "Report the status of subagent tasks, or one specific task.",
    parameters: statusParameters,
    execute: async (_id, params: Static<typeof statusParameters>): Promise<AgentToolResult<StatusDetails>> => executeStatus(deps, params),
    renderCall: (args, theme) => renderStatusCall(args, theme),
    renderResult: (result, opts, theme) => renderStatusResult(result, opts, theme),
  });

  pi.registerTool({
    name: "subagent_wait",
    label: "Wait for subagent tasks to finish",
    description: "Block until one or more subagent tasks finish, then report their outcomes.",
    parameters: waitParameters,
    execute: async (_id, params: Static<typeof waitParameters>, signal, onUpdate): Promise<AgentToolResult<WaitDetails>> => executeWait(deps, params, signal, onUpdate),
    renderCall: (args, theme) => renderWaitCall(args, theme),
    renderResult: (result, opts, theme) => renderWaitResult(result, opts, theme),
  });

  pi.registerTool({
    name: "subagent_result",
    label: "Get a subagent task's report",
    description: "Return the full report of a finished subagent task.",
    parameters: resultParameters,
    execute: async (_id, params: Static<typeof resultParameters>, _signal, _onUpdate, ctx): Promise<AgentToolResult<ResultDetails>> => executeResult(deps, params, ctx),
    renderCall: (args, theme) => renderResultCall(args, theme),
    renderResult: (result, opts, theme, context) => renderResultResult(result, opts, theme, context),
  });

  pi.registerTool({
    name: "subagent_kill",
    label: "Abort a subagent task",
    description: "Abort a running subagent task and record the outcome as killed.",
    parameters: killParameters,
    execute: async (_id, params: Static<typeof killParameters>): Promise<AgentToolResult<KillDetails>> => executeKill(deps, params),
    renderCall: (args, theme) => renderKillCall(args, theme),
    renderResult: (result, opts, theme) => renderKillResult(result, opts, theme),
  });

  // ---- system prompt -------------------------------------------------------

  // A subagent's own session never has these tools active, which is how this handler tells the two apart: the
  // section goes to the session that can delegate, and a subagent is never told to recurse.
  const section = subagentPromptSection(configs, groups, slots);
  pi.on("before_agent_start", (event) => {
    if (section && pi.getActiveTools().includes(SUBAGENT_TOOL_NAMES[0])) {
      event.systemPromptOptions.sections.subagents = section;
    }
  });

  // ---- slash command -------------------------------------------------------

  pi.registerCommand("subagents", commandDefinition(deps));

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
      void killRecord(record, 0, registry).catch(() => {});
    }
    // This instance's slots are freed right away instead of expiring after the TTL.
    store?.close();
  });
}
