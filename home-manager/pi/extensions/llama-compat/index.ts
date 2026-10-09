import { getAgentDir, type ExtensionAPI, type ProviderConfig, type ProviderModelConfig } from "@earendil-works/pi-coding-agent";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

// pi doesn't know what llama.cpp server actually serves: the served n_ctx after a re-fit, whether the
// chat template has a thinking switch and which one it reads, whether the instance has a vision projector.
// This extension reads that from the server and re-registers the configured provider with it, making llama-server
// the primary source of truth about a model instead of models.json

const PROBE_TIMEOUT_MS = 2000;
/** Its own built-in provider already reads /models and /props; re-registering it would drop its classifiers. */
const BUILTIN_PROVIDER = "llama.cpp";

type Caps = {
  supports_tools?: boolean;
  supports_reasoning_effort?: boolean;
  supports_preserve_reasoning?: boolean;
};

type ServerProps = {
  role?: string;
  models_autoload?: boolean;
  model_alias?: string;
  chat_template?: string;
  chat_template_caps?: Caps;
  modalities?: { vision?: boolean };
  default_generation_settings?: { n_ctx?: number };
};

type RouterModel = {
  id: string;
  aliases?: string[];
  source?: string;
  status?: { value?: string; failed?: boolean; args?: string[] };
  meta?: { n_ctx?: number };
  architecture?: { input_modalities?: string[] };
};

type Served = {
  id: string;
  aliases: string[];
  nCtx?: number;
  /** What the preset was started with, from its launch args; weaker than the served n_ctx. */
  requested?: number;
  vision?: boolean;
  /** What the chat template can do about thinking; absent when the template could not be read. */
  thinking?: TemplateThinking;
};

/** The chat variant of a registered model config. */
type ChatModelConfig = Exclude<ProviderModelConfig, { type: "image" } | { type: "classifier" }>;

type ModelsJsonCompat = Record<string, unknown>;

type Derived = {
  reasoning?: boolean;
  input?: ("text" | "image")[];
  contextWindow?: number;
  maxTokens?: number;
  thinkingLevelMap?: ChatModelConfig["thinkingLevelMap"];
};

/** How pi should switch a model's thinking on and off, as far as the template allows. */
type ThinkingPolicy = {
  reasoning: boolean;
  thinkingFormat?: string;
  chatTemplateKwargs?: ModelsJsonCompat;
  supportsReasoningEffort?: boolean;
  thinkingLevelMap?: ChatModelConfig["thinkingLevelMap"];
  label: string;
};

/** What a served chat template says about thinking, read out of the template itself. */
type TemplateThinking = {
  /** The variable it switches thinking on and off with, e.g. enable_thinking. */
  switchName?: string;
  /** The variable it takes the effort from, e.g. reasoning_effort. */
  effortName?: string;
  /** The effort values the template names; empty when it reads an effort without naming a value. */
  efforts: string[];
  /** Whether it keeps past thoughts in context when asked (Qwen3's preserve_thinking). */
  preserveThinking: boolean;
  /** Whether it writes its own thinking tags - a reasoning model even with no switch and no effort. */
  emitsThinking: boolean;
  /** chat_template_caps.supports_reasoning_effort. */
  effortCap?: boolean;
};

const PI_EFFORT_LEVELS = ["minimal", "low", "medium", "high", "xhigh", "max"];

/** llama.cpp reads OpenAI's own field into the template context, so a template named that way needs no kwargs. */
const OPENAI_EFFORT_FIELD = "reasoning_effort";

const EFFORT_NAME = String.raw`\w*reasoning_effort`;
const EFFORT_LITERAL = String.raw`['"]([a-z][a-z0-9_-]*)['"]`;
const EFFORT_VARIABLE = /(?<![\w.])([a-z_]*reasoning_effort)(?![\w.])/g;
const THINKING_VARIABLE = /(?<![\w.])([a-z0-9_]*thinking[a-z0-9_]*)(?![\w.])/g;
const PRESERVE_THINKING = /(?<![\w.])preserve_thinking(?![\w.])/;

/** The two spellings of an opening thinking tag llama.cpp splits on; assembled so this file stays literal-free. */
const THINKING_TAGS = ["think", "im_start>thinking"].map((name) => `<${name}>`);

