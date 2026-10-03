#!/usr/bin/env node
// Dev-only preview of the footer: renders the real layout at chosen widths and request phases, so the look can be
// judged in a terminal without starting pi. Imports ../layout.ts directly, which is why that file has no runtime
// imports. `node preview.mjs [--width 120,160] [--only idle,prefilling] [--plain] [--check] [--legend]`
import { metricGroups, metricsLine, baseLine, flatten } from "../layout.ts";
import { legend } from "../legend.ts";

const NOCTALIA = {
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
  used: "#c4a82e",
  flight: "#00a66c",
  free: "#2578a9",
  none: "",
};

const ansi = (hex) => {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
  return `\x1b[38;2;${r};${g};${b}m`;
};

// Only the theme tokens legend.ts reaches for.
const TOKEN = { muted: "#9bb0c7", accent: "#c4a82e", text: "#e4eaf3", dim: "#2578a9" };

const colorize = (segments) => segments.map((s) => (NOCTALIA[s.tone] ? `${ansi(NOCTALIA[s.tone])}${s.text}\x1b[0m` : s.text)).join("");
const cols = (s) => [...s].length;

const CWD = "~/src/steel-pi";
const MODEL = "qwen3-coder-27b";
const TOTAL = 262144;

const SCENARIOS = [
  { name: "idle", facts: { live: "idle", pp: 658, tg: 59, prompt: 8400, eval: 1800, reuse: 6600, out: 21, reqs: 2, sessionIn: 10200, sessionOut: 80, cacheRead: 3500, queue: 0, processing: 0, slots: 1, busy: 1, specAccepted: 13, specDrafted: 21, specLifeAccepted: 1240, specLifeDrafted: 1430, ttft: 10100, host: "fwpc:33333", slotId: 0, nTokensMax: 12300, charsPerToken: 3.9, exactTimings: true }, used: 8400, flight: 0 },
  { name: "prefilling", facts: { live: "prefill", pp: 712, ppEstimated: true, tg: 58, tgEstimated: true, prompt: 15200, promptEstimated: true, eval: 6600, reuse: 8600, out: 0, reqs: 3, sessionIn: 25400, sessionOut: 260, cacheRead: 12800, queue: 0, processing: 1, slots: 1, busy: 1, specAccepted: 22, specDrafted: 35, specLifeAccepted: 1262, specLifeDrafted: 1465, host: "fwpc:33333", slotId: 0, nTokensMax: 12300, charsPerToken: 3.9, exactTimings: false }, used: 8400, flight: 6600 },
  { name: "decoding", facts: { live: "decode", pp: 640, tg: 57.8, prompt: 15200, eval: 6600, reuse: 8600, out: 340, reqs: 3, sessionIn: 25400, sessionOut: 600, cacheRead: 12800, queue: 1, processing: 2, slots: 2, busy: 1.6, specAccepted: 190, specDrafted: 340, specLifeAccepted: 1452, specLifeDrafted: 1805, ttft: 8100, host: "fwpc:33333", slotId: 1, nTokensMax: 15900, charsPerToken: 3.9, exactTimings: true }, used: 8400, flight: 6940 },
  { name: "near full", facts: { live: "decode", pp: 412, tg: 41, prompt: 240000, eval: 12000, reuse: 228000, out: 6200, reqs: 41, sessionIn: 1200000, sessionOut: 41000, cacheRead: 998000, queue: 3, processing: 2, slots: 2, busy: 2, specAccepted: 900, specDrafted: 3100, specLifeAccepted: 9000, specLifeDrafted: 12000, ttft: 412000, host: "pc:51536", slotId: 1, nTokensMax: 262000, charsPerToken: 4.1, exactTimings: true }, used: 246200, flight: 1200 },
  { name: "just compacted", facts: { live: "prefill", pp: 588, ppEstimated: true, tg: 60, tgEstimated: true, prompt: 42000, promptEstimated: true, eval: 42000, reuse: 0, out: 0, reqs: 42, sessionIn: 1240000, sessionOut: 47000, cacheRead: 1010000, queue: 0, processing: 1, slots: 1, busy: 1, specAccepted: 4, specDrafted: 9, specLifeAccepted: 9004, specLifeDrafted: 12009, host: "pc:51536", slotId: 0, nTokensMax: 262000, charsPerToken: 4.1, exactTimings: false }, used: null, flight: 21000 },
  { name: "no --metrics", facts: { live: "decode", pp: 658, tg: 59, prompt: 8400, eval: 1800, reuse: 6600, out: 96, reqs: 4, sessionIn: 34000, sessionOut: 900, cacheRead: 21000, processing: 1, slots: 1, busy: 1, ttft: 900, host: "fwpc:33333", slotId: 0, nTokensMax: 9600, charsPerToken: 3.9, exactTimings: true }, used: 8400, flight: 96 },
];

