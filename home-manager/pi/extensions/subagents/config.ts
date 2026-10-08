// Config schema, loading, and tool resolution for the subagents extension.
//
// A subagent is bound to one provider + model. Each subagent also carries a
// `tools` setting that decides which tools it gets, out of `mainTools` (the
// main agent's active tools, read at spawn):
//   - omitted        -> mainTools
//   - { disable }    -> mainTools minus these
//   - a list / { enable } -> that exact list, and nothing else
// Validation runs against the TypeBox schemas below; entries that fail are
// reported and skipped instead of taking the whole config down.

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { Type } from "typebox";
import { Value } from "typebox/value";

// The five tools this extension exposes to the main agent. Always excluded from
// a subagent so a subagent can neither spawn nor manage other subagents.
export const SUBAGENT_TOOL_NAMES: string[] = [
  "subagent_spawn",
  "subagent_status",
  "subagent_wait",
  "subagent_result",
  "subagent_kill",
];

// Exact allowlist, or the selective form. `additionalProperties: false` makes
// { enable, disable } match neither branch, so the two stay mutually exclusive.
const ToolConfigSchema = Type.Union([
  Type.Array(Type.String({ minLength: 1 }), { minItems: 1, description: "Exact tool allowlist" }),
  Type.Object({ enable: Type.Array(Type.String({ minLength: 1 }), { minItems: 1 }) }, { additionalProperties: false }),
  Type.Object({ disable: Type.Array(Type.String({ minLength: 1 }), { minItems: 1 }) }, { additionalProperties: false }),
]);

/** Group name -> max concurrent subagents in that group (integer >= 1). */
const GroupsSchema = Type.Record(Type.String({ minLength: 1 }), Type.Integer({ minimum: 1 }));

export const SubagentConfigSchema = Type.Object({
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
  tools?: string[] | { enable?: string[]; disable?: string[] };
  /** Groups this subagent occupies a slot in (each must be in the `groups` map). */
  groups?: string[];
}

export interface ResolvedTools {
  /** Exact allowlist; when present it is the only set of tools the subagent gets. */
  tools?: string[];
  /** Tools to turn off on top of the default set (subagent tools always here). */
  excludeTools: string[];
}

/**
 * Resolve a subagent's tool setting into `createAgentSession` options.
 * Subagent tools are always excluded (isolation), whatever the setting says.
 *
 * Without an exact allowlist the subagent inherits `mainTools`, so a tool the
 * main agent does not have cannot leak in. An empty `mainTools` means the
 * caller cannot see the main session's set at all, and pi's own default
 * selection is left alone.
 */
export function resolveTools(config: SubagentConfig | undefined, mainTools: string[] = []): ResolvedTools {
  const excluded = new Set<string>(SUBAGENT_TOOL_NAMES);
  if (config?.tools) {
    // Allowlist forms: the subagent tools are simply not part of the list.
    const allow = Array.isArray(config.tools) ? config.tools : config.tools.enable;
    if (allow) return { tools: allow.filter((name) => !excluded.has(name)), excludeTools: [] };
    for (const name of config.tools.disable ?? []) excluded.add(name);
  }
  if (mainTools.length === 0) return { excludeTools: [...excluded] };
  return { tools: mainTools.filter((name) => !excluded.has(name)), excludeTools: [] };
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

/** First validation complaint about an entry, in words a config author can use. */
function firstError(name: string, value: unknown): string {
  for (const err of Value.Errors(SubagentConfigSchema, value)) {
    const where = err.instancePath || "#";
    // A union only ever reports "must be array", so name the accepted forms instead.
    if (where === "/tools") return "tools must be a non-empty list, or { enable } / { disable }";
    return `${where} ${err.message}`;
  }
  return `${name} is malformed`;
}

/**
 * Load and validate `subagents.json` from the user agent dir and the project.
 * Project entries append to user entries; on a name clash the project wins.
 */
export function loadSubagentConfigs(cwd: string, agentDir: string): LoadedConfig {
  const errors: string[] = [];
  const subagents = new Map<string, SubagentConfig>();
  const groups = new Map<string, number>();

  // A config that cannot be read or parsed is not the same as no config: loading on would leave the main agent with
  // no subagents and no clue why, so it throws and pi reports this extension as failed to load.
  const user = readJson(join(agentDir, "subagents.json"));
  if (user.error) throw new Error(user.error);
  const project = readJson(join(cwd, ".pi", "subagents.json"));
  if (project.error) throw new Error(project.error);

  const sources: Array<{ data: unknown; source: string }> = [];
  if (user.data !== undefined) sources.push({ data: user.data, source: "user" });
  if (project.data !== undefined) sources.push({ data: project.data, source: "project" });

  // User first, then project, so a project entry overrides a user entry of the same name.
  for (const { data, source } of sources) {
    if (!isObject(data) || !isObject(data.subagents)) {
      errors.push(`${source} config is malformed (expected { "subagents": { "<name>": { "provider", "model" } } } ); skipped`);
      continue;
    }
    if (data.groups !== undefined) {
      if (!Value.Check(GroupsSchema, data.groups)) {
        errors.push(`${source} config groups must be a { "<name>": <positive integer> } map; skipped`);
      } else {
        for (const [groupName, limit] of Object.entries(data.groups as Record<string, number>)) groups.set(groupName, limit);
      }
    }
    for (const [name, raw] of Object.entries(data.subagents)) {
      if (!Value.Check(SubagentConfigSchema, raw)) {
        errors.push(`${source} subagent "${name}" skipped: ${firstError(name, raw)}`);
        continue;
      }
      subagents.set(name, raw as SubagentConfig);
    }
  }

  // A subagent may only name a group that some config declares with a limit, and it may name each of them once:
  // naming one twice asks for two of its slots, which that group's own limit then refuses forever.
  for (const [name, cfg] of subagents) {
    if (cfg.groups) {
      const unique = [...new Set(cfg.groups)];
      if (unique.length !== cfg.groups.length) {
        errors.push(
          `subagent "${name}" lists groups [${cfg.groups.join(", ")}] more than once; collapsed to [${unique.join(", ")}] so it holds one slot per group`,
        );
      }
      cfg.groups = unique;
    }
    for (const group of cfg.groups ?? []) {
      if (!groups.has(group)) {
        errors.push(`subagent "${name}" references unknown group "${group}" (not in any config's groups map); spawning it will fail`);
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
