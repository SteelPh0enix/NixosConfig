import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { Model } from "@earendil-works/pi-ai";
import { Type } from "typebox";

// What a llama.cpp router answers on /props and /models; only the fields pi's models.json depends on.
type Caps = {
  supports_tools?: boolean;
  supports_tool_calls?: boolean;
  supports_system_role?: boolean;
  supports_parallel_tool_calls?: boolean;
  supports_preserve_reasoning?: boolean;
  supports_reasoning_effort?: boolean;
  supports_object_arguments?: boolean;
};

type ServerProps = {
  role?: string;
  max_instances?: number;
  models_autoload?: boolean;
  build_info?: string;
  model_alias?: string;
  model_ftype?: string;
  total_slots?: number;
  is_sleeping?: boolean;
  chat_template?: string;
  chat_template_caps?: Caps;
  modalities?: { vision?: boolean };
  endpoint_slots?: boolean;
  default_generation_settings?: { n_ctx?: number };
};

type RouterInstance = {
  id: string;
  aliases?: string[];
  source?: string;
  status?: { value?: string; failed?: boolean };
  meta?: { n_ctx?: number; ftype?: string };
  architecture?: { input_modalities?: string[] };
};

type CompatLike = {
  supportsReasoningEffort?: boolean;
  thinkingFormat?: string;
  supportsDeveloperRole?: boolean;
  maxTokensField?: string;
};

type Level = "error" | "warn" | "info";

type Finding = {
  level: Level;
  /** "provider/id" for a pi model, or the server root for a router-wide problem. */
  scope: string;
  code: string;
  message: string;
  fix?: string;
  dedupeKey?: string;
};

type Instance = {
  id: string;
  aliases: string[];
  status: string;
  failed: boolean;
  nCtx?: number;
  ftype?: string;
  totalSlots?: number;
  sleeping?: boolean;
  caps?: Caps;
  vision?: boolean;
  templateThinking?: boolean;
  note?: string;
};

type Server = {
  root: string;
  buildInfo?: string;
  role?: string;
  maxInstances?: number;
  autoload?: boolean;
  /** Set when the endpoint is unreachable or is not a llama.cpp server; such servers are skipped. */
  skip?: string;
  instances: Instance[];
  models: { provider: string; id: string; instance?: string }[];
};

type Report = { checkedAt: string; servers: Server[]; findings: Finding[] };

const PROBE_TIMEOUT_MS = 5000;
const WIDGET_KEY = "llama-compat";
const WIDGET_MAX_LINES = 30;
const LEVELS: Record<Level, number> = { error: 0, warn: 1, info: 2 };
const MARKS: Record<Level, string> = { error: "x", warn: "!", info: "-" };

function envList(name: string): string[] {
  return (process.env[name] ?? "")
    .split(",")
    .map((entry) => entry.trim().replace(/\/+$/, "").replace(/\/v1$/, ""))
    .filter(Boolean);
}

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

/**
 * Chat models grouped by the llama.cpp server that would serve them. Detection always runs: a
 * server is managed when its provider is named after llama (pi's built-in `llama.cpp`, or a
 * models.json provider like `llama-b`), or when LLAMA_COMPAT_URLS lists it - and then every model
 * pointing at it is compared, whatever its provider is called. Model names are deliberately not
 * matched, because llama models served by a hosted provider are not a local llama.cpp server.
 */
function candidates(models: Model<unknown>[]): Map<string, Model<unknown>[]> {
  const listed = new Set(envList("LLAMA_COMPAT_URLS"));
  const grouped = new Map<string, Model<unknown>[]>();
  const add = (root: string, model?: Model<unknown>) => {
    grouped.set(root, model ? [...(grouped.get(root) ?? []), model] : (grouped.get(root) ?? []));
  };
  for (const model of models) {
    if (model.type && model.type !== "chat") continue;
    const root = serverRoot(model.baseUrl);
    if (!root) continue;
    if (model.provider.toLowerCase().includes("llama") || listed.has(root)) add(root, model);
  }
  for (const root of listed) add(root);
  return grouped;
}

