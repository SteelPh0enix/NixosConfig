import type { ExtensionAPI, ExtensionContext, Theme } from "@earendil-works/pi-coding-agent";
import type { Component, TUI } from "@earendil-works/pi-tui";

// Reads live per-slot counters off the llama.cpp server behind the current model, plus the timings
// llama.cpp puts in every stream chunk (timings_per_token), and renders one line below the editor.

const POLL_MS = 250;
const WIDGET_KEY = "llama-dx";

type Slot = {
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
  prompt_ms?: number;
  prompt_per_second?: number;
  predicted_n?: number;
  predicted_ms?: number;
  predicted_per_second?: number;
  draft_n?: number;
  draft_n_accepted?: number;
};

type Live = {
  root: string;
  instance: string;
  /** Request body size, used for the token estimate until llama.cpp answers exactly. */
  chars: number;
  estPrompt: number;
  seenPrompt: number;
  processed: number;
  cached: number;
  decoded: number;
  nCtx: number;
  slots: number;
  processing: boolean;
  prefillTps: number;
  decodeTps: number;
  timings?: Timings;
  /** Prefill speed frozen when the first token arrived; llama.cpp's own number is noise after that. */
  prefillDoneTps?: number;
  endedAt?: number;
};

let live: Live | undefined;
let detailed = false;
let keepAfterDone = false;
let charsPerToken = 3.6;
let misses = 0;
let warned = false;
let pollTimer: ReturnType<typeof setInterval> | undefined;
let idlePolls = 0;
/** Servers that do not answer /slots; polled once, then left alone for the session. */
const noSlots = new Set<string>();
let tui: TUI | undefined;

const debug = process.env.LLAMA_DX_DEBUG === "1" ? (m: string) => process.stderr.write(`llama-dx: ${m}\n`) : () => {};
const kfmt = (n: number): string => (n >= 1_000_000 ? `${(n / 1_000_000).toFixed(1)}M` : n >= 10_000 ? `${Math.round(n / 1000)}k` : n >= 1000 ? `${(n / 1000).toFixed(1)}k` : String(Math.round(n)));

