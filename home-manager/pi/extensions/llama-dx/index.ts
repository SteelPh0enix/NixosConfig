// llama.cpp's diagnostics as pi's footer. Two lines: the metrics line on top, and below it the working directory,
// the model, and between them a context bar filling whatever room is left — KV held, tokens landing right now,
// room left. Groups on the metrics line drop from the right as the terminal narrows, so nothing is ever
// compressed; only the width decides what is there, never the state of the request.
//
// The layout (everything between "LAYOUT" and "STATE") imports nothing at runtime — colours are named tones and
// widths are measured here — so preview.mjs can render it under plain node.

import type { ExtensionAPI, ExtensionContext, ReadonlyFooterDataProvider, Theme, ThemeColor } from "@earendil-works/pi-coding-agent";
import type { Component, TUI } from "@earendil-works/pi-tui";

// ------------------------------------------------------------------ layout

export type Tone = "label" | "value" | "live" | "dim" | "warn" | "error" | "separator" | "ident" | "model" | "number" | "percent" | "used" | "flight" | "free" | "none";
export type Segment = { text: string; tone: Tone };
export type Cell = Segment[];
export type Group = { name: string; cells: Cell[] };

const GAP = "  ";
const SEP = "  │  ";
const GUTTER = "  ";

/** Block Elements only: ▰▱ and friends are missing from Berkeley Mono and fall back to another font mid-bar. */
const EIGHTHS = ["▏", "▎", "▍", "▌", "▋", "▊", "▉"];

const clamp = (v: number, min = 0, max = 1): number => Math.min(max, Math.max(min, v));

export const short = (n: number): string =>
  n >= 1_000_000 ? `${(n / 1_000_000).toFixed(1)}M` : n >= 10_000 ? `${Math.round(n / 1000)}k` : n >= 1000 ? `${(n / 1000).toFixed(1)}k` : String(Math.round(n));

export const full = (n: number | null | undefined): string =>
  n === undefined || n === null || !Number.isFinite(n) ? "—" : Math.round(n).toLocaleString("en-US");

/** Three significant digits in a field that never changes width: `0.02%` `1.22%` `12.3%` `100%`. */
export const percent = (used: number, total: number): string => {
  if (!(total > 0)) return "—";
  const p = (used / total) * 100;
  return p >= 100 ? "100%" : p >= 10 ? `${p.toFixed(1)}%` : `${p.toFixed(2)}%`;
};

/** pi's own compaction thresholds, shared by the percent text and the bar's used zone. */
export type Load = "normal" | "warn" | "error";
export const load = (used: number, total: number): Load => {
  const p = total > 0 ? (used / total) * 100 : 0;
  return p > 90 ? "error" : p > 70 ? "warn" : "normal";
};

const ZONE: Record<Load, { used: Tone; percent: Tone }> = {
  normal: { used: "used", percent: "percent" },
  warn: { used: "warn", percent: "warn" },
  error: { used: "error", percent: "error" },
};

export const fmtMs = (ms: number): string => (ms < 1000 ? `${Math.round(ms)}ms` : `${(ms / 1000).toFixed(1)}s`);

type Style = { estimated?: boolean; live?: boolean; tone?: Tone };

const lab = (t: string): Segment => ({ text: t, tone: "label" });

const str = (t: string, s: Style = {}): Segment => ({ text: t, tone: s.estimated ? "warn" : s.live ? "live" : (s.tone ?? "value") });

/** Right-align, but keep an unknown value short: `—`, not five spaces and a dash. */
const pad = (s: string, width: number): string => (s === "—" ? " —" : s.padStart(width));

const num = (v: number | undefined, width: number, s: Style = {}): Segment => {
  const body = v === undefined || !Number.isFinite(v) ? "—" : short(v);
  if (body === "—") return str(" —", s); // nothing to mark as estimated
  return str(s.estimated ? `~${body}`.padStart(width) : pad(body, width), s);
};

/**
 * The context bar: KV already held, the tokens landing right now, and the room left. Both edges round to 1/8 of a
 * cell, so a prompt creeping through prefill visibly creeps instead of jumping whole cells.
 */
