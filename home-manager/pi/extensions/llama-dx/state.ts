// What llama.cpp is doing with the request pi is making: the polled slot, the scraped metrics and the stream's
// timings turned into the numbers the footer shows, with the last speeds llama.cpp reported standing in between.

import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { TUI } from "@earendil-works/pi-tui";
import { debug } from "./debug.ts";
import type { Facts } from "./layout.ts";
import { fetchSlots, isKnownLlama, isLlama, keyOf, metricsShown, metricsSupport, pickSlot, probeRoot, scrapeMetrics, serverRoot, shortHost, type Metrics, type Timings } from "./server.ts";

/** `/slots` is dear: it posts a task to the server queue and answers with the whole prompt and answer detokenized
 * (~1.8 MB at a 57k context, measured). The stream carries what happens to *this* request, so it only needs to
 * say whether the slot is busy and how big it is. */
const POLL_MS = 1000;
const METRICS_EVERY_MS = 2000;
/** Repaint at most this often: `timings_per_token` means one stream event per generated token. */
const RENDER_MIN_MS = 200;
/** Below these measured amounts the server's own speed is noise rather than a signal. */
const TRUST_PP = 200;
const TRUST_TG = 16;

type Req = {
  root: string;
  instance: string;
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
  /** The prompt size llama.cpp reported in a stream `usage`, for a server without progress chunks. */
  promptTotal?: number;
  /** The slot's counters as they were last poll; a smaller one means the slot moved to another task. */
  raw?: { processed: number; decoded: number };
  started: number;
  /** What pi called the context when this request went out: the bar's used zone, without what is landing now. */
  base: number | null;
  firstToken?: number;
  ended?: number;
  timings?: Timings;
  metrics?: Metrics;
  metricsAt?: number;
  counted: boolean;
};

type Nums = {
  pp?: number;
  tg?: number;
  spec?: [accepted: number, drafted: number];
  ttft?: number;
  prompt?: number;
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
let idlePolls = 0;
let pollTimer: ReturnType<typeof setInterval> | undefined;
/** The numbers of the request that ended last, frozen: a new request holds them until it measures its own. */
let settled: Nums | undefined;

/** A compaction pi is running. It is not one of our requests, so nothing is polled, but the bar must keep its level. */
type Compaction = { reason: "manual" | "threshold" | "overflow"; tokensBefore: number; started: number };
let compacting: Compaction | undefined;
let compactTimer: ReturnType<typeof setInterval> | undefined;
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
    root: serverRoot(ctx.model?.baseUrl ?? ""),
    nCtx: ctx.model?.contextWindow ?? 0,
  };
  if (runtime.model.root) probeRoot(runtime.model.root, () => serverAnswer());
}

export function resetAll(): void {
  sess.reqs = 0;
  req = undefined;
  last = undefined;
  settled = undefined;
  compacting = undefined;
  if (compactTimer) clearInterval(compactTimer);
  compactTimer = undefined;
  metricsShown.clear();
}

/**
 * pi is compacting the context. The summarizer runs outside the request pipeline - pi's own compaction and a
 * delegated one both call the model directly - so there are no timings to show; what is known is the reason and the
 * size of the context being rewritten, and the elapsed time is the only progress there is.
 */
export function beginCompaction(info: { reason: Compaction["reason"]; tokensBefore: number }): void {
  stopPolling();
  compacting = { ...info, started: Date.now() };
  if (compactTimer) clearInterval(compactTimer);
  compactTimer = setInterval(() => paint(false), 1000); // the elapsed time on the line has to move
  paint(false);
}

/**
 * A compaction that ended. A successful one rebuilt the context from the summary, so the request that triggered it
 * describes the context *before* the rewrite and must not lend its tokens to the bar; a failed one changed nothing.
 */
export function endCompaction(succeeded: boolean): void {
  if (compactTimer) clearInterval(compactTimer);
  compactTimer = undefined;
  compacting = undefined;
  if (succeeded) {
    req = undefined;
    last = undefined;
    settled = undefined;
    stopPolling();
  }
  paint(false);
}

/** The numbers of one request: only what llama.cpp reported, or nothing until it has. */
function numbers(r: Req): Nums {
  const timing = r.timings;
  // Only a finished task's timings describe its whole prompt: `timings_per_token` repeats them after every token with
  // `prompt_n` counting what has been evaluated *so far*. llama.cpp's progress chunks carry the real total for the
  // same reason, and they arrive before prefill has done anything with the prompt.
  const exact = timing !== undefined && r.ended !== undefined;
  const total = r.progress?.total ?? r.promptTotal ?? (exact ? (timing.prompt_n ?? 0) + (timing.cache_n ?? 0) : 0);
  // A server number measured over a handful of tokens is worse than no number at all; below the trust threshold the
  // cell keeps the last one llama.cpp reported, which `hold` puts back.
  return {
    pp: (timing?.prompt_n ?? 0) >= TRUST_PP ? timing?.prompt_per_second : undefined,
    tg: (timing?.predicted_n ?? 0) >= TRUST_TG ? timing?.predicted_per_second : undefined,
    spec: timing?.draft_n ? [timing.draft_n_accepted ?? 0, timing.draft_n] : undefined,
    ttft: r.firstToken,
    prompt: total > 0 ? total : undefined,
    evalToks: Math.max(timing?.prompt_n ?? 0, r.progress?.done ?? 0, r.processed),
    reuse: r.progress?.cache ?? (exact ? (timing.cache_n ?? 0) : r.cached),
    out: timing?.predicted_n ?? r.decoded,
    nCtx: r.nCtx,
  };
}

