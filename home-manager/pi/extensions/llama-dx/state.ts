// What llama.cpp is doing with the request pi is making: the polled slot, the scraped metrics and the stream's
// timings turned into the numbers the footer shows, plus the speeds measured for this server and model so far.

import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { TUI } from "@earendil-works/pi-tui";
import { debug } from "./debug.ts";
import type { Facts } from "./layout.ts";
import { fetchSlots, isLlama, keyOf, metricsShown, metricsSupport, pickSlot, probeRoot, scrapeMetrics, serverRoot, shortHost, type Metrics, type Timings } from "./server.ts";

/** `/slots` is dear: it posts a task to the server queue and answers with the whole prompt and answer detokenized
 * (~1.8 MB at a 57k context, measured). The stream carries what happens to *this* request, so it only needs to
 * say whether the slot is busy and how big it is. */
const POLL_MS = 1000;
const METRICS_EVERY_MS = 2000;
const WINDOW_MS = 3000;
/** Shorter than this the window covers a single batch step, which is a spike rather than a speed. */
const MIN_SPAN_MS = 1200;
/** Share of a fresh rate the cell takes each poll: prefill advances in whole batches, so the raw window rate jumps by hundreds. */
const BLEND = 0.4;
/** Repaint at most this often: `timings_per_token` means one stream event per generated token. */
const RENDER_MIN_MS = 200;
/** How many recent measurements an estimate is built from; lives only for this session and model. */
const HISTORY = 10;
/** Below these measured amounts the server's own speed is noise rather than a signal. */
const TRUST_PP = 200;
const TRUST_TG = 16;