export function contextBar(cells: number, used: number, flight: number, total: number, l: Load = "normal"): Segment[] {
  const n = Math.max(1, Math.round(cells));
  const tones = { used: ZONE[l].used, flight: "flight" as Tone, free: "free" as Tone };
  const eighth = (v: number) => EIGHTHS[clamp(Math.round(v * 8) - 1, 0, EIGHTHS.length - 1)];
  const out: Segment[] = [];
  const put = (glyph: string, tone: Tone) => {
    const last = out[out.length - 1];
    if (last && last.tone === tone) last.text += glyph;
    else out.push({ text: glyph, tone });
  };
  const end = (v: number) => (total > 0 ? clamp(v / total) : 0);
  const usedAt = end(used);
  const flightAt = end(used + Math.max(0, flight));
  for (let i = 0; i < n; i++) {
    const u = (usedAt - i / n) * n;
    const f = (flightAt - i / n) * n;
    if (u >= 1) put("█", tones.used);
    else if (u > 0) put(eighth(u), tones.used);
    else if (f >= 1) put("▓", tones.flight);
    else if (f > 0) put(eighth(f), tones.flight);
    else put("░", tones.free);
  }
  return out;
}

/** Everything the metrics line can show; absent fields render as `—`, absent groups are left out. */
export type Facts = {
  live?: "prefill" | "decode" | "idle" | "done";
  pp?: number;
  ppEstimated?: boolean;
  tg?: number;
  tgEstimated?: boolean;
  prompt?: number;
  promptEstimated?: boolean;
  eval?: number;
  reuse?: number;
  out?: number;
  reqs?: number;
  sessionIn?: number;
  sessionOut?: number;
  cacheRead?: number;
  queue?: number;
  processing?: number;
  slots?: number;
  busy?: number;
  specAccepted?: number;
  specDrafted?: number;
  specLifeAccepted?: number;
  specLifeDrafted?: number;
  ttft?: number;
  host?: string;
  slotId?: number;
  nTokensMax?: number;
  charsPerToken?: number;
  exactTimings?: boolean;
};

const rate = (accepted?: number, drafted?: number): string => (drafted ? `${Math.round(((accepted ?? 0) / drafted) * 100)}%` : "—");
const pair = (a?: number, b?: number): string => (a === undefined || b === undefined ? "—" : `${a}/${b}`);
const quiet = (s: string): Segment => str(s, { tone: "dim" });

/**
 * The metric cells, most important group first: what the machine is doing, what this request is made of, what the
 * session has cost, what else is on the server, speculation, latency, and the gory detail.
 */
export function metricGroups(f: Facts): Group[] {
  const groups: Group[] = [
    {
      name: "throughput",
      cells: [[lab("pp"), num(f.pp, 5, { estimated: f.ppEstimated, live: f.live === "prefill" }), lab(" tg"), num(f.tg, 4, { estimated: f.tgEstimated, live: f.live === "decode" }), lab(" t/s")]],
    },
    {
      name: "this request",
      cells: [
        [lab("fp"), num(f.prompt, 6, { estimated: f.promptEstimated })],
        [lab("ev"), num(f.eval, 6, { live: f.live === "prefill" })],
        [lab("re"), num(f.reuse, 6)],
        [lab("out"), num(f.out, 5, { live: f.live === "decode" })],
      ],
    },
    {
      name: "session",
      cells: [
        [lab("#"), quiet(String(f.reqs ?? 0))],
        [lab("↑"), quiet(f.sessionIn === undefined ? "—" : short(f.sessionIn))],
        [lab("↓"), quiet(f.sessionOut === undefined ? "—" : short(f.sessionOut))],
        [lab("R"), quiet(f.cacheRead === undefined ? "—" : short(f.cacheRead))],
      ],
    },
  ];
  if (f.queue !== undefined || f.processing !== undefined || f.busy !== undefined) {
    groups.push({
      name: "server",
      cells: [
        [lab("q"), { text: String(f.queue ?? "—").padStart(2), tone: f.queue ? "warn" : "dim" }],
        [lab("fl"), quiet(pad(pair(f.processing, Math.max(f.slots ?? 1, 1)), 5))],
        [lab("bd"), quiet(pad(f.busy === undefined ? "—" : f.busy.toFixed(2), 5))],
      ],
    });
  }
  if (f.specDrafted !== undefined || f.specLifeDrafted !== undefined) {
    groups.push({
      name: "speculation",
      cells: [[lab("sc"), str(pad(rate(f.specAccepted, f.specDrafted), 4)), quiet(" "), quiet(pad(pair(f.specAccepted, f.specDrafted), 9))], [lab("st"), quiet(pad(rate(f.specLifeAccepted, f.specLifeDrafted), 4))]],
    });
  }
  groups.push({ name: "latency", cells: [[lab("tt"), str(pad(f.ttft === undefined ? "—" : fmtMs(f.ttft), 7))]] });
  if (f.host !== undefined) {
    groups.push({
      name: "detail",
      cells: [
        [lab("@"), quiet(f.host ?? "—")],
        [lab("#"), quiet(pad(pair(f.slotId, f.slots), 4))],
        [lab("max"), num(f.nTokensMax, 6)],
        [quiet(`${(f.charsPerToken ?? 0).toFixed(1)}c/t`)],
        [lab(f.exactTimings ? "exact" : "fitted")],
      ],
    });
  }
  return groups.filter((g) => g.cells.length > 0);
}