type Fetched<T> = { ok: true; data: T } | { ok: false; status?: number; error: string };

async function getJson<T>(url: string, signal?: AbortSignal, headers?: Record<string, string>): Promise<Fetched<T>> {
  const timeout = AbortSignal.timeout(PROBE_TIMEOUT_MS);
  const linked = signal ? AbortSignal.any([signal, timeout]) : timeout;
  try {
    const response = await fetch(url, {
      signal: linked,
      headers: headers && Object.keys(headers).length > 0 ? headers : undefined,
    });
    const text = await response.text();
    if (!response.ok) {
      const detail = text.slice(0, 200).replace(/\s+/g, " ");
      return { ok: false, status: response.status, error: detail || `HTTP ${response.status}` };
    }
    return { ok: true, data: JSON.parse(text) as T };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return { ok: false, error: message === "fetch failed" ? "unreachable" : message };
  }
}

function isLlamaProps(props: ServerProps): boolean {
  return props.role === "router" || typeof props.model_alias === "string" || props.chat_template_caps !== undefined;
}

function templateSupportsThinking(props: ServerProps): boolean {
  return typeof props.chat_template === "string" && props.chat_template.includes("enable_thinking");
}

/** Instances that several pi models share should report one instance-wide problem, not one per model. */
function addFinding(
  findings: Finding[],
  level: Level,
  scope: string,
  code: string,
  message: string,
  fix?: string,
  dedupeKey?: string,
): void {
  const key = dedupeKey ?? `${scope} ${code}`;
  if (findings.some((entry) => (entry.dedupeKey ?? `${entry.scope} ${entry.code}`) === key)) return;
  findings.push({ level, scope, code, message, fix, dedupeKey });
}

function instanceFor(server: Server, modelId: string): Instance | undefined {
  return server.instances.find(
    (instance) => instance.id === modelId || instance.aliases.includes(modelId) || instance.id === modelId.toLowerCase(),
  );
}

function instanceSummary(instance: Instance): string {
  const caps = instance.caps;
  const parts = [instance.status, `ctx ${instance.nCtx ?? "?"}`, instance.totalSlots === undefined ? "" : `slots ${instance.totalSlots}`];
  if (instance.ftype) parts.push(instance.ftype);
  if (caps) {
    parts.push(`tools ${caps.supports_tools && caps.supports_tool_calls ? "yes" : "NO"}`);
    parts.push(`effort ${caps.supports_reasoning_effort ? "yes" : "no"}`);
  }
  return parts.filter(Boolean).join(", ");
}

