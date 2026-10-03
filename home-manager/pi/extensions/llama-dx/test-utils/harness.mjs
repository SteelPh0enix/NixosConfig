#!/usr/bin/env node
// Dev-only: drives the extension outside pi with a stubbed ExtensionAPI, against a real llama-server, so the
// polling, the bands of a running request and the held band can be watched live. A cold instance
// is included in `--seconds`: the first tick shows the model loading, then prefill, then generation.
//   node test-utils/harness.mjs [--root http://steelph0enix.pc:51536] [--model qwen-27B] [--ctx 32768] [--seconds 75]
import llamaDx from "../index.ts";

const argv = process.argv.slice(2);
const arg = (name, fallback) => (argv.includes(`--${name}`) ? argv[argv.indexOf(`--${name}`) + 1] : fallback);
const root = arg("root", "http://steelph0enix.pc:51536");
const model = arg("model", "qwen-27B");
const nCtx = Number(arg("ctx", "32768"));
const seconds = Number(arg("seconds", "75"));

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
  model: { id: model, baseUrl: `${root}/v1`, contextWindow: nCtx, reasoning: true },
  thinkingLevel: "high",
  ui: { setFooter: (factory) => (footer = factory ? factory({ requestRender: () => {} }, theme, footerData) : null), notify: (m) => console.log(`notify: ${m}`) },
  sessionManager: {
    getSessionId: () => "harness",
    getLeafId: () => "leaf",
    getCwd: () => "/home/dev/src/steel-pi",
    getSessionName: () => undefined,
    getEntries: () => [{ type: "usage", usage: { input: 12200, output: 340, cacheRead: 9800 } }],
  },
  getContextUsage: () => ({ tokens: usedTokens, contextWindow: nCtx, percent: 1 }),
};
let usedTokens = 9200;
const footerData = { getGitBranch: () => "master", getExtensionStatuses: () => new Map(), onBranchChange: () => () => {} };

await fire("session_start", {}, ctx);
// `--repeat` stretches the prompt so prefill is long enough to watch and to measure.
const ask = arg("prompt", "count to 200 out loud, one number per line");
const again = Number(arg("repeat", "0"));
const payload = { model, messages: [{ role: "user", content: Array(again + 1).fill(ask).join(" ") }] };
const patched = await emit("before_provider_request", { payload }, ctx);
console.log(`timings_per_token injected: ${patched?.timings_per_token === true}`);

const started = Date.now();
const tick = () => {
  if (!footer) return console.log("(no footer mounted)");
  const t = ((Date.now() - started) / 1000).toFixed(1).padStart(5);
  for (const line of footer.render(180)) console.log(`${t} │ ${line}`);
};
const stop = async () => {
  clearInterval(timer);
  clearTimeout(limit);
  usedTokens = Math.min(nCtx, usedTokens + 3000); // pi would have recorded the answer by now
  await fire("agent_end", {});
  tick();
  process.exit(0);
};
const timer = setInterval(tick, 700);
const limit = setTimeout(() => {
  console.log(`stopped after ${seconds}s`);
  void stop();
}, seconds * 1000);

if (!patched) {
  console.log("the extension left the request alone: not a llama.cpp model");
  await stop();
}

// The harness is the transport pi would otherwise be: it sends what the extension handed over and feeds every
// chunk back, which is the only way the stream's own timings and usage reach the cells.
const response = await fetch(`${root}/v1/chat/completions`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ ...patched, stream: true, stream_options: { include_usage: true }, max_tokens: Number(arg("max-tokens", "200")) }),
  signal: AbortSignal.timeout(seconds * 1000 + 5000),
}).catch((e) => ({ status: `failed: ${e.message}` }));
if (response.status !== 200) {
  console.log(`request ${response.status}`);
  await stop();
}

let buffer = "";
let chars = 0;
let finish = null;
let timings = null;
let usage = null;
for await (const bytes of response.body) {
  buffer += new TextDecoder().decode(bytes, { stream: true });
  const lines = buffer.split("\n");
  buffer = lines.pop() ?? "";
  for (const line of lines) {
    if (!line.startsWith("data: ")) continue;
    const body = line.slice(6);
    if (body === "[DONE]") continue;
    const chunk = JSON.parse(body);
    chars += chunk.choices?.[0]?.delta?.content?.length ?? 0;
    finish ??= chunk.choices?.[0]?.finish_reason ?? null;
    if (chunk.timings) timings = chunk.timings; // the last one is the complete set
    if (chunk.usage) usage = chunk.usage;
    await fire("provider_stream_event", { data: chunk });
  }
}
console.log(`streamed ${chars} chars finish=${finish}`);
console.log(`usage=${JSON.stringify(usage)}\ntimings=${JSON.stringify(timings)}`);
await stop();
