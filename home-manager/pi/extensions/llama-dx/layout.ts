// The two lines of the footer as coloured segments of measured width. Nothing here imports at runtime — colours are
// named tones and widths are measured here — so test-utils/preview.mjs can render it under plain node.
export type Tone = "label" | "value" | "live" | "dim" | "warn" | "error" | "separator" | "ident" | "model" | "number" | "percent" | "held" | "evaluating" | "pending" | "generating" | "free" | "none";
/** `bg` is the layer under `tone`, used only where two layers share a cell. */
export type Segment = { text: string; tone: Tone; bg?: Tone };
export type Cell = Segment[];
export type Group = { name: string; cells: Cell[] };

const GAP = "  ";
const SEP = "  │  ";
const GUTTER = "  ";

/** The whole alphabet of the context bar: three Block Elements glyphs, so nothing falls back to another font
 * mid-bar and no partial block leaves a gap next to a full one. ▰▱ and friends are missing from Berkeley Mono. */
const FULL = "█";
/** Where layers share a cell: the one on top in the foreground, the one under it in the background. */
const SHADE = "▒";
const TRACK = "░";

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

/** pi's own compaction thresholds, shared by the percent text and the bar's held layer. */
export type Load = "normal" | "warn" | "error";
export const load = (used: number, total: number): Load => {
  const p = total > 0 ? (used / total) * 100 : 0;
  return p > 90 ? "error" : p > 70 ? "warn" : "normal";
};

const ZONE: Record<Load, { held: Tone; percent: Tone }> = {
  normal: { held: "held", percent: "percent" },
  warn: { held: "warn", percent: "warn" },
  error: { held: "error", percent: "error" },
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

/** How much of one cell each band covers, 0 to 1. A band that covers none of it is 0 and never claims the cell. */
export type BarCell = { held: number; evaluating: number; pending: number; generating: number };
export type BarState = { cells: number; used: number; evaluating: number; pending: number; generating: number; total: number };

/** The bands in the order they sit in the bar: what is held, what is being evaluated, the prompt yet to evaluate
 * (which comes before what is produced), and what is being produced. */
const BANDS = ["held", "evaluating", "pending", "generating"] as const;

/** Where the bands end, in fractions of the bar. Over capacity held gives way and the rest keep the right edge,
 * so what is landing now is never squeezed out of sight by a context figure that has run past `n_ctx`. */
function barEnds(s: BarState): number[] {
  if (!(s.total > 0)) return [0, 0, 0, 0];
  const at = (v: number) => (s.used + Math.max(0, v)) / s.total;
  const ends: number[] = [];
  const shift = Math.max(0, at(s.evaluating + s.pending + s.generating) - 1);
  for (const v of [s.used / s.total, at(s.evaluating), at(s.evaluating + s.pending), at(s.evaluating + s.pending + s.generating)]) {
    ends.push(clamp(Math.max(v - shift, ends[ends.length - 1] ?? 0)));
  }
  return ends;
}

/** Coverage of every cell, left to right — the bar without colours or glyphs, which is what the tests read. */
export function barCells(s: BarState): BarCell[] {
  const n = Math.max(1, Math.round(s.cells));
  const ends = barEnds(s);
  const reach = (i: number, from: number, to: number) => Math.max(0, Math.min(to, (i + 1) / n) - Math.max(from, i / n)) * n;
  return Array.from({ length: n }, (_, i) => {
    const cell = { held: 0, evaluating: 0, pending: 0, generating: 0 } as BarCell;
    BANDS.forEach((band, b) => (cell[band] = reach(i, b === 0 ? 0 : ends[b - 1]!, ends[b]!)));
    return cell;
  });
}

/** Top down. `pending` is a forecast rather than a layer: it loses to every real band and is never a background. */
const PRECEDENCE = ["generating", "evaluating", "held", "pending"] as const;

/**
 * The context bar: what the context holds, what prefill is evaluating and generation producing right now, the
 * prompt this request has yet to evaluate, and the room left — one full block per cell, coloured by the band that
 * owns it. A band claims a cell by touching it, so one token held is a block and one block stands for thousands of
 * tokens. What is still to come is the quiet track in the colour it will turn into, so the green `█` of evaluating
 * visibly eats into the green `░` of pending. Where bands share a cell the topmost one is the foreground and the one
 * under it the background, drawn as a shade block so both show through.
 */
export function contextBar(s: BarState, l: Load = "normal"): Segment[] {
  const toneOf = (layer: (typeof BANDS)[number] | "pending"): Tone => (layer === "held" ? ZONE[l].held : layer);
  const out: Segment[] = [];
  const put = (glyph: string, tone: Tone, bg?: Tone) => {
    const last = out[out.length - 1];
    if (last && last.tone === tone && last.bg === bg) last.text += glyph;
    else out.push(bg === undefined ? { text: glyph, tone } : { text: glyph, tone, bg });
  };
  for (const cell of barCells(s)) {
    const stack = PRECEDENCE.filter((layer) => cell[layer] > 0);
    const real = stack.filter((layer) => layer !== "pending");
    if (real.length === 0) put(TRACK, stack.length > 0 ? "pending" : "free");
    else put(real.length > 1 ? SHADE : FULL, toneOf(real[0]!), real.length > 1 ? toneOf(real[1]!) : undefined);
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
  /** Prefill progress: of the tokens this request has to evaluate, how many are evaluated already. */
  pfDone?: number;
  pfTarget?: number;
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

/** Prefill progress in the same three significant digits as the percent of the context bar; `—` when nothing has to be evaluated. */
const progress = (done: number | undefined, target: number, estimated?: boolean): Segment => {
  if (done === undefined || !(target > 0)) return str(pad("—", 7));
  return str((estimated ? `~${percent(done, target)}` : percent(done, target)).padStart(7), { estimated });
};

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
        [lab("pf"), progress(f.pfDone, f.pfTarget ?? 0, f.pfDone !== undefined && f.promptEstimated)],
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
  evaluating?: number;
  pending?: number;
  generating?: number;
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

  const avail = () => {
    const blocks = [leftW, usedTxt.length + (showPercent ? 1 + pctTxt.length : 0), totalTxt.length, showRight ? rightW : 0];
    return i.width - blocks.reduce((a, b) => a + b, 0) - GUTTER.length * blocks.filter((b) => b > 0).length;
  };

  for (let guard = 0; guard < 12 && avail() < minBar; guard++) {
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
  out.push(...contextBar({ cells: Math.max(1, avail()), used: i.used ?? 0, evaluating: i.evaluating ?? 0, pending: i.pending ?? 0, generating: i.generating ?? 0, total: i.total }, l));
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
export const cols = (s: string): number => [...s].length;
export const cut = (s: string, w: number): string => (cols(s) <= w ? s : `${[...s].slice(0, Math.max(0, w - 1)).join("")}…`);
