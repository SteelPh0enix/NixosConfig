#!/usr/bin/env node
// Dev-only preview of the footer: renders the real layout at chosen widths and request phases, so the look can be
// judged in a terminal without starting pi. Imports ../layout.ts directly, which is why that file has no runtime
// imports. `node preview.mjs [--width 80,120] [--only idle,prefilling] [--plain] [--check] [--legend] [--demo]`
//   --demo  every combination of the context bar's bands, plus one whole request running through the bar
import { barCells, baseLine, contextBar, flatten, load, metricGroups, metricsLine } from "../layout.ts";
import { legend } from "../legend.ts";

// The theme tokens of footer.ts resolved through the noctalia palette, so the preview shows the real colours.
const COLOUR = {
  label: "#4a76a3",
  value: "#e4eaf3",
  live: "#c4a82e",
  dim: "#2578a9",
  warn: "#d14358",
  error: "#b32d2d",
  separator: "#2e5f85",
  ident: "#6f8fae",
  model: "#9b6bc1",
  number: "#e4eaf3",
  percent: "#9dc7ea",
  held: "#c4a82e",
  evaluating: "#00a66c",
  pending: "#00a66c",
  generating: "#e4eaf3",
  free: "#2578a9",
  none: "",
};

const rgb = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16)).join(";");
const segment = (s) => {
  const fg = s.tone !== "none" && COLOUR[s.tone] ? `\x1b[38;2;${rgb(COLOUR[s.tone])}m` : "";
  const bg = s.bg ? `\x1b[48;2;${rgb(COLOUR[s.bg])}m` : "";
  return fg || bg ? `${fg}${bg}${s.text}\x1b[0m` : s.text;
};
const colorize = (segments) => segments.map(segment).join("");

// Only the theme tokens legend.ts reaches for.
const TOKEN = { muted: "#9bb0c7", accent: "#c4a82e", text: "#e4eaf3", dim: "#2578a9" };

const cols = (s) => [...s].length;

const CWD = "~/src/steel-pi";
const MODEL = "qwen3-coder-27b";
const TOTAL = 262144;