function inspectModel(
  model: Model<unknown>,
  server: Server,
  instance: Instance | undefined,
  findings: Finding[],
  current: boolean,
): void {
  const scope = `${model.provider}/${model.id}`;
  const compat = (model.compat ?? {}) as CompatLike;
  // Tools are sent to every model pi selects, so a template without tool support fails on any model.
  const toolLevel: Level = current ? "error" : "warn";
  const softToolLevel: Level = current ? "warn" : "info";

  if (!instance) {
    const offered = server.instances.map((entry) => entry.id).join(", ") || "none";
    addFinding(
      findings,
      "error",
      scope,
      "not-offered",
      `the server does not list "${model.id}" (it offers: ${offered}); requests fail with 400 model not found`,
      "use a name the server lists, add a preset section for it (then GET /models?reload=1), or refresh pi's catalog",
    );
    return;
  }

  if (instance.status !== "loaded" && instance.status !== "sleeping") {
    addFinding(
      findings,
      instance.failed ? "error" : "info",
      scope,
      "caps-unknown",
      `instance "${instance.id}" is ${instance.status}${instance.failed ? " (failed to load)" : ""}: no template capabilities to check`,
      server.autoload ? "load it (POST /models/load) or let autoload warm it, then re-run" : undefined,
    );
    return;
  }

  const caps = instance.caps ?? {};

  if (!caps.supports_tools) {
    addFinding(
      findings,
      toolLevel,
      scope,
      "no-tools",
      "pi sends tool definitions to every model, but this chat template cannot use them: answers come back tool-free",
      "pick an instance whose preset runs with jinja = true and a tool-capable template",
    );
  } else if (caps.supports_tool_calls === false) {
    addFinding(
      findings,
      toolLevel,
      scope,
      "no-tool-calls",
      "the template takes tool definitions but cannot emit calls: tool-using requests stay tool-free",
      "pick an instance with a tool-calling template",
    );
  }
  if (caps.supports_object_arguments === false) {
    addFinding(
      findings,
      softToolLevel,
      scope,
      "object-arguments",
      "the template wants string tool arguments while pi sends JSON objects",
      "verify a real tool round trip before trusting this model with tools",
    );
  }
  if (caps.supports_parallel_tool_calls === false) {
    addFinding(
      findings,
      "info",
      scope,
      "parallel-tool-calls",
      "the template supports one tool call per turn",
      undefined,
      `${server.root} ${instance.id} parallel-tool-calls`,
    );
  }

  const images = model.input?.includes("image") === true;
  if (images && instance.vision === false) {
    addFinding(
      findings,
      "warn",
      scope,
      "vision-declared",
      `models.json declares image input but the instance has no vision projector`,
      `set "input": ["text"] for ${model.id}`,
    );
  } else if (!images && instance.vision === true) {
    addFinding(
      findings,
      "info",
      scope,
      "vision-unused",
      "the instance can take images but models.json declares text only",
      `set "input": ["text", "image"] for ${model.id}`,
    );
  }

  const liveCtx = instance.nCtx;
  if (liveCtx && liveCtx > 0) {
    if (model.contextWindow > liveCtx) {
      addFinding(
        findings,
        "error",
        scope,
        "context-overflow",
        `models.json declares contextWindow ${model.contextWindow} above the served n_ctx ${liveCtx}`,
        `set "contextWindow": ${liveCtx}`,
      );
    } else if (model.contextWindow < liveCtx * 0.75) {
      addFinding(
        findings,
        "info",
        scope,
        "context-undersized",
        `served n_ctx is ${liveCtx} but pi stops at ${model.contextWindow}`,
        `set "contextWindow": ${liveCtx} to use the whole instance`,
      );
    }
    if (model.maxTokens > liveCtx) {
      addFinding(
        findings,
        "error",
        scope,
        "max-tokens",
        `maxTokens ${model.maxTokens} exceeds served n_ctx ${liveCtx}`,
        `set "maxTokens": ${Math.min(liveCtx, 32768)}`,
      );
    }
  }

  const effortFromTemplate = caps.supports_reasoning_effort === true;
  // pi detects both from the URL, and a LAN endpoint lands on the hosted-OpenAI defaults.
  const thinkingFormat = compat.thinkingFormat ?? "openai";
  const sendsReasoningEffort = compat.supportsReasoningEffort !== false && thinkingFormat === "openai";
  const thinkingFromTemplate = instance.templateThinking === true || caps.supports_preserve_reasoning === true;
  if (model.reasoning) {
    if (!effortFromTemplate && !thinkingFromTemplate) {
      addFinding(
        findings,
        "warn",
        scope,
        "thinking-unsupported",
        "reasoning is on in models.json but the template has no thinking switch",
        `set "reasoning": false for ${model.id}, or check the preset (jinja = true)`,
      );
    } else if (sendsReasoningEffort && !effortFromTemplate) {
      addFinding(
        findings,
        "warn",
        scope,
        "thinking-ignored",
        "pi sends reasoning_effort, but this template ignores it: the thinking level does nothing",
        `"thinkingFormat": "qwen-chat-template" for ${model.id}`,
      );
    } else if (thinkingFormat === "openai" && compat.supportsReasoningEffort === false) {
      addFinding(
        findings,
        "warn",
        scope,
        "thinking-not-sent",
        "pi sends no thinking switch at all, so the thinking level does nothing and the server default wins",
        `"thinkingFormat": "qwen-chat-template" for ${model.id}`,
      );
    } else if (effortFromTemplate && thinkingFormat === "qwen-chat-template" && compat.supportsReasoningEffort !== true) {
      addFinding(
        findings,
        "info",
        scope,
        "effort-unused",
        "the template reads reasoning_effort but pi only sends enable_thinking",
        'drop "thinkingFormat" and set "supportsReasoningEffort": true to expose effort levels',
      );
    }
    if (thinkingFormat === "qwen-chat-template" && caps.supports_preserve_reasoning === false) {
      addFinding(
        findings,
        "info",
        scope,
        "preserve-thinking",
        "pi sends preserve_thinking, which this template ignores",
      );
    }
  } else if (instance.templateThinking === true) {
    addFinding(
      findings,
      "info",
      scope,
      "reasoning-off",
      "the template has a thinking switch but models.json says reasoning: false",
      `set "reasoning": true for ${model.id}`,
    );
  }

  if (instance.totalSlots === 1) {
    addFinding(
      findings,
      "info",
      scope,
      "single-slot",
      "the instance has one slot: simultaneous requests queue instead of interleaving",
      "raise parallel = N in the preset (KV cache splits per slot)",
      `${server.root} ${instance.id} single-slot`,
    );
  }
}

