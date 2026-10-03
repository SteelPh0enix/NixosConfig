#!/usr/bin/env node
// Dev-only check: runs the whole extension against a fake llama.cpp server, so polling, the flight zone, the
// /metrics cells and the footer hand-back can be verified offline in a few seconds.
//   node test-utils/check.mjs [--port 39451] [--dump]
// Asserts what must be visible in the footer; --dump prints it as plain text at every poll.
import llamaDx from "../index.ts";
import { metricGroups } from "../layout.ts";
import { view } from "../state.ts";

const argv = process.argv.slice(2);
const arg = (name, fallback) => (argv.includes(`--${name}`) ? argv[argv.indexOf(`--${name}`) + 1] : fallback);
const port = Number(arg("port", "39451"));

// The fake server answers by how many times /slots has been polled, so the request always takes the same steps:
// prefill for four polls, generation for four, then idle long enough for the request to be declared over.
let polls = 0;
const server = (await import("node:http")).createServer((req, res) => {
  const send = (body, type = "application/json") => (res.writeHead(200, { "content-type": type }), res.end(body));
  // Anything under /nope answers like a server that is not llama.cpp, which is how the footer hand-back is checked.
  const nope = req.url.startsWith("/nope");
  if (req.url.endsWith("/props")) return send(JSON.stringify(nope ? {} : { role: "router", model_alias: "qwen", chat_template_caps: {} }));
  if (req.url.startsWith("/slots")) {
    const processed = Math.min(6000, polls * 1600);
    const decoded = polls > 8 ? Math.min(120, (polls - 8) * 40) : 0;
    return send(JSON.stringify([{ id: 0, n_ctx: 262144, is_processing: polls < 12, n_prompt_tokens: processed + decoded, n_prompt_tokens_processed: processed, n_prompt_tokens_cache: 4000, next_token: [{ n_decoded: decoded }] }]));
  }
  if (req.url.startsWith("/metrics"))
    return send(
      ["llamacpp:requests_deferred 3", "llamacpp:requests_processing 1", "llamacpp:n_busy_slots_per_decode 1.50", "llamacpp:spec_decode_num_accepted_tokens_total 120", "llamacpp:spec_decode_num_draft_tokens_total 200", "llamacpp:n_tokens_max 12000"].join("\n"),
      "text/plain",
    );
  res.writeHead(404);
  res.end("{}");
});
await new Promise((r) => server.listen(port, "127.0.0.1", r));

const handlers = new Map();
llamaDx({ on: (event, handler) => handlers.set(event, handler), registerCommand: (name, def) => handlers.set(`cmd:${name}`, def.handler) });

const theme = { fg: (_token, s) => s };
let footer = null;
const footerData = { getGitBranch: () => "master", getExtensionStatuses: () => new Map(), onBranchChange: () => () => {} };
const ctx = {
  mode: "tui",
  model: { id: "qwen", baseUrl: `http://127.0.0.1:${port}/v1`, contextWindow: 262144, reasoning: true },
  thinkingLevel: "high",
  ui: { setFooter: (f) => (footer = f ? f({ requestRender: () => {} }, theme, footerData) : null), notify: (m) => notes.push(m), theme },
  sessionManager: { getSessionId: () => "s", getLeafId: () => "l", getCwd: () => "/home/dev/src", getEntries: () => [{ type: "usage", usage: { input: 12200, output: 340, cacheRead: 9800 } }] },
  getContextUsage: () => ({ tokens: 9200, contextWindow: 262144, percent: 1 }),
};
const notes = [];
const fire = async (event, ...rest) => handlers.get(event)?.(...rest, ctx);
const lines = () => (footer === null ? ["(no footer)"] : footer.render(200));

const problems = [];
const expect = (what, ok) => {
  console.log(`${ok ? "ok  " : "FAIL"} ${what}`);
  if (!ok) problems.push(what);
};
/** The cells of the last rendered metrics line, e.g. `pp`, `q`, `tt`. */
const shown = () => lines()[0];

await fire("session_start", {});
expect("footer taken on a llama.cpp model", footer !== null);

await fire("before_provider_request", { payload: { model: "qwen", messages: [{ role: "user", content: "hello ".repeat(2000) }] } });
const seen = [];
for (let i = 0; i < 14; i++) {
  await new Promise((r) => setTimeout(r, 260));
  polls += 1;
  seen.push(lines().join("\n"));
  if (polls === 10)
    await fire("provider_stream_event", {
      data: { choices: [{ delta: { content: "hi" } }], timings: { cache_n: 4000, prompt_n: 6000, prompt_per_second: 712.5, predicted_n: 120, predicted_per_second: 57.5, draft_n: 90, draft_n_accepted: 54 }, usage: { prompt_tokens: 10000 } },
    });
}
const all = seen.join("\n");

expect("the live pp rate is marked as not the server's own", /pp ?~\s*[\d.]+/.test(all));
expect("the server's own speeds replace it once timings arrive", /pp\s+713\b.*tg\s+58\b/.test(seen.at(-1) ?? ""));
expect("the server cells appear once /metrics answers", /\bq\b.*\bfl\b.*\bbd\b/.test(all));
expect("prefill shows up in the flight zone", /[▓▊▋▌▍▎▏]/.test(all));
expect("the prompt size is estimated first", /fp ~\s*[\d.]+/.test(all));
expect("and is replaced by llama.cpp's exact number", /fp\s+10k\b/.test(seen.at(-1) ?? ""));
expect("time to first token is measured", /\btt\b\s+\S/.test(all));
expect("the footer stays mounted while it is llama.cpp", footer !== null);

await fire("agent_end", {});
const done = shown();
expect("the request is counted", /#1/.test(done));

// Every indicator the line can hold has to be explained by `/llama-dx info`: two places, one set of cells.
await handlers.get("cmd:llama-dx")("info", ctx);
const explained = new Set((notes.at(-1) ?? "").split("\n").map((l) => /^ {2}(\S+)\s{2}/.exec(l)?.[1]).filter(Boolean));
const cells = new Set(
  metricGroups({ ...view()?.facts }).flatMap((g) => g.cells.flatMap((c) => c.filter((s) => s.tone === "label").map((s) => s.text.trim()))),
);
const missing = [...cells].filter((c) => !explained.has(c));
expect(`every indicator on the line is explained (${missing.join(" ") || "all"})`, cells.size >= 15 && missing.length === 0);
expect("the ~ , — and bright markers are explained too", explained.has("~") && explained.has("—") && explained.has("bright"));

await handlers.get("cmd:llama-dx")("reset", ctx);
expect("reset zeroes the counter", notes.at(-1)?.includes("cleared"));

ctx.model = { ...ctx.model, baseUrl: `http://127.0.0.1:${port}/nope/v1` };
await fire("model_select", {}, ctx);
await new Promise((r) => setTimeout(r, 300)); // the /props probe answers asynchronously
expect("a non-llama.cpp model hands the footer back", footer === null);
await fire("session_shutdown", {});
server.close();

if (argv.includes("--dump")) console.log(`\n${seen.map((s, i) => `${String(i + 1).padStart(2)} │ ${s.replace(/\n/g, "\n   │ ")}`).join("\n")}`);
console.log(problems.length === 0 ? "\neverything holds" : `\n${problems.length} failed`);
process.exit(problems.length === 0 ? 0 : 1);