const cellWidth = (cell: Cell): number => cell.reduce((w, s) => w + s.text.length, 0);
const groupWidth = (g: Group): number => g.cells.reduce((w, c) => w + cellWidth(c), GAP.length * (g.cells.length - 1));

/** Whole groups in priority order until the width runs out, so cells keep their columns and never dance. */
export function metricsLine(groups: Group[], width: number): Segment[] {
  const kept: Group[] = [];
  let taken = 0;
  for (const g of groups) {
    const cost = groupWidth(g) + (kept.length ? SEP.length : 0);
    if (taken + cost > width) break;
    taken += cost;
    kept.push(g);
  }
  const out: Segment[] = [];
  kept.forEach((g, i) => {
    if (i > 0) out.push({ text: SEP, tone: "separator" });
    g.cells.forEach((cell, j) => {
      if (j > 0) out.push({ text: GAP, tone: "none" });
      out.push(...cell);
    });
  });
  return out;
}

export type BaseLineInput = {
  width: number;
  cwd: string;
  branch?: string | null;
  model?: string;
  thinking?: string | null;
  used: number | null;
  flight?: number;
  total: number;
  minBar?: number;
};

/**
 * The bottom line: path and branch on the left, model and thinking on the right, and between them the tokens held,
 * their percent and the context bar, which takes every column the others leave. Identity gives way before the bar
 * does: the thinking level first, then the ends of both names, then the percent, then the model.
 */
export function baseLine(i: BaseLineInput): Segment[] {
  const minBar = i.minBar ?? 10;
  const leftRaw = i.branch ? `${i.cwd} (${i.branch})` : i.cwd;
  const model = i.model ?? "no-model";
  const rightFull = i.thinking ? `${model} • ${i.thinking}` : model;
  const rightShort = i.thinking ? model : rightFull;
  const usedTxt = full(i.used);
  const totalTxt = full(i.total);
  const known = typeof i.used === "number";
  const pctTxt = i.used === null || i.used === undefined ? "" : percent(i.used, i.total);
  const l = load(i.used ?? 0, i.total);

  let leftW = Math.min(cols(leftRaw), Math.max(8, Math.floor(i.width * 0.3)));
  let rightRaw = rightFull;
  let rightW = Math.min(cols(rightFull), Math.max(8, Math.floor(i.width * 0.22)));
  let showPercent = known;
  let showRight = true;

  const barCells = () => {
    const blocks = [leftW, usedTxt.length + (showPercent ? 1 + pctTxt.length : 0), totalTxt.length, showRight ? rightW : 0];
    return i.width - blocks.reduce((a, b) => a + b, 0) - GUTTER.length * blocks.filter((b) => b > 0).length;
  };

  for (let guard = 0; guard < 12 && barCells() < minBar; guard++) {
    if (showRight && rightRaw !== rightShort && rightW >= cols(rightShort)) {
      rightRaw = rightShort;
      rightW = cols(rightShort);
    } else if (leftW > 8) leftW = Math.max(8, leftW - 6);
    else if (showRight && rightW > 8) rightW = Math.max(8, rightW - 6);
    else if (showPercent) showPercent = false;
    else if (showRight) {
      showRight = false;
      rightW = 0;
    } else break;
  }

  const out: Segment[] = [];
  const emit = (s: string, tone: Tone) => {
    if (s.length > 0) out.push({ text: s, tone });
  };
  emit(cut(leftRaw, leftW), "ident");
  emit(GUTTER, "none");
  emit(usedTxt, "number");
  if (showPercent) {
    emit(" ", "none");
    emit(pctTxt, ZONE[l].percent);
  }
  emit(GUTTER, "none");
  out.push(...contextBar(Math.max(1, barCells()), i.used ?? 0, i.flight ?? 0, i.total, l));
  emit(GUTTER, "none");
  emit(totalTxt, "number");
  if (showRight) {
    emit(GUTTER, "none");
    emit(cut(rightRaw, rightW), "model");
  }
  return out;
}

