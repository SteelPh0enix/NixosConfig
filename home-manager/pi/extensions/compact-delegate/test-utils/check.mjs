#!/usr/bin/env node
// Dev-only check for the compact-delegate extension: serialization, the budget fit, the prompt, the file lists and
// config loading - all offline, no pi running and no model called.
//
//   node test-utils/check.mjs
//
// summarize.ts and config.ts import nothing at runtime (`import type` is stripped), so they load straight from the
// extension directory without pi's node_modules. A run prints one line per assertion and exits non-zero on failures.
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";

let failed = 0;
const ok = (label, cond) => {
  if (!cond) failed += 1;
  console.log(`${cond ? "PASS" : "FAIL"}  ${label}`);
};

const { serializeConversation, fitConversation, charBudget, buildSummaryRequest, carryFileOps, fileLists, formatFileLists } =
  await import(new URL("../summarize.ts", import.meta.url).href);
const { loadConfig, conflictingModel } = await import(new URL("../config.ts", import.meta.url).href);

const user = (text) => ({ role: "user", content: [{ type: "text", text }], timestamp: 0 });
const assistant = (blocks) => ({ role: "assistant", content: blocks, timestamp: 0 });
const toolResult = (text) => ({ role: "toolResult", toolCallId: "t1", toolName: "bash", content: [{ type: "text", text }], timestamp: 0 });
const ops = () => ({ read: new Set(), written: new Set(), edited: new Set() });

console.log("\nserialization");
const conversation = serializeConversation(
  [
    user("do the thing"),
    assistant([
      { type: "thinking", thinking: "x".repeat(500) },
      { type: "text", text: "on it" },
      { type: "toolCall", name: "read", arguments: { path: "a.ts" } },
    ]),
    toolResult("y".repeat(500)),
  ],
  100,
);
ok("user, thinking, speech and tool calls each get their line", [
  "[User]: do the thing",
  "[Assistant thinking]:",
  "[Assistant]: on it",
  "[Assistant tool calls]: read(path=\"a.ts\")",
  "[Tool result]:",
].every((needle) => conversation.includes(needle)));
ok("a thinking block is clipped to the cap", conversation.includes(`${"x".repeat(100)}\n\n[... 400 more characters truncated]`));
ok("a tool result is clipped to the cap", conversation.includes(`${"y".repeat(100)}\n\n[... 400 more characters truncated]`));
ok("nothing past the cap leaks through", !conversation.includes("y".repeat(101)));

console.log("\nbudget fit");
const big = [toolResult("z".repeat(100_000))];
const roomy = fitConversation(big, 10_000_000, 16000);
ok("a request with room to spare keeps the configured cap", roomy.cap === 16000 && roomy.conversation.length < 10_000_000);
const tight = fitConversation(big, 8_000, 16000);
ok("a tight budget lowers the cap", tight.cap === 4000 && tight.conversation.length <= 8_000);
ok("the cap never goes below 200 chars", fitConversation(big, 100, 16000).cap === 200);
ok("a previous summary counts against the budget", fitConversation(big, 1000, 16000, "p".repeat(10_000)).conversation.length <= 1000);
const window = 749_056;
ok("the budget for a 749k window leaves room for the summary", charBudget(window, 16384) < window * 4);
ok("the budget for a small window is still usable", charBudget(8000, 16384) === 32_000);

console.log("\nprompt");
const first = buildSummaryRequest({ conversation: "conv", cap: 16000 });
ok("the conversation is wrapped, not inlined", first.includes("<conversation>\nconv\n</conversation>"));
ok("the first summary asks for the format", first.includes("Use this EXACT format:") && first.includes("## Critical Context"));
ok("no previous-summary block when there is none", !first.includes("<previous-summary>"));
ok("the clip cap is stated to the model", first.includes("clipped at 16000 characters"));
const update = buildSummaryRequest({ conversation: "conv", previousSummary: "old", customInstructions: "keep the nix", cap: 500 });
ok("a previous summary switches to the update rules", update.includes("PRESERVE all existing information"));
ok("the previous summary travels with the request", update.includes("<previous-summary>\nold\n</previous-summary>"));
ok("custom instructions are passed on", update.includes("Additional focus: keep the nix"));

