import type { ExtensionAPI, ExtensionContext, Theme, ThemeColor } from "@earendil-works/pi-coding-agent";
import type { Component, TUI } from "@earendil-works/pi-tui";

// Three fixed rows under the editor: speeds, token totals, prefill progress + session counters.
// Cell order and widths never change, values latch instead of dropping out, and latched values are dimmed.

const POLL_MS = 250;
/** /metrics is scraped less often than /slots: it posts a task to the server queue and answers ~2.5 kB. */
const METRICS_EVERY_MS = 1000;
const WINDOW_MS = 3000;
const PROBE_TIMEOUT_MS = 1500;
const WIDGET_KEY = "llama-dx";
const BAR = 12;
const GAP = "  ";

type Slot = {
  id?: number;
  n_ctx?: number;
  is_processing?: boolean;
  n_prompt_tokens?: number;
  n_prompt_tokens_processed?: number;
  n_prompt_tokens_cache?: number;
  next_token?: { n_decoded?: number }[];
};

type Timings = {
  cache_n?: number;
  prompt_n?: number;
  prompt_per_second?: number;
  predicted_n?: number;
  predicted_per_second?: number;
  draft_n?: number;
  draft_n_accepted?: number;
};

type Req = {
  root: string;
  instance: string;
  chars: number;
  estPrompt: number;
  seenPrompt: number;
  processed: number;
  cached: number;
  decoded: number;
  nCtx: number;
  slots: number;
  slotId?: number;
  processing: boolean;
  started: number;
  firstToken?: number;
  ended?: number;
  timings?: Timings;
  /** Server-wide gauges from /metrics; absent when the server was started without --metrics. */
  metrics?: Metrics;
  metricsAt?: number;
  counted: boolean;
};

type Metrics = {
  deferred?: number;
  processing?: number;
  busy?: number;
  accepted?: number;
  drafted?: number;
  nmax?: number;
};

type Nums = {
  pp?: number;
  /** True when the value is not llama.cpp's own number: a live window rate or an estimate from history. */
  ppEstimated: boolean;
  tgEstimated: boolean;
  tg?: number;
  spec?: [accepted: number, drafted: number];
  ttft?: number;
  prompt?: number;
  /** True while the prompt size is the body-size estimate rather than llama.cpp's number. */
  estimated: boolean;
  evalToks?: number;
  reuse?: number;
  out?: number;
  nCtx?: number;
};

const debug = process.env.LLAMA_DX_DEBUG === "1" ? (m: string) => process.stderr.write(`llama-dx: ${m}\n`) : () => void 0;

const kfmt = (n: number): string =>
  n >= 1_000_000 ? `${(n / 1_000_000).toFixed(1)}M` : n >= 10_000 ? `${Math.round(n / 1000)}k` : n >= 1000 ? `${(n / 1000).toFixed(1)}k` : String(Math.round(n));

const fmtMs = (ms: number): string => (ms < 1000 ? `${Math.round(ms)}ms` : `${(ms / 1000).toFixed(1)}s`);

const num = (v: number | undefined, w: number): string => (v === undefined || !Number.isFinite(v) ? "—" : kfmt(v)).padStart(w);

const word = (v: string | undefined, w: number): string => (v ?? "—").padStart(w);

let req: Req | undefined;
let last: Req | undefined;
const sess = { reqs: 0, prompt: 0, evalToks: 0, reuse: 0, out: 0 };
let samples: { t: number; processed: number; decoded: number }[] = [];
let charsPerToken = 3.6;
let detailed = false;
let freeze = true;
let misses = 0;
let idlePolls = 0;
let warned = false;
let pollTimer: ReturnType<typeof setInterval> | undefined;
let tui: TUI | undefined;
/** The model pi is on, so the panel has something to show before the first request. */
let model = { root: undefined as string | undefined, id: "", nCtx: 0 };
/** Settled "is this a llama.cpp server" answers; unknown roots are treated as one. */
const llamaRoots = new Map<string, boolean>();
const probing = new Set<string>();

