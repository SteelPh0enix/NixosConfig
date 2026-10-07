// Config schema, loading, and tool resolution for the subagents extension.
//
// A subagent is bound to one provider + model. Each subagent also carries a
// `tools` setting that decides which of the main agent's tools it gets:
//   - omitted  -> every main-agent tool except the subagent tools themselves
//   - a list   -> that exact list, and nothing else (subagent tools dropped)
//   - a dict   -> { enable?: string[], disable?: string[] } layered on top of
//                 the default set; enable and disable are mutually exclusive.

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { Type, type Static } from "typebox";

// The five tools this extension exposes to the main agent. Always excluded from
// a subagent so a subagent can neither spawn nor manage other subagents.
export const SUBAGENT_TOOL_NAMES: string[] = [
  "subagent_spawn",
  "subagent_status",
  "subagent_wait",
  "subagent_result",
  "subagent_kill",
];

// A subagent's tool setting: either an exact allowlist or selective enable/disable.
const ToolConfigSchema = Type.Union([
  Type.Array(Type.String({ minLength: 1 }), { minItems: 1, description: "Exact tool allowlist" }),
  Type.Object(
    {
      enable: Type.Optional(Type.Array(Type.String({ minLength: 1 }), { minItems: 1 })),
      disable: Type.Optional(Type.Array(Type.String({ minLength: 1 }), { minItems: 1 })),
    },
    { description: "Selective enable/disable relative to the default toolset" },
  ),
]);

const SubagentConfigSchema = Type.Object({
  provider: Type.String({ minLength: 1 }),
  model: Type.String({ minLength: 1 }),
  description: Type.Optional(Type.String()),
  tools: Type.Optional(ToolConfigSchema),
  groups: Type.Optional(Type.Array(Type.String({ minLength: 1 }), { minItems: 1 })),
});

export interface SubagentConfig {
  provider: string;
  model: string;
  description?: string;
  tools?: ToolConfig;
  /** Groups this subagent occupies a slot in (each must be in the `groups` map). */
  groups?: string[];
}

export type ToolConfig = Static<typeof ToolConfigSchema>;

/** Everything `createAgentSession` needs to build a subagent's tool set. */
export interface ResolvedTools {
  /** Exact allowlist; when present it is the only set of tools the subagent gets. */
  tools?: string[];
  /** Tools to turn off on top of the default set (subagent tools always here). */
  excludeTools: string[];
}

/**
 * Resolve a subagent's tool setting into `createAgentSession` options.
 * Subagent tools are always excluded (isolation), regardless of the setting.
 */
export function resolveTools(config: SubagentConfig | undefined): ResolvedTools {
  if (!config?.tools) {
    return { excludeTools: [...SUBAGENT_TOOL_NAMES] };
  }
  if (Array.isArray(config.tools)) {
    const excluded = new Set(SUBAGENT_TOOL_NAMES);
    const tools = config.tools.filter((name) => !excluded.has(name));
    return { tools, excludeTools: [] };
  }
  if (config.tools.enable && config.tools.disable) {
    throw new Error("subagent `tools` must be either a fixed list or { enable/disable }, not both");
  }
  const exclude = new Set<string>(SUBAGENT_TOOL_NAMES);
  for (const name of config.tools.disable ?? []) exclude.add(name);
  for (const name of config.tools.enable ?? []) exclude.delete(name);
  // Re-add the subagent tools: they are the isolation boundary and stay excluded.
  for (const name of SUBAGENT_TOOL_NAMES) exclude.add(name);
  return { excludeTools: [...exclude] };
}

export interface LoadedConfig {
  subagents: Map<string, SubagentConfig>;
  /** Group name -> max concurrent subagents for that group. */
  groups: Map<string, number>;
  errors: string[];
}