function inspectServer(server: Server, findings: Finding[]): void {
  const presets = server.instances.length;
  if (server.maxInstances !== undefined && presets > server.maxInstances) {
    addFinding(
      findings,
      "info",
      server.root,
      "lru-eviction",
      `the router knows ${presets} instances but keeps only max_instances ${server.maxInstances}: the least recently used one is unloaded when another loads`,
      "raise --models-max or keep fewer models loaded",
    );
  }
  const failed = server.instances.filter((instance) => instance.failed).map((instance) => instance.id);
  if (failed.length > 0) {
    addFinding(
      findings,
      "error",
      server.root,
      "instance-failed",
      `${failed.join(", ")} failed to start and ${failed.length === 1 ? "answers nothing" : "answer nothing"}; check the server log`,
    );
  }
}

function describeServer(server: Server): string {
  const bits = [`${server.role === "router" ? "router" : "single"} ${server.buildInfo ?? "?"}`];
  if (server.maxInstances !== undefined) bits.push(`max_instances ${server.maxInstances}`);
  if (server.autoload !== undefined) bits.push(`autoload ${server.autoload ? "on" : "off"}`);
  return bits.join(", ");
}

async function probe(
  root: string,
  models: Model<unknown>[],
  signal: AbortSignal | undefined,
  headers?: Record<string, string>,
): Promise<Server> {
  const server: Server = { root, instances: [], models: models.map((model) => ({ provider: model.provider, id: model.id })) };

  const props = await getJson<ServerProps>(`${root}/props`, signal, headers);
  if (!props.ok) {
    server.skip = props.error;
    return server;
  }
  if (!isLlamaProps(props.data)) {
    server.skip = "not a llama.cpp server";
    return server;
  }

  server.role = props.data.role;
  server.buildInfo = props.data.build_info;
  server.maxInstances = props.data.max_instances;
  server.autoload = props.data.models_autoload;

  if (server.role === "router") {
    const listed = await getJson<{ data?: RouterInstance[] }>(`${root}/models`, signal, headers);
    const entries = listed.ok ? listed.data.data ?? [] : [];
    server.instances = entries.map((entry) => ({
      id: entry.id,
      aliases: entry.aliases ?? [],
      status: entry.status?.value ?? "unknown",
      failed: entry.status?.failed === true,
      nCtx: entry.meta?.n_ctx,
      ftype: entry.meta?.ftype,
      vision: entry.architecture?.input_modalities?.includes("image"),
    }));
    const warm = server.instances.filter((instance) => instance.status === "loaded" || instance.status === "sleeping");
    await Promise.all(
      warm.map(async (instance) => {
        // autoload=false keeps a sleeping instance asleep and an unloaded instance cold.
        const instanceProps = await getJson<ServerProps>(
          `${root}/props?${new URLSearchParams({ model: instance.id, autoload: "false" })}`,
          signal,
          headers,
        );
        if (!instanceProps.ok) {
          instance.note = instanceProps.error;
          return;
        }
        instance.caps = instanceProps.data.chat_template_caps;
        instance.totalSlots = instanceProps.data.total_slots;
        instance.sleeping = instanceProps.data.is_sleeping;
        instance.nCtx = instanceProps.data.default_generation_settings?.n_ctx ?? instance.nCtx;
        instance.ftype = instanceProps.data.model_ftype ?? instance.ftype;
        instance.vision = instanceProps.data.modalities?.vision ?? instance.vision;
        instance.templateThinking = templateSupportsThinking(instanceProps.data);
      }),
    );
    return server;
  }

  // Single-model llama.cpp: /props already carries the instance.
  server.instances = [
    {
      id: props.data.model_alias ?? "default",
      aliases: [],
      status: props.data.is_sleeping ? "sleeping" : "loaded",
      failed: false,
      nCtx: props.data.default_generation_settings?.n_ctx,
      ftype: props.data.model_ftype,
      totalSlots: props.data.total_slots,
      sleeping: props.data.is_sleeping,
      caps: props.data.chat_template_caps,
      vision: props.data.modalities?.vision,
      templateThinking: templateSupportsThinking(props.data),
    },
  ];
  return server;
}

