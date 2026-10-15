// System prompt building, both directions: the section addressed to the session that may spawn subagents, and the
// prompt a subagent itself gets.
//
// The limits come out of the config rather than out of prose, so what the model is told and what the lease store
// enforces cannot drift apart. The main-agent section is built once at load: the text never changes mid-session, so
// the prompt cache stays warm.

import type { SubagentConfig } from "./config.ts";

const slotsWord = (n: number) => `${n} slot${n === 1 ? "" : "s"}`;
const modelsWord = (n: number) => `${n} model${n === 1 ? "" : "s"}`;

/**
 * One line per model that carries a subagent, roomiest first, so the model with free capacity is the first thing
 * a reader reaches. `slots` is that model's own count; a model nobody listed has one.
 */
function modelLines(configs: Map<string, SubagentConfig>, slots: Map<string, number>): string {
  const byModel = new Map<string, string[]>();
  for (const [name, cfg] of configs) {
    const key = `${cfg.provider}/${cfg.model}`;
    byModel.set(key, [...(byModel.get(key) ?? []), name]);
  }
  const rows = [...byModel].map(([key, names]) => ({
    model: key.slice(key.lastIndexOf("/") + 1),
    capacity: slots.get(key) ?? 1,
    names: names.join(", "),
  }));
  rows.sort((a, b) => b.capacity - a.capacity || a.model.localeCompare(b.model));
  return rows.map((r) => `  - ${r.model}: ${slotsWord(r.capacity)} — ${r.names}`).join("\n");
}

/** Every subagent is one of these, whether or not its config adds anything. */
export const SUBAGENT_FRAMING =
  "You are a background subagent. A coordinator agent has given you a single job: do exactly that job and nothing else, and finish with a focused report as quickly as you can.";

/**
 * What a subagent's system prompt is built from: the framing, then its own role text. This is the whole prompt - a
 * subagent is not given the main agent's system prompt.
 */
export function subagentPromptText(config: SubagentConfig): string {
  return config.prompt ? `${SUBAGENT_FRAMING}\n\n${config.prompt}` : SUBAGENT_FRAMING;
}

/** The part of pi's `NormalizedBuildSystemPromptOptions` this extension touches. */
export interface SubagentPromptOptions {
  customPrompt?: string;
  appendSystemPrompt: string;
  selectedTools: string[];
  toolSnippets: Record<string, string>;
  contextFiles: Array<{ path: string; content: string }>;
  skills: unknown[];
  sections: Record<string, string>;
}

/**
 * Shape a subagent's prompt options in place, from a `before_agent_start` handler.
 *
 * The role text goes through `customPrompt`, so pi drops its own preamble, rules and docs, and the rest of pi's
 * additions are emptied too (the global append, AGENTS.md, the skills list): a subagent gets its own short prompt
 * and nothing of the main agent's. pi renders no `<tools>` section for a custom prompt and a section called `tools`
 * is allowed, so the tool index is rendered here the same way pi does it - the tool declarations themselves travel
 * with the request either way.
 */
export function applySubagentPrompt(options: SubagentPromptOptions, text: string): void {
  const listed = options.selectedTools.filter((name) => options.toolSnippets[name]);
  options.customPrompt = text;
  options.appendSystemPrompt = "";
  options.contextFiles = [];
  options.skills = [];
  options.sections.tools = listed.length > 0 ? listed.map((name) => `- ${name}: ${options.toolSnippets[name]}`).join("\n") : "(none)";
}

/**
 * The section body, or an empty string when there is nothing to delegate to (pi omits an empty section).
 */
export function subagentPromptSection(
  configs: Map<string, SubagentConfig>,
  groups: Map<string, number>,
  slots: Map<string, number>,
): string {
  if (configs.size === 0) return "";
  // Which models stand in each group, so a reader can tell at a glance what cannot run beside what. Roomiest first,
  // matching the order of the model list below.
  const shortName = (key: string) => key.slice(key.lastIndexOf("/") + 1);
  const members = new Map<string, string[]>();
  for (const cfg of configs.values()) {
    for (const group of cfg.groups ?? []) {
      members.set(group, [...new Set([...(members.get(group) ?? []), `${cfg.provider}/${cfg.model}`])]);
    }
  }
  for (const [group, keys] of members) {
    keys.sort((a, b) => (slots.get(b) ?? 1) - (slots.get(a) ?? 1) || shortName(a).localeCompare(shortName(b)));
  }
  const groupLines =
    groups.size === 0
      ? "No groups are configured, so only the slot counts below apply."
      : [...groups]
          .map(([name, limit]) => {
            const who = members.get(name);
            return `  - \`${name}\`: ${modelsWord(limit)} at a time${who ? ` (${who.map(shortName).join(", ")})` : ""}`;
          })
          .join("\n");

  return [
    "The `subagents` extension hands work to background agents running on local llama.cpp models, and you manage them:",
    "",
    "- `subagent_spawn(name, task)` starts one and returns its id (`task-1`) at once — it keeps going in the background. The task text is all the new agent sees, so put the goal, the constraints and the shape of the report in it.",
    "- `subagent_status(id?)` reports one task or all of them, including what each is doing right now.",
    "- `subagent_wait(ids?, timeout_s?)` blocks until one finishes and reports status lines, not the report itself.",
    "- `subagent_result(id)` returns a finished task's full report.",
    "- `subagent_kill(id)` aborts a task and gives its capacity back.",
    "",
    "The user sees the same tasks under `/subagents`.",
    "",
    "Capacity, and why a spawn gets refused:",
    "",
    "A **group** is models sharing one card, and its limit counts *distinct models* holding it at once. A task on one",
    "model of a group blocks every *other* model in that group, so switching models is what gets refused, not sharing",
    "one out. Only two things run together: more tasks on the model already holding the group, or a task in another",
    "group. Leases are shared across every pi session, so a task in another window holds the group too.",
    groupLines,
    "",
    "A **slot** is one running task on one model, so a model's slot count is how many of it may run together:",
    modelLines(configs, slots),
    "",
    "- Pick ONE model for a batch and send all its tasks to the subagents running on it; the widest parallelism here is",
    "  one model per group.",
    "- A spawn that cannot take capacity is refused on the spot rather than queued; the refusal names the group and the",
    "  model in the way. Retry only once the tasks it lists have finished, and do not try a third model to dodge it.",
    "- Models are local, so a parallel task costs nothing you would miss. Delegate anything that can run while you work.",
    "- Spawn a batch in one turn and end your turn: when a task settles, its report arrives as a message in this session",
    "  and starts a new turn, so the user keeps control while it works. You are notified automatically — do not busy-wait",
    "  in `subagent_wait`; use it only when you need the result before you can do anything else. `subagent_status` shows",
    "  what is still running.",
    "- This session's model is the slowest here and the one that reads best, so spend it on deciding and delegating, and let the subagents do the reading.",
  ].join("\n");
}