/**
 * The holes of the running request filled with the last values llama.cpp reported; speeds are held whatever else is
 * known. Once the request knows its own prompt its token counters are its own, and nothing is taken from the last one.
 */
function hold(n: Nums): void {
  const p = settled;
  if (!p) return;
  if (!n.nCtx) n.nCtx = p.nCtx;
  if (n.pp === undefined) n.pp = p.pp;
  if (n.tg === undefined) n.tg = p.tg;
  if (n.prompt !== undefined) return;
  if (!n.evalToks) n.evalToks = p.evalToks;
  if (!n.reuse) n.reuse = p.reuse;
  if (!n.out) n.out = p.out;
}

function finalize(r: Req): void {
  if (r.counted) return;
  r.counted = true;
  const n = numbers(r);
  settled = n;
  sess.reqs += 1;
  last = r;
  debug(`#${sess.reqs} prompt=${n.prompt} eval=${n.evalToks} reuse=${n.reuse} out=${n.out} pp=${Math.round(n.pp ?? 0)} tg=${Math.round(n.tg ?? 0)} ttft=${n.ttft}`);
}

async function refreshMetrics(r: Req): Promise<void> {
  // Nothing is asked of a server whose identity is still unknown, so a non-llama.cpp model is never scraped.
  if (!isKnownLlama(r.root)) return;
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
  // Waiting for the probe is not waiting on the server: `/props` answers in 1.5 s at worst, and the request the bar
  // describes is normally long in flight by then.
  const r = req;
  if (!r || !isKnownLlama(r.root)) return;
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
    }
    r.raw = { processed, decoded };
    r.processed = Math.max(r.processed, processed);
    r.decoded = Math.max(r.decoded, decoded);
    r.cached = Math.max(r.cached, slot.n_prompt_tokens_cache ?? 0);
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
  debug(`total=${slot.n_prompt_tokens ?? 0} processed=${processed} cache=${slot.n_prompt_tokens_cache ?? 0} decoded=${decoded}`);
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
  idlePolls = 0;
}

const phaseOf = (): "idle" | "prefill" | "decode" | "done" | "compact" => {
  if (compacting) return "compact";
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
 *
 * The walk is pi's own `getSessionStats()` arithmetic (usage entries, assistant and tool-result messages, and the
 * usage a compaction or branch summary carries); it has no equivalent on ExtensionContext, so if pi changes what
 * counts towards a session, this is what has to follow.
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
  const n: Nums = r ? numbers(r) : { nCtx: runtime.model.nCtx };
  if (req?.ended === undefined) hold(n);
  const session = sessionState();
  const m = r ? (r.metrics ?? metricsShown.get(keyOf(r))) : undefined;
  const hasMetrics = r ? metricsSupport.get(keyOf(r)) === true : false;

  // The held layer is pi's own context number: the one at the moment this request went out, since everything
  // arriving now belongs to the live layers. Once the request has ended what it added is committed context, and
  // joining it back in is what keeps the bar from shrinking by those very tokens until the next request starts.
  const committed = req !== undefined && req.ended !== undefined ? (n.evalToks ?? 0) + (n.out ?? 0) : 0;
  // While compaction runs the bar holds at the context it is rewriting, not at a request's committed tokens.
  const base = compacting ? compacting.tokensBefore : req ? (req.base === null ? null : req.base + committed) : (session.context?.tokens ?? last?.base ?? null);
  const facts: Facts = {
    live: phase,
    compacting: compacting ? { reason: compacting.reason, tokensBefore: compacting.tokensBefore, elapsed: Date.now() - compacting.started } : undefined,
    pp: n.pp,
    tg: n.tg,
    prompt: n.prompt,
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
  if (compacting || r === undefined || r.ended !== undefined) return { evaluating: 0, generating: 0, pending: 0 };
  const done = n.evalToks ?? 0;
  return { evaluating: done, generating: Math.max(r.decoded, r.timings?.predicted_n ?? 0), pending: Math.max(0, prefillTarget(n) - done) };
}

/**
 * The outgoing request: begins tracking it and asks llama.cpp for the timings and progress the footer needs.
 * Returns the payload with `timings_per_token` and `return_progress` set, since llama.cpp only reports them when asked.
 */
export function startRequest(payload: Record<string, unknown>, ctx: ExtensionContext): Record<string, unknown> | undefined {
  if (!isInteractive(ctx)) return undefined;
  const root = serverRoot(ctx.model?.baseUrl ?? "");
  // A server that `/props` has said is not llama.cpp is never tracked: another provider's request never becomes
  // one of ours.
  if (!root || !isLlama(root)) return undefined;
  runtime.ctx = ctx;
  // A tool call that finished faster than the idle detection still belongs to the session totals.
  finishRequest();
  req = {
    root,
    instance: String(payload.model ?? ctx.model?.id ?? "?"),
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
  stopPolling();
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
  // llama.cpp sends its usage only when asked for, so the prompt size can also arrive this way - the only one an old
  // server without progress chunks has.
  if (event.usage?.prompt_tokens) req.promptTotal = event.usage.prompt_tokens;
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