function serverRoot(m: { baseUrl?: string } | undefined): string | undefined {
  if (!m?.baseUrl) return undefined;
  try {
    const url = new URL(m.baseUrl);
    if (url.protocol !== "http:" && url.protocol !== "https:") return undefined;
    url.pathname = url.pathname.replace(/\/+$/, "").replace(/\/v1$/, "");
    url.search = "";
    url.hash = "";
    return url.toString().replace(/\/$/, "");
  } catch {
    return undefined;
  }
}

/** One /props per server, off the request path: it decides polling, timings injection and visibility. */
function probeRoot(root: string): void {
  if (llamaRoots.has(root) || probing.has(root)) return;
  probing.add(root);
  fetch(`${root}/props`, { signal: AbortSignal.timeout(PROBE_TIMEOUT_MS) })
    .then(async (response) => {
      if (!response.ok) return false;
      const props = (await response.json()) as { role?: string; model_alias?: string; chat_template_caps?: unknown };
      return props.role === "router" || typeof props.model_alias === "string" || props.chat_template_caps !== undefined;
    })
    .catch(() => false)
    .then((answer) => {
      llamaRoots.set(root, answer);
      probing.delete(root);
      debug(`${root}: llama.cpp=${answer}`);
    });
}

const isLlama = (root: string): boolean => llamaRoots.get(root) ?? true;

function trackModel(ctx: ExtensionContext): void {
  model = {
    root: serverRoot(ctx.model as { baseUrl?: string } | undefined),
    id: ctx.model?.id ?? "",
    nCtx: ctx.model?.contextWindow ?? 0,
  };
  if (model.root) probeRoot(model.root);
}

async function fetchSlots(root: string, instance: string): Promise<Slot[] | undefined> {
  try {
    const response = await fetch(`${root}/slots?${new URLSearchParams({ model: instance })}`, { signal: AbortSignal.timeout(1500) });
    if (!response.ok) return undefined;
    return (await response.json()) as Slot[];
  } catch (error) {
    debug(`/slots: ${error instanceof Error ? error.message : String(error)}`);
    return undefined;
  }
}

/** Optional per-instance metrics; `"off"` means this server has no /metrics endpoint at all. */
const metricsSupport = new Map<string, boolean>();

function parseMetrics(text: string): Metrics {
  const value = (name: string): number | undefined => {
    const found = new RegExp(`^llamacpp:${name} (\\S+)$`, "m").exec(text);
    return found ? Number(found[1]) : undefined;
  };
  return {
    deferred: value("requests_deferred"),
    processing: value("requests_processing"),
    busy: value("n_busy_slots_per_decode"),
    accepted: value("spec_decode_num_accepted_tokens_total"),
    drafted: value("spec_decode_num_draft_tokens_total"),
    nmax: value("n_tokens_max"),
  };
}

/**
 * autoload=false is required: on a router /metrics is proxied per model and a plain read would load the
 * instance. The rate gauges are not read at all, since every scrape resets the buckets behind them.
 */
async function fetchMetrics(root: string, instance: string): Promise<Metrics | "off" | undefined> {
  try {
    const response = await fetch(`${root}/metrics?${new URLSearchParams({ model: instance, autoload: "false" })}`, { signal: AbortSignal.timeout(1500) });
    const text = await response.text();
    if (response.ok) return parseMetrics(text);
    return /does not support metrics/i.test(text) ? "off" : undefined;
  } catch {
    return undefined;
  }
}

async function scrapeMetrics(r: Req): Promise<void> {
  const key = keyOf(r);
  if (metricsSupport.get(key) === false) return;
  const result = await fetchMetrics(r.root, r.instance);
  if (result === "off") {
    metricsSupport.set(key, false);
    debug(`${key}: no /metrics`);
    return;
  }
  if (!result) return; // cold instance or a hiccup: ask again next time
  metricsSupport.set(key, true);
  r.metrics = result;
  tui?.requestRender();
}

