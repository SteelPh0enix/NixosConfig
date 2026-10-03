#!/usr/bin/env node
// Dev-only preview of the footer: renders the real layout at chosen widths and request phases, so the look can be
// judged in a terminal without starting pi. Imports ../layout.ts directly, which is why that file has no runtime
// imports. `node preview.mjs [--width 80,120] [--only idle,prefilling] [--plain] [--check] [--legend] [--demo]`
//   --demo  every combination of the context bar's layers, plus one whole request running through the bar
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
  { name: "idle", facts: { live: "idle", pp: 658, tg: 59, prompt: 8400, eval: 1800, reuse: 6600, out: 21, reqs: 2, sessionIn: 10200, sessionOut: 80, cacheRead: 3500, queue: 0, processing: 0, slots: 1, busy: 1, specAccepted: 13, specDrafted: 21, specLifeAccepted: 1240, specLifeDrafted: 1430, ttft: 10100, host: "fwpc:33333", slotId: 0, nTokensMax: 12300, charsPerToken: 3.9, exactTimings: true }, used: 8400, evaluating: 0, generating: 0 },
  { name: "prefilling", facts: { live: "prefill", pp: 712, ppEstimated: true, tg: 58, tgEstimated: true, prompt: 15200, promptEstimated: true, eval: 6600, reuse: 8600, out: 0, reqs: 3, sessionIn: 25400, sessionOut: 260, cacheRead: 12800, queue: 0, processing: 1, slots: 1, busy: 1, specAccepted: 22, specDrafted: 35, specLifeAccepted: 1262, specLifeDrafted: 1465, host: "fwpc:33333", slotId: 0, nTokensMax: 12300, charsPerToken: 3.9, exactTimings: false }, used: 8400, evaluating: 6600, generating: 0 },
  { name: "decoding", facts: { live: "decode", pp: 640, tg: 57.8, prompt: 15200, eval: 6600, reuse: 8600, out: 340, reqs: 3, sessionIn: 25400, sessionOut: 600, cacheRead: 12800, queue: 1, processing: 2, slots: 2, busy: 1.6, specAccepted: 190, specDrafted: 340, specLifeAccepted: 1452, specLifeDrafted: 1805, ttft: 8100, host: "fwpc:33333", slotId: 1, nTokensMax: 15900, charsPerToken: 3.9, exactTimings: true }, used: 8400, evaluating: 6600, generating: 340 },
  { name: "near full", facts: { live: "decode", pp: 412, tg: 41, prompt: 240000, eval: 12000, reuse: 228000, out: 6200, reqs: 41, sessionIn: 1200000, sessionOut: 41000, cacheRead: 998000, queue: 3, processing: 2, slots: 2, busy: 2, specAccepted: 900, specDrafted: 3100, specLifeAccepted: 9000, specLifeDrafted: 12000, ttft: 412000, host: "pc:51536", slotId: 1, nTokensMax: 262000, charsPerToken: 4.1, exactTimings: true }, used: 238000, evaluating: 12000, generating: 6200 },
  { name: "just compacted", facts: { live: "prefill", pp: 588, ppEstimated: true, tg: 60, tgEstimated: true, prompt: 42000, promptEstimated: true, eval: 42000, reuse: 0, out: 0, reqs: 42, sessionIn: 1240000, sessionOut: 47000, cacheRead: 1010000, queue: 0, processing: 1, slots: 1, busy: 1, specAccepted: 4, specDrafted: 9, specLifeAccepted: 9004, specLifeDrafted: 12009, host: "pc:51536", slotId: 0, nTokensMax: 262000, charsPerToken: 4.1, exactTimings: false }, used: null, evaluating: 42000, generating: 0 },
  { name: "no --metrics", facts: { live: "decode", pp: 658, tg: 59, prompt: 8400, eval: 1800, reuse: 6600, out: 96, reqs: 4, sessionIn: 34000, sessionOut: 900, cacheRead: 21000, processing: 1, slots: 1, busy: 1, ttft: 900, host: "fwpc:33333", slotId: 0, nTokensMax: 9600, charsPerToken: 3.9, exactTimings: true }, used: 8400, evaluating: 0, generating: 96 },
];

