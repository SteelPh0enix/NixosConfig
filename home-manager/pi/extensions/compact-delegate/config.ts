// Config for compact-delegate: which model writes the session summary, and how
// much of the conversation it may read.
//
// provider/model default to the `summarizer` entry of subagents.json, so there is
// still one place that says what the summarizer is; compact-delegate.json names
// over it. A value that cannot be used is reported and the extension stays out of
// the way - pi's own compaction runs instead. Nothing here is worth failing a
// session over.

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

export interface DelegateConfig {
  provider: string;
  model: string;
  /** Per tool result and per thinking block, in the text handed to the summarizer. */
  toolResultMaxChars: number;
  maxSummaryTokens: number;
  /** Thinking level for the summary request. "off" sends nothing and leaves it to the server. */
  reasoning: string;
}

export interface LoadedConfig {
  config?: DelegateConfig;
  errors: string[];
}

const KEYS = new Set(["enabled", "provider", "model", "toolResultMaxChars", "maxSummaryTokens", "reasoning"]);
const REASONING = new Set(["off", "minimal", "low", "medium", "high", "xhigh"]);

interface Draft {
  enabled?: boolean;
  provider?: string;
  model?: string;
  toolResultMaxChars?: number;
  maxSummaryTokens?: number;
  reasoning?: string;
}

function readJsonObject(path: string): { data?: Record<string, unknown>; error?: string } {
  if (!existsSync(path)) return {};
  let parsed: unknown;
  try {
    parsed = JSON.parse(readFileSync(path, "utf8"));
  } catch (err) {
    return { error: `${path} is not readable JSON: ${(err as Error).message}` };
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    return { error: `${path} must hold a JSON object` };
  }
  return { data: parsed as Record<string, unknown> };
}

/** Copy the keys we know, complaining about the rest: a typo is a setting silently not set. */
function take(source: Record<string, unknown>, where: string, errors: string[]): Draft {
  const draft: Draft = {};
  for (const [key, value] of Object.entries(source)) {
    if (!KEYS.has(key)) {
      errors.push(`${where}: "${key}" is not a setting (known: ${[...KEYS].join(", ")})`);
      continue;
    }
    if (key === "enabled" && typeof value !== "boolean") errors.push(`${where}: enabled must be true or false`);
    if ((key === "provider" || key === "model") && (typeof value !== "string" || !value)) {
      errors.push(`${where}: ${key} must be a non-empty string`);
    }
    if (key === "toolResultMaxChars" && (typeof value !== "number" || value < 200)) {
      errors.push(`${where}: toolResultMaxChars must be a number of at least 200`);
    }
    if (key === "maxSummaryTokens" && (typeof value !== "number" || value < 256)) {
      errors.push(`${where}: maxSummaryTokens must be a number of at least 256`);
    }
    if (key === "reasoning" && (typeof value !== "string" || !REASONING.has(value))) {
      errors.push(`${where}: reasoning must be one of ${[...REASONING].join(", ")}`);
    }
    Object.assign(draft, { [key]: value });
  }
  return draft;
}

/** The summarizer subagent's own provider and model, so its model is named in one file. */
function summarizerModel(agentDir: string, projectDir: string, errors: string[]): { provider: string; model: string } | undefined {
  for (const dir of [projectDir, agentDir]) {
    const { data, error } = readJsonObject(join(dir, "subagents.json"));
    if (error) {
      errors.push(error);
      continue;
    }
    const entry = (data?.subagents as Record<string, unknown> | undefined)?.summarizer as Record<string, unknown> | undefined;
    if (typeof entry?.provider === "string" && typeof entry.model === "string") {
      return { provider: entry.provider, model: entry.model };
    }
  }
  return undefined;
}

export function loadConfig(cwd: string, agentDir: string): LoadedConfig {
  const errors: string[] = [];
  const sources: Array<{ path: string; where: string }> = [
    { path: join(agentDir, "compact-delegate.json"), where: "compact-delegate.json" },
    { path: join(cwd, ".pi", "compact-delegate.json"), where: ".pi/compact-delegate.json" },
  ];

  let draft: Draft = {};
  for (const { path, where } of sources) {
    const { data, error } = readJsonObject(path);
    if (error) {
      errors.push(error);
      continue;
    }
    if (data) draft = { ...draft, ...take(data, where, errors) };
  }

  if (draft.enabled === false) return { errors };

  const fallback = summarizerModel(agentDir, join(cwd, ".pi"), errors);
  const provider = typeof draft.provider === "string" ? draft.provider : fallback?.provider;
  const model = typeof draft.model === "string" ? draft.model : fallback?.model;
  if (!provider || !model) {
    return {
      errors: [...errors, "no summarizer model: set provider and model in compact-delegate.json, or define a summarizer subagent"],
    };
  }

  return {
    config: {
      provider,
      model,
      toolResultMaxChars: draft.toolResultMaxChars ?? 16000,
      maxSummaryTokens: draft.maxSummaryTokens ?? 16384,
      reasoning: draft.reasoning ?? "off",
    },
    errors,
  };
}