/** The slot carrying our request: a processing one, else the busiest. Exact only with --parallel 1. */
function pickSlot(slots: Slot[]): Slot | undefined {
  if (slots.length === 0) return undefined;
  return slots.find((slot) => slot.is_processing) ?? slots.reduce((a, b) => ((b.n_prompt_tokens ?? 0) > (a.n_prompt_tokens ?? 0) ? b : a));
}

/** Rate over the last WINDOW_MS; a single poll delta moves by whole --batch-size steps and reads 0 or a spike. */
function windowRate(t: number, counter: (s: { t: number; processed: number; decoded: number }) => number): number {
  const current = counter(samples[samples.length - 1] ?? { t, processed: 0, decoded: 0 });
  const oldest = samples.filter((s) => t - s.t <= WINDOW_MS)[0];
  if (!oldest || oldest.t === t) return 0;
  return Math.max(0, (current - counter(oldest)) / ((t - oldest.t) / 1000));
}

const prefillRate = (t: number): number => windowRate(t, (s) => s.processed);

const decodeRate = (t: number): number => windowRate(t, (s) => s.decoded);

type PrefillSample = { ctx: number; tps: number };

/** How many recent measurements an estimate is built from; lives only for this session and model. */
const HISTORY = 10;

/** Below these measured amounts the server's own speed is noise rather than a signal. */
const TRUST_PP = 200;
const TRUST_TG = 16;

/**
 * Measured speeds per server+instance. Both are properties of the machine, so a request that cannot measure
 * one yet (nothing to prefill, nothing generated) shows the estimate from the recent ones instead of a blank.
 * Prefill declines slowly as the context grows, so its estimate is fitted against context.
 */
const prefillHist = new Map<string, PrefillSample[]>();
const decodeHist = new Map<string, number[]>();

const keyOf = (r: { root: string; instance: string }): string => `${r.root}|${r.instance}`;

function push<T>(map: Map<string, T[]>, key: string, value: T): void {
  const list = map.get(key) ?? [];
  list.push(value);
  if (list.length > HISTORY) list.shift();
  map.set(key, list);
}

function resetAll(): void {
  Object.assign(sess, { reqs: 0, prompt: 0, evalToks: 0, reuse: 0, out: 0 });
  req = undefined;
  last = undefined;
  samples = [];
  prefillHist.clear();
  decodeHist.clear();
}

const trimmedMean = (values: number[], trim = 0.1): number => {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const drop = Math.floor(sorted.length * trim);
  const core = drop * 2 >= sorted.length ? sorted : sorted.slice(drop, sorted.length - drop);
  return core.reduce((a, b) => a + b, 0) / core.length;
};

const mean = (values: number[]): number => (values.length === 0 ? 0 : values.reduce((a, b) => a + b, 0) / values.length);

const estimateDecode = (key: string): number | undefined => {
  const recent = decodeHist.get(key) ?? [];
  return recent.length === 0 ? undefined : trimmedMean(recent) || undefined;
};

/** Trimmed mean, adjusted to the given context by a least-squares fit of speed against context. */
function estimatePrefill(key: string, ctx: number): number | undefined {
  const recent = prefillHist.get(key) ?? [];
  if (recent.length === 0) return undefined;
  const avg = trimmedMean(recent.map((s) => s.tps));
  if (avg <= 0 || recent.length < 5) return avg || undefined;
  const xs = recent.map((s) => s.ctx / 1000);
  const ys = recent.map((s) => s.tps);
  const mx = mean(xs);
  const my = mean(ys);
  const sxx = xs.reduce((a, x) => a + (x - mx) ** 2, 0);
  if (sxx < 1000) return avg; // no context spread to fit against
  const slope = xs.reduce((a, x, i) => a + (x - mx) * (ys[i]! - my), 0) / sxx;
  const fitted = my + slope * (ctx / 1000 - mx);
  // A dozen samples never justify a big swing, so keep the fit inside a band around the mean.
  return Math.min(avg * 1.25, Math.max(avg * 0.75, fitted));
}

