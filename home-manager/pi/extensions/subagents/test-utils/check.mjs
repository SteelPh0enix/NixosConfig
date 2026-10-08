#!/usr/bin/env node
// Dev-only check for the subagents extension: the task registry, the group lease store, config validation and the
// tool renderers, all offline — no pi running and no model called.
//
//   node test-utils/check.mjs
//
// state.ts and store.ts need nothing outside node, but config.ts (`typebox`) and ui.ts (`pi-tui`) do, so they are
// copied to a scratch dir that links pi's node_modules. The location is read from the pi on PATH, or given with
// PI_NODE_MODULES=/nix/store/<hash>-pi/lib/pi/node_modules. A run prints one line per assertion and exits non-zero
// on the first failure. node:sqlite prints an ExperimentalWarning; that is expected.
import { execSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";

const SRC = new URL("..", import.meta.url).pathname;
let failed = 0;
const ok = (label, cond) => {
  if (!cond) failed += 1;
  console.log(`${cond ? "PASS" : "FAIL"}  ${label}`);
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const importFrom = (dir, file) => import(pathToFileURL(join(dir, file)).href);

const record = (id, over = {}) => ({
  id, name: "researcher", provider: "p", model: "m", taskText: "t", state: "running", startedAt: Date.now(),
  lastActivityAt: Date.now(), turns: 0, lastText: "", output: "out", recentOutput: "tail",
  usage: { tokens: 1, cost: 0 }, groups: [], claimed: false, ...over,
});

// ---- the completion queue (state.ts) ----

const { TaskRegistry, toSummary, killRecord, withTimeout } = await importFrom(SRC, "state.ts");

console.log("\nregistry");
const reg = new TaskRegistry();
reg.add(record("task-1"));
reg.add(record("task-2"));
reg.markFinished("task-1");
reg.markFinished("task-2");
ok("claimFinished(ids) claims only the named task", reg.claimFinished(["task-2"]).map((r) => r.id).join() === "task-2");
ok("a task that was not asked for stays claimable", reg.claimFinished(["task-1"]).map((r) => r.id).join() === "task-1");
ok("every task is delivered once", reg.claimFinished().length === 0);

// The bug this guards: a finish nobody waited for used to wake the wait, and the wait then threw the queued tasks away.
const waitReg = new TaskRegistry();
waitReg.add(record("task-a"));
waitReg.add(record("task-b"));
waitReg.markFinished("task-a");
let woke = "pending";
const waiting = waitReg.waitForCompletion(400, ["task-b"]).then((v) => { woke = v; });
ok("unasked-for finish is still claimable while waiting", waitReg.claimFinished(["task-a"]).length === 1);
await sleep(30);
ok("waiting for task-b ignores task-a finishing", woke === "pending");
waitReg.markFinished("task-b");
await sleep(5);
ok("waiting resolves as soon as its own task finishes", woke === true);
await waiting;

// The bug this guards: a finish nobody asked for dropped the waiter, so the task it *was* waiting for never woke it
// and the wait sat out its whole timeout.
const lateReg = new TaskRegistry();
lateReg.add(record("task-c"));
lateReg.add(record("task-d"));
const lateWait = lateReg.waitForCompletion(2000, ["task-d"]);
await sleep(10);
lateReg.markFinished("task-c");
await sleep(10);
lateReg.markFinished("task-d");
const lateAt = Date.now();
ok("a wait survives a finish it did not ask for", (await lateWait) === true && Date.now() - lateAt < 500);

// What a kill promises: never block the caller longer than it said it would.
const hungRecord = record("task-hang", { runner: { abort: async () => {}, done: () => new Promise(() => {}), releaseLeases() { this.freed = true; } } });
const killedAt = Date.now();
const settled = await killRecord(hungRecord, 40);
ok("a kill of a task that never settles returns anyway", settled === false && hungRecord.state === "killed" && Date.now() - killedAt < 1000);
ok("and hands its group slots back", hungRecord.runner.freed === true);
const cleanRecord = record("task-clean", { output: "", lastText: "what it said before stopping", runner: { abort: async () => {}, done: async () => {}, releaseLeases() {} } });
ok("a kill of a task that stops cleanly says so", (await killRecord(cleanRecord, 1000)) === true && cleanRecord.state === "killed");
ok("a killed task that had said something keeps it as its report", cleanRecord.output === "what it said before stopping");
ok("killing a finished task is not a second kill", (await killRecord(record("task-done", { state: "done" }), 10)) === true);
ok("withTimeout reports a slow promise as timed out", (await withTimeout(new Promise(() => {}), 5)) === false);
ok("withTimeout reports a rejected promise as settled", (await withTimeout(Promise.reject(new Error("boom")), 1000)) === true);

// Reading a report with `subagent_result` is a delivery too, or the task shows up again on the next wait.
const readReg = new TaskRegistry();
readReg.add(record("task-q"));
readReg.markFinished("task-q");
readReg.delivered("task-q");
ok("a task whose report was read is not handed out again by a later wait", readReg.claimFinished().length === 0);

// A kill that ran out of time marks the task killed while its runner is still going; the runner must not resurrect it.
const resurrectReg = new TaskRegistry();
const forceKilled = record("task-r", { state: "killed", finishedAt: Date.now() });
resurrectReg.add(forceKilled);
resurrectReg.markFinished("task-r");
ok("a task killed before its runner settled stays killed", forceKilled.state === "killed");

const counting = toSummary(record("task-tok", { usage: { tokens: 5000, cost: 0, generated: 1200, streaming: 80 } }));
const finishedTokens = toSummary(record("task-tok2", { state: "done", finishedAt: Date.now(), usage: { tokens: 5000, cost: 0, generated: 1200, streaming: 80 } }));
ok("a running task counts what it is still writing", counting.generated === 1280 && counting.generatedLive === true);
ok("a finished task reports the model's own figure", finishedTokens.generated === 1200 && finishedTokens.generatedLive === false);
const withContext = toSummary(record("task-ctx", { context: { tokens: 41200, contextWindow: 262144, percent: 15.7 } }));
ok("the summary carries its context window", withContext.contextTokens === 41200 && withContext.contextWindow === 262144 && withContext.contextPercent === 15.7);

const timeoutReg = new TaskRegistry();
timeoutReg.add(record("task-x"));
ok("a wait with nothing claimable ends false", (await timeoutReg.waitForCompletion(20, ["task-y"])) === false);
const controller = new AbortController();
const aborted = timeoutReg.waitForCompletion(5000, undefined, controller.signal);
controller.abort();
ok("Ctrl-C ends the wait instead of holding it", (await aborted) === false);

// `now` is pinned twice, far apart, so a summary that quietly measures from the finish cannot pass.
const endedAt = Date.now() - 5000;
const ended = record("task-1", {
  state: "done", startedAt: endedAt - 15000, finishedAt: endedAt,
  recentOutput: "x".repeat(3000),
});
const done = toSummary(ended, endedAt);
ok("elapsed is how long the task ran", done.elapsed === 15000);
ok("elapsed stops at the finish", toSummary(ended, endedAt + 60000).elapsed === 15000);
ok("a running task reports its running time", toSummary(record("task-2", { startedAt: Date.now() - 3000 })).elapsed > 2900);
const quiet = toSummary(record("task-q", { lastActivityAt: Date.now() - 20000 }));
ok("a running task says how long it has been silent", quiet.idle > 19900);
ok("a finished task is never idle", toSummary(record("task-f", { state: "done", finishedAt: Date.now() - 20000 })).idle === undefined);
ok("details carry a bounded output", done.recentOutput.length === 1000);

// ---- group leases (store.ts) ----

const { LeaseStore } = await importFrom(SRC, "store.ts");
const dbDir = mkdtempSync(join(tmpdir(), "subagents-check-"));
const store = new LeaseStore(join(dbDir, "leases.db"), "inst-A");
store.start();

console.log("\nleases");
const held = store.acquire("gpu-batch", [{ group: "gpu", limit: 1 }]);
ok("acquire holds a slot", Array.isArray(held) && held.length === 1);
ok("a full group rejects", store.acquire("gpu-batch", [{ group: "gpu", limit: 1 }]) === null);
const rows = store.list();
ok("list() names its columns the way the code reads them", rows.length === 1 && typeof rows[0].expiresAt === "number" && typeof rows[0].instanceId === "string" && rows[0].expiresAt > Date.now());
ok("a multi-group spawn that cannot fill every group fills none", store.acquire("x", [{ group: "gpu", limit: 1 }, { group: "mem", limit: 3 }]) === null && !store.list().some((l) => l.grp === "mem"));
// An expired lease is a slot somebody else may already be standing in; listing it reads as a full group.
const { DatabaseSync } = await import("node:sqlite");
const expDir = mkdtempSync(join(tmpdir(), "subagents-exp-"));
const expiring = new LeaseStore(join(expDir, "leases.db"), "inst-E");
expiring.acquire("late", [{ group: "gpu", limit: 1 }]);
new DatabaseSync(join(expDir, "leases.db")).exec("UPDATE leases SET expires_at = 1");
ok("list() hides a lease whose slot has already expired", expiring.list().length === 0);
ok("an expired lease is still reaped", expiring.reap() === 1);
expiring.close();

store.release(held[0]);
ok("release frees the slot", store.acquire("gpu-batch", [{ group: "gpu", limit: 1 }]) !== null);
store.close();
ok("close empties this instance's leases", store.list().length === 0);
let closedThrew = false;
try {
  store.acquire("x", [{ group: "gpu", limit: 1 }]);
} catch {
  closedThrew = true;
}
ok("acquire after close says so", closedThrew);
store.release(1);
store.heartbeat();
ok("a late release or heartbeat is harmless", true);

// ---- config (config.ts) and renderers (ui.ts), through pi's node_modules ----

const nodeModules = findNodeModules();
if (!nodeModules) {
  console.log("\nSKIP  config and renderers: pi's node_modules not found (set PI_NODE_MODULES)");
  failed += 1;
} else {
  const ws = mkdtempSync(join(tmpdir(), "subagents-ws-"));
  symlinkSync(nodeModules, join(ws, "node_modules"));
  for (const file of readdirSync(SRC)) if (file.endsWith(".ts")) copyFileSync(join(SRC, file), join(ws, file));

  const { loadSubagentConfigs, resolveTools } = await importFrom(ws, "config.ts");
  const { renderStatusResult, renderWaitResult, renderSpawnResult, renderKillResult, renderResultResult, formatElapsed, formatTokenStats, emitStatus, notifyCompletion, tailLines } = await importFrom(ws, "ui.ts");

  console.log("\nconfig");
  const agentDir = mkdtempSync(join(tmpdir(), "subagents-agent-"));
  const projectDir = mkdtempSync(join(tmpdir(), "subagents-project-"));
  const write = (dir, name, data) => writeFileSync(join(dir, name), JSON.stringify(data));
  const subagents = (extra) => ({
    good: { provider: "llama.cpp", model: "m", tools: ["read"] },
    enable: { provider: "llama.cpp", model: "m", tools: { enable: ["read", "grep"] } },
    disable: { provider: "llama.cpp", model: "m", tools: { disable: ["write"] } },
    grouped: { provider: "llama.cpp", model: "m", groups: ["gpu"] },
    ghost: { provider: "llama.cpp", model: "m", groups: ["nope"] },
    ...extra,
  });

  // no .pi/subagents.json yet, so only the user config is read
  write(agentDir, "subagents.json", { subagents: subagents({}), groups: { gpu: 1 } });
  const loaded = loadSubagentConfigs(projectDir, agentDir);
  ok("valid entries load", ["good", "enable", "disable", "grouped", "ghost"].every((n) => loaded.subagents.has(n)));
  ok("a group limit loads", loaded.groups.get("gpu") === 1);
  ok("an unknown group is reported", loaded.errors.some((e) => e.includes("ghost") && e.includes("unknown group")));

  write(agentDir, "subagents.json", {
    subagents: subagents({
      bothKeys: { provider: "p", model: "m", tools: { enable: ["a"], disable: ["b"] } },
      enableNotList: { provider: "p", model: "m", tools: { enable: 42 } },
      misspelled: { provider: "p", model: "m", tools: { dissable: ["x"] } },
      noModel: { provider: "p" },
      noProvider: { model: "m" },
    }),
    groups: { gpu: 1 },
  });
  const broken = loadSubagentConfigs(projectDir, agentDir);
  ok("enable and disable together are refused", !broken.subagents.has("bothKeys"));
  ok("a non-list enable is refused", !broken.subagents.has("enableNotList"));
  ok("a misspelled tool key is refused", !broken.subagents.has("misspelled"));
  ok("a missing provider or model is refused", !broken.subagents.has("noModel") && !broken.subagents.has("noProvider"));
  const rejected = ["bothKeys", "enableNotList", "misspelled", "noModel", "noProvider"];
  ok("every rejected entry is named, with a reason", rejected.every((n) => broken.errors.some((e) => e.includes(`"${n}" skipped`))) && broken.errors.filter((e) => e.includes("skipped")).length === rejected.length);
  ok("a bad tools value says what it should have been", broken.errors.some((e) => e.includes("tools must be")));
  ok("a rejected entry never reaches spawn", [...broken.subagents.keys()].join() === "good,enable,disable,grouped,ghost");

  write(agentDir, "subagents.json", { subagents: subagents({}), groups: { gpu: 1, wrong: 0 } });
  ok("one bad limit skips the whole groups map", loadSubagentConfigs(projectDir, agentDir).groups.size === 0);

  mkdirSync(join(projectDir, ".pi"), { recursive: true });
  write(agentDir, "subagents.json", { subagents: { good: { provider: "user", model: "m" }, other: { provider: "user", model: "o" } } });
  write(join(projectDir, ".pi"), "subagents.json", { subagents: { good: { provider: "project", model: "m" }, fresh: { provider: "project", model: "f" } } });
  const merged = loadSubagentConfigs(projectDir, agentDir);
  ok("a project config adds to the user one", merged.subagents.size === 3);
  ok("on a name clash the project wins", merged.subagents.get("good").provider === "project");

  // A config that cannot be read is not an empty config; loading on would hide it completely.
  const unreadable = mkdtempSync(join(tmpdir(), "subagents-unreadable-"));
  writeFileSync(join(unreadable, "subagents.json"), "{ this is not json");
  let threwLoudly = false;
  try {
    loadSubagentConfigs(mkdtempSync(join(tmpdir(), "subagents-noproj-")), unreadable);
  } catch (err) {
    threwLoudly = String(err.message).includes("could not read");
  }
  ok("a config that cannot be parsed throws instead of loading as nothing", threwLoudly);

  // Listing one group twice asks for two slots in it, which that group's own limit then refuses forever.
  const dupDir = mkdtempSync(join(tmpdir(), "subagents-dup-"));
  write(dupDir, "subagents.json", { subagents: { dupg: { provider: "p", model: "m", groups: ["gpu", "gpu", "fast"] } }, groups: { gpu: 1, fast: 2 } });
  const dupRead = loadSubagentConfigs(mkdtempSync(join(tmpdir(), "subagents-dupproj-")), dupDir);
  ok("a duplicated group is collapsed to one slot", dupRead.subagents.get("dupg").groups.join() === "gpu,fast");
  ok("and reported as a mistake in the config", dupRead.errors.some((e) => e.includes("dupg") && e.includes("more than once")));

  const json = (v) => JSON.stringify(v);
  const SUBAGENT_TOOLS = ["subagent_spawn", "subagent_status", "subagent_wait", "subagent_result", "subagent_kill"];
  ok("omitted tools exclude only the subagent tools", json(resolveTools({ provider: "p", model: "m" })) === json({ excludeTools: SUBAGENT_TOOLS }));
  ok("a list is an exact allowlist", json(resolveTools(subagents({}).good)) === json({ tools: ["read"], excludeTools: [] }));
  ok("enable is an allowlist too", json(resolveTools(subagents({}).enable)) === json({ tools: ["read", "grep"], excludeTools: [] }));
  ok("disable layers on the default set", json(resolveTools(subagents({}).disable)) === json({ excludeTools: [...SUBAGENT_TOOLS, "write"] }));
  ok("the subagent tools never survive an allowlist", json(resolveTools({ provider: "p", model: "m", tools: ["read", "subagent_spawn"] })) === json({ tools: ["read"], excludeTools: [] }));
  const main = ["read", "bash", "edit", "write", "codemode", "subagent_spawn"];
  ok("with no list the subagent inherits the main agent's tools", json(resolveTools({ provider: "p", model: "m" }, main)) === json({ tools: ["read", "bash", "edit", "write", "codemode"], excludeTools: [] }));
  ok("disable subtracts from the main agent's tools", json(resolveTools(subagents({}).disable, ["read", "bash", "write"])) === json({ tools: ["read", "bash"], excludeTools: [] }));
  ok("a tool the main agent lacks never leaks in", !JSON.stringify(resolveTools({ provider: "p", model: "m" }, ["read"])).includes("bash"));
  ok("with no view of the main session pi's own defaults stay", json(resolveTools({ provider: "p", model: "m" }, [])) === json({ excludeTools: SUBAGENT_TOOLS }));

  console.log("\nrenderers");
  const theme = { fg: (_token, s) => s, bold: (s) => s };
  const opts = { expanded: true, isPartial: false };
  // details are persisted, so a renderer has to survive a result that carries none
  for (const [name, render] of [["status", renderStatusResult], ["wait", renderWaitResult], ["kill", renderKillResult]]) {
    let survived = true;
    try {
      render({ content: [{ type: "text", text: "x" }], details: undefined }, opts, theme);
    } catch {
      survived = false;
    }
    ok(`${name} survives a result with no details`, survived);
  }
  let resultSurvived = true;
  try {
    renderResultResult({ content: [{ type: "text", text: "x" }], details: undefined }, opts, theme, { isError: false });
  } catch {
    resultSurvived = false;
  }
  ok("result survives a result with no details", resultSurvived);

  const toasts = [];
  const toastRecord = record("task-n", { state: "done", finishedAt: Date.now() });
  notifyCompletion({ ui: { notify: (m) => toasts.push(m) } }, toastRecord);
  notifyCompletion({ ui: { notify: (m) => toasts.push(m) } }, toastRecord);
  ok("a finishing task toasts once, not again when its report is read", toasts.length === 1);

  const full = { ...toSummary(record("task-stats", { usage: { tokens: 1234, cost: 0, generated: 1234 }, context: { tokens: 41200, contextWindow: 262144, percent: 15.7 } })), generatedLive: false };
  ok("tokens read as out and context fill", formatTokenStats(full) === "out 1.2k · ctx 41.2k/262k (16%)");
  ok("a count still being streamed says so", formatTokenStats({ ...full, generatedLive: true }).startsWith("out ~1.2k"));
  ok("an unknown context says what it lacks", formatTokenStats({ ...full, contextTokens: null, contextPercent: null }) === "out 1.2k · ctx ?/262k");

  const summary = toSummary(record("task-1", { state: "done", finishedAt: Date.now(), error: "boom", lastActivity: "read src/x.ts" }));
  const status = renderStatusResult({ content: [{ type: "text", text: "x" }], details: { count: 1, tasks: [summary] } }, opts, theme).render(120).join("\n");
  ok("the state renders as text, not [object Object]", !status.includes("[object Object]") && status.includes("DONE"));
  ok("the expanded status shows the error and the last activity", status.includes("boom") && status.includes("read src/x.ts"));
  const wait = renderWaitResult({ content: [{ type: "text", text: "x" }], details: { count: 1, tasks: [summary] } }, opts, theme).render(120).join("\n");
  ok("the wait result names the task", !wait.includes("[object Object]") && wait.includes("task-1"));
  const stuck = toSummary(record("task-s", { lastActivity: "retrying: Connection error.", lastActivityAt: Date.now() - 90000, retry: "2/5 after 40s" }));
  const stuckView = renderStatusResult({ content: [{ type: "text", text: "x" }], details: { count: 1, tasks: [stuck] } }, opts, theme).render(120).join("\n");
  ok("the status view names the silence and the retry", stuckView.includes("idle 1m30s") && stuckView.includes("retrying 2/5 after 40s"));

  // the live wait widget: the running subagent's own last lines, next to what it is doing
  ok("tailLines keeps the last three lines only", tailLines("a\nb\nc\nd") === "b\nc\nd" && tailLines("") === "");
  const chatter = "first thought\nsecond thought\nthird thought\nfourth thought";
  const liveTask = { ...toSummary(record("task-2", { lastText: chatter, lastActivity: "bash: nix flake check" })), preview: tailLines(chatter) };
  const liveWait = renderWaitResult({ content: [{ type: "text", text: "x" }], details: { count: 1, tasks: [liveTask] } }, { expanded: false, isPartial: true }, theme).render(120).join("\n");
  ok("a live wait shows the tail of what the subagent writes", liveWait.includes("second thought") && liveWait.includes("fourth thought") && !liveWait.includes("first thought"));
  ok("a live wait says the tasks run, not that they finished", liveWait.includes("still running") && !liveWait.includes("finished"));
  ok("a finished wait carries no preview of the report", !wait.includes("│"));
  const settledSummary = toSummary(record("task-3", { state: "done", finishedAt: Date.now() }));
  const settledCollapsed = renderWaitResult({ content: [{ type: "text", text: "x" }], details: { count: 1, tasks: [settledSummary] } }, { expanded: false, isPartial: false }, theme).render(120).join("\n");
  ok("a finished task claims no activity", !settledCollapsed.includes("▸") && settledCollapsed.includes("task-3"));
  ok("expanded, it still shows what it cost", renderStatusResult({ content: [{ type: "text", text: "x" }], details: { count: 1, tasks: [settledSummary] } }, opts, theme).render(120).join("\n").includes("0 turn(s)"));
  const timedOut = renderWaitResult({ content: [{ type: "text", text: "subagent_wait: timed out — still running: task-9 (coder)" }], details: { count: 0, tasks: [toSummary(record("task-9"))] } }, opts, theme).render(120).join("\n");
  ok("a timed-out wait says so and keeps the pending task", timedOut.includes("timed out") && timedOut.includes("task-9"));

  const { SubagentTask } = await importFrom(ws, "task.ts");
  const live = record("task-l");
  const task = new SubagentTask({ record: live, onStatus: () => {} });
  task.onEvent({ type: "turn_start" });
  ok("a turn opens as thinking", live.lastActivity === "thinking…");
  task.onEvent({ type: "auto_retry_start", attempt: 2, maxAttempts: 5, delayMs: 40000, errorMessage: "connect ECONNREFUSED 192.168.0.150:51536" });
  ok("a retry is reported with its number and delay", live.retry === "2/5 after 40s" && live.lastActivity === "retrying: connect ECONNREFUSED 192.168.0.150:51536");
  task.onEvent({ type: "message_end", message: { role: "assistant", content: [], stopReason: "error", errorMessage: "Connection error." } });
  ok("a failed model call reads as one", live.lastActivity === "model error: Connection error." && live.turns === 1);
  task.onEvent({ type: "auto_retry_end", success: true, attempt: 3 });
  ok("a recovered retry clears the flag", live.retry === undefined && live.lastActivity === "answered after 3 attempt(s)");

  const streaming = record("task-s2");
  const streamer = new SubagentTask({ record: streaming, onStatus: () => {} });
  streamer.onEvent({ type: "message_update", assistantMessageEvent: { type: "text_delta" }, message: { role: "assistant", content: [{ type: "text", text: "half a report" }] } });
  ok("the report lands in the record while it streams", streaming.lastText === "half a report");
  streamer.onEvent({ type: "tool_execution_start", toolName: "bash", args: { command: "sleep 60" } });
  streamer.applyOutcome();
  ok("a finished task stops claiming an activity", streaming.state === "done" && streaming.lastActivity === "");
  ok("a task whose last message carried no text still reports what it said", streaming.output === "half a report");

  const aborted = record("task-k2", { lastActivity: "bash: sleep 60" });
  const aborter = new SubagentTask({ record: aborted, onStatus: () => {} });
  await aborter.abort();
  // an abort arrives as an assistant error message, and must not overwrite the line the task stopped on
  aborter.onEvent({ type: "message_end", message: { role: "assistant", content: [], stopReason: "error", errorMessage: "This operation was aborted" } });
  ok("an abort never reads as a model error", aborted.lastActivity === "bash: sleep 60");
  // pi opens the next turn even when the prompt was aborted; that must not overwrite the line it stopped on
  aborter.onEvent({ type: "turn_start" });
  ok("a turn opened by the abort does not rename what it stopped on", aborted.lastActivity === "bash: sleep 60");
  aborter.applyOutcome();
  ok("an aborted task keeps the line it stopped on", aborted.state === "killed" && aborted.lastActivity === "bash: sleep 60");

  const reporting = new TaskRegistry();
  reporting.add(record("task-e"));
  let statusThrew = false;
  try {
    emitStatus({ events: { emit() { throw new Error("this ctx is stale"); } } }, reporting);
  } catch {
    statusThrew = true;
  }
  ok("reporting into a session pi has replaced does not throw", !statusThrew);

  const spawn = renderSpawnResult({ content: [{ type: "text", text: "x" }], details: { id: "task-1", name: "researcher", model: "m" } }, opts, theme).render(120).join("\n");
  ok("the spawn result reads `task-1 ← researcher (m)`", spawn.includes("task-1") && spawn.includes("researcher"));
  const blocked = renderSpawnResult({ content: [{ type: "text", text: "spawn blocked: gpu (limit 1) at capacity" }], details: { id: null, name: "g", model: "m", blocked: true } }, opts, theme).render(120).join("\n");
  ok("a blocked spawn says why", blocked.includes("gpu"));
  ok("elapsed formats as 41s / 3m12s / 1h05m", formatElapsed(41000) === "41s" && formatElapsed(192000) === "3m12s" && formatElapsed(3900000) === "1h05m");

  console.log("\nentry point");
  // The entry reads its config at load, so it gets a workspace of its own: a temp agent dir, a temp cwd, and no
  // model that resolves — every path below has to fail before a session could be created, so no server is called.
  const entry = mkdtempSync(join(tmpdir(), "subagents-entry-"));
  symlinkSync(nodeModules, join(entry, "node_modules"));
  for (const file of readdirSync(SRC)) if (file.endsWith(".ts")) copyFileSync(join(SRC, file), join(entry, file));
  const entryAgent = mkdtempSync(join(tmpdir(), "subagents-entry-agent-"));
  writeFileSync(
    join(entryAgent, "subagents.json"),
    JSON.stringify({
      subagents: {
        worker: { provider: "p", model: "nope" },
        limited: { provider: "p", model: "ok", groups: ["gpu"] },
      },
      groups: {},
    }),
  );
  process.env.PI_CODING_AGENT_DIR = entryAgent;
  process.chdir(entry);

  const tools = new Map();
  const commands = new Map();
  const notices = [];
  const emitted = [];
  // The extension warns about `limited` naming a group nobody limited; that warning is the point of the fixture.
  const warn = console.warn;
  console.warn = () => {};
  const fakePi = {
    registerTool: (tool) => tools.set(tool.name, tool),
    registerCommand: (name, def) => commands.set(name, def),
    getActiveTools: () => ["read", "bash"],
    on: () => {},
    events: { emit: (_channel, data) => emitted.push(data) },
  };
  (await importFrom(entry, "index.ts")).default(fakePi);
  console.warn = warn;
  ok("the five tools register", ["spawn", "status", "wait", "result", "kill"].every((n) => tools.has(`subagent_${n}`)));
  ok("the /subagents command registers", commands.has("subagents"));

  const registryLog = [];
  const ctx = {
    cwd: entry,
    modelRegistry: {
      refresh: (options) => (
        registryLog.push(`refresh:${options.providers.join()}:${options.force ? "force" : "lazy"}`),
        Promise.resolve({ aborted: false, errors: new Map() })
      ),
      find: (_p, model) => (registryLog.push(`find:${model}`), model === "ok" ? {} : undefined),
    },
    sessionManager: { getSessionFile: () => undefined },
    ui: { notify: (message) => notices.push(message) },
  };
  const call = (name, params, signal) => tools.get(name).execute("tc", params, signal, undefined, ctx);
  const rejects = async (name, params, needle) => {
    try {
      await call(name, params);
      return false;
    } catch (err) {
      return String(err.message).includes(needle);
    }
  };

  ok("status on an empty registry says so", (await call("subagent_status", {})).content[0].text === "no subagent tasks");
  ok("status refuses an unknown id", await rejects("subagent_status", { id: "task-9" }, "no such subagent task"));
  ok("result refuses an unknown id", await rejects("subagent_result", { id: "task-9" }, "no such subagent task"));
  ok("kill refuses an unknown id", await rejects("subagent_kill", { id: "task-9" }, "no such subagent task"));
  ok("spawn refuses an unconfigured name", await rejects("subagent_spawn", { name: "ghost", task: "t" }, "unknown subagent"));
  ok("spawn refuses a model it cannot find", await rejects("subagent_spawn", { name: "worker", task: "t" }, 'unknown model "p/nope"'));
  ok("spawn refreshed that provider first", registryLog.slice(0, 2).join("|") === "refresh:p:force|find:nope");
  ok("save_session needs a session name", await rejects("subagent_spawn", { name: "worker", task: "t", save_session: true }, "need a session name"));
  ok("workdir needs a session name", await rejects("subagent_spawn", { name: "worker", task: "t", workdir: true }, "need a session name"));
  ok("a session name must be kebab-case", await rejects("subagent_spawn", { name: "worker", task: "t", session: "Repo Scan" }, "invalid session name"));
  ok("a group nobody limited refuses the spawn", await rejects("subagent_spawn", { name: "limited", task: "t" }, "no config gives a limit"));
  ok("and does so before touching the lease store", !existsSync(join(entryAgent, "subagents", "leases.db")));

  ok("wait with nothing to wait for is not an error", (await call("subagent_wait", { timeout_s: 0 })).content[0].text.includes("no tasks to wait for"));
  ok("wait names ids it does not know", (await call("subagent_wait", { ids: ["task-9"], timeout_s: 0 })).content[0].text.includes("no such subagent tasks"));
  // Nothing running and nothing queued is not something a wait can fix by standing still.
  const idleAt = Date.now();
  const idleWait = await call("subagent_wait", { timeout_s: 30 });
  ok("waiting with nothing to wait for answers at once", idleWait.content[0].text.includes("no tasks to wait for") && Date.now() - idleAt < 1000);

  const cancelled = new AbortController();
  cancelled.abort();
  ok("an aborted wait says interrupted", (await call("subagent_wait", { timeout_s: 0 }, cancelled.signal)).content[0].text.includes("interrupted"));

  const complete = commands.get("subagents").getArgumentCompletions;
  ok("completions offer the two subcommands", complete("k").map((c) => c.value).join() === "kill" && complete("leases").map((c) => c.value).join() === "leases");
  ok("`kill ` with nothing running completes to nothing", complete("kill ").length === 0);

  const command = commands.get("subagents").handler;
  await command("", { ui: { notify: (m) => notices.push(m) } });
  ok("`/subagents` lists the tasks", notices.at(-1) === "subagents: no tasks");
  ok("listing re-emits the status snapshot", emitted.length > 0 && Array.isArray(emitted.at(-1).tasks));
  await command("leases", { ui: { notify: (m) => notices.push(m) } });
  ok("`/subagents leases` answers", String(notices.at(-1)).includes("no active leases"));
  await command("kill task-9", { ui: { notify: (m) => notices.push(m) } });
  ok("`/subagents kill` on a stray id reports it", String(notices.at(-1)).includes('no such task "task-9"'));

  rmSync(entry, { recursive: true, force: true });
  rmSync(entryAgent, { recursive: true, force: true });
  rmSync(ws, { recursive: true, force: true });
  rmSync(agentDir, { recursive: true, force: true });
  rmSync(projectDir, { recursive: true, force: true });
}

rmSync(dbDir, { recursive: true, force: true });
console.log(failed === 0 ? "\nall good" : `\n${failed} failed`);
process.exit(failed === 0 ? 0 : 1);

/** Where `typebox` and `pi-tui` live: pi's own node_modules, found through the pi on PATH. */
function findNodeModules() {
  if (process.env.PI_NODE_MODULES) return process.env.PI_NODE_MODULES;
  let dir;
  try {
    dir = dirname(realpathSync(execSync("command -v pi", { encoding: "utf8" }).trim()));
  } catch {
    return null;
  }
  for (; dir !== "/"; dir = dirname(dir)) {
    for (const cand of [join(dir, "node_modules"), join(dir, "lib", "pi", "node_modules")]) {
      if (existsSync(join(cand, "typebox")) && existsSync(join(cand, "@earendil-works", "pi-tui"))) return cand;
    }
  }
  return null;
}
