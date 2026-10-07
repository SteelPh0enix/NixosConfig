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
  lastActivityAt: Date.now(), lastText: "", output: "out", recentOutput: "tail",
  usage: { tokens: 1, cost: 0 }, groups: [], claimed: false, ...over,
});

// ---- the completion queue (state.ts) ----

const { TaskRegistry, toSummary } = await importFrom(SRC, "state.ts");

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

const timeoutReg = new TaskRegistry();
timeoutReg.add(record("task-x"));
ok("a wait with nothing claimable ends false", (await timeoutReg.waitForCompletion(20, ["task-y"])) === false);
const controller = new AbortController();
const aborted = timeoutReg.waitForCompletion(5000, undefined, controller.signal);
controller.abort();
ok("Ctrl-C ends the wait instead of holding it", (await aborted) === false);

const done = toSummary(record("task-1", {
  state: "done", startedAt: Date.now() - 15000, finishedAt: Date.now() - 5000,
  recentOutput: "x".repeat(3000),
}));
ok("elapsed stops at the finish", done.elapsed > 4900 && done.elapsed < 5100);
ok("a running task reports its running time", toSummary(record("task-2", { startedAt: Date.now() - 3000 })).elapsed > 2900);
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
  const { renderStatusResult, renderWaitResult, renderSpawnResult, formatElapsed } = await importFrom(ws, "ui.ts");

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

  const json = (v) => JSON.stringify(v);
  const SUBAGENT_TOOLS = ["subagent_spawn", "subagent_status", "subagent_wait", "subagent_result", "subagent_kill"];
  ok("omitted tools exclude only the subagent tools", json(resolveTools({ provider: "p", model: "m" })) === json({ excludeTools: SUBAGENT_TOOLS }));
  ok("a list is an exact allowlist", json(resolveTools(subagents({}).good)) === json({ tools: ["read"], excludeTools: [] }));
  ok("enable is an allowlist too", json(resolveTools(subagents({}).enable)) === json({ tools: ["read", "grep"], excludeTools: [] }));
  ok("disable layers on the default set", json(resolveTools(subagents({}).disable)) === json({ excludeTools: [...SUBAGENT_TOOLS, "write"] }));
  ok("the subagent tools never survive an allowlist", json(resolveTools({ provider: "p", model: "m", tools: ["read", "subagent_spawn"] })) === json({ tools: ["read"], excludeTools: [] }));

  console.log("\nrenderers");
  const theme = { fg: (_token, s) => s, bold: (s) => s };
  const opts = { expanded: true, isPartial: false };
  const summary = toSummary(record("task-1", { state: "done", finishedAt: Date.now(), error: "boom", lastActivity: "read src/x.ts" }));
  const status = renderStatusResult({ content: [{ type: "text", text: "x" }], details: { count: 1, tasks: [summary] } }, opts, theme).render(120).join("\n");
  ok("the state renders as text, not [object Object]", !status.includes("[object Object]") && status.includes("DONE"));
  ok("the expanded status shows the error and the last activity", status.includes("boom") && status.includes("read src/x.ts"));
  const wait = renderWaitResult({ content: [{ type: "text", text: "x" }], details: { count: 1, tasks: [summary] } }, opts, theme).render(120).join("\n");
  ok("the wait result names the task", !wait.includes("[object Object]") && wait.includes("task-1"));
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
    on: () => {},
    events: { emit: (_channel, data) => emitted.push(data) },
  };
  (await importFrom(entry, "index.ts")).default(fakePi);
  console.warn = warn;
  ok("the five tools register", ["spawn", "status", "wait", "result", "kill"].every((n) => tools.has(`subagent_${n}`)));
  ok("the /subagents command registers", commands.has("subagents"));

  const ctx = {
    cwd: entry,
    modelRegistry: { find: (_p, model) => (model === "ok" ? {} : undefined) },
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
  ok("save_session needs a session name", await rejects("subagent_spawn", { name: "worker", task: "t", save_session: true }, "need a session name"));
  ok("workdir needs a session name", await rejects("subagent_spawn", { name: "worker", task: "t", workdir: true }, "need a session name"));
  ok("a session name must be kebab-case", await rejects("subagent_spawn", { name: "worker", task: "t", session: "Repo Scan" }, "invalid session name"));
  ok("a group nobody limited refuses the spawn", await rejects("subagent_spawn", { name: "limited", task: "t" }, "no config gives a limit"));
  ok("and does so before touching the lease store", !existsSync(join(entryAgent, "subagents", "leases.db")));

  ok("wait with nothing to wait for is not an error", (await call("subagent_wait", { timeout_s: 0 })).content[0].text.includes("no tasks to wait for"));
  ok("wait names ids it does not know", (await call("subagent_wait", { ids: ["task-9"], timeout_s: 0 })).content[0].text.includes("no such subagent tasks"));
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