function record(r: Req, n: Nums): void {
  const key = keyOf(r);
  if (!n.ppEstimated && n.pp) push(prefillHist, key, { ctx: ctxUsed(n), tps: n.pp });
  if (!n.tgEstimated && n.tg) push(decodeHist, key, n.tg);
}

/** The numbers of one request: llama.cpp's own once they arrived, the live counters until then. */
function numbers(r: Req, t = Date.now()): Nums {
  const timing = r.timings;
  const ctx = (timing?.cache_n ?? r.cached) + (timing?.prompt_n ?? r.processed) + (timing?.predicted_n ?? r.decoded);
  // A server number measured over a handful of tokens is worse than no number: below the trust threshold the
  // cell falls back to the live rate or to the recent estimate, and carries the ~ marker.
  const ppExact = (timing?.prompt_n ?? 0) >= TRUST_PP ? timing?.prompt_per_second : undefined;
  const tgExact = (timing?.predicted_n ?? 0) >= TRUST_TG ? timing?.predicted_per_second : undefined;
  const key = keyOf(r);
  const n: Nums = {
    pp: ppExact ?? ((r.processed >= 200 ? prefillRate(t) : undefined) ?? estimatePrefill(key, ctx) ?? timing?.prompt_per_second),
    ppEstimated: ppExact === undefined,
    tg: tgExact ?? (decodeRate(t) || estimateDecode(key) || timing?.predicted_per_second || undefined),
    tgEstimated: tgExact === undefined,
    spec: timing?.draft_n ? [timing.draft_n_accepted ?? 0, timing.draft_n] : undefined,
    ttft: r.firstToken,
    prompt: timing ? (timing.prompt_n ?? 0) + (timing.cache_n ?? 0) : Math.max(r.seenPrompt, r.estPrompt),
    estimated: timing === undefined,
    evalToks: timing?.prompt_n ?? r.processed,
    reuse: timing?.cache_n ?? r.cached,
    out: timing?.predicted_n ?? r.decoded,
    nCtx: r.nCtx,
  };
  return n;
}

function finalize(r: Req): void {
  if (r.counted) return;
  r.counted = true;
  const n = numbers(r);
  record(r, n);
  sess.reqs += 1;
  sess.prompt += n.prompt ?? 0;
  sess.evalToks += n.evalToks ?? 0;
  sess.reuse += n.reuse ?? 0;
  sess.out += n.out ?? 0;
  last = r;
  debug(`#${sess.reqs} prompt=${n.prompt} eval=${n.evalToks} reuse=${n.reuse} out=${n.out} pp=${Math.round(n.pp ?? 0)} tg=${Math.round(n.tg ?? 0)} ttft=${n.ttft}`);
}