function serverRoot(model: { baseUrl?: string } | undefined): string | undefined {
  if (!model?.baseUrl) return undefined;
  try {
    const url = new URL(model.baseUrl);
    url.pathname = url.pathname.replace(/\/+$/, "").replace(/\/v1$/, "");
    url.search = "";
    url.hash = "";
    return url.toString().replace(/\/$/, "");
  } catch {
    return undefined;
  }
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

/** The slot carrying our request: a processing one, else the one with the most tokens. */
function pickSlot(slots: Slot[]): Slot | undefined {
  if (slots.length === 0) return undefined;
  return slots.find((slot) => slot.is_processing) ?? slots.reduce((a, b) => ((b.n_prompt_tokens ?? 0) > (a.n_prompt_tokens ?? 0) ? b : a));
}

/**
 * Tokens per second over the last WINDOW_MS of polls. llama.cpp only advances
 * n_prompt_tokens_processed one batch (--batch-size) at a time, so a single-poll delta reads either
 * zero or a spike; a window smooths both.
 */
const WINDOW_MS = 3000;
type Sample = { t: number; processed: number; decoded: number };
let samples: Sample[] = [];

function windowRate(t: number, counter: (s: Sample) => number): number {
  const current = counter(samples[samples.length - 1] ?? { t, processed: 0, decoded: 0 });
  const window = samples.filter((s) => t - s.t <= WINDOW_MS);
  const oldest = window[0];
  if (!oldest || oldest.t === t) return 0;
  return Math.max(0, (current - counter(oldest)) / ((t - oldest.t) / 1000));
}

async function poll(ctx: ExtensionContext): Promise<void> {
  if (!live) return;
  const slots = await fetchSlots(live.root, live.instance);
  const slot = slots ? pickSlot(slots) : undefined;
  if (!slot) {
    // Nothing more to learn here: the stream timings still drive the decode side of the bar, so stop
    // asking a server that does not have the endpoint (llama-server needs --slots).
    if (++misses < 3) return;
    noSlots.add(live.root);
    stopPolling();
    if (!warned) {
      warned = true;
      ctx.ui.notify(`llama-dx: ${live.root} has no /slots, showing stream timings only`, "warning");
    }
    return;
  }
  misses = 0;
  const t = Date.now();
  const processed = slot.n_prompt_tokens_processed ?? 0;
  const decoded = slot.next_token?.[0]?.n_decoded ?? 0;

  live.processed = processed;
  live.decoded = decoded;
  samples = [...samples.filter((s) => t - s.t <= WINDOW_MS), { t, processed, decoded }];
  live.prefillTps = windowRate(t, (s) => s.processed);
  live.decodeTps = windowRate(t, (s) => s.decoded);
  // Freeze the prefill speed at the first generated token; after that its window rate falls to zero.
  if (decoded > 0 && live.prefillDoneTps === undefined) live.prefillDoneTps = live.prefillTps;

  live.seenPrompt = Math.max(slot.n_prompt_tokens ?? 0, live.seenPrompt);
  live.cached = Math.max(slot.n_prompt_tokens_cache ?? 0, live.cached);
  live.nCtx = slot.n_ctx ?? live.nCtx;
  live.slots = slots?.length ?? 0;
  live.processing = slot.is_processing === true;
  // The llama.cpp task ends before pi's agent loop does (tools follow). Two idle polls in a row, so a
  // single transient one cannot end the display mid-generation.
  idlePolls = live.processing ? 0 : idlePolls + 1;
  if (idlePolls >= 2 && (processed > 0 || decoded > 0)) {
    live.prefillDoneTps ??= live.prefillTps;
    live.endedAt = t;
  }
  debug(`total=${slot.n_prompt_tokens ?? 0} processed=${processed} cache=${slot.n_prompt_tokens_cache ?? 0} decoded=${decoded} prefill=${Math.round(live.prefillTps)} decode=${Math.round(live.decodeTps)}`);
  tui?.requestRender();
}

function stopPolling(): void {
  if (pollTimer) clearInterval(pollTimer);
  pollTimer = undefined;
  samples = [];
  idlePolls = 0;
}

/** Rates read as noise before the first sample arrives. */
const tps = (n: number): string => (n >= 1 ? kfmt(Math.round(n)) : "…");

function bar(fraction: number, width = 10): string {
  const filled = Math.max(0, Math.min(width, Math.round(fraction * width)));
  return "▰".repeat(filled) + "▱".repeat(width - filled);
}

type Phase = "queued" | "prefill" | "decode" | "done";

function phaseOf(l: Live): Phase {
  if (l.endedAt !== undefined) return "done";
  if (l.decoded > 0 || (l.timings?.predicted_n ?? 0) > 0) return "decode";
  // /slots reports is_processing=false between prefill chunks, so only a lasting idle is a real queue.
  return l.processing || idlePolls < 2 ? "prefill" : "queued";
}

/** Progress over the whole prompt: cached tokens need no work, but they are part of the prompt. */
function progressOf(l: Live): { done: number; total: number; toEvaluate: number } {
  const total = Math.max(l.seenPrompt, l.estPrompt, 1);
  const cached = Math.max(l.cached, l.timings?.cache_n ?? 0);
  const done = Math.min(total, l.processed + cached);
  return { done, total, toEvaluate: Math.max(0, total - cached) };
}

const TONE = { queued: "warning", prefill: "warning", decode: "accent", done: "dim" } as const;

function partsOf(l: Live, phase: Phase): string[] {
  const { total, toEvaluate } = progressOf(l);
  const exact = l.timings !== undefined || l.estPrompt <= l.seenPrompt;
  // What the server will have to read for this request; reuse is only known once the prompt ran.
  if (phase === "queued") return [`waiting for a slot`, `${exact ? "" : "~"}${kfmt(total)} prompt tok`];
  if (phase === "prefill") {
    // n_prompt_tokens_processed counts cached tokens restored to the KV cache as work, and
    // n_prompt_tokens_cache only learns the real reuse when the prompt finishes - hence "≥".
    if (toEvaluate < 200) return [`kv reuse ${kfmt(l.cached)}/${kfmt(total)}`, `prompt needs no prefill`];
    return [
      `${bar(Math.min(0.99, l.processed / total))} ${kfmt(l.processed)}/${exact ? "" : "~"}${kfmt(total)} prompt tok` + (l.prefillTps >= 1 ? ` · ~${Math.max(0, Math.round((total - l.processed) / l.prefillTps))}s left` : ""),
      `${tps(l.prefillTps)} tok/s${l.cached > 0 ? ` · reuse ≥${kfmt(l.cached)}` : ""}`,
    ];
  }
  // Once a token exists, llama.cpp's own timings are exact and constant for the rest of the stream:
  // prompt_n is what had to be evaluated, cache_n what came back from the KV cache.
  const decodeTps = phase === "done" ? (l.timings?.predicted_per_second ?? l.decodeTps) : l.decodeTps;
  const out = l.timings?.predicted_n ?? l.decoded;
  const evaluated = l.timings?.prompt_n ?? toEvaluate;
  const parts = [`${kfmt(out)} tok out @ ${tps(decodeTps)}/s`];
  if (evaluated > 200) parts.push(`${kfmt(evaluated)} tok prefill @ ${tps(l.timings?.prompt_per_second ?? l.prefillDoneTps ?? l.prefillTps)}/s`);
  const reused = l.timings?.cache_n ?? l.cached;
  if (reused > 0) parts.push(`${kfmt(reused)} tok reused`);
  const draft = l.timings?.draft_n ?? 0;
  if (draft > 0) parts.push(`speculative ${l.timings?.draft_n_accepted ?? 0}/${draft} accepted`);
  return parts;
}

function context(l: Live): string {
  const used = (l.timings?.prompt_n ?? 0) + (l.timings?.cache_n ?? l.cached) + (l.timings?.predicted_n ?? l.decoded);
  return l.nCtx > 0 ? `ctx ${kfmt(used)}/${kfmt(l.nCtx)} ${Math.round((used / l.nCtx) * 100)}%` : "";
}

class DxBar implements Component {
  constructor(private theme: Theme) {}

  render(width: number): string[] {
    if (!live || (live.endedAt !== undefined && !keepAfterDone)) return [];
    const phase = phaseOf(live);
    const parts = partsOf(live, phase);
    const head = `${phase} ${live.instance.slice(0, 20)}`;
    const lines = [` ${head} ${parts[0]}`];
    if (parts[1]) lines.push(` ${" ".repeat(head.length)} ${parts[1]}`);
    if (detailed) {
      const tail = parts.slice(2);
      if (phase === "decode" || phase === "done") tail.push(context(live));
      tail.push(live.root.replace(/^https?:\/\//, ""), `slots ${live.slots}`);
      lines.push(` ${tail.join(" · ")}`);
    }
    return lines.map((line) => this.theme.fg(TONE[phase], line.length > width ? `${line.slice(0, width - 1)}…` : line));
  }

  invalidate(): void {}
}

export default function llamaDx(pi: ExtensionAPI) {
  const mount = (ctx: ExtensionContext) => {
    ctx.ui.setWidget(WIDGET_KEY, keepAfterDone || live ? (_tui: TUI, theme: Theme) => ((tui = _tui), new DxBar(theme)) : undefined, { placement: "belowEditor" });
  };

  pi.on("session_start", (_event, ctx) => {
    if (ctx.mode === "tui") mount(ctx);
  });

  pi.on("before_provider_request", async (event, ctx) => {
    const payload = event.payload as Record<string, unknown>;
    const root = serverRoot(ctx.model as { baseUrl?: string } | undefined);
    if (!root) return undefined;
    live = {
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
      prefillTps: 0,
      decodeTps: 0,
    };
    misses = 0;
    stopPolling();
    if (ctx.mode === "tui") mount(ctx);
    if (!noSlots.has(root)) pollTimer = setInterval(() => void poll(ctx), POLL_MS);
    // llama.cpp only repeats its timings in every chunk when asked for it.
    return { ...payload, timings_per_token: true };
  });

  pi.on("provider_stream_event", async (event) => {
    const data = event.data as { timings?: Timings; usage?: { prompt_tokens?: number } } | undefined;
    if (!data || typeof data !== "object" || !live) return;
    if (data.timings) live.timings = data.timings;
    if (data.usage?.prompt_tokens) {
      live.estPrompt = data.usage.prompt_tokens;
      // Almost the same body goes out next turn, so this ratio is a good estimate then.
      charsPerToken = live.chars / data.usage.prompt_tokens;
    }
  });

  const finish = async (_event: unknown, ctx: ExtensionContext) => {
    stopPolling();
    if (!live) return;
    live.endedAt = Date.now();
    debug(`prompt=${live.timings?.prompt_n} cache=${live.timings?.cache_n} out=${live.timings?.predicted_n} prompt_tps=${Math.round(live.timings?.prompt_per_second ?? 0)} out_tps=${Math.round(live.timings?.predicted_per_second ?? 0)} ratio=${(live.chars / Math.max(1, live.estPrompt)).toFixed(2)} chars/tok`);
    tui?.requestRender();
    mount(ctx);
  };

  pi.on("agent_end", finish as never);

  pi.on("session_shutdown", (_event, ctx) => {
    stopPolling();
    live = undefined;
    ctx.ui.setWidget(WIDGET_KEY, undefined);
  });

  pi.registerCommand("llama-dx", {
    description: "Toggle llama.cpp prefill/decode diagnostics below the editor",
    handler: async (args, ctx) => {
      if (args.trim() === "detail") detailed = !detailed;
      else keepAfterDone = !keepAfterDone;
      mount(ctx);
      ctx.ui.notify(`llama-dx: keep-after-done=${keepAfterDone ? "on" : "off"}, detail=${detailed ? "on" : "off"}`, "info");
    },
  });
}