/** A template that writes its own thinking tags is a reasoning model whatever variable it reads about it. */
const emitsThinkingTags = (template: string) => THINKING_TAGS.some((tag) => template.includes(tag));
const CONTROL_TAG = /^\{[%{]-?\s*(?:if|elif|set)\b/;

/** preserve_thinking keeps past thoughts and thinking_budget sizes them; neither switches thinking on. */
const isSwitchName = (name: string) => !/preserve|budget|tokens|content|signature|length/.test(name);

/** The switch names that mean "think or don't"; anything else that mentions thinking only ranks behind them. */
const SWITCH_NAME = /^(?:enable_|add_|do_|allow_)?thinking(?:_enabled)?$/;

/** A template's jinja expressions, with comments and string literals gone: prose about thinking is not a switch. */
function jinjaTags(template: string): string[] {
  const uncommented = template.replace(/\{#[\s\S]*?#\}/g, "");
  return (uncommented.match(/\{[{%][\s\S]*?[%}]\}/g) ?? []).map((tag) => tag.replace(/'[^'\\]*'|"[^"\\]*"/g, '""'));
}

/** The variable the template switches thinking on; known switch names first, then the one that enables. */
function switchIn(tags: string[]): string | undefined {
  const namesIn = (controlOnly: boolean) => [
    ...new Set(
      tags
        .filter((tag) => !controlOnly || CONTROL_TAG.test(tag))
        .flatMap((tag) => [...tag.matchAll(THINKING_VARIABLE)].map((match) => match[1]!)),
    ),
  ].filter(isSwitchName);
  const inControl = namesIn(true);
  const found = (inControl.length > 0 ? inControl : namesIn(false)).sort(
    (a, b) =>
      Number(SWITCH_NAME.test(b)) - Number(SWITCH_NAME.test(a)) ||
      Number(b.includes("enable")) - Number(a.includes("enable")) ||
      a.length - b.length,
  );
  return found[0];
}

/**
 * The effort variable a template reads and the values it accepts, from the values it branches on, defaults
 * to or validates. Undefined when there is no template; no values when it reads an effort without naming one.
 */
function effortIn(template: string, tags: string[]): { name: string; values: string[] } | undefined {
  const names = tags.flatMap((tag) => [...tag.matchAll(EFFORT_VARIABLE)].map((match) => match[1]!));
  if (names.length === 0) return undefined;
  const found = new Set<string>();
  const collect = (text: string) => {
    for (const literal of text.matchAll(new RegExp(EFFORT_LITERAL, "g"))) found.add(literal[1]!);
  };
  for (const [pattern, tuple] of [
    [String.raw`${EFFORT_NAME}\s*==\s*${EFFORT_LITERAL}`, false],
    [String.raw`${EFFORT_LITERAL}\s*==\s*${EFFORT_NAME}`, false],
    [String.raw`${EFFORT_NAME}[^\n]{0,80}?\bin \(([^)]{1,160})\)`, true],
    [String.raw`${EFFORT_NAME}\s*\|\s*default\(\s*${EFFORT_LITERAL}`, false],
  ] as const) {
    for (const match of template.matchAll(new RegExp(pattern, "g"))) (tuple ? collect(match[1]!) : found.add(match[1]!));
  }
  const unique = [...new Set(names)];
  const name = unique.includes(OPENAI_EFFORT_FIELD)
    ? OPENAI_EFFORT_FIELD
    : unique.sort((a, b) => a.length - b.length)[0]!;
  return { name, values: [...found].sort() };
}

/** Everything the served template says about thinking; undefined when there is no template to read. */
function templateThinking(props: ServerProps): TemplateThinking | undefined {
  if (typeof props.chat_template !== "string") return undefined;
  const tags = jinjaTags(props.chat_template);
  const effort = effortIn(props.chat_template, tags);
  return {
    switchName: switchIn(tags),
    effortName: effort?.name,
    efforts: effort?.values ?? [],
    preserveThinking:
      props.chat_template_caps?.supports_preserve_reasoning ?? tags.some((tag) => PRESERVE_THINKING.test(tag)),
    emitsThinking: emitsThinkingTags(props.chat_template),
    effortCap: props.chat_template_caps?.supports_reasoning_effort,
  };
}

const THINKING_ENABLED = { $var: "thinking.enabled" };
const THINKING_EFFORT = { $var: "thinking.effort", omitWhenOff: true };

/** pi sends thinkingLevelMap[level] ?? level, so a level the template would reject has to be marked null. */
function effortMap(efforts: string[]): Record<string, string | null> {
  const map: Record<string, string | null> = {};
  for (const level of PI_EFFORT_LEVELS) map[level] = efforts.includes(level) ? level : null;
  return map;
}

const levelsIn = (efforts: string[]) => PI_EFFORT_LEVELS.filter((level) => efforts.includes(level));

function thinkingPolicy(served: Served): ThinkingPolicy | undefined {
  const template = served.thinking;
  if (!template) return undefined;
  const named = template.efforts.length > 0;
  // pi fills chat_template_kwargs from thinkingFormat alone and then never sends reasoning_effort, so a
  // template naming its own variables is driven through the generic chat-template format, which carries a
  // switch and an effort in one request. Only a plain OpenAI reasoning_effort belongs at the top level.
  const ownEffort = template.effortName !== undefined && template.effortName !== OPENAI_EFFORT_FIELD;
  const driven = template.switchName !== undefined || ownEffort;
  if (!driven) {
    if (template.effortCap !== true) {
      // Writing its own thinking tags makes it a reasoning model on its own say-so: nothing can be asked of it
      // beyond off, which pi sends as reasoning_effort none, so the levels stay as models.json gave them.
      if (template.effortCap === false && template.effortName === undefined)
        return template.emitsThinking ? { reasoning: true, label: "thinking tags" } : { reasoning: false, label: "none" };
      return undefined;
    }
    if (!named) return { reasoning: true, supportsReasoningEffort: true, label: "reasoning_effort (unvalidated)" };
    return {
      reasoning: true,
      supportsReasoningEffort: true,
      thinkingLevelMap: effortMap(template.efforts),
      label: `reasoning_effort (${levelsIn(template.efforts).join(", ") || "none"})`,
    };
  }
  const kwargs: ModelsJsonCompat = {};
  if (template.switchName) kwargs[template.switchName] = THINKING_ENABLED;
  // A value the template never named would reach it as pi's own level name, so an effort stays unsent when
  // its values are unknown and the switch alone can carry the request.
  const effortVar = template.effortName;
  const effortSent = effortVar !== undefined && (named || template.effortCap === true || template.switchName === undefined);
  if (effortVar && effortSent) kwargs[effortVar] = THINKING_EFFORT;
  if (template.preserveThinking) kwargs.preserve_thinking = true;
  const sent = Object.keys(kwargs).filter((key) => key !== "preserve_thinking");
  return {
    reasoning: true,
    thinkingFormat: "chat-template",
    chatTemplateKwargs: kwargs,
    supportsReasoningEffort: false,
    thinkingLevelMap: named && effortSent ? effortMap(template.efforts) : undefined,
    label: `${sent.join("+")}${named && effortSent ? ` (${levelsIn(template.efforts).join(", ")})` : ""}`,
  };
}

type ModelsJsonModel = {
  id: string;
  name?: string;
  api?: string;
  baseUrl?: string;
  reasoning?: boolean;
  input?: ("text" | "image")[];
  cost?: { input?: number; output?: number; cacheRead?: number; cacheWrite?: number };
  contextWindow?: number;
  maxTokens?: number;
  headers?: Record<string, string>;
  compat?: ModelsJsonCompat;
  thinkingLevelMap?: Record<string, string | null>;
  samplingParams?: Record<string, unknown>;
};

type ModelsJsonProvider = {
  name?: string;
  baseUrl?: string;
  apiKey?: string;
  api?: string;
  headers?: Record<string, string>;
  authHeader?: boolean;
  compat?: ModelsJsonCompat;
  models?: ModelsJsonModel[];
};

const debug = process.env.LLAMA_COMPAT_DEBUG === "1" ? (message: string) => process.stderr.write(`llama-compat: ${message}\n`) : () => {};

/**
 * Turn an inference baseUrl (ends with /v1) into the server root that answers /props and /models.
 * The same helper sits in ../llama-dx/server.ts and ../subagents/slots.ts; the three extensions are installed
 * side by side but never import each other, so a change belongs in all three.
 */
function serverRoot(baseUrl: string): string | undefined {
  try {
    const url = new URL(baseUrl);
    if (url.protocol !== "http:" && url.protocol !== "https:") return undefined;
    url.pathname = url.pathname.replace(/\/+$/, "").replace(/\/v1$/, "");
    url.search = "";
    url.hash = "";
    return url.toString().replace(/\/$/, "");
  } catch {
    return undefined;
  }
}

async function getJson<T>(url: string, signal?: AbortSignal): Promise<T | undefined> {
  const timeout = AbortSignal.timeout(PROBE_TIMEOUT_MS);
  const linked = signal ? AbortSignal.any([signal, timeout]) : timeout;
  try {
    const response = await fetch(url, { signal: linked });
    if (!response.ok) return undefined;
    return JSON.parse(await response.text()) as T;
  } catch (error) {
    debug(`${url}: ${error instanceof Error ? error.message : error}`);
    return undefined;
  }
}

function isLlamaProps(props: ServerProps | undefined): props is ServerProps {
  return props !== undefined && (props.role === "router" || typeof props.model_alias === "string" || props.chat_template_caps !== undefined);
}

/** Flags that make a preset answer only embeddings or similarity scores, so it can never be chatted with. */
function embeddingOnly(model: RouterModel): boolean {
  return (model.status?.args ?? []).some((flag) => flag === "--embeddings" || flag === "--pooling");
}

/**
 * Whether pi can route a request to a preset: a loaded or sleeping instance answers, a cold one only when
 * the router autoloads it on first use (llama.cpp's own rule for /v1/models + status.value).
 */
function routable(model: RouterModel, autoload: boolean): boolean {
  const status = model.status;
  if (status?.value === "loaded" || status?.value === "sleeping") return true;
  return autoload && status?.value === "unloaded" && !status.failed && model.source === "preset";
}

/** The value a launch flag carries, written `--flag 4` or `--flag=4`; undefined when the flag is absent. */
function flagValue(args: string[], ...flags: string[]): string | undefined {
  for (let i = 0; i < args.length; i++) {
    for (const flag of flags) {
      if (args[i] === flag) return args[i + 1];
      if (args[i]!.startsWith(`${flag}=`)) return args[i]!.slice(flag.length + 1);
    }
  }
  return undefined;
}

/** The context a preset was started with, for a cold instance that cannot report the served one. */
function requestedContext(model: RouterModel): number | undefined {
  const size = Number(flagValue(model.status?.args ?? [], "--ctx-size", "-ctx", "-c"));
  return Number.isSafeInteger(size) && size > 0 ? size : undefined;
}

/** Instances pi can route a configured model to: the preset name, one of its aliases, or the lowercased name. */
function servedFor(models: RouterModel[], root: string, signal?: AbortSignal): Promise<Served[]> {
  return Promise.all(
    models.map(async (model): Promise<Served> => {
      const served: Served = {
        id: model.id,
        aliases: model.aliases ?? [],
        nCtx: model.meta?.n_ctx,
        requested: requestedContext(model),
        vision: model.architecture?.input_modalities?.includes("image"),
      };
      const status = model.status?.value;
      // Only a loaded or sleeping instance answers about its template, and autoload=false keeps it that way:
      // without it the props query would load a cold preset.
      if (status !== "loaded" && status !== "sleeping") return served;
      const props = await getJson<ServerProps>(`${root}/props?${new URLSearchParams({ model: model.id, autoload: "false" })}`, signal);
      if (!props) return served;
      return {
        ...served,
        nCtx: props.default_generation_settings?.n_ctx ?? served.nCtx,
        vision: props.modalities?.vision ?? served.vision,
        thinking: templateThinking(props),
      };
    }),
  );
}

function match(served: Served[], modelId: string): Served | undefined {
  return served.find((entry) => entry.id === modelId || entry.aliases.includes(modelId) || entry.id === modelId.toLowerCase());
}

/**
 * The configured model plus whatever the server says about it. A question the server could not answer
 * (a cold preset, for instance) keeps the configured value.
 */
function withServedInfo(model: ModelsJsonModel, providerCompat: ModelsJsonCompat | undefined, served: Served): {
  config: ChatModelConfig;
  added: string[];
  thinking: string;
} {
  const compat: ModelsJsonCompat = { ...(providerCompat ?? {}), ...(model.compat ?? {}) };
  const llamaCompat: ModelsJsonCompat = {
    supportsStore: false,
    supportsDeveloperRole: false,
    supportsStrictMode: false,
    supportsUsageInStreaming: true,
    maxTokensField: "max_tokens",
  };
  const policy = thinkingPolicy(served);
  if (policy) {
    if (policy.thinkingFormat) compat.thinkingFormat = policy.thinkingFormat;
    else delete compat.thinkingFormat;
    if (policy.chatTemplateKwargs) compat.chatTemplateKwargs = policy.chatTemplateKwargs;
    else delete compat.chatTemplateKwargs;
    llamaCompat.supportsReasoningEffort = policy.supportsReasoningEffort ?? false;
  }

  const servedValues: Derived = {
    reasoning: policy ? policy.reasoning : model.reasoning,
    input: served.vision === undefined ? model.input : served.vision ? ["text", "image"] : ["text"],
    // A hand-written context beats the preset's launch args, which only fill in for a discovered preset.
    contextWindow: served.nCtx ?? model.contextWindow ?? served.requested,
    thinkingLevelMap: policy?.thinkingLevelMap ?? model.thinkingLevelMap,
  };
  if (servedValues.contextWindow && model.maxTokens) {
    servedValues.maxTokens = Math.min(model.maxTokens, servedValues.contextWindow);
  }

  const added = Object.entries(servedValues)
    .filter(([field, value]) => value !== undefined && JSON.stringify(value) !== JSON.stringify((model as Record<string, unknown>)[field]))
    .map(([field]) => field);
  for (const [field, value] of Object.entries(llamaCompat)) {
    if (compat[field] !== value) added.push(field);
    compat[field] = value;
  }

  return {
    config: {
      id: model.id,
      name: model.name ?? model.id,
      reasoning: servedValues.reasoning === true,
      input: servedValues.input ?? ["text"],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, ...(model.cost ?? {}) },
      contextWindow: servedValues.contextWindow ?? 128000,
      maxTokens: servedValues.maxTokens ?? servedValues.contextWindow ?? 128000,
      compat: compat as ChatModelConfig["compat"],
      ...(servedValues.thinkingLevelMap ? { thinkingLevelMap: servedValues.thinkingLevelMap } : {}),
      ...(model.baseUrl ? { baseUrl: model.baseUrl } : {}),
      ...(model.headers ? { headers: model.headers } : {}),
      ...(model.samplingParams ? { samplingParams: model.samplingParams } : {}),
    },
    added,
    thinking: policy?.label ?? "as configured",
  };
}

async function readConfiguredProviders(): Promise<Map<string, ModelsJsonProvider>> {
  const text = await readFile(join(getAgentDir(), "models.json"), "utf8").catch(() => undefined);
  if (!text) return new Map();
  try {
    const parsed = JSON.parse(text.replace(/^\uFEFF/, "")) as { providers?: Record<string, ModelsJsonProvider> };
    return new Map(Object.entries(parsed.providers ?? {}));
  } catch (error) {
    debug(`models.json unreadable: ${error instanceof Error ? error.message : error}`);
    return new Map();
  }
}

export default async function llamaCompat(pi: ExtensionAPI) {
  const providers = await readConfiguredProviders();

  await Promise.all(
    [...providers].map(async ([name, provider]) => {
      const declared = provider.models ?? [];
      const api = provider.api ?? "openai-completions";
      if (name === BUILTIN_PROVIDER || api !== "openai-completions") return;
      const root = serverRoot(provider.baseUrl ?? declared[0]?.baseUrl ?? "");
      const router = await getJson<ServerProps>(root ? `${root}/props` : "");
      if (!root || !isLlamaProps(router)) return;
      const autoload = router.models_autoload === true;

      // A provider that declares models keeps exactly those; one that declares nothing is filled from the
      // presets the router advertises, so a new preset needs no config change.
      const wanted = (advertised: RouterModel[]): ModelsJsonModel[] =>
        declared.length > 0
          ? declared
          : advertised
              .filter((model) => routable(model, autoload) && !embeddingOnly(model))
              .map((model) => ({ id: model.id, name: model.id }));

      let current: ChatModelConfig[] = [];
      let detail = "";
      const rebuild = async (signal?: AbortSignal): Promise<boolean> => {
        const advertised = (await getJson<{ data?: RouterModel[] }>(`${root}/models`, signal))?.data ?? [];
        const served = await servedFor(advertised, root, signal);
        const models = wanted(advertised);
        // Registering a provider replaces its whole model list, so a single configured model the server does
        // not offer means the provider stays exactly as models.json describes it rather than losing it.
        const missing = models.map((model) => model.id).filter((id) => !match(served, id));
        if (missing.length > 0) {
          debug(`${name}: ${root} does not offer ${missing.join(", ")}`);
          return false;
        }
        const built = models.map((model) => withServedInfo(model, provider.compat, match(served, model.id) ?? { id: model.id, aliases: [] }));
        current = built.map((entry) => entry.config);
        detail = built.map((entry) => `${entry.config.id}: ${entry.added.join(" ") || "nothing new"}, thinking=${entry.thinking}`).join("; ");
        return true;
      };

      if (!(await rebuild())) return;

      const config: ProviderConfig = {
        name: provider.name,
        baseUrl: provider.baseUrl,
        api: "openai-completions",
        headers: provider.headers,
        authHeader: provider.authHeader,
        models: current,
        refreshModels: async (context) => {
          if (context.allowNetwork && !context.signal.aborted) await rebuild(context.signal);
          return current;
        },
      };
      // models.json holds the key as a literal or as $NAME interpolation, both accepted here.
      if (provider.apiKey) config.apiKey = provider.apiKey;

      pi.registerProvider(name, config);
      debug(`${name} <- ${root}: ${current.length} models: ${detail || "none routable"}`);
    }),
  );
}