async function poll(ctx: ExtensionContext): Promise<void> {
  const r = req;
  if (!r) return;
  const slots = await fetchSlots(r.root, r.instance);
  const slot = slots ? pickSlot(slots) : undefined;
  if (!slot) {
    if (++misses < 3) return;
    stopPolling();
    if (!warned) {
      warned = true;
      ctx.ui.notify(`llama-dx: ${r.root} has no /slots, showing stream timings only`, "warning");
    }
    return;
  }
  misses = 0;
  const t = Date.now();
  const processed = slot.n_prompt_tokens_processed ?? 0;
  const decoded = slot.next_token?.[0]?.n_decoded ?? 0;

  r.processed = Math.max(r.processed, processed);
  r.decoded = Math.max(r.decoded, decoded);
  r.seenPrompt = Math.max(r.seenPrompt, slot.n_prompt_tokens ?? 0);
  r.cached = Math.max(r.cached, slot.n_prompt_tokens_cache ?? 0);
  r.nCtx = slot.n_ctx ?? r.nCtx;
  r.slots = slots?.length ?? 0;
  r.slotId = slot.id;
  r.processing = slot.is_processing === true;
  samples = [...samples.filter((s) => t - s.t <= WINDOW_MS), { t, processed, decoded }];
  if (metricsSupport.get(keyOf(r)) !== false && t - (r.metricsAt ?? 0) >= METRICS_EVERY_MS) {
    r.metricsAt = t;
    void scrapeMetrics(r);
  }

  // The llama.cpp task ends before pi's agent loop does (tools follow), and is_processing drops between
  // prefill chunks, so only a lasting idle with work done means the request is over.
  idlePolls = r.processing ? 0 : idlePolls + 1;
  if (idlePolls >= 2 && (processed > 0 || decoded > 0)) {
    r.ended = t;
    finalize(r);
  }
  debug(`total=${slot.n_prompt_tokens ?? 0} processed=${processed} cache=${slot.n_prompt_tokens_cache ?? 0} decoded=${decoded} pp=${Math.round(prefillRate(t))} tg=${Math.round(decodeRate(t))}`);
  tui?.requestRender();
}

function stopPolling(): void {
  if (pollTimer) clearInterval(pollTimer);
  pollTimer = undefined;
  samples = [];
  idlePolls = 0;
}

const bar = (fraction: number): string => {
  const filled = Math.max(0, Math.min(BAR, Math.round(fraction * BAR)));
  return "▰".repeat(filled) + "▱".repeat(BAR - filled);
};

const phaseOf = (): "idle" | "queued" | "prefill" | "decode" | "done" => {
  const r = req;
  if (!r) return last ? "done" : "idle";
  if (r.ended !== undefined) return "done";
  if (r.decoded > 0 || (r.timings?.predicted_n ?? 0) > 0) return "decode";
  return r.processing || idlePolls < 2 ? "prefill" : "queued";
};

/** Seconds left of prompt processing; "cached" when there is essentially nothing to evaluate. */
function etaOf(r: Req, n: Nums): string {
  const reuse = n.reuse ?? 0;
  if ((n.prompt ?? 0) - reuse < 200) return "cached";
  if (r.ended !== undefined) return "done";
  const rate = prefillRate(Date.now());
  const left = Math.max(0, (n.prompt ?? 0) - (r.processed + reuse));
  if (rate < 1) return "…";
  return `~${Math.max(1, Math.round(left / rate))}s`;
}

type Cell = [text: string, tone: ThemeColor];

const ctxUsed = (n: Nums): number => (n.evalToks ?? 0) + (n.reuse ?? 0) + (n.out ?? 0);

const doneOf = (r: Req | undefined, n: Nums): number => Math.min(n.prompt ?? 0, (r?.processed ?? 0) + (n.reuse ?? 0));

const progressOf = (r: Req | undefined, n: Nums): number => {
  const total = n.prompt ?? 0;
  if (total <= 0) return 0;
  if (r?.ended !== undefined) return 1;
  return Math.min(0.99, doneOf(r, n) / total);
};

/** Join cells in fixed columns, dropping only what no longer fits. */
function clip(cells: Cell[], width: number, theme: Theme): string {
  const line = (items: Cell[]): string => items.map((c) => theme.fg(c[1], c[0])).join(GAP);
  if (cells.map((c) => c[0]).join(GAP).length <= width) return line(cells);
  const kept: Cell[] = [];
  let room = width;
  for (const cell of cells) {
    if (cell[0].length > room) break;
    kept.push(cell);
    room -= cell[0].length + GAP.length;
  }
  return line(kept);
}