const SCENARIOS = [
  { name: "idle", facts: { live: "idle", pp: 658, tg: 59, prompt: 8400, eval: 1800, pfDone: 1800, pfTarget: 1800, reuse: 6600, out: 21, reqs: 2, sessionIn: 10200, sessionOut: 80, cacheRead: 3500, queue: 0, processing: 0, slots: 1, busy: 1, specAccepted: 13, specDrafted: 21, specLifeAccepted: 1240, specLifeDrafted: 1430, ttft: 10100, host: "fwpc:33333", slotId: 0, nTokensMax: 12300, charsPerToken: 3.9, exactTimings: true }, used: 8400, evaluating: 0, pending: 0, generating: 0 },
  { name: "prefilling", facts: { live: "prefill", pp: 712, ppEstimated: true, tg: 58, tgEstimated: true, prompt: 15200, promptEstimated: true, eval: 3300, pfDone: 3300, pfTarget: 6600, reuse: 8600, out: 0, reqs: 3, sessionIn: 25400, sessionOut: 260, cacheRead: 12800, queue: 0, processing: 1, slots: 1, busy: 1, specAccepted: 22, specDrafted: 35, specLifeAccepted: 1262, specLifeDrafted: 1465, host: "fwpc:33333", slotId: 0, nTokensMax: 12300, charsPerToken: 3.9, exactTimings: false }, used: 8400, evaluating: 3300, pending: 3300, generating: 0 },
  { name: "decoding", facts: { live: "decode", pp: 640, tg: 57.8, prompt: 15200, eval: 6600, pfDone: 6600, pfTarget: 6600, reuse: 8600, out: 340, reqs: 3, sessionIn: 25400, sessionOut: 600, cacheRead: 12800, queue: 1, processing: 2, slots: 2, busy: 1.6, specAccepted: 190, specDrafted: 340, specLifeAccepted: 1452, specLifeDrafted: 1805, ttft: 8100, host: "fwpc:33333", slotId: 1, nTokensMax: 15900, charsPerToken: 3.9, exactTimings: true }, used: 8400, evaluating: 6600, pending: 0, generating: 340 },
  { name: "near full", facts: { live: "decode", pp: 412, tg: 41, prompt: 240000, eval: 12000, pfDone: 12000, pfTarget: 12000, reuse: 228000, out: 6200, reqs: 41, sessionIn: 1200000, sessionOut: 41000, cacheRead: 998000, queue: 3, processing: 2, slots: 2, busy: 2, specAccepted: 900, specDrafted: 3100, specLifeAccepted: 9000, specLifeDrafted: 12000, ttft: 412000, host: "pc:51536", slotId: 1, nTokensMax: 262000, charsPerToken: 4.1, exactTimings: true }, used: 238000, evaluating: 12000, pending: 0, generating: 6200 },
  { name: "just compacted", facts: { live: "prefill", pp: 588, ppEstimated: true, tg: 60, tgEstimated: true, prompt: 42000, promptEstimated: true, eval: 34000, pfDone: 34000, pfTarget: 42000, reuse: 0, out: 0, reqs: 42, sessionIn: 1240000, sessionOut: 47000, cacheRead: 1010000, queue: 0, processing: 1, slots: 1, busy: 1, specAccepted: 4, specDrafted: 9, specLifeAccepted: 9004, specLifeDrafted: 12009, host: "pc:51536", slotId: 0, nTokensMax: 262000, charsPerToken: 4.1, exactTimings: false }, used: null, evaluating: 34000, pending: 8000, generating: 0 },
  { name: "no --metrics", facts: { live: "decode", pp: 658, tg: 59, prompt: 8400, eval: 1800, pfDone: 1800, pfTarget: 1800, reuse: 6600, out: 96, reqs: 4, sessionIn: 34000, sessionOut: 900, cacheRead: 21000, processing: 1, slots: 1, busy: 1, ttft: 900, host: "fwpc:33333", slotId: 0, nTokensMax: 9600, charsPerToken: 3.9, exactTimings: true }, used: 8400, evaluating: 0, pending: 0, generating: 96 },
];

const argv = process.argv.slice(2);
const plain = argv.includes("--plain");
const at = argv.indexOf("--width");
const widths = at === -1 ? [80, 96, 120, 160, 200] : argv[at + 1].split(",").map(Number);
const onlyAt = argv.indexOf("--only");
const only = onlyAt === -1 ? null : argv[onlyAt + 1].split(",");
const scenarios = SCENARIOS.filter((s) => !only || only.includes(s.name));

const lineOf = (s, width) => baseLine({ width, cwd: CWD, branch: "master", model: MODEL, thinking: "high", used: s.used, evaluating: s.evaluating, pending: s.pending, generating: s.generating, total: TOTAL });
const fill = (segments, width) => (plain ? flatten(segments) : colorize([...segments, { text: " ".repeat(Math.max(0, width - cols(flatten(segments)))), tone: "none" }]));