async function buildReport(ctx: ExtensionContext): Promise<Report> {
  const grouped = candidates(ctx.modelRegistry.getAll() as Model<unknown>[]);
  const sessionKey = ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : undefined;
  const servers: Server[] = [];
  const findings: Finding[] = [];

  await Promise.all(
    [...grouped].map(async ([root, models]) => {
      // A listed server may have no pi model at all; then it is probed without credentials.
      const auth = models[0] ? await ctx.modelRegistry.getApiKeyAndHeaders(models[0]) : undefined;
      const headers = auth?.ok
        ? { ...(auth.headers ?? {}), ...(auth.apiKey ? { Authorization: `Bearer ${auth.apiKey}` } : {}) }
        : undefined;
      const server = await probe(root, models, ctx.signal, headers);
      if (server.skip === undefined) servers.push(server);
      else if (process.env.LLAMA_COMPAT_DEBUG) findings.push({ level: "info", scope: root, code: "skipped", message: server.skip });
    }),
  );

  for (const server of servers) {
    inspectServer(server, findings);
    for (const ref of server.models) {
      const model = ctx.modelRegistry.find(ref.provider, ref.id) as Model<unknown> | undefined;
      if (!model) continue;
      const instance = instanceFor(server, model.id);
      if (instance) ref.instance = instance.id;
      inspectModel(model, server, instance, findings, `${model.provider}/${model.id}` === sessionKey);
    }
  }

  servers.sort((a, b) => a.root.localeCompare(b.root));
  findings.sort((a, b) => LEVELS[a.level] - LEVELS[b.level] || a.scope.localeCompare(b.scope));
  return { checkedAt: new Date().toISOString(), servers, findings };
}