type Req = {
  root: string;
  instance: string;
  chars: number;
  estPrompt: number;
  processed: number;
  cached: number;
  decoded: number;
  nCtx: number;
  slots: number;
  slotId?: number;
  processing: boolean;
  /** Whether the watched slot has been seen busy: a task that has not started cannot have ended. */
  busy: boolean;
  /** llama.cpp's own prefill progress: the whole prompt, its cached prefix, and how much of it is evaluated. */
  progress?: { total: number; cache: number; done: number };
  /** The slot's counters as they were last poll; a smaller one means the slot moved to another task. */
  raw?: { processed: number; decoded: number };
  started: number;
  /** What pi called the context when this request went out: the bar's used zone, without what is landing now. */
  base: number | null;
  shownPp?: number;
  shownTg?: number;
  firstToken?: number;
  ended?: number;
  timings?: Timings;
  metrics?: Metrics;
  metricsAt?: number;
  counted: boolean;
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

/** The few things the other modules share: the current context, the mounted TUI, and the model pi is on. */
export const runtime = {
  ctx: undefined as ExtensionContext | undefined,
  tui: undefined as TUI | undefined,
  /** Root and context window of the model pi is on, so the footer has something to show before the first request. */
  model: { root: undefined as string | undefined, nCtx: 0 },
  /** Columns the footer last filled, so printed text breaks where the footer does. */
  width: 0,
};

let req: Req | undefined;
let last: Req | undefined;
/** Requests llama.cpp has served in this session; pi's own usage entries carry the token totals. */
export const sess = { reqs: 0 };
let samples: { t: number; processed: number; decoded: number }[] = [];
let charsPerToken = 3.6;
let idlePolls = 0;
let pollTimer: ReturnType<typeof setInterval> | undefined;
/** The numbers of the request that ended last, frozen: a new request holds them until it measures its own. */
let settled: Nums | undefined;
/** What to do when a server's identity settles, which may hand the footer back to pi. */
let serverAnswer: () => void = () => paint(false);

export const onServerAnswer = (handler: () => void): void => {
  serverAnswer = handler;
};

/**
 * The bound context, or nothing. pi invalidates a context as soon as its session is replaced, reloaded or
 * disposed — a background subagent session does all three — and reading anything from an invalid one throws.
 * The footer renders on a timer, so it has to ask this way rather than touch `runtime.ctx` directly.
 */
export function ctxSafe(): ExtensionContext | undefined {
  const ctx = runtime.ctx;
  if (!ctx) return undefined;
  try {
    void ctx.cwd;
  } catch {
    runtime.ctx = undefined;
    return undefined;
  }
  return ctx;
}

/**
 * Whether this is the pi in the terminal. Extensions load into every session pi makes, including the in-memory
 * ones another extension runs a subagent in, and those share this module — so they are passed over entirely.
 */
export const isInteractive = (ctx: ExtensionContext): boolean => ctx.mode === "tui";

export function trackModel(ctx: ExtensionContext): void {
  if (!isInteractive(ctx)) return;
  runtime.ctx = ctx;
  runtime.model = {
    root: serverRoot(ctx.model as { baseUrl?: string } | undefined),
    nCtx: ctx.model?.contextWindow ?? 0,
  };
  if (runtime.model.root) probeRoot(runtime.model.root, () => serverAnswer());
}

export function resetAll(): void {
  sess.reqs = 0;
  req = undefined;
  last = undefined;
  settled = undefined;
  samples = [];
  metricsShown.clear();
  prefillHist.clear();
  decodeHist.clear();
}

/**
 * Rate over the last WINDOW_MS, between the samples at its ends: divided by the time since the window started it
 * would decay towards 0 for as long as the counter stands still, which it does between batch steps.
 */
function windowRate(t: number, counter: (s: { t: number; processed: number; decoded: number }) => number, minStep: number): number {
  const window = samples.filter((s) => t - s.t <= WINDOW_MS);
  const oldest = window[0];
  const newest = window[window.length - 1];
  const step = oldest && newest ? counter(newest) - counter(oldest) : 0;
  if (!oldest || !newest || newest.t - oldest.t < MIN_SPAN_MS || step < minStep) return 0;
  return step / ((newest.t - oldest.t) / 1000);
}

/** A window over too little of the phase is a rate of nothing: prefill advances in batches, generation token by token. */
const prefillRate = (t: number): number => windowRate(t, (s) => s.processed, 64);

const decodeRate = (t: number): number => windowRate(t, (s) => s.decoded, 8);

/**
 * The rate for this poll: the fresh one taken towards the one already shown, and the shown one held when nothing
 * new arrived. Speeds are properties of the machine, so holding one across a stall of a second says no lie.
 */
const blend = (fresh: number, shown: number | undefined): number | undefined =>
  fresh <= 0
    ? shown !== undefined && shown > 0
      ? shown
      : undefined
    : shown !== undefined && shown > 0
      ? shown + (fresh - shown) * BLEND
      : fresh;

type PrefillSample = { ctx: number; tps: number };

/**
 * Measured speeds per server+instance. Both are properties of the machine, so a request that cannot measure
 * one yet (nothing to prefill, nothing generated) shows the estimate from the recent ones instead of a blank.
 * Prefill declines slowly as the context grows, so its estimate is fitted against context.
 */
const prefillHist = new Map<string, PrefillSample[]>();
const decodeHist = new Map<string, number[]>();

function push<T>(map: Map<string, T[]>, key: string, value: T): void {
  const list = map.get(key) ?? [];
  list.push(value);
  if (list.length > HISTORY) list.shift();
  map.set(key, list);
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
  // Only a finished task's timings describe its whole prompt: `timings_per_token` repeats them after every token with
  // `prompt_n` counting what has been evaluated *so far*. llama.cpp's progress chunks carry the real total for the
  // same reason, and they arrive before prefill has done anything with the prompt.
  const exact = timing !== undefined && r.ended !== undefined;
  const total = r.progress?.total ?? (exact ? (timing.prompt_n ?? 0) + (timing.cache_n ?? 0) : 0);
  const ctx = total + (timing?.predicted_n ?? r.decoded);
  // A server number measured over a handful of tokens is worse than no number: below the trust threshold the cell
  // keeps its own smoothed live rate, or the recent estimate, and carries the ~ marker.
  const ppExact = (timing?.prompt_n ?? 0) >= TRUST_PP ? timing?.prompt_per_second : undefined;
  const tgExact = (timing?.predicted_n ?? 0) >= TRUST_TG ? timing?.predicted_per_second : undefined;
  const key = keyOf(r);
  const n: Nums = {
    pp: ppExact ?? blend(r.processed >= TRUST_PP ? prefillRate(t) : 0, r.shownPp) ?? estimatePrefill(key, ctx),
    ppEstimated: ppExact === undefined,
    tg: tgExact ?? blend(decodeRate(t), r.shownTg) ?? estimateDecode(key),
    tgEstimated: tgExact === undefined,
    spec: timing?.draft_n ? [timing.draft_n_accepted ?? 0, timing.draft_n] : undefined,
    ttft: r.firstToken,
    prompt: total > 0 ? total : r.estPrompt,
    estimated: total === 0,
    evalToks: Math.max(timing?.prompt_n ?? 0, r.progress?.done ?? 0, r.processed),
    reuse: r.progress?.cache ?? (exact ? (timing.cache_n ?? 0) : r.cached),
    out: timing?.predicted_n ?? r.decoded,
    nCtx: r.nCtx,
  };
  r.shownPp = n.pp;
  r.shownTg = n.tg;
  return n;
}

/**
 * The holes of the running request filled with the previous one's numbers; the KV context survives between them.
 * Once the request knows its own prompt it needs none of them: the tokens they count are not this request's.
 */
function hold(n: Nums): void {
  const p = settled;
  if (!p) return;
  if (!n.nCtx) n.nCtx = p.nCtx;
  if (!n.estimated) return;
  if (!n.evalToks) n.evalToks = p.evalToks;
  if (!n.reuse) n.reuse = p.reuse;
  if (!n.out) n.out = p.out;
}

function finalize(r: Req): void {
  if (r.counted) return;
  r.counted = true;
  const n = numbers(r);
  settled = n;
  record(r, n);
  sess.reqs += 1;
  last = r;
  debug(`#${sess.reqs} prompt=${n.prompt} eval=${n.evalToks} reuse=${n.reuse} out=${n.out} pp=${Math.round(n.pp ?? 0)} tg=${Math.round(n.tg ?? 0)} ttft=${n.ttft}`);
}

async function refreshMetrics(r: Req): Promise<void> {
  const m = await scrapeMetrics(r.root, r.instance);
  if (!m) return;
  r.metrics = m;
  paint();
}

/**
 * One /slots at a time. It posts a task to the server queue and answers with the whole prompt detokenized, so a
 * llama.cpp that is up to its neck in prefill answers it slowly, and queueing them up only makes every one of them
 * time out — which stops the panel moving entirely.
 */
let polling = false;

async function poll(): Promise<void> {
  if (polling) return;
  polling = true;
  try {
    await pollOnce();
  } finally {
    polling = false;
  }
}

async function pollOnce(): Promise<void> {
  const r = req;
  if (!r) return;
  const slots = (await fetchSlots(r.root, r.instance)) ?? [];
  const slot = pickSlot(slots); // nothing to read while the instance is loading or without --slots
  if (!slot) return;
  const t = Date.now();
  const processed = slot.n_prompt_tokens_processed ?? 0;
  const decoded = slot.next_token?.[0]?.n_decoded ?? 0;

  // What the slot counts belongs to this request only while it is busy with it: until it takes the task it answers
  // with the previous one (`task_prev`), and a task that ends clears its stats. Once it is busy, a counter that went
  // down since last poll means the slot moved to another task, so this one starts over instead of holding it.
  r.nCtx = slot.n_ctx ?? r.nCtx;
  r.slots = slots.length;
  r.slotId = slot.id;
  r.processing = slot.is_processing === true;
  if (r.processing) {
    if (r.raw && (processed < r.raw.processed || decoded < r.raw.decoded)) {
      r.processed = 0;
      r.decoded = 0;
      r.cached = 0;
      samples = [];
    }
    r.raw = { processed, decoded };
    r.processed = Math.max(r.processed, processed);
    r.decoded = Math.max(r.decoded, decoded);
    r.cached = Math.max(r.cached, slot.n_prompt_tokens_cache ?? 0);
    samples = [...samples.filter((s) => t - s.t <= WINDOW_MS), { t, processed, decoded }];
  }
  r.busy ||= r.processing;
  if (metricsSupport.get(keyOf(r)) !== false && t - (r.metricsAt ?? 0) >= METRICS_EVERY_MS) {
    r.metricsAt = t;
    void refreshMetrics(r);
  }

  // The llama.cpp task ends before pi's agent loop does (tools follow), and is_processing drops between
  // prefill chunks, so only a lasting idle with work done means the request is over. A slot that has never been
  // seen busy is a queue or a loading model, not a finished request.
  idlePolls = r.processing ? 0 : idlePolls + 1;
  if (idlePolls >= 2 && r.busy && (r.processed > 0 || r.decoded > 0)) {
    r.ended = t;
    finalize(r);
  }
  debug(`total=${slot.n_prompt_tokens ?? 0} processed=${processed} cache=${slot.n_prompt_tokens_cache ?? 0} decoded=${decoded} pp=${Math.round(prefillRate(t))} tg=${Math.round(decodeRate(t))}`);
  paint();
}

let painted = 0;

/** Stream events come once per generated token, and /slots polls four times a second: a panel only needs a few. */
export function paint(throttled = true): void {
  const now = Date.now();
  if (throttled && now - painted < RENDER_MIN_MS) return;
  painted = now;
  runtime.tui?.requestRender();
}

export function stopPolling(): void {
  if (pollTimer) clearInterval(pollTimer);
  pollTimer = undefined;
  samples = [];
  idlePolls = 0;
}

const ctxUsed = (n: Nums): number => (n.evalToks ?? 0) + (n.reuse ?? 0) + (n.out ?? 0);

const phaseOf = (): "idle" | "prefill" | "decode" | "done" => {
  const r = req;
  if (!r) return last ? "done" : "idle";
  if (r.ended !== undefined) return "done";
  return r.decoded > 0 || (r.timings?.predicted_n ?? 0) > 0 ? "decode" : "prefill";
};

type Totals = { input: number; output: number; cacheRead: number; context: { tokens: number | null; contextWindow: number } | undefined };

let totalsCache: { key: string; value: Totals } | undefined;

/**
 * What pi recorded for this session, plus its own estimate of the context. Both walk the whole session, so they
 * are taken once per leaf: entries are append-only, and every append moves the leaf.
 */
function sessionState(): Totals {
  const ctx = ctxSafe();
  const key = `${ctx?.sessionManager.getSessionId()}/${ctx?.sessionManager.getLeafId()}/${ctx?.model?.id}`;
  if (totalsCache?.key === key) return totalsCache.value;
  const totals = { input: 0, output: 0, cacheRead: 0 };
  const add = (u: { input: number; output: number; cacheRead: number } | undefined): void => {
    if (!u) return;
    totals.input += u.input;
    totals.output += u.output;
    totals.cacheRead += u.cacheRead;
  };
  for (const entry of ctx?.sessionManager.getEntries() ?? []) {
    if (entry.type === "usage") add(entry.usage);
    else if (entry.type === "message" && (entry.message.role === "assistant" || entry.message.role === "toolResult")) add(entry.message.usage);
    else if (entry.type === "compaction" || entry.type === "branch_summary") add(entry.usage);
  }
  const usage = ctx?.getContextUsage();
  const value: Totals = { ...totals, context: usage ? { tokens: usage.tokens, contextWindow: usage.contextWindow } : undefined };
  totalsCache = { key, value };
  return value;
}

/** What a number is: the running request's own numbers, with the previous request's holding the holes. */
export function view(): { facts: Facts; used: number | null; evaluating: number; pending: number; generating: number; total: number } | undefined {
  const root = req?.root ?? last?.root ?? runtime.model.root;
  if (!isLlama(root)) return undefined;
  const r = req ?? last;
  const phase = phaseOf();
  const n: Nums = r ? numbers(r) : { estimated: false, ppEstimated: true, tgEstimated: true, nCtx: runtime.model.nCtx };
  if (req?.ended === undefined) hold(n);
  const session = sessionState();
  const m = r ? (r.metrics ?? metricsShown.get(keyOf(r))) : undefined;
  const hasMetrics = r ? metricsSupport.get(keyOf(r)) === true : false;

  // The held layer is pi's own context number: the one at the moment this request went out, since everything
  // arriving now belongs to the live layers. Once the request has ended what it added is committed context, and
  // joining it back in is what keeps the bar from shrinking by those very tokens until the next request starts.
  const committed = req !== undefined && req.ended !== undefined ? (n.evalToks ?? 0) + (n.out ?? 0) : 0;
  const base = req ? (req.base === null ? null : req.base + committed) : (session.context?.tokens ?? last?.base ?? null);
  const facts: Facts = {
    live: phase,
    pp: n.pp,
    ppEstimated: n.ppEstimated,
    tg: n.tg,
    tgEstimated: n.tgEstimated,
    prompt: n.prompt,
    promptEstimated: n.estimated,
    eval: n.evalToks,
    pfDone: n.evalToks,
    pfTarget: prefillTarget(n),
    reuse: n.reuse,
    out: n.out,
    reqs: sess.reqs,
    sessionIn: session.input,
    sessionOut: session.output,
    cacheRead: session.cacheRead,
    specAccepted: n.spec?.[0],
    specDrafted: n.spec?.[1],
    ttft: n.ttft,
    host: shortHost(root!),
    slotId: r?.slotId,
    slots: Math.max(r?.slots ?? 1, 1),
    nTokensMax: m?.nmax,
    charsPerToken,
    exactTimings: r?.timings !== undefined,
  };
  if (hasMetrics) {
    facts.queue = m?.deferred;
    facts.processing = m?.processing;
    facts.busy = m?.busy;
    facts.specLifeAccepted = m?.accepted;
    facts.specLifeDrafted = m?.drafted;
  }
  return { facts, used: base, ...active(n), total: n.nCtx || session.context?.contextWindow || runtime.model.nCtx };
}

/** The prompt tokens a request has to evaluate: its whole prompt, the cached part of it excluded. */
const prefillTarget = (n: Nums): number => Math.max(0, (n.prompt ?? 0) - (n.reuse ?? 0));

/**
 * What is landing in the KV right now and what is still to come: what prefill has evaluated, the prompt tokens it
 * has yet to evaluate, and what generation has produced. A running request's prompt size is the server's own
 * number from `/slots` (which counts the cached part too), so what is left to evaluate needs no estimating;
 * without `--slots` the stream's generated-token count stands in for generation's.
 */
function active(n: Nums): { evaluating: number; generating: number; pending: number } {
  const r = req;
  if (r === undefined || r.ended !== undefined) return { evaluating: 0, generating: 0, pending: 0 };
  const done = n.evalToks ?? 0;
  return { evaluating: done, generating: Math.max(r.decoded, r.timings?.predicted_n ?? 0), pending: Math.max(0, prefillTarget(n) - done) };
}

/**
 * The outgoing request: everything the footer can only learn from the body pi sends, plus the polling this
 * request needs. Returns the payload with `timings_per_token` asked for, since llama.cpp only repeats its
 * timings in every chunk when asked.
 */
export function startRequest(payload: Record<string, unknown>, ctx: ExtensionContext): Record<string, unknown> | undefined {
  if (!isInteractive(ctx)) return undefined;
  const root = serverRoot(ctx.model as { baseUrl?: string } | undefined);
  if (!root) return undefined;
  runtime.ctx = ctx;
  // A tool call that finished faster than the idle detection still belongs to the session totals.
  finishRequest();
  req = {
    root,
    instance: String(payload.model ?? ctx.model?.id ?? "?"),
    chars: JSON.stringify(payload.messages ?? "").length + (Array.isArray(payload.tools) ? JSON.stringify(payload.tools).length : 0),
    estPrompt: Math.round(JSON.stringify(payload.messages ?? "").length / charsPerToken),
    processed: 0,
    cached: 0,
    decoded: 0,
    nCtx: ctx.model?.contextWindow ?? 0,
    slots: 0,
    processing: false,
    busy: false,
    started: Date.now(),
    base: ctx.getContextUsage()?.tokens ?? null,
    counted: false,
  };
  // A new request opens at the speeds already measured on this server rather than at 0, and glides from there.
  const key = keyOf(req);
  req.shownPp = estimatePrefill(key, req.nCtx);
  req.shownTg = estimateDecode(key);
  stopPolling();
  if (!isLlama(root)) return undefined;
  void refreshMetrics(req); // learns whether this server has --metrics at all
  pollTimer = setInterval(() => void poll(), POLL_MS);
  // `return_progress` makes llama.cpp post its own prefill progress (`prompt_progress`) into the stream once per
  // batch, which is the only exact figure for what it has to evaluate: `/slots` answers with the size of the
  // slot's whole KV, cached prefix and generated tokens included, so it cannot say how big this prompt is.
  return { ...payload, timings_per_token: true, return_progress: true };
}

/**
 * What the stream told us: prefill progress, the first token, and the timings llama.cpp repeats every chunk — those
 * describe the whole task only once it has ended, which is when `finalize` reads them.
 */
export function observeStream(data: unknown): void {
  if (!data || typeof data !== "object" || !req) return;
  const event = data as { timings?: Timings; usage?: { prompt_tokens?: number }; prompt_progress?: { total?: number; cache?: number; processed?: number }; choices?: { delta?: { content?: string | null; reasoning_content?: string | null } }[] };
  const delta = event.choices?.[0]?.delta;
  if (req.firstToken === undefined && (delta?.content || delta?.reasoning_content)) req.firstToken = Date.now() - req.started;
  if (event.timings) req.timings = event.timings;
  const p = event.prompt_progress;
  if (p?.total) {
    req.progress = { total: p.total, cache: p.cache ?? 0, done: Math.max(0, (p.processed ?? 0) - (p.cache ?? 0)) };
    debug(`progress total=${p.total} cache=${p.cache} processed=${p.processed}`);
  }
  // llama.cpp sends its usage only when asked for, so the prompt size arrives from `usage` or from the progress
  // chunks. Nearly the same body goes out next turn, so the ratio measured here is a good estimate of it then.
  const exact = event.usage?.prompt_tokens ?? p?.total;
  if (exact) {
    req.estPrompt = exact;
    charsPerToken = req.chars / exact;
  }
  paint();
}

/** Close off the running request; a tool call that ends faster than the idle detection still counts. */
export function finishRequest(): void {
  if (!req) return;
  req.ended ??= Date.now();
  finalize(req);
}

/** Forget the running request; called on shutdown, where nothing renders any more. */
export function dropRequest(): void {
  req = undefined;
}
