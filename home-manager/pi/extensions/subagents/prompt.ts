// The system prompt section addressed to the session that may spawn subagents.
//
// The limits come out of the config rather than out of prose, so what the model is told and what the lease store
// enforces cannot drift apart. It is built once at load: the text never changes mid-session, so the prompt cache
// stays warm.

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

/**
 * The section body, or an empty string when there is nothing to delegate to (pi omits an empty section).
 */
export function subagentPromptSection(
  configs: Map<string, SubagentConfig>,
  groups: Map<string, number>,
  slots: Map<string, number>,
): string {
  if (configs.size === 0) return "";
  const groupLines =
    groups.size === 0
      ? "No groups are configured, so only the slot counts below apply."
      : [...groups]
          .map(([name, limit]) => `  - \`${name}\`: ${modelsWord(limit)} at a time`)
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
    "A **group** is a named bucket of models, and its limit counts *distinct models* holding it at once:",
    groupLines,
    "",
    "A **slot** is one running task on one model, so a model's slot count is how many of it may run together:",
    modelLines(configs, slots),
    "",
    "- A spawn that cannot take a slot is refused on the spot rather than queued; the refusal names the group and the model in the way. Retry only once the tasks it lists have finished.",
    "- So a batch that mixes models gets most of its spawns refused — send several tasks to the subagents sharing the roomiest model instead.",
    "- Models are local, so a parallel task costs nothing you would miss. Delegate anything that can run while you work.",
    "- Spawn a batch in one turn, then get on with your own work instead of sitting in a wait: check back with `subagent_status`, or `subagent_wait` with a short `timeout_s`.",
    "- This session's model is the slowest here and the one that reads best, so spend it on deciding and delegating, and let the subagents do the reading.",
  ].join("\n");
}
