#!/usr/bin/env node
// Dev-only check: runs the whole extension against a fake llama.cpp server, so polling, the bands of a request, the
// /metrics cells and the footer hand-back can be verified offline in a few seconds.
//   node test-utils/check.mjs [--port 39451] [--dump]
// Asserts what must be visible in the footer; --dump prints it as plain text at every poll.
import llamaDx from "../index.ts";
import { agentsRow } from "../agents.ts";
import { barCells, cols, metricGroups } from "../layout.ts";
import { view } from "../state.ts";

const argv = process.argv.slice(2);
const arg = (name, fallback) => (argv.includes(`--${name}`) ? argv[argv.indexOf(`--${name}`) + 1] : fallback);
const port = Number(arg("port", "39451"));

// A 10000-token prompt of which 4000 are cached, so 6000 have to be evaluated: prefill for four answers, generation
// for four, then idle long enough for the request to be declared over. `step` is advanced by the check itself, never
// by the timers of the machine under test, and both the fake slot and the progress events the check feeds the stream
// follow it, so the two always describe the same moment.
//
// `/slots` answers the way llama.cpp does: `n_prompt_tokens` is the size of the slot's whole KV (`prompt.tokens.size()`),
// so during prefill it is the cached prefix plus what has been batched and generation keeps adding to it — it is not
// the size of this prompt, which is why the prompt total comes from `prompt_progress`. The first answer of a request
// still describes the task before it (`task_prev`), counters included.
const PROMPT = 10000;
const CACHE = 4000;
const TARGET = PROMPT - CACHE;
let step = 0;
let askedElsewhere = 0;
const script = (n) => ({ processed: Math.max(0, Math.min(TARGET, (n - 1) * 800)), decoded: n > 11 ? Math.min(120, (n - 11) * 40) : 0 });
const server = (await import("node:http")).createServer((req, res) => {
  const send = (body, type = "application/json") => (res.writeHead(200, { "content-type": type }), res.end(body));
  // Anything under /nope answers like a server that is not llama.cpp, which is how the footer hand-back is checked.
  const nope = req.url.startsWith("/nope");
  // Nothing is asked of such a server beyond the one /props that says what it is.
  if (nope && /\/(slots|metrics)(\?|$)/.test(req.url)) askedElsewhere += 1;
  // /nope3 answers /props late, so a request made just after switching to it is still running with the server's
  // identity unknown — which is the moment nothing may be asked of it.
  if (req.url.endsWith("/props")) {
    if (req.url.startsWith("/nope3")) return setTimeout(() => send("{}"), 400);
    return send(JSON.stringify(nope ? {} : { role: "router", model_alias: "qwen", chat_template_caps: {} }));
  }
  if (req.url.startsWith("/slots")) {
    const s = step > 0 ? script(step) : { processed: 2000, decoded: 80 };
    const cache = step > 0 ? CACHE : 1800;
    return send(JSON.stringify([{ id: 0, n_ctx: 262144, is_processing: step > 0 && step < 16, n_prompt_tokens: cache + s.processed + s.decoded, n_prompt_tokens_processed: s.processed, n_prompt_tokens_cache: cache, next_token: [{ n_decoded: s.decoded }] }]));
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
// pi hands every extension of a session one event bus; this is ours, so the check can report what the subagents
// extension reports and read what the footer does with it.
const channels = new Map();
llamaDx({
  on: (event, handler) => handlers.set(event, handler),
  registerCommand: (name, def) => handlers.set(`cmd:${name}`, def.handler),
  events: { emit: (channel, data) => channels.get(channel)?.(data), on: (channel, handler) => (channels.set(channel, handler), () => channels.delete(channel)) },
});

// A theme that answers like pi's but paints nothing: the assertions read the text of the two lines, and `colors`
// is there because a cell where two layers of the bar meet asks for its background.
const theme = { fg: (_token, s) => s, colors: { accent: "#c4a82e", success: "#00a66c", text: "#e4eaf3", borderMuted: "#2578a9", warning: "#d14358", error: "#b32d2d", muted: "#9b6bc1", dim: "#2578a9" }, style: (s) => s };
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
/** What the bar of the current state shows, read off the layers rather than off the glyphs. */
const bar = () => {
  const v = view();
  if (!v) return { evaluating: 0, pending: 0, generating: 0, frontier: false };
  const cells = barCells({ cells: 20, used: v.used ?? 0, evaluating: v.evaluating, pending: v.pending, generating: v.generating, total: v.total });
  const sum = (band) => cells.reduce((a, c) => a + c[band], 0);
  return { evaluating: sum("evaluating"), pending: sum("pending"), generating: sum("generating"), frontier: cells.some((c) => c.held > 0 && c.evaluating > 0) };
};

const problems = [];
const expect = (what, ok) => {
  console.log(`${ok ? "ok  " : "FAIL"} ${what}`);
  if (!ok) problems.push(what);
};
await fire("session_start", {});
expect("footer taken on a llama.cpp model", footer !== null);

await fire("before_provider_request", { payload: { model: "qwen", messages: [{ role: "user", content: "hello ".repeat(2000) }] } });
const seen = [];
const bars = [];
for (step = 0; step < 16; step++) {
  await new Promise((r) => setTimeout(r, 260));
  if (step > 0) {
    const s = script(step);
    await fire("provider_stream_event", { data: { prompt_progress: { total: PROMPT, cache: CACHE, processed: CACHE + s.processed, time_ms: step * 350 } } });
    if (step === 13)
      await fire("provider_stream_event", {
        data: { choices: [{ delta: { content: "hi" } }], timings: { cache_n: 4000, prompt_n: 6000, prompt_per_second: 712.5, predicted_n: 120, predicted_per_second: 57.5, draft_n: 90, draft_n_accepted: 54 }, usage: { prompt_tokens: PROMPT } },
      });
  }
  seen.push(lines().join("\n"));
  bars.push(bar());
}
const all = seen.join("\n");
const pfs = seen.map((s) => Number(/\bpf\s+([\d.]+)%/.exec(s)?.[1] ?? NaN));

expect("speeds stay blank until llama.cpp reports its own", /pp\s+—/.test(seen[0] ?? ""));
expect("and then keep the value llama.cpp gave", seen.slice(13).every((s) => /pp\s+713\b/.test(s)) && /tg\s+58\b/.test(seen.at(-1) ?? ""));
expect("the server cells appear once /metrics answers", /\bq\b.*\bfl\b.*\bbd\b/.test(all));
expect("prefill shows up in the evaluating layer", bars.some((b) => b.evaluating > 0 && b.generating === 0));
expect("the prompt still to evaluate is shown once llama.cpp reports the prompt size", bars[0].pending === 0 && bars[1].pending > 0 && bars[2].pending > 0);
const known = bars.slice(1); // from the first progress chunk on, the prompt total is llama.cpp's own
expect(
  "from the moment the prompt is known the forecast only shrinks, and to nothing",
  known.every((b, i) => i === 0 || known[i - 1].pending >= b.pending) && known.some((b, i) => i > 0 && b.pending < known[i - 1].pending) && known.at(-1).pending === 0,
);
expect("prefill progress is on the metrics line", /\bpf\b\s+\d/.test(all));
expect("prefill progress never falls back while the request runs", pfs.every((p, i) => Number.isNaN(p) || i === 0 || Number.isNaN(pfs[i - 1]) || p >= pfs[i - 1]));
expect("the metrics line carries no approximate marker", seen.every((s) => !/~/.test(s.split("\n")[0] ?? "")));
const doneAt = pfs.findIndex((_, i) => script(i).processed >= TARGET);
const fullAt = pfs.findIndex((p) => p >= 100);
expect(`prefill progress reads 100% exactly when the prompt is evaluated (seen at ${fullAt}, done at ${doneAt})`, fullAt === doneAt && fullAt > 0 && pfs.every((p, i) => Number.isNaN(p) || (i < fullAt ? p < 100 : p >= 100)));
expect("the whole prompt is known before prefill ends", /\bfp\s+10k\b/.test(seen[5] ?? ""));
expect("generation shows up in its own layer", bars.some((b) => b.generating > 0));
expect("the live layer lands on the held one, sharing a cell", bars.some((b) => b.frontier));
expect("the prompt size is blank until llama.cpp reports it", /\bfp\s+—/.test(seen[0] ?? "") && /\bfp\s+10k\b/.test(all));
expect("and it is llama.cpp's own number once reported", /\bfp\s+10k\b/.test(seen.at(-1) ?? ""));
expect("time to first token is measured", /\btt\b\s+\S/.test(all));
expect("the footer stays mounted while it is llama.cpp", footer !== null);

// The row of running subagents, reported the way the subagents extension reports it.
/** Whether these fragments appear in this order — the cells of a line are separated by as much as the layout wants. */
const inOrder = (line, ...parts) => {
  let at = 0;
  return parts.every((part) => {
    const found = line.indexOf(part, at);
    at = found === -1 ? line.length : found + part.length;
    return found !== -1;
  });
};
const render120 = () => footer.render(120);
const without = render120();
const report = (tasks) => channels.get("subagents:status")?.({ tasks });
report(undefined);
expect("a snapshot of nothing leaves the footer alone", render120().length === without.length);
report([{ id: "task-1", name: "researcher", state: "running", elapsed: 12_000, idle: 1_000, lastActivity: "bash: nix flake check" }, { id: "task-2", name: "coder", state: "running", elapsed: 192_000, idle: 40_000, lastActivity: "edit home-manager/pi/subagents/ui.ts", slot: { index: 2, total: 2 } }]);
const row = render120();
// the two lines of llama.cpp stay where they were, one place further down
expect("the subagent row sits above the two lines", row.length === without.length + 1 && row[0].startsWith("subagents 2") && row[1].includes("pp") && row[2].includes("/home/dev/src"));
const wide = footer.render(200)[0];
expect("a task says who it is, how long it runs and what it is busy with", inOrder(wide, "task-2 coder 2/2", "3m12s", "edit home-manager/pi/subagents/ui…") && inOrder(wide, "task-1 researcher", "12s", "bash: nix flake check"));
expect("what a task is doing is told in a fixed number of columns", /edit home-manager\/pi\/subagents\/ui…/.test(wide));
expect("a task silent this long is called out next to its age", inOrder(wide, "3m12s idle 40s") && !/idle 1s/.test(wide));
expect("a narrower row drops the tasks it has no room for, from the right", row[0].includes("task-1") && !row[0].includes("task-2"));
expect("the row never runs past the width it is given", [40, 56, 80, 120, 200].every((width) => cols(footer.render(width)[0]) <= width));
const cramped = footer.render(40)[0];
expect("and when tasks no longer fit, the count is what stays", cramped.startsWith("subagents 2") && !cramped.includes("task-2"));
report([{ id: "task-3", name: "reviewer", state: "running", elapsed: 3_900_000, idle: 2_000, retry: "2/5 after 40s" }]);
expect("a task being retried says so, and for how long it has been at it", inOrder(render120()[0], "task-3 reviewer", "1h05m", "retrying 2/5 after 40s"));
report([{ id: "task-5", name: "coder", state: "running", elapsed: 8_000, idle: 1_000, tool: { name: "bash", summary: "nix build .#foo", elapsed: 4_200 }, generated: 1_240, generatedLive: true, contextTokens: 41_200, contextWindow: 262_144, contextPercent: 15.7 }]);
const rich = footer.render(200)[0];
expect("a running tool is named with its live timer", inOrder(rich, "task-5 coder", "bash: nix build .#foo", "(") && /\(\d/.test(rich));
expect("and what its model produced and how full its context is ride along", inOrder(rich, "out ~1.2k", "ctx 41k/262k"));
report([{ id: "task-6", name: "generalist", state: "running", elapsed: 2_000, generated: 9_000, contextTokens: 200_000, contextWindow: 262_144, contextPercent: 76.3 }]);
expect("a task's own context past 70% is called out", (agentsRow(200) ?? []).some((s) => s.tone === "warn" && s.text.includes("200k/262k")));
report([]);
expect("the row goes away with the last task", render120().length === without.length && !render120().join("\n").includes("subagents "));

await fire("agent_end", {});
const done = lines()[0];
expect("the request is counted", /#1/.test(done));
expect("what a finished request committed joins the held layer", /15,320/.test(lines()[1] ?? ""));

// The spent script leaves the fake answering idle with the finished task's counters, which is what a queued request
// or a loading model looks like: nothing of this request has happened yet, so nothing about it may be counted.
await fire("before_provider_request", { payload: { model: "qwen", messages: [{ role: "user", content: "hello ".repeat(2000) }] } });
// llama.cpp repeats `timings` after every chunk, with `prompt_n` counting only what it has evaluated *so far*. Taking
// that partial set for the whole prompt is what used to make `pf` jump to 100% halfway through prefill.
await fire("provider_stream_event", { data: { prompt_progress: { total: PROMPT, cache: CACHE, processed: CACHE + 1600, time_ms: 900 } } });
await fire("provider_stream_event", { data: { timings: { cache_n: CACHE, prompt_n: 1600, prompt_per_second: 712.5 } } });
const partial = lines()[0];
await new Promise((r) => setTimeout(r, 2400));
expect("a running request's partial timings do not become its whole prompt", /\bfp\s+10k\b/.test(partial) && /\bpf\s+26\.7%/.test(partial));
expect("a slot that has never been seen busy neither ends the request nor lends it the last one's counters", /#1\b/.test(lines()[0]));
await fire("agent_end", {});
expect("and it is counted once pi's turn ends", /#2\b/.test(lines()[0]));

// Compaction runs its summarizer outside the request pipeline, so llama-dx hears about it only on pi's own events.
await fire("session_before_compact", { preparation: { tokensBefore: 198_000 }, reason: "threshold", willRetry: false });
const during = lines();
expect("a compaction leads the metrics line while it runs", /compact\s+threshold\s+before\s+198k/.test(during[0] ?? ""));
expect("and the bar holds at the context being rewritten", /198,000/.test(during[1] ?? ""));
await fire("session_compact", { compactionEntry: {}, fromExtension: false, reason: "threshold", willRetry: false });
const compacted = lines();
expect("a finished compaction drops the stale request so the bar reads the new context", !/compact\s+threshold/.test(compacted[0] ?? "") && /9,200/.test(compacted[1] ?? "") && !/198,000/.test(compacted[1] ?? ""));
await fire("session_before_compact", { preparation: { tokensBefore: 120_000 }, reason: "manual", willRetry: false });
expect("an aborted compaction is shown while it is attempted", /compact\s+manual/.test(lines()[0] ?? ""));
await fire("session_compact_failed", { reason: "manual", aborted: true, willRetry: false, fromExtension: false });
expect("and failing only clears the indicator", !/compact\s+manual/.test(lines()[0] ?? ""));

// pi loads extensions into every session it makes, including the in-memory ones another extension creates (a
// subagent's). Those share this module, so they may not drive these cells nor be remembered as "the" context.
const bg = {
  ...ctx,
  mode: "print",
  model: { id: "other", baseUrl: `http://127.0.0.1:${port}/v1`, contextWindow: 140000, reasoning: true },
  sessionManager: { ...ctx.sessionManager, getCwd: () => "/home/dev/subagent" },
  getContextUsage: () => ({ tokens: 140000, contextWindow: 140000, percent: 100 }),
};
for (const [event, arg] of [
  ["session_start", {}],
  ["before_provider_request", { payload: { model: "other", messages: [] } }],
  ["provider_stream_event", { data: { prompt_progress: { total: 900, cache: 0, processed: 450 } } }],
  ["agent_end", {}],
]) {
  await handlers.get(event)?.(arg, bg);
}
expect("a background session leaves the counter alone", /#2\b/.test(lines()[0]));
expect("and never becomes the session the footer reads", !lines().join("\n").includes("/home/dev/subagent"));

// The context of a session pi has already thrown away: reading it throws, and the footer renders on a timer.
await fire("model_select", {}); // re-bind, so the ctx broken below is the one the footer holds
const fields = { cwd: ctx.cwd, mode: ctx.mode, sessionManager: ctx.sessionManager, model: ctx.model };
for (const name of Object.keys(fields)) {
  Object.defineProperty(ctx, name, { configurable: true, get() { throw new Error("this ctx is stale"); } });
}
let threw = false;
try {
  lines();
} catch {
  threw = true;
}
for (const [name, value] of Object.entries(fields)) {
  delete ctx[name];
  ctx[name] = value;
}
expect("a ctx pi invalidated leaves the line instead of killing it", !threw);
await fire("model_select", {});

// The row belongs to the session that reported it, and this module outlives that session.
report([{ id: "task-4", name: "coder", state: "running", elapsed: 5_000, idle: 5_000, lastActivity: "thinking…" }]);
await fire("model_select", {});
expect("switching pi's model keeps the row of subagents", render120()[0].startsWith("subagents 1"));
await fire("session_start", {});
expect("a new session starts with no row of the tasks the session before it ran", !render120().join("\n").includes("subagents "));

// Every indicator the line can hold has to be explained by `/llama-dx info`: two places, one set of cells.
await handlers.get("cmd:llama-dx")("info", ctx);
const explained = new Set((notes.at(-1) ?? "").split("\n").map((l) => /^ {2}(\S+)\s{2}/.exec(l)?.[1]).filter(Boolean));
const cells = new Set(
  metricGroups({ ...view()?.facts }).flatMap((g) => g.cells.flatMap((c) => c.filter((s) => s.tone === "label").map((s) => s.text.trim()))),
);
const missing = [...cells].filter((c) => !explained.has(c));
expect(`every indicator on the line is explained (${missing.join(" ") || "all"})`, cells.size >= 15 && missing.length === 0);
expect("the — and bright markers are explained too", explained.has("—") && explained.has("bright"));

await handlers.get("cmd:llama-dx")("reset", ctx);
expect("reset zeroes the counter", notes.at(-1)?.includes("cleared"));

ctx.model = { ...ctx.model, baseUrl: `http://127.0.0.1:${port}/nope/v1` };
await fire("model_select", {}, ctx);
await new Promise((r) => setTimeout(r, 300)); // the /props probe answers asynchronously
expect("a non-llama.cpp model hands the footer back", footer === null);
// Not reaching a server says nothing about what it is, so it is not the moment to hand the footer back either: the
// root stays unknown, the line survives, and the probe asks again instead of settling for a guess.
ctx.model = { ...ctx.model, baseUrl: "http://127.0.0.1:1/v1" };
await fire("model_select", {}, ctx);
await new Promise((r) => setTimeout(r, 300));
expect("an unreachable server leaves the footer alone", footer !== null);
// Handing the footer back is only half of it: the polling and the scraping have to stop going there as well —
// including for a second server whose /props probe is still on its way while the request goes out.
await fire("before_provider_request", { payload: { model: "somewhere-else", messages: [] } }, ctx);
ctx.model = { ...ctx.model, baseUrl: `http://127.0.0.1:${port}/nope3/v1` };
void fire("model_select", {}, ctx);
await fire("before_provider_request", { payload: { model: "somewhere-else", messages: [] } }, ctx);
await new Promise((r) => setTimeout(r, 2400));
expect("and nothing is ever scraped from it, nor before /props has said what it is", askedElsewhere === 0);
await fire("session_shutdown", {});
server.close();

if (argv.includes("--dump")) console.log(`\n${seen.map((s, i) => `${String(i + 1).padStart(2)} │ ${s.replace(/\n/g, "\n   │ ")}`).join("\n")}`);
console.log(problems.length === 0 ? "\neverything holds" : `\n${problems.length} failed`);
process.exit(problems.length === 0 ? 0 : 1);