export default function llamaDx(pi: ExtensionAPI) {
  const mount = (ctx: ExtensionContext) =>
    ctx.ui.setWidget(WIDGET_KEY, (_tui: TUI, theme: Theme) => ((tui = _tui), new DxBar(theme)), { placement: "belowEditor" });

  pi.on("session_start", (_event, ctx) => {
    resetAll();
    trackModel(ctx);
    if (ctx.mode === "tui") mount(ctx);
  });

  // A new model is a different machine: nothing measured on the old one may leak into these cells.
  pi.on("model_select", (_event, ctx) => {
    resetAll();
    trackModel(ctx);
  });

  pi.on("before_provider_request", async (event, ctx) => {
    const payload = event.payload as Record<string, unknown>;
    const root = serverRoot(ctx.model as { baseUrl?: string } | undefined);
    if (!root) return undefined;
    // A tool call that finished faster than the idle detection still belongs to the session totals.
    if (req && !req.counted) {
      req.ended ??= Date.now();
      finalize(req);
    }
    req = {
      root,
      instance: String(payload.model ?? ctx.model?.id ?? "?"),
      chars: JSON.stringify(payload.messages ?? "").length + (Array.isArray(payload.tools) ? JSON.stringify(payload.tools).length : 0),
      estPrompt: Math.round(JSON.stringify(payload.messages ?? "").length / charsPerToken),
      seenPrompt: 0,
      processed: 0,
      cached: 0,
      decoded: 0,
      nCtx: ctx.model?.contextWindow ?? 0,
      slots: 0,
      processing: false,
      started: Date.now(),
      counted: false,
    };
    misses = 0;
    stopPolling();
    if (ctx.mode === "tui") mount(ctx);
    if (!isLlama(root)) return undefined;
    void scrapeMetrics(req); // learns whether this server has --metrics at all
    pollTimer = setInterval(() => void poll(ctx), POLL_MS);
    // llama.cpp only repeats its timings in every chunk when asked for it.
    return { ...payload, timings_per_token: true };
  });

  pi.on("provider_stream_event", async (event) => {
    const data = event.data as
      | { timings?: Timings; usage?: { prompt_tokens?: number }; choices?: { delta?: { content?: string | null; reasoning_content?: string | null } }[] }
      | undefined;
    if (!data || typeof data !== "object" || !req) return;
    const delta = data.choices?.[0]?.delta;
    if (req.firstToken === undefined && (delta?.content || delta?.reasoning_content)) req.firstToken = Date.now() - req.started;
    if (data.timings) req.timings = data.timings;
    if (data.usage?.prompt_tokens) {
      req.estPrompt = data.usage.prompt_tokens;
      // Nearly the same body goes out next turn, so this ratio is a good estimate then.
      charsPerToken = req.chars / data.usage.prompt_tokens;
    }
    tui?.requestRender();
  });

  pi.on("agent_end", async () => {
    stopPolling();
    if (req) {
      req.ended ??= Date.now();
      finalize(req);
    }
    tui?.requestRender();
  });

  pi.on("session_shutdown", (_event, ctx) => {
    stopPolling();
    req = undefined;
    ctx.ui.setWidget(WIDGET_KEY, undefined);
  });

  pi.registerCommand("llama-dx", {
    description: "Toggle llama.cpp diagnostics below the editor (/llama-dx detail|freeze|reset)",
    handler: async (args, ctx) => {
      const what = args.trim();
      if (what === "detail") detailed = !detailed;
      else if (what === "reset") resetAll();
      else freeze = !freeze;
      mount(ctx);
      ctx.ui.notify(`llama-dx: freeze=${freeze ? "on" : "off"}, detail=${detailed ? "on" : "off"}`, "info");
      tui?.requestRender();
    },
  });

  class DxBar implements Component {
    constructor(private theme: Theme) {}

    render(width: number): string[] {
      const root = req?.root ?? last?.root ?? model.root;
      if (!root || llamaRoots.get(root) === false) return [];
      if (!req && !freeze) return [];
      const r = req ?? last;
      const phase = phaseOf();
      const running = req !== undefined && req.ended === undefined;
      const n: Nums = r ? numbers(r) : { estimated: false, ppEstimated: true, tgEstimated: true, nCtx: model.nCtx };
      const tone = (live: boolean): ThemeColor => (live ? "accent" : "dim");

      const rows: Cell[][] = [
        [
          [(r?.instance ?? model.id).slice(0, 14).padEnd(14), "muted"],
          [`pp ${n.ppEstimated ? "~" : " "}${num(n.pp, 5)} t/s`, tone(running && phase === "prefill" && !n.ppEstimated)],
          [`tg ${n.tgEstimated ? "~" : " "}${num(n.tg, 5)} t/s`, tone(running && phase === "decode" && !n.tgEstimated)],
          [`spec ${word(n.spec ? `${Math.round(((n.spec[0] / n.spec[1]) * 100) | 0)}%` : undefined, 4)} ${n.spec ? `${n.spec[0]}/${n.spec[1]}`.padStart(9) : "—".padStart(9)}`, "muted"],
          [`ttft ${word(n.ttft === undefined ? undefined : fmtMs(n.ttft), 6)}`, "muted"],
        ],
        [
          [`prompt${n.estimated ? " ~" : "  "}${num(n.prompt, 6)}`, "text"],
          [`eval ${num(n.evalToks, 6)}`, "muted"],
          [`reuse ${num(n.reuse, 6)}`, "muted"],
          [`out ${num(n.out, 6)}`, tone(running && phase === "decode")],
          [`ctx ${num(ctxUsed(n), 6)}/${num(n.nCtx, 6)} ${word(n.nCtx ? `${Math.round(((ctxUsed(n) / n.nCtx) * 100) | 0)}%` : undefined, 4)}`, "muted"],
        ],
        [
          [bar(progressOf(r, n)), phase === "prefill" ? "warning" : "dim"],
          [`${num(doneOf(r, n), 6)}${n.estimated ? "/~" : "/ "}${num(n.prompt, 6)}`, "muted"],
          [word(r ? etaOf(r, n) : "—", 7), "muted"],
          [`session ${word(String(sess.reqs), 3)} req ${num(sess.prompt, 6)} in ${num(sess.out, 6)} out ${num(sess.reuse, 6)} reused`, "dim"],
        ],
      ];

      // Server-wide state, shown only for a server that answers /metrics; nothing else on it is per request.
      if (r && metricsSupport.get(keyOf(r)) === true) {
        const m = r.metrics;
        const accept = m?.accepted !== undefined && m.drafted ? `${Math.round((m.accepted / m.drafted) * 100)}%`.padStart(4) : "   —";
        rows.push([
          [`queue ${num(m?.deferred, 3)}`, m?.deferred ? "warning" : "muted"],
          [`in flight ${num(m?.processing, 2)}/${Math.max(r.slots, 1)}`, "muted"],
          [`busy/dec ${word(m?.busy === undefined ? undefined : m.busy.toFixed(2), 4)}`, "muted"],
          [`spec life ${accept} ${num(m?.accepted, 5)}/${num(m?.drafted, 5)}`, "muted"],
        ]);
      }

      if (detailed && r) {
        rows.push([
          [`host ${root.replace(/^https?:\/\//, "")}`, "muted"],
          [`slot ${r?.slotId ?? "—"}/${Math.max(r.slots, 1)}`, "muted"],
          [`n_tokens_max ${num(r.metrics?.nmax, 6)}`, "muted"],
          [`${charsPerToken.toFixed(2)} ch/tok`, "muted"],
          [r.timings ? "timings: exact" : "timings: estimated", "muted"],
        ]);
      }

      return rows.map((cells) => clip(cells, width, this.theme));
    }

    invalidate(): void {}
  }
}