/** Ready-to-paste models.json entry per server, built from what the instances actually serve. */
function modelsJsonBlocks(report: Report): string[] {
  const lines: string[] = [];
  for (const server of report.servers) {
    const usable = server.instances.filter((instance) => instance.status === "loaded" || instance.status === "sleeping");
    const contextOf = (instance: Instance) => instance.nCtx ?? 0;
    const provider = providerNameFor(server);
    if (usable.length === 0) {
      lines.push(`// ${provider}: load an instance on ${server.root} to read its served context`);
      continue;
    }
    const hasThinking = (instance: Instance) =>
      instance.templateThinking === true || instance.caps?.supports_reasoning_effort === true;
    const reasoning = usable.some(hasThinking);
    lines.push(`"${provider}": {`);
    lines.push(`  "baseUrl": "${server.root}/v1",`);
    lines.push(`  "api": "openai-completions",`);
    lines.push(`  "apiKey": "none",`);
    lines.push(`  "compat": {`);
    lines.push(`    "supportsStore": false,`);
    lines.push(`    "supportsDeveloperRole": false,`);
    lines.push(`    "supportsReasoningEffort": false,`);
    lines.push(`    "supportsUsageInStreaming": true,`);
    lines.push(`    "supportsStrictMode": false,`);
    lines.push(`    "maxTokensField": "max_tokens"${reasoning ? "," : ""}`);
    if (reasoning) lines.push(`    "thinkingFormat": "qwen-chat-template"`);
    lines.push(`  },`);
    lines.push(`  "models": [`);
    usable.forEach((instance, index) => {
      const context = contextOf(instance);
      const input = instance.vision ? `["text", "image"]` : `["text"]`;
      lines.push(`    {`);
      lines.push(`      "id": "${instance.id}",`);
      lines.push(`      "name": "${instance.id}${instance.ftype ? ` (${instance.ftype})` : ""}",`);
      lines.push(`      "reasoning": ${hasThinking(instance)},`);
      lines.push(`      "input": ${input},`);
      lines.push(`      "contextWindow": ${context || 1},`);
      lines.push(`      "maxTokens": ${Math.min(context || 1, 32768)},`);
      lines.push(`      "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }`);
      lines.push(`    }${index === usable.length - 1 ? "" : ","}`);
    });
    lines.push(`  ]`);
    lines.push(`},`);
    lines.push("");
  }
  return lines.length === 0 ? ["// no llama.cpp server answered"] : lines;
}

function providerNameFor(server: Server): string {
  const providers = new Set(server.models.map((model) => model.provider));
  if (providers.size === 1) return [...providers][0]!;
  const host = new URL(server.root).hostname.split(".")[0]!;
  return `${host}-${new URL(server.root).port || "80"}`;
}

function renderReport(report: Report): string[] {
  const lines: string[] = [];
  if (report.servers.length === 0) {
    return [
      "llama-compat: no llama.cpp server answered",
      "check the providers in models.json, or set LLAMA_COMPAT_URLS to the server roots",
    ];
  }
  for (const server of report.servers) {
    lines.push(`${new URL(server.root).host} - ${describeServer(server)}`);
    for (const instance of server.instances) {
      const models = server.models.filter((model) => model.instance === instance.id);
      const pinned = models.length > 0 ? `  <- ${models.map((model) => `${model.provider}/${model.id}`).join(", ")}` : "";
      lines.push(`  ${instance.status === "loaded" ? "o" : instance.status === "failed" ? "x" : "."} ${instance.id}: ${instanceSummary(instance)}${pinned}`);
      if (instance.note) lines.push(`      note: ${instance.note}`);
    }
  }
  if (report.findings.length === 0) {
    lines.push("no mismatches");
    return lines;
  }
  lines.push("");
  lines.push("findings:");
  for (const finding of report.findings) {
    lines.push(`  ${MARKS[finding.level]} ${finding.scope} [${finding.code}] ${finding.message}`);
    if (finding.fix) lines.push(`      fix: ${finding.fix}`);
  }
  return lines;
}

function reportFor(report: Report, filter: string | undefined): Report {
  if (!filter) return report;
  const keep = (scope: string) => scope.includes(filter);
  return {
    ...report,
    servers: report.servers.filter((server) => keep(server.root) || server.models.some((model) => keep(`${model.provider}/${model.id}`))),
    findings: report.findings.filter((finding) => keep(finding.scope)),
  };
}