/** Plain text of a composed line, for padding, tests and the preview. */
export const flatten = (segments: Segment[]): string => segments.reduce((s, x) => s + x.text, "");

/**
 * Column count and truncation of plain text. Codepoints rather than pi's `visibleWidth`, because only this file's
 * own strings reach it — the colours are applied afterwards — and the two strings that can hold wide characters
 * (a path and a model id) are the ones being cut here, where losing a column or two beats pulling in a dependency.
 */
const cols = (s: string): number => [...s].length;
const cut = (s: string, w: number): string => (cols(s) <= w ? s : `${[...s].slice(0, Math.max(0, w - 1)).join("")}…`);

// ------------------------------------------------------------------ state

const POLL_MS = 250;
/** /metrics is scraped less often than /slots: it posts a task to the server queue and answers ~2.5 kB. */
const METRICS_EVERY_MS = 1000;
const WINDOW_MS = 3000;
/** Shorter than this the window covers a single batch step, which is a spike rather than a speed. */
const MIN_SPAN_MS = 1200;
/** Share of a fresh rate the cell takes each poll: prefill advances in whole batches, so the raw window rate jumps by hundreds. */
const BLEND = 0.4;
/** Repaint at most this often: `timings_per_token` means one stream event per generated token. */
const RENDER_MIN_MS = 200;
const PROBE_TIMEOUT_MS = 1500;
/** How many recent measurements an estimate is built from; lives only for this session and model. */
const HISTORY = 10;
/** Below these measured amounts the server's own speed is noise rather than a signal. */
const TRUST_PP = 200;
const TRUST_TG = 16;

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

let req: Req | undefined;
let last: Req | undefined;
/** Requests llama.cpp has served in this session; pi's own usage entries carry the token totals. */
const sess = { reqs: 0 };
let samples: { t: number; processed: number; decoded: number }[] = [];
let charsPerToken = 3.6;
let idlePolls = 0;
let pollTimer: ReturnType<typeof setInterval> | undefined;
let tui: TUI | undefined;
/** The freshest context: the footer reads the session, the model and the context usage through it. */
let ctxRef: ExtensionContext | undefined;
/** The model pi is on, so the footer has something to show before the first request. */
let model = { root: undefined as string | undefined, nCtx: 0 };
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

/** Which machine this is, short enough for a detail cell: `pc:51536`, `local:33333`. */
const shortHost = (root: string): string => {
  try {
    const url = new URL(root);
    const loopback = ["localhost", "127.0.0.1", "0.0.0.0", "::1"].includes(url.hostname);
    const name = loopback ? "local" : (url.hostname.split(".").at(-1) ?? url.hostname);
    return url.port ? `${name}:${url.port}` : name;
  } catch {
    return root;
  }
};

/** One /props per server, off the request path: it decides polling, timings injection and whether to take the footer at all. */
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
      if (ctxRef) syncFooter(ctxRef); // a server that turns out not to be llama.cpp gets pi's footer back
      else paint(false);
    });
}

const isLlama = (root: string | undefined): boolean => (root === undefined ? false : llamaRoots.get(root) ?? true);