const argv = process.argv.slice(2);
const plain = argv.includes("--plain");
const at = argv.indexOf("--width");
const widths = at === -1 ? [80, 96, 120, 160, 200] : argv[at + 1].split(",").map(Number);
const onlyAt = argv.indexOf("--only");
const only = onlyAt === -1 ? null : argv[onlyAt + 1].split(",");
const scenarios = SCENARIOS.filter((s) => !only || only.includes(s.name));

const pair = (width, s) => ({
  metrics: metricsLine(metricGroups(s.facts), width),
  base: baseLine({ width, cwd: CWD, branch: "master", model: MODEL, thinking: "high", used: s.used, flight: s.flight, total: TOTAL }),
});

if (argv.includes("--check")) {
  let bad = 0;
  for (const width of [40, 60, 80, 96, 120, 140, 160, 200, 240, 280]) {
    for (const s of SCENARIOS) {
      for (const [used, flight] of [[0, 0], [s.used, s.flight], [TOTAL, 0], [TOTAL + 9000, 9000]]) {
        const line = flatten(baseLine({ width, cwd: CWD, branch: "master", model: MODEL, thinking: "high", used, flight, total: TOTAL }));
        const metrics = flatten(metricsLine(metricGroups(s.facts), width));
        const bar = line.match(/[█▏▎▍▌▋▊▉▓░]+/)?.[0] ?? "";
        const filled = [...bar].filter((c) => c !== "░").length;
        const want = Math.min(1, ((used ?? 0) + (flight ?? 0)) / TOTAL) * bar.length;
        const problems = [
          cols(line) === width ? "" : `base ${cols(line)} != ${width}`,
          cols(metrics) <= width ? "" : `metrics ${cols(metrics)} > ${width}`,
          bar.length >= 10 ? "" : `bar ${bar.length} < 10`,
          Math.abs(filled - want) <= 1.5 ? "" : `fill ${filled} vs ${want.toFixed(1)}`,
        ].filter(Boolean);
        if (problems.length) (console.log(`${width} ${s.name} used=${used}: ${problems.join(", ")}`), bad++);
      }
    }
  }
  console.log(bad === 0 ? "layout invariants hold at every width" : `${bad} problems`);
  process.exit(bad === 0 ? 0 : 1);
}

const show = (segments, width) => (plain ? flatten(segments) : colorize([...segments, { text: " ".repeat(Math.max(0, width - cols(flatten(segments)))), tone: "none" }]));

if (argv.includes("--legend")) {
  const theme = plain ? { fg: (_token, s) => s } : { fg: (token, s) => (TOKEN[token] ? `${ansi(TOKEN[token])}${s}\x1b[0m` : s) };
  for (const width of widths) console.log(`\n${"═".repeat(width)}  ${width} columns\n${legend(theme, width)}`);
  process.exit(0);
}

for (const width of widths) {
  console.log(`\n${"═".repeat(width)}  ${width} columns`);
  for (const s of scenarios) {
    const { metrics, base } = pair(width, s);
    console.log(`${s.name.padEnd(15)}${show(metrics, width)}`);
    console.log(`${"".padEnd(15)}${show(base, width)}`);
  }
}
if (!plain) console.log(`\n\x1b[0mused\x1b[0m=KV held  \x1b[38;2;0;166;108m▓\x1b[0m flight=tokens landing now  \x1b[38;2;37;120;169m░\x1b[0m free   ~ = not llama.cpp's own number`);