export default function llamaCompat(pi: ExtensionAPI) {
  async function check(ctx: ExtensionContext, filter?: string): Promise<Report> {
    return reportFor(await buildReport(ctx), filter);
  }

  pi.registerCommand("llama-check", {
    description: "Check llama.cpp routers against models.json (usage: /llama-check [text] [block|off])",
    handler: async (args, ctx) => {
      const parts = args.trim().split(/\s+/).filter(Boolean);
      const mode = parts.find((part) => part === "block" || part === "off") ?? "";
      const filter = parts.find((part) => part !== mode);

      if (mode === "off") {
        ctx.ui.setWidget(WIDGET_KEY, undefined);
        return;
      }

      const report = await check(ctx, filter);
      if (mode === "block") {
        const block = modelsJsonBlocks(report);
        ctx.ui.setWidget(WIDGET_KEY, block.slice(0, WIDGET_MAX_LINES), { placement: "aboveEditor" });
        ctx.ui.notify(`llama-compat: models.json block for ${report.servers.length} server(s) shown above`, "info");
        return;
      }

      const lines = renderReport(report);
      const errors = report.findings.filter((finding) => finding.level === "error").length;
      const warnings = report.findings.filter((finding) => finding.level === "warn").length;
      ctx.ui.setWidget(WIDGET_KEY, lines.slice(0, WIDGET_MAX_LINES), { placement: "aboveEditor" });
      if (errors > 0) ctx.ui.notify(`llama-compat: ${errors} error(s), ${warnings} warning(s) - see panel above`, "error");
      else if (warnings > 0) ctx.ui.notify(`llama-compat: ${warnings} warning(s) - see panel above`, "warning");
      else ctx.ui.notify("llama-compat: no mismatches", "info");
    },
  });

  pi.registerTool({
    name: "llama_compat",
    label: "llama.cpp Compat",
    description:
      "Read what each llama.cpp instance can do (tool calling, thinking, slots, served context) and report mismatches with pi's models.json.",
    promptSnippet: "Check llama.cpp instance capabilities against models.json before using a router model",
    promptGuidelines: [
      "Call llama_compat with format \"summary\" before selecting a llama.cpp model for tool work; format \"json\" gives raw caps and format \"block\" a models.json entry.",
    ],
    exposure: "codemode",
    parameters: Type.Object({
      filter: Type.Optional(Type.String({ description: "Only check servers or models whose name contains this text" })),
      format: Type.Optional(
        Type.Union([Type.Literal("summary"), Type.Literal("json"), Type.Literal("block")], {
          description: "summary = findings text (default), json = raw caps, block = paste-ready models.json entry",
        }),
      ),
    }),

    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      const report = await check(ctx, params.filter);
      const format = params.format ?? "summary";
      const lines =
        format === "json"
          ? [JSON.stringify(report, null, 2)]
          : format === "block"
            ? modelsJsonBlocks(report)
            : renderReport(report);
      return {
        content: [{ type: "text", text: lines.join("\n") }],
        details: {
          servers: report.servers.map((server) => server.root),
          errors: report.findings.filter((finding) => finding.level === "error").length,
          warnings: report.findings.filter((finding) => finding.level === "warn").length,
        },
      };
    },
  });

  pi.on("session_start", async (_event, ctx) => {
    if (process.env.PI_LLAMA_CHECK !== "1") return;
    try {
      const report = await check(ctx);
      const errors = report.findings.filter((finding) => finding.level === "error").length;
      if (errors > 0) {
        ctx.ui.setWidget(WIDGET_KEY, renderReport(report).slice(0, WIDGET_MAX_LINES), { placement: "aboveEditor" });
        ctx.ui.notify(`llama-compat: ${errors} error(s) in models.json - run /llama-check`, "error");
      }
    } catch {
      // Never block a session on a server probe.
    }
  });
}

export { buildReport, modelsJsonBlocks, probe, renderReport };