function trackModel(ctx: ExtensionContext): void {
  ctxRef = ctx;
  model = {
    root: serverRoot(ctx.model as { baseUrl?: string } | undefined),
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

/** Optional per-instance metrics; `false` means this server has no /metrics endpoint at all. */
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
    if (response.ok) return parseMetrics(await response.text());
    // 501 "Start it with --metrics" is the only answer that means there is no /metrics; anything else, including a
    // router refusing to speak for an instance that is not loaded, is worth asking about again.
    return response.status === 501 && /does not support metrics/i.test(await response.text()) ? "off" : undefined;
  } catch {
    return undefined;
  }
}

/** The last scrape per server+instance, so a request whose first scrape is late or lost does not show a row of dashes. */
const metricsShown = new Map<string, Metrics>();

let scraping = false;

async function scrapeMetrics(r: Req): Promise<void> {
  const key = keyOf(r);
  if (scraping || metricsSupport.get(key) === false) return;
  scraping = true;
  try {
    const result = await fetchMetrics(r.root, r.instance);
    if (result === "off") {
      metricsSupport.set(key, false);
      debug(`${key}: no /metrics`);
      return;
    }
    if (!result) return; // cold instance or a hiccup: ask again next time
    metricsSupport.set(key, true);
    metricsShown.set(key, result);
    r.metrics = result;
    paint();
  } finally {
    scraping = false;
  }
}

/** The slot carrying our request: a processing one, else the busiest. Exact only with --parallel 1. */
function pickSlot(slots: Slot[]): Slot | undefined {
  if (slots.length === 0) return undefined;
  return slots.find((slot) => slot.is_processing) ?? slots.reduce((a, b) => ((b.n_prompt_tokens ?? 0) > (a.n_prompt_tokens ?? 0) ? b : a));
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

const keyOf = (r: { root: string; instance: string }): string => `${r.root}|${r.instance}`;

function push<T>(map: Map<string, T[]>, key: string, value: T): void {
  const list = map.get(key) ?? [];
  list.push(value);
  if (list.length > HISTORY) list.shift();
  map.set(key, list);
}

function resetAll(): void {
  sess.reqs = 0;
  req = undefined;
  last = undefined;
  settled = undefined;
  samples = [];
  metricsShown.clear();
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
    prompt: timing ? (timing.prompt_n ?? 0) + (timing.cache_n ?? 0) : Math.max(r.seenPrompt, r.estPrompt),
    estimated: timing === undefined,
    evalToks: timing?.prompt_n ?? r.processed,
    reuse: timing?.cache_n ?? r.cached,
    out: timing?.predicted_n ?? r.decoded,
    nCtx: r.nCtx,
  };
  r.shownPp = n.pp;
  r.shownTg = n.tg;
  return n;
}

/** The numbers of the request that ended last, frozen: a new request holds them until it measures its own. */
let settled: Nums | undefined;