if (argv.includes("--check")) {
  const BANDS = ["held", "evaluating", "pending", "generating"];
  let bad = 0;
  // Down to 20 columns, where only the two numbers and a stub of a bar are left; below ~16 the two numbers alone
  // need more room than a terminal of that width has, and no layout can say otherwise.
  for (const width of [20, 24, 28, 32, 40, 60, 80, 96, 120, 140, 160, 200, 240, 280]) {
    for (const s of SCENARIOS) {
      for (const [used, evaluating, pending, generating] of [[0, 0, 0, 0], [s.used, s.evaluating, s.pending, s.generating], [TOTAL, 0, 0, 0], [TOTAL + 9000, 9000, 9000, 9000]]) {
        const state = { used, evaluating, pending, generating };
        const line = flatten(lineOf({ ...s, ...state }, width));
        const metrics = flatten(metricsLine(metricGroups(s.facts), width));
        const bar = line.match(/[█▒░]+/)?.[0] ?? "";
        const n = bar.length;
        const end = (v) => Math.min(1, ((used ?? 0) + v) / TOTAL);
        const claimed = (v) => Math.ceil(end(v) * n - 1e-9); // a band claims every cell it touches
        const cells = barCells({ cells: n, used: used ?? 0, evaluating, pending, generating, total: TOTAL });
        const sum = (band) => cells.reduce((a, c) => a + c[band], 0);
        const ranks = cells.map((c) => BANDS.findIndex((b) => c[b] > 0)).filter((r) => r >= 0);
        const tokens = { held: used, evaluating, pending, generating };
        const off = used === null || end(evaluating + pending + generating) >= 1 ? 0 : Math.max(...BANDS.map((b) => Math.abs(sum(b) - (tokens[b] / TOTAL) * n)));
        const problems = [
          cols(line) === width ? "" : `base ${cols(line)} != ${width}`,
          cols(metrics) <= width ? "" : `metrics ${cols(metrics)} > ${width}`,
          n >= (width >= 40 ? 10 : 1) ? "" : `bar ${n} < ${width >= 40 ? 10 : 1}`,
          // held, evaluating and generating are contiguous unless a forecast sits between the last two, which only
          // ever happens while a request both still has a prompt to read and is already producing tokens.
          pending === 0 || generating === 0
            ? bar.replaceAll("░", "").length === claimed(evaluating + generating)
              ? ""
              : `filled ${bar.replaceAll("░", "").length} != ${claimed(evaluating + generating)}`
            : "",
          cells.filter((c) => BANDS.some((b) => c[b] > 0)).length === claimed(evaluating + pending + generating) ? "" : "cells claimed by the bands differ from the forecast",
          ranks.every((r, i) => i === 0 || ranks[i - 1] <= r) ? "" : "bands out of order",
          off <= 1e-6 ? "" : `band areas off by ${off.toFixed(3)}`,
        ].filter(Boolean);
        if (problems.length) (console.log(`${width} ${s.name} used=${used}: ${problems.join(", ")}`), bad++);
      }
    }
  }
  console.log(bad === 0 ? "layout invariants hold at every width" : `${bad} problems`);
  process.exit(bad === 0 ? 0 : 1);
}

if (argv.includes("--legend")) {
  const theme = plain ? { fg: (_token, s) => s } : { fg: (token, s) => (TOKEN[token] ? `\x1b[38;2;${rgb(TOKEN[token])}${s}\x1b[0m` : s) };
  for (const width of widths) console.log(`\n${"═".repeat(width)}  ${width} columns\n${legend(theme, width)}`);
  process.exit(0);
}

const KEY = `${colorize([{ text: "█", tone: "held" }])} held  ${colorize([{ text: "█", tone: "evaluating" }])} evaluating  ${colorize([{ text: "░", tone: "pending" }])} prompt yet to evaluate  ${colorize([{ text: "█", tone: "generating" }])} generating  ${colorize([{ text: "▒", tone: "evaluating", bg: "held" }])} where two bands meet  ${colorize([{ text: "░", tone: "free" }])} free  ${colorize([{ text: "█", tone: "warn" }])} past 70%  ${colorize([{ text: "█", tone: "error" }])} past 90%`;

