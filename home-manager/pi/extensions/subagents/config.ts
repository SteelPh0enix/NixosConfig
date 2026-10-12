// Config schema, loading, and tool resolution for the subagents extension.
//
// A subagent is bound to one provider + model, carries the system prompt it is
// told about itself with (`prompt`, plus `replace_system_prompt` to swap pi's out
// instead of adding to it), and carries a `tools` setting that decides which tools
// it gets, out of `mainTools` (the main agent's active tools, read at spawn):
//   - omitted        -> mainTools
//   - { disable }    -> mainTools minus these
//   - a list / { enable } -> that exact list, and nothing else
// Validation runs against the TypeBox schemas below; entries that fail are
// reported and skipped instead of taking the whole config down.

import { existsSync, readFileSync } from "node:fs";
import { isAbsolute, join, resolve } from "node:path";
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

/** provider/model -> how many of that model may run at once (integer >= 1); a model left out of this map has one. */
const SlotsSchema = Type.Record(Type.String({ minLength: 1 }), Type.Integer({ minimum: 1 }));

const ENTRY_KEYS = "provider, model, description, tools, groups, prompt and replace_system_prompt";

// `additionalProperties: false` matters: an entry whose `groups` key is misspelled would otherwise load as a
// subagent with no group at all, which is a concurrency limit silently not enforced.
const SubagentConfigSchema = Type.Object(
  {
    provider: Type.String({ minLength: 1 }),
    model: Type.String({ minLength: 1 }),
    description: Type.Optional(Type.String()),
    tools: Type.Optional(ToolConfigSchema),
    groups: Type.Optional(Type.Array(Type.String({ minLength: 1 }), { minItems: 1 })),
    prompt: Type.Optional(Type.String({ minLength: 1 })),
    replace_system_prompt: Type.Optional(Type.Boolean()),
  },
  { additionalProperties: false },
);

export interface SubagentConfig {
  provider: string;
  model: string;
  description?: string;
  tools?: string[] | { enable?: string[]; disable?: string[] };
  /** Groups this subagent occupies a slot in (each must be in the `groups` map). */
  groups?: string[];
  /**
   * The subagent's own system prompt text. A value naming a file is replaced by that file's contents at load,
   * resolved against the directory of the config that declared it.
   */
  prompt?: string;
  /** Replace pi's system prompt with `prompt` rather than appending to it. */
  replace_system_prompt?: boolean;
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
  const tools = config?.tools;
  if (tools) {
    // Allowlist forms: the subagent tools are simply not part of the list.
    if (Array.isArray(tools)) return { tools: tools.filter((name) => !excluded.has(name)), excludeTools: [] };
    if (tools.enable) return { tools: tools.enable.filter((name) => !excluded.has(name)), excludeTools: [] };
    for (const name of tools.disable ?? []) excluded.add(name);
  }
  if (mainTools.length === 0) return { excludeTools: [...excluded] };
  return { tools: mainTools.filter((name) => !excluded.has(name)), excludeTools: [] };
}