/** The holes of the running request filled with the previous one's numbers; the KV context survives between them. */
function hold(n: Nums): void {
  const p = settled;
  if (!p) return;
  if (!n.prompt) {
    n.prompt = p.prompt;
    n.estimated = true;
  }
  if (!n.evalToks) n.evalToks = p.evalToks;
  if (!n.reuse) n.reuse = p.reuse;
  if (!n.out) n.out = p.out;
  if (!n.nCtx) n.nCtx = p.nCtx;
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

/**
 * One /slots at a time. A llama.cpp that is up to its neck in prefill answers them slowly, and letting the poll
 * timer queue them up every 250ms only makes every one of them time out — which stops the panel moving entirely.
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

  r.processed = Math.max(r.processed, processed);
  r.decoded = Math.max(r.decoded, decoded);
  // /slots counts the whole KV slot, generation included, so the prompt size is what is left after subtracting.
  r.seenPrompt = Math.max(r.seenPrompt, (slot.n_prompt_tokens ?? 0) - decoded);
  r.cached = Math.max(r.cached, slot.n_prompt_tokens_cache ?? 0);
  r.nCtx = slot.n_ctx ?? r.nCtx;
  r.slots = slots.length;
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
  paint();
}

let painted = 0;

/** Stream events come once per generated token, and /slots polls four times a second: a panel only needs a few. */
function paint(throttled = true): void {
  const now = Date.now();
  if (throttled && now - painted < RENDER_MIN_MS) return;
  painted = now;
  tui?.requestRender();
}

function stopPolling(): void {
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
  const ctx = ctxRef;
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
function view(): { facts: Facts; used: number | null; flight: number; total: number } | undefined {
  const root = req?.root ?? last?.root ?? model.root;
  if (!isLlama(root)) return undefined;
  const r = req ?? last;
  const phase = phaseOf();
  const n: Nums = r ? numbers(r) : { estimated: false, ppEstimated: true, tgEstimated: true, nCtx: model.nCtx };
  if (req?.ended === undefined) hold(n);
  const session = sessionState();
  const m = r ? (r.metrics ?? metricsShown.get(keyOf(r))) : undefined;
  const hasMetrics = r ? metricsSupport.get(keyOf(r)) === true : false;

  // The used zone is pi's own context number: the one at the moment this request went out, since everything
  // arriving now belongs to the flight zone. Without a request it is pi's current estimate.
  const base = req ? req.base : (session.context?.tokens ?? last?.base ?? null);
  const facts: Facts = {
    live: phase,
    pp: n.pp,
    ppEstimated: n.ppEstimated,
    tg: n.tg,
    tgEstimated: n.tgEstimated,
    prompt: n.prompt,
    promptEstimated: n.estimated,
    eval: n.evalToks,
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
  return { facts, used: base, flight: flight(), total: n.nCtx || session.context?.contextWindow || model.nCtx };
}

/** What is landing in the KV right now: what this request's prefill has evaluated and generation has produced. */
function flight(): number {
  const r = req;
  if (r === undefined || r.ended !== undefined) return 0;
  // Without --slots the server counters stay at 0, so the stream's own generated-token count stands in.
  return Math.max(0, r.processed + r.decoded, r.timings?.predicted_n ?? 0);
}

const TONE: Record<Tone, ThemeColor | undefined> = {
  label: "dim",
  value: "text",
  live: "accent",
  dim: "dim",
  warn: "warning",
  error: "error",
  separator: "borderMuted",
  ident: "dim",
  model: "muted",
  number: "text",
  percent: "text",
  used: "accent",
  flight: "success",
  free: "borderMuted",
  none: undefined,
};

const colorize = (segments: Segment[], theme: Theme, to?: number): string => {
  const text = segments.map((s) => (TONE[s.tone] ? theme.fg(TONE[s.tone]!, s.text) : s.text)).join("");
  const room = to === undefined ? 0 : to - cols(flatten(segments));
  return room > 0 ? `${text}${" ".repeat(room)}` : text;
};

/** What other extensions set with ctx.ui.setStatus(), on a line of its own above the rest. */
function statusLine(footerData: ReadonlyFooterDataProvider, width: number, theme: Theme): string | undefined {
  const texts = [...footerData.getExtensionStatuses().values()];
  if (texts.length === 0) return undefined;
  const text = texts.join(" ").replace(/[\r\n\t]/g, " ").replace(/ +/g, " ").trim();
  return theme.fg("dim", cut(text, width));
}

/** pi's footer, with llama.cpp in it: the metrics line, and below it path, context bar and model. */
// Plain fields rather than constructor parameter properties: the layout half of this file is imported by
// preview.mjs under plain node, which strips types without transforming them.
class DxFooter implements Component {
  private theme: Theme;
  private footerData: ReadonlyFooterDataProvider;
  private stopBranchChange: () => void;

  constructor(theme: Theme, footerData: ReadonlyFooterDataProvider) {
    this.theme = theme;
    this.footerData = footerData;
    this.stopBranchChange = footerData.onBranchChange(() => paint(false));
  }

  render(width: number): string[] {
    const lines: string[] = [];
    const status = statusLine(this.footerData, width, this.theme);
    if (status !== undefined) lines.push(status);
    const v = view();
    if (v === undefined) return [...lines, colorize(baseLine({ width, cwd: cwdOf(), branch: this.footerData.getGitBranch(), model: ctxRef?.model?.id, thinking: thinkingOf(), used: null, total: model.nCtx }), this.theme, width)];
    lines.push(colorize(metricsLine(metricGroups(v.facts), width), this.theme));
    lines.push(
      colorize(
        baseLine({ width, cwd: cwdOf(), branch: this.footerData.getGitBranch(), model: ctxRef?.model?.id, thinking: thinkingOf(), used: v.used, flight: v.flight, total: v.total }),
        this.theme,
        width,
      ),
    );
    return lines;
  }

  dispose(): void {
    this.stopBranchChange();
  }

  invalidate(): void {}
}

/** Take pi's footer while the model's server answers like llama.cpp, hand it back when it does not. */
function syncFooter(ctx: ExtensionContext): void {
  ctxRef = ctx;
  if (ctx.mode !== "tui") return;
  if (isLlama(model.root)) ctx.ui.setFooter((_tui: TUI, theme: Theme, footerData: ReadonlyFooterDataProvider) => ((tui = _tui), new DxFooter(theme, footerData)));
  else ctx.ui.setFooter(undefined);
}

export default function llamaDx(pi: ExtensionAPI) {
  pi.on("session_start", (_event, ctx) => {
    resetAll();
    trackModel(ctx);
    syncFooter(ctx);
  });

  // A new model is a different machine: nothing measured on the old one may leak into these cells.
  pi.on("model_select", (_event, ctx) => {
    resetAll();
    trackModel(ctx);
    syncFooter(ctx);
    paint(false);
  });

  pi.on("before_provider_request", async (event, ctx) => {
    const payload = event.payload as Record<string, unknown>;
    const root = serverRoot(ctx.model as { baseUrl?: string } | undefined);
    if (!root) return undefined;
    ctxRef = ctx;
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
      base: ctx.getContextUsage()?.tokens ?? null,
      counted: false,
    };
    // A new request opens at the speeds already measured on this server rather than at 0, and glides from there.
    const key = keyOf(req);
    req.shownPp = estimatePrefill(key, req.nCtx);
    req.shownTg = estimateDecode(key);
    stopPolling();
    if (!isLlama(root)) return undefined;
    void scrapeMetrics(req); // learns whether this server has --metrics at all
    pollTimer = setInterval(() => void poll(), POLL_MS);
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
    paint();
  });

  pi.on("agent_end", async () => {
    stopPolling();
    if (req) {
      req.ended ??= Date.now();
      finalize(req);
    }
    paint(false);
  });

  pi.on("session_shutdown", (_event, ctx) => {
    stopPolling();
    req = undefined;
    ctx.ui.setFooter(undefined);
  });

  pi.registerCommand("llama-dx", {
    description: "llama.cpp footer: /llama-dx prints its state, /llama-dx reset zeroes the counters",
    handler: async (args, ctx) => {
      if (args.trim() === "reset") {
        resetAll();
        ctx.ui.notify("llama-dx: request counter and speed history cleared", "info");
      } else {
        const v = view();
        ctx.ui.notify(
          v === undefined
            ? "llama-dx: not on a llama.cpp model, pi's footer is back"
            : `llama-dx: ${sess.reqs} requests, ${v.facts.ppEstimated ? "~" : ""}${Math.round(v.facts.pp ?? 0)} pp, ${v.facts.tgEstimated ? "~" : ""}${Math.round(v.facts.tg ?? 0)} tg t/s, host ${v.facts.host}, bar ${percent(v.used ?? 0, v.total)} of ${full(v.total)}`,
          "info",
        );
      }
      tui?.requestRender();
    },
  });
}

const cwdOf = (): string => {
  const path = ctxRef?.sessionManager.getCwd() ?? process.cwd();
  const home = process.env.HOME ?? process.env.USERPROFILE;
  return home && (path === home || path.startsWith(`${home}/`)) ? `~${path.slice(home.length)}` : path;
};

const thinkingOf = (): string | null => {
  const ctx = ctxRef;
  if (!ctx?.model?.reasoning) return null;
  return !ctx.thinkingLevel || ctx.thinkingLevel === "off" ? "thinking off" : ctx.thinkingLevel;
};
