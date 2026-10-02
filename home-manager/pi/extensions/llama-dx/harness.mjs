#!/usr/bin/env node
// Dev-only: drives the extension outside pi with a stubbed ExtensionAPI, against a real llama-server, so the
// polling, the flight zone and the used-zone snapshot can be watched while an actual request runs.
//   node harness.mjs --root http://host:port --model <alias> [--seconds 30]
import llamaDx from "./index.ts";

const argv = process.argv.slice(2);
const arg = (name, fallback) => (argv.includes(`--${name}`) ? argv[argv.indexOf(`--${name}`) + 1] : fallback);
const root = arg("root", "http://steelph0enix.framework:33333");
const model = arg("model", "qwen-next");
const seconds = Number(arg("seconds", "25"));

const NOCTALIA = {
  accent: "#c4a82e", text: "#e4eaf3", dim: "#2578a9", muted: "#9b6bc1", warning: "#d14358", error: "#b32d2d",
  borderMuted: "#2578a9", success: "#00a66c",
};
const theme = {
  fg: (token, s) => {
    const hex = NOCTALIA[token] ?? "#888888";
    const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
    return `\x1b[38;2;${r};${g};${b}m${s}\x1b[0m`;
  },
};

const handlers = new Map();
const api = {
  on: (event, handler) => handlers.set(event, handler),
  registerCommand: () => {},
};

llamaDx(api);

let footer = null;
const emit = (event, ...args) => {
  const handler = handlers.get(event);
  return handler ? handler(...args) : undefined;
};
const fire = async (event, ...args) => {
  const result = await emit(event, ...args);
  void result;
};

const ctx = {
  mode: "tui",
  model: { id: model, baseUrl: `${root}/v1`, contextWindow: 262144, reasoning: true },
  thinkingLevel: "high",
  ui: { setFooter: (factory) => (footer = factory ? factory({ requestRender: () => {} }, theme, footerData) : null), notify: (m) => console.log(`notify: ${m}`) },
  sessionManager: {
    getSessionId: () => "harness",
    getLeafId: () => "leaf",
    getCwd: () => "/home/dev/src/steel-pi",
    getSessionName: () => undefined,
    getEntries: () => [{ type: "usage", usage: { input: 12200, output: 340, cacheRead: 9800 } }],
  },
  getContextUsage: () => ({ tokens: usedTokens, contextWindow: 262144, percent: 1 }),
};
let usedTokens = 9200;
const footerData = { getGitBranch: () => "master", getExtensionStatuses: () => new Map(), onBranchChange: () => () => {} };

await fire("session_start", {}, ctx);
const payload = { model, messages: [{ role: "user", content: "count to 300 out loud, one number per line" }] };
const patched = await emit("before_provider_request", { payload }, ctx);
console.log(`timings_per_token injected: ${patched?.timings_per_token === true}`);

const started = Date.now();
const tick = () => {
  if (!footer) return console.log("(no footer mounted)");
  const t = ((Date.now() - started) / 1000).toFixed(1).padStart(5);
  for (const line of footer.render(180)) console.log(`${t} │ ${line}`);
};
const timer = setInterval(tick, 700);
setTimeout(async () => {
  clearInterval(timer);
  usedTokens = 12000;
  await fire("agent_end", {});
  tick();
  process.exit(0);
}, seconds * 1000);