function readJson(path: string): { data: unknown; error?: string } {
  try {
    return { data: JSON.parse(readFileSync(path, "utf8")) };
  } catch (err) {
    const e = err as NodeJS.ErrnoException & Error;
    if (e.code === "ENOENT") return { data: undefined };
    return { data: undefined, error: `could not read ${path}: ${e.message || e}` };
  }
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isValidGroupsMap(value: unknown): value is Record<string, number> {
  if (!isObject(value)) return false;
  return Object.values(value).every(
    (v) => typeof v === "number" && Number.isInteger(v) && v >= 1,
  );
}

function isValidToolConfig(value: unknown): boolean {
  if (Array.isArray(value)) return value.length > 0 && value.every((t) => typeof t === "string" && t.length > 0);
  if (!isObject(value)) return false;
  const enable = value.enable;
  const disable = value.disable;
  const hasEnable = enable !== undefined;
  const hasDisable = disable !== undefined;
  if (hasEnable && hasDisable) return false;
  const checkList = (v: unknown) => Array.isArray(v) && v.length > 0 && v.every((t) => typeof t === "string" && t.length > 0);
  return !hasEnable || !hasDisable || (checkList(enable) && checkList(disable));
}

/**
 * Load and validate `subagents.json` from the user agent dir and the project.
 * Project entries append to user entries; on a name clash the project wins.
 */
export function loadSubagentConfigs(cwd: string, agentDir: string): LoadedConfig {
  const errors: string[] = [];
  const subagents = new Map<string, SubagentConfig>();
  const groups = new Map<string, number>();

  const sources: Array<{ data: unknown; error?: string; source: string }> = [];
  const user = readJson(join(agentDir, "subagents.json"));
  if (user.data !== undefined) sources.push({ data: user.data, error: user.error, source: "user" });
  const project = readJson(join(cwd, ".pi", "subagents.json"));
  if (project.data !== undefined) sources.push({ data: project.data, error: project.error, source: "project" });

  // User first, then project, so a project entry overrides a user entry of the same name.
  for (const { data, error, source } of sources) {
    if (error) {
      errors.push(error);
      continue;
    }
    if (!isObject(data) || !isObject(data.subagents)) {
      errors.push(`${source} config is malformed (expected { "subagents": { "<name>": { "provider", "model" } } } ); skipped`);
      continue;
    }
    if (data.groups !== undefined) {
      if (!isValidGroupsMap(data.groups)) {
        errors.push(`${source} config groups must be a { "<name>": <positive-integer> } map; skipped`);
      } else {
        for (const [groupName, limit] of Object.entries(data.groups)) groups.set(groupName, limit);
      }
    }
    for (const [name, raw] of Object.entries(data.subagents)) {
      if (
        !isObject(raw) ||
        typeof raw.provider !== "string" ||
        raw.provider.trim() === "" ||
        typeof raw.model !== "string" ||
        raw.model.trim() === "" ||
        (raw.description !== undefined && typeof raw.description !== "string") ||
        (raw.tools !== undefined && !isValidToolConfig(raw.tools)) ||
        (raw.groups !== undefined &&
          !(Array.isArray(raw.groups) && raw.groups.length > 0 && raw.groups.every((g) => typeof g === "string" && g.length > 0)))
      ) {
        errors.push(`${source} subagent "${name}" is malformed; skipped`);
        continue;
      }
      subagents.set(name, raw as unknown as SubagentConfig);
    }
  }

  // A subagent may only name a group that some config declares with a limit.
  for (const [name, cfg] of subagents) {
    for (const group of cfg.groups ?? []) {
      if (!groups.has(group)) {
        errors.push(`subagent "${name}" references unknown group "${group}" (not in any config's groups map)`);
      }
    }
  }

  return { subagents, groups, errors };
}

/** Build the `name` enum for `subagent_spawn` from the configured subagent names. */
export function nameSchema(names: string[]) {
  if (names.length === 0) return Type.String({ description: "configured subagents: (none configured)" });
  if (names.length === 1) return Type.Literal(names[0], { description: names[0] });
  return Type.Union(names.map((name) => Type.Literal(name)), { description: names.join(", ") });
}