if (argv.includes("--demo")) {
  const cells = Number(argv.includes("--cells") ? argv[argv.indexOf("--cells") + 1] : 48);
  const tokens = 100; // so one cell is exactly `tokens` tokens and every band of a small request shows up
  const total = cells * tokens;
  const bar = (used, evaluating, pending, generating) => {
    const segments = contextBar({ cells, used: used ?? 0, evaluating, pending, generating, total }, load(used ?? 0, total));
    return plain ? flatten(segments) + " ".repeat(cells - cols(flatten(segments))) : colorize(segments);
  };
  const r = (v) => (v === null ? null : Math.round(v));
  const row = (what, used, evaluating, pending, generating, shows) => {
    const [u, e, p, g] = [used, evaluating, pending, generating].map(r);
    console.log(`  ${what.padEnd(23)}${bar(u, e, p, g)}  ${String(u ?? "—").padStart(6)} held ${String(e).padStart(5)} eval ${String(p).padStart(5)} next ${String(g).padStart(5)} gen  ${shows}`);
  };

  console.log(`\nevery combination the context bar can be in — ${cells} cells over ${total} tokens, so one cell is ${tokens} tokens`);
  if (plain) console.log("  (under --plain the pending track looks like the free one: only its colour tells them apart)");
  row("empty", 0, 0, 0, 0, "nothing held, nothing landing, nothing coming");
  row("one token", 1, 0, 0, 0, "a single token claims its whole cell");
  row("held", 0.42 * total, 0, 0, 0, "held block, free track, one cell for the part-held one");
  row("pending, not started", 0.42 * total, 0, 0.15 * total, 0, "the whole incoming prompt, before a token is evaluated");
  row("mid prefill", 0.42 * total, 0.06 * total, 0.09 * total, 0, "evaluating eats into the prompt still to come");
  row("held ▒ evaluating", 0.44 * total, 0.02 * total, 0.06 * total, 0, "evaluating lands on held: eval in front, held behind");
  row("eval ends, next begins", 0.4 * total, 0.07 * total, 0.06 * total, 0, "no composite: the green █ stops and the green ░ goes on");
  row("eval ▒ generating", 0.4 * total, 0.07 * total, 0, 0.02 * total, "generating lands on evaluating");
  row("held ▒ generating", 0.44 * total, 0, 0, 0.03 * total, "cache hit: nothing evaluated and nothing pending");
  row("three in a cell", 0.44 * total, 0.01 * total, 0.01 * total, 0.01 * total, "held, eval and gen together: gen in front, eval behind");
  row("pending over the edge", 0.72 * total, 0.03 * total, 0.19 * total, 0, "the forecast reaching past 90% of n_ctx");
  row("over capacity", 0.975 * total, 0.055 * total, 0.035 * total, 0, "past n_ctx: held gives way, the bands keep the edge");
  row("used unknown", null, 0.16 * total, 0.06 * total, 0.02 * total, "right after compaction: the bands start at 0");
  row("one gen token", 0.4 * total, 0, 0, 1, "the live edge is never invisible");
  row("warning", 0.74 * total, 0.02 * total, 0, 0, "held past 70%, and the frontier follows it");
  row("error", 0.93 * total, 0.02 * total, 0, 0, "held past 90%");

  console.log("\none request through the bar — held 1250, a 2650-token prompt to evaluate, then generation; `pf` says where prefill is");
  const base = 1250;
  const frames = [
    ["the request goes out", base, 0, 2650, 0],
    ...Array.from({ length: 7 }, (_, i) => [`prefill ${i + 1}/7`, base, (i + 1) * 350, 2650 - (i + 1) * 350, 0]),
    ["prefill done", base, 2650, 0, 0],
    ...Array.from({ length: 5 }, (_, i) => [`generate ${i + 1}/5`, base, 2650, 0, (i + 1) * 80]),
    ["the request ends", base + 2650 + 400, 0, 0, 0],
  ];
  for (const [what, used, evaluating, pending, generating] of frames) console.log(`  ${what.padEnd(23)}${bar(used, evaluating, pending, generating)}`);

  console.log("\nthe whole footer where identity has to give way to the bar");
  for (const width of [56, 72, 96]) {
    const s = SCENARIOS.find((x) => x.name === "prefilling");
    console.log(`\n${"═".repeat(width)}  ${width} columns`);
    console.log(fill(metricsLine(metricGroups(s.facts), width), width));
    console.log(fill(lineOf(s, width), width));
  }

  if (!plain) console.log(`\n${KEY}   ~ = not llama.cpp's own number`);
  process.exit(0);
}

for (const width of widths) {
  console.log(`\n${"═".repeat(width)}  ${width} columns`);
  for (const s of scenarios) {
    console.log(`${s.name.padEnd(15)}${fill(metricsLine(metricGroups(s.facts), width), width)}`);
    console.log(`${"".padEnd(15)}${fill(lineOf(s, width), width)}`);
  }
}
if (!plain) console.log(`\n${KEY}   ~ = not llama.cpp's own number`);