console.log("\nfile lists");
const carried = ops();
carried.read.add("kept.ts");
carryFileOps(carried, { readFiles: ["a.ts"], modifiedFiles: ["b.ts"] });
carryFileOps(carried, undefined);
carryFileOps(carried, { readFiles: "not a list" });
carried.edited.add("c.ts");
carried.written.add("d.ts");
const lists = fileLists(carried);
ok("a previous summary's files are carried forward", lists.readFiles.includes("a.ts") && lists.modifiedFiles.includes("b.ts"));
ok("malformed details are ignored rather than thrown", lists.readFiles.join() === "a.ts,kept.ts");
ok("a file both read and modified counts as modified only", !lists.readFiles.includes("c.ts"));
ok("modified wins over read", lists.modifiedFiles.join() === "b.ts,c.ts,d.ts" && !lists.readFiles.includes("c.ts"));
ok("the tags are the ones pi writes", formatFileLists(["a.ts"], ["b.ts"]) === "\n\n<read-files>\na.ts\n</read-files>\n\n<modified-files>\nb.ts\n</modified-files>");
ok("no files, no tags", formatFileLists([], []) === "");

console.log("\nconfig");
const dir = mkdtempSync("/tmp/compact-delegate-check-");
try {
  const agentDir = join(dir, "agent");
  const project = join(dir, "repo", ".pi");
  mkdirSync(agentDir, { recursive: true });
  mkdirSync(project, { recursive: true });
  const cwd = join(dir, "repo");
  const write = (path, value) => writeFileSync(path, JSON.stringify(value));

  write(join(agentDir, "subagents.json"), { subagents: { summarizer: { provider: "llama-pc", model: "sharp-spark" } } });
  const defaults = loadConfig(cwd, agentDir);
  ok("provider and model come from the summarizer subagent", defaults.config?.provider === "llama-pc" && defaults.config?.model === "sharp-spark");
  ok("defaults are stated", defaults.config?.toolResultMaxChars === 16000 && defaults.config?.maxSummaryTokens === 16384 && defaults.config?.reasoning === "off");
  ok("a config that needs no file reports no errors", defaults.errors.length === 0);

  write(join(agentDir, "compact-delegate.json"), { model: "occult-nail", maxSummaryTokens: 4096 });
  ok("the config file names over the subagent default", loadConfig(cwd, agentDir).config?.model === "occult-nail");
  ok("a value the file did not set keeps the default", loadConfig(cwd, agentDir).config?.toolResultMaxChars === 16000);

  write(join(project, "compact-delegate.json"), { model: "lfm" });
  ok("the project file wins over the user one", loadConfig(cwd, agentDir).config?.model === "lfm");
  rmSync(join(project, "compact-delegate.json"));

  write(join(agentDir, "compact-delegate.json"), { enabled: false });
  ok("enabled false means no delegation", loadConfig(cwd, agentDir).config === undefined);

  write(join(agentDir, "compact-delegate.json"), { model: "sharp-sparkk", toolResultMaxChars: 5 });
  const bad = loadConfig(cwd, agentDir);
  ok("a nonsense value is reported", bad.errors.length === 1 && bad.errors[0].includes("toolResultMaxChars"));
  ok("the usable part of a partly bad config still applies", bad.config?.model === "sharp-sparkk");

  write(join(agentDir, "compact-delegate.json"), { sumarizer: "sharp-spark" });
  ok("a key nobody spelled right is reported", loadConfig(cwd, agentDir).errors.some((e) => e.includes("sumarizer")));

  rmSync(join(agentDir, "compact-delegate.json"));
  rmSync(join(agentDir, "subagents.json"));
  const orphan = loadConfig(cwd, agentDir);
  ok("with no summarizer and no config there is no delegation", orphan.config === undefined);
  ok("and it says why", orphan.errors.some((e) => e.includes("no summarizer model")));

  writeFileSync(join(agentDir, "compact-delegate.json"), "{ not json");
  ok("a file that is not JSON is reported, not fatal", loadConfig(cwd, agentDir).errors.some((e) => e.includes("not readable JSON")));
} finally {
  rmSync(dir, { recursive: true, force: true });
}

console.log("\nresident conflict");
const busy = [
  { provider: "llama-pc", model: "cyber-tiel-coder" },
  { provider: "llama-main", model: "qwen-next" },
];
ok("another model on the summarizer's provider blocks delegation", conflictingModel(busy, "llama-pc", "sharp-spark") === "cyber-tiel-coder");
ok("a task on the summarizer's own model does not", conflictingModel([{ provider: "llama-pc", model: "sharp-spark" }], "llama-pc", "sharp-spark") === undefined);
ok("a task on another provider does not", conflictingModel(busy, "openrouter", "sharp-spark") === undefined);
ok("nothing running means delegate", conflictingModel([], "llama-pc", "sharp-spark") === undefined);

console.log(failed === 0 ? "\nall good" : `\n${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
