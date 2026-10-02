import type { ExtensionAPI, ProviderConfig, ProviderModelConfig } from "@earendil-works/pi-coding-agent";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

// pi cannot know what a llama.cpp server actually serves: the served n_ctx after a re-fit, whether the
// chat template has a thinking switch and which one it reads, whether the instance has a vision projector.
// This extension reads that from the server and re-registers the configured provider with it, so the
// hand-written numbers in models.json stop mattering. It never loads or unloads a model, and it shows
// nothing: no command, no tool, no panel.

const PROBE_TIMEOUT_MS = 2000;
/** Its own built-in provider already reads /models and /props; re-registering it would drop its classifiers. */
const BUILTIN_PROVIDER = "llama.cpp";

type Caps = {
  supports_tools?: boolean;
  supports_reasoning_effort?: boolean;
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

/** What one instance of a router is able to do, as far as the server will say without loading it. */
type Served = {
  id: string;
  aliases: string[];
  nCtx?: number;
  /** What the preset was started with, from its launch args; weaker than the served n_ctx. */
  requested?: number;
  vision?: boolean;
  /** The template has an enable_thinking switch. */
  thinkingSwitch?: boolean;
  /** The template reads OpenAI's reasoning_effort. */
  effortCap?: boolean;
  /** The effort values the template names; empty when it validates none. */
  efforts?: string[];
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
  supportsReasoningEffort?: boolean;
  thinkingLevelMap?: ChatModelConfig["thinkingLevelMap"];
  label: string;
};

const PI_EFFORT_LEVELS = ["minimal", "low", "medium", "high", "xhigh", "max"];

const EFFORT_NAME = String.raw`\w*reasoning_effort`;
const EFFORT_LITERAL = String.raw`['"]([a-z][a-z0-9_-]*)['"]`;

/**
 * The effort values a chat template accepts, taken from the values it branches on, defaults to or validates.
 * Undefined when the template is unknown, empty when it reads reasoning_effort without naming a value.
 */
function effortsIn(template: unknown): string[] | undefined {
  if (typeof template !== "string") return undefined;
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
  return [...found].sort();
}

function thinkingPolicy(served: Served): ThinkingPolicy | undefined {
  // A bool switch can turn thinking off, an effort cannot, so it wins where a template has both. pi checks
  // thinkingFormat before reasoning_effort, so only one of the two is ever sent.
  if (served.thinkingSwitch === true) {
    return { reasoning: true, thinkingFormat: "qwen-chat-template", supportsReasoningEffort: false, label: "bool" };
  }
  if (served.effortCap !== true) {
    if (served.thinkingSwitch === false && served.effortCap === false) return { reasoning: false, label: "none" };
    return undefined;
  }
  if (!served.efforts || served.efforts.length === 0) {
    return { reasoning: true, supportsReasoningEffort: true, label: "efforts (unvalidated)" };
  }
  // pi sends thinkingLevelMap[level] ?? level, so a level the template would reject has to be marked null.
  const map: Record<string, string | null> = {};
  for (const level of PI_EFFORT_LEVELS) map[level] = served.efforts.includes(level) ? level : null;
  const supported = PI_EFFORT_LEVELS.filter((level) => map[level] !== null);
  return { reasoning: true, supportsReasoningEffort: true, thinkingLevelMap: map, label: `efforts (${supported.join(", ") || "none"})` };
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

/** Turn an inference baseUrl (ends with /v1) into the server root that answers /props and /models. */
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

/** The context a preset was started with, for a cold instance that cannot report the served one. */
function requestedContext(model: RouterModel): number | undefined {
  const args = model.status?.args ?? [];
  for (let i = 0; i < args.length - 1; i++) {
    if (args[i] !== "--ctx-size" && args[i] !== "-c" && args[i] !== "-ctx") continue;
    const size = Number(args[i + 1]);
    if (Number.isSafeInteger(size) && size > 0) return size;
  }
  return undefined;
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
        thinkingSwitch: typeof props.chat_template === "string" ? props.chat_template.includes("enable_thinking") : undefined,
        effortCap: props.chat_template_caps?.supports_reasoning_effort,
        efforts: effortsIn(props.chat_template),
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
  const agentDir = process.env.PI_CODING_AGENT_DIR ?? join(process.env.HOME ?? "", ".pi", "agent");
  const text = await readFile(join(agentDir, "models.json"), "utf8").catch(() => undefined);
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