interface LoadedConfig {
  subagents: Map<string, SubagentConfig>;
  /** Group name -> max concurrent subagents for that group. */
  groups: Map<string, number>;
  /** provider/model -> how many of that model may run at once; a model left out has one. */
  slots: Map<string, number>;
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

/**
 * Turn a config's `prompt` value into text, reading the file when the value names one, so a spawn never has to.
 * A value is a file when it is one line and either absolute or path-like (`subagents/coder.md`); anything else is
 * the text itself. A path that cannot be read is an error rather than a subagent prompted with "coder.md".
 */
function resolvePromptText(value: string, configDir: string): { text?: string; error?: string } {
  const isFile = !value.includes("\n") && (isAbsolute(value) || value.includes("/") || value.endsWith(".md"));
  if (!isFile) return { text: value };
  const path = isAbsolute(value) ? value : resolve(configDir, value);
  if (!existsSync(path)) return { error: `prompt file ${path} does not exist` };
  try {
    const text = readFileSync(path, "utf8").trim();
    return text ? { text } : { error: `prompt file ${path} is empty` };
  } catch (err) {
    return { error: `prompt file ${path} could not be read: ${(err as Error).message}` };
  }
}

/** First validation complaint about an entry, in words a config author can use. */
function firstError(name: string, value: unknown): string {
  for (const err of Value.Errors(SubagentConfigSchema, value)) {
    const where = err.instancePath || "#";
    // A union only ever reports "must be array", so name the accepted forms instead.
    if (where === "/tools") return "tools must be a non-empty list, or { enable } / { disable }";
    // A key nobody spelled right is the mistake worth catching: `groups` misspelled means no limit at all.
    // typebox reports it twice, once on the key ("schema is false") and once on the entry.
    if (err.message.includes("additional properties") || err.message === "schema is false") {
      const key = where === "#" ? "" : ` (${where} is not one of them)`;
      return `only ${ENTRY_KEYS} go in an entry${key}`;
    }
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
  const slots = new Map<string, number>();

  // A config that cannot be read or parsed is not the same as no config: loading on would leave the main agent with
  // no subagents and no clue why, so it throws and pi reports this extension as failed to load.
  const user = readJson(join(agentDir, "subagents.json"));
  if (user.error) throw new Error(user.error);
  const project = readJson(join(cwd, ".pi", "subagents.json"));
  if (project.error) throw new Error(project.error);

  // Each source resolves its own `prompt` paths, so a project entry can name a file in the repo.
  const sources: Array<{ data: unknown; source: string; dir: string }> = [];
  if (user.data !== undefined) sources.push({ data: user.data, source: "user", dir: agentDir });
  if (project.data !== undefined) sources.push({ data: project.data, source: "project", dir: join(cwd, ".pi") });

  // User first, then project, so a project entry overrides a user entry of the same name.
  for (const { data, source, dir } of sources) {
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
    if (data.slots !== undefined) {
      if (!Value.Check(SlotsSchema, data.slots)) {
        errors.push(`${source} config slots must be a { "provider/model": <positive integer> } map; skipped`);
      } else {
        for (const [providerModel, count] of Object.entries(data.slots as Record<string, number>)) slots.set(providerModel, count);
      }
    }
    for (const [name, raw] of Object.entries(data.subagents)) {
      if (!Value.Check(SubagentConfigSchema, raw)) {
        errors.push(`${source} subagent "${name}" skipped: ${firstError(name, raw)}`);
        continue;
      }
      const entry = raw as SubagentConfig;
      if (entry.prompt !== undefined) {
        const resolved = resolvePromptText(entry.prompt, dir);
        if (resolved.error) {
          errors.push(`${source} subagent "${name}" skipped: ${resolved.error}`);
          continue;
        }
        entry.prompt = resolved.text;
      }
      // An empty preamble is not a preference: it is a subagent with no instructions at all.
      if (entry.replace_system_prompt && !entry.prompt) {
        errors.push(`${source} subagent "${name}" skipped: replace_system_prompt needs a prompt to replace with`);
        continue;
      }
      subagents.set(name, entry);
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

  return { subagents, groups, slots, errors };
}

/**
 * The `name` parameter of `subagent_spawn`: every configured subagent, each with its description on the same line.
 * pi hands a tool's parameter schema to the provider unchanged, and only the field-level `description` is read
 * reliably, so this listing is the one place a subagent's description reaches the main agent.
 */
export function nameSchema(configs: Map<string, SubagentConfig>) {
  if (configs.size === 0) return Type.String({ description: "configured subagents: (none configured)" });
  const listing = [...configs].map(([name, cfg]) => (cfg.description ? `${name}: ${cfg.description}` : name)).join("\n");
  const names = [...configs.keys()];
  if (names.length === 1) return Type.Literal(names[0], { description: listing });
  return Type.Union(names.map((name) => Type.Literal(name)), { description: listing });
}