const argv = process.argv.slice(2);
const plain = argv.includes("--plain");
const at = argv.indexOf("--width");
const widths = at === -1 ? [80, 96, 120, 160, 200] : argv[at + 1].split(",").map(Number);
const onlyAt = argv.indexOf("--only");
const only = onlyAt === -1 ? null : argv[onlyAt + 1].split(",");
const scenarios = SCENARIOS.filter((s) => !only || only.includes(s.name));

const lineOf = (s, width) => baseLine({ width, cwd: CWD, branch: "master", model: MODEL, thinking: "high", used: s.used, evaluating: s.evaluating, generating: s.generating, total: TOTAL });
const fill = (segments, width) => (plain ? flatten(segments) : colorize([...segments, { text: " ".repeat(Math.max(0, width - cols(flatten(segments)))), tone: "none" }]));

if (argv.includes("--check")) {
  let bad = 0;
  for (const width of [40, 60, 80, 96, 120, 140, 160, 200, 240, 280]) {
    for (const s of SCENARIOS) {
      for (const [used, evaluating, generating] of [[0, 0, 0], [s.used, s.evaluating, s.generating], [TOTAL, 0, 0], [TOTAL + 9000, 9000, 9000]]) {
        const line = flatten(lineOf({ ...s, used, evaluating, generating }, width));
        const metrics = flatten(metricsLine(metricGroups(s.facts), width));
        const bar = line.match(/[█▒░]+/)?.[0] ?? "";
        const n = bar.length;
        const end = Math.min(1, ((used ?? 0) + evaluating + generating) / TOTAL);
        const cells = barCells({ cells: n, used: used ?? 0, evaluating, generating, total: TOTAL });
        const sum = (layer) => cells.reduce((a, c) => a + c[layer], 0);
        // A layer claims every cell it touches, so the filled cells are exactly the ones the union of the bands reaches.
        const want = Math.ceil(end * n - 1e-9);
        const layers = ["held", "evaluating", "generating"];
        const ranks = cells.map((c) => layers.findIndex((l) => c[l] > 0)).filter((r) => r >= 0);
        const inOrder = ranks.every((r, i) => i === 0 || ranks[i - 1] <= r);
        const off = used === null || end >= 1 ? 0 : Math.max(Math.abs(sum("held") - (used / TOTAL) * n), Math.abs(sum("evaluating") - (evaluating / TOTAL) * n), Math.abs(sum("generating") - (generating / TOTAL) * n));
        const problems = [
          cols(line) === width ? "" : `base ${cols(line)} != ${width}`,
          cols(metrics) <= width ? "" : `metrics ${cols(metrics)} > ${width}`,
          n >= 10 ? "" : `bar ${n} < 10`,
          bar.replaceAll("░", "").length === want ? "" : `filled ${bar.replaceAll("░", "").length} != ${want}`,
          inOrder ? "" : "bands out of order",
          off <= 1e-6 ? "" : `layer areas off by ${off.toFixed(3)}`,
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

if (argv.includes("--demo")) {
  const cells = Number(argv.includes("--cells") ? argv[argv.indexOf("--cells") + 1] : 48);
  const tokens = 100; // so one cell is exactly `tokens` tokens and every layer of a small request shows up
  const total = cells * tokens;
  const bar = (used, evaluating, generating) => {
    const segments = contextBar({ cells, used: used ?? 0, evaluating, generating, total }, load(used ?? 0, total));
    const text = flatten(segments);
    return plain ? text + " ".repeat(cells - cols(text)) : colorize(segments);
  };
  const r = (v) => (v === null ? null : Math.round(v));
  const row = (what, used, evaluating, generating, shows) => {
    const [u, e, g] = [r(used), r(evaluating), r(generating)];
    console.log(`  ${what.padEnd(20)}${bar(u, e, g)}  ${String(u ?? "—").padStart(6)} held ${String(e).padStart(5)} eval ${String(g).padStart(5)} gen  ${shows}`);
  };

  console.log(`\nevery combination the context bar can be in — ${cells} cells over ${total} tokens, so one cell is ${tokens} tokens`);
  row("empty", 0, 0, 0, "nothing held, nothing landing");
  row("one token", 1, 0, 0, "a single token claims its whole cell");
  row("held", 0.42 * total, 0, 0, "held block, free track, one cell for the part-held one");
  row("held ▒ evaluating", 0.44 * total, 0.02 * total, 0, "evaluating lands on held: eval in front, held behind");
  row("evaluating", 0.4 * total, 0.09 * total, 0, "whole cells of evaluating behind the frontier cell");
  row("eval ▒ generating", 0.4 * total, 0.07 * total, 0.02 * total, "generating lands on evaluating");
  row("held ▒ generating", 0.44 * total, 0, 0.03 * total, "cache hit: nothing evaluated, so gen lands on held");
  row("three in a cell", 0.44 * total, 0.01 * total, 0.01 * total, "held, eval and gen together: gen in front, eval behind");
  row("generating", 0.4 * total, 0.09 * total, 0.08 * total, "a band of generated tokens");
  row("the last cells", 0.955 * total, 0.02 * total, 0.01 * total, "the live edge with almost no room left");
  row("full", total, 0, 0, "no free cell left");
  row("over capacity", 0.975 * total, 0.055 * total, 0.035 * total, "past n_ctx: held gives way, the live bands keep the edge");
  row("used unknown", null, 0.16 * total, 0.03 * total, "right after compaction: the live layers start at 0");
  row("one gen token", 0.4 * total, 0, 1, "the live edge is never invisible");
  row("warning", 0.74 * total, 0.02 * total, 0, "held past 70%, and the frontier follows it");
  row("error", 0.93 * total, 0.02 * total, 0, "held past 90%");

  console.log("\none request through the bar — held 1250 (mid-cell, so the frontier shows), prefill to 2450, generation to ~2850, then committed back into held");
  const base = 1250;
  const frames = [
    ["the request goes out", base, 0, 0],
    ...Array.from({ length: 8 }, (_, i) => [`prefill ${i + 1}/8`, base, (i + 1) * 150, 0]),
    ...Array.from({ length: 6 }, (_, i) => [`generate ${i + 1}/6`, base, 1200, (i + 1) * 66]),
    ["the request ends", base + 1200 + 400, 0, 0],
  ];
  for (const [what, used, evaluating, generating] of frames) console.log(`  ${what.padEnd(21)}${bar(used, evaluating, generating)}`);

  console.log("\nthe whole footer where identity has to give way to the bar");
  for (const width of [44, 58, 72]) {
    const s = SCENARIOS.find((x) => x.name === "decoding");
    console.log(`\n${"═".repeat(width)}  ${width} columns`);
    console.log(fill(metricsLine(metricGroups(s.facts), width), width));
    console.log(fill(lineOf(s, width), width));
  }

  if (!plain)
    console.log(
      `\n${colorize([{ text: "█", tone: "held" }])} held  ${colorize([{ text: "█", tone: "evaluating" }])} evaluating  ${colorize([{ text: "█", tone: "generating" }])} generating  ` +
        `${colorize([{ text: "▒", tone: "evaluating", bg: "held" }])} the newer colour over the one it lands on  ${colorize([{ text: "░", tone: "free" }])} free` +
        `  ${colorize([{ text: "█", tone: "warn" }])} past 70%  ${colorize([{ text: "█", tone: "error" }])} past 90%`,
    );
  process.exit(0);
}

for (const width of widths) {
  console.log(`\n${"═".repeat(width)}  ${width} columns`);
  for (const s of scenarios) {
    console.log(`${s.name.padEnd(15)}${fill(metricsLine(metricGroups(s.facts), width), width)}`);
    console.log(`${"".padEnd(15)}${fill(lineOf(s, width), width)}`);
  }
}
if (!plain)
  console.log(
    `\n${colorize([{ text: "█", tone: "held" }])} held  ${colorize([{ text: "█", tone: "evaluating" }])} evaluating  ${colorize([{ text: "█", tone: "generating" }])} generating  ` +
      `${colorize([{ text: "▒", tone: "evaluating", bg: "held" }])} where two layers meet  ${colorize([{ text: "░", tone: "free" }])} free   ~ = not llama.cpp's own number`,
  );
