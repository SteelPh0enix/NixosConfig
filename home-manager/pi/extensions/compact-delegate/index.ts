// compact-delegate: another model writes the session summary.
//
// pi compacts by asking the *session* model to summarize the part of the
// conversation it is about to drop, and it clips every tool result to 2000
// characters so that request still fits the window it just ran out of. Answering
// `session_before_compact` here asks a model with a far larger window instead -
// the summarizer subagent's model by default - and hands it roomy tool results,
// so the summary keeps details that would otherwise be gone before the main model
// ever read them.
//
// Everything else stays pi's: the trigger, the cut point, the structured format,
// the entry it writes. On any problem this handler returns nothing and pi's own
// compaction runs as though the extension were not installed.

import { uuidv7, type ThinkingLevel } from "@earendil-works/pi-ai";
import {
  convertToLlm,
  getAgentDir,
  getLatestCompactionEntry,
  type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";
import { conflictingModel, loadConfig } from "./config.ts";
import {
  buildSummaryRequest,
  carryFileOps,
  charBudget,
  fileLists,
  fitConversation,
  formatFileLists,
  SUMMARIZATION_SYSTEM_PROMPT,
} from "./summarize.ts";

const k = (chars: number) => `${Math.round(chars / 4000)}k`;

export default function (pi: ExtensionAPI) {
  const { config, errors } = loadConfig(process.cwd(), getAgentDir());

  // What the subagents extension says is running: a llama.cpp server keeps one preset resident, so summarizing on a
  // different model of the same provider would swap a running task's model out from under it.
  let busy: Array<{ provider: string; model: string }> = [];
  pi.events.on("subagents:status", (data) => {
    const tasks = (data as { tasks?: Array<{ provider?: string; model?: string }> })?.tasks;
    if (!Array.isArray(tasks)) return;
    busy = tasks
      .filter((task): task is { provider: string; model: string } => typeof task.provider === "string" && typeof task.model === "string")
      .map((task) => ({ provider: task.provider, model: task.model }));
  });

  pi.on("session_start", async (_event, ctx) => {
    for (const error of errors) ctx.ui.notify(`compact-delegate: ${error}`, "warning");
  });

  pi.registerCommand("compact-delegate", {
    description: "show which model writes session summaries",
    handler: async (_args, ctx) => {
      if (!config) {
        ctx.ui.notify("compact-delegate: off (no usable provider/model in compact-delegate.json)", "warning");
        return;
      }
      const found = ctx.modelRegistry.find(config.provider, config.model);
      const window = found ? `, ${Math.round(found.contextWindow / 1000)}k window` : "";
      const state = found ? "ready" : "model not available - pi compacts";
      ctx.ui.notify(
        `compact-delegate: ${config.provider}/${config.model}${window}; blocks clipped at ${config.toolResultMaxChars} chars, summary up to ${config.maxSummaryTokens} tokens, thinking ${config.reasoning} (${state})`,
        "info",
      );
    },
  });

  pi.on("session_before_compact", async (event, ctx) => {
    if (!config) return;
    const { preparation, customInstructions, signal } = event;
    const messages = [...preparation.messagesToSummarize, ...preparation.turnPrefixMessages];
    if (messages.length === 0) return;

    const held = conflictingModel(busy, config.provider, config.model);
    if (held) {
      ctx.ui.notify(`compact-delegate: ${config.provider} is busy with ${held}, using pi's compaction`, "info");
      return;
    }

    const model = ctx.modelRegistry.find(config.provider, config.model);
    if (!model) {
      ctx.ui.notify(`compact-delegate: ${config.provider}/${config.model} is unavailable, using pi's compaction`, "warning");
      return;
    }

    // pi only carries file lists forward out of compactions it wrote itself, so
    // the ones recorded by an earlier summary of ours are merged in here.
    carryFileOps(preparation.fileOps, getLatestCompactionEntry(event.branchEntries)?.details);

    // Custom entries (bash runs, custom messages) only have meaning as LLM messages.
    const previousSummary = preparation.previousSummary;
    const { conversation, cap } = fitConversation(
      convertToLlm(messages),
      charBudget(model.contextWindow, config.maxSummaryTokens),
      config.toolResultMaxChars,
      previousSummary ?? "",
    );
    const prompt = buildSummaryRequest({ conversation, previousSummary, customInstructions, cap });
    const started = Date.now();
    ctx.ui.notify(`compact-delegate: ~${k(conversation.length)} tok to ${config.provider}/${config.model} (${messages.length} messages)`, "info");

    try {
      const response = await ctx.modelRegistry
        .streamSimple(
          model,
          {
            systemPrompt: SUMMARIZATION_SYSTEM_PROMPT,
            messages: [{ role: "user", content: [{ type: "text", text: prompt }], timestamp: Date.now() }],
          },
          {
            maxTokens: config.maxSummaryTokens,
            signal,
            cacheRetention: "none",
            sessionId: uuidv7(),
            ...(config.reasoning === "off" ? {} : { reasoning: config.reasoning as ThinkingLevel }),
          },
        )
        .result();

      // A summary cut off by the output cap is a partial checkpoint, and pi refuses
      // to persist one; going back to pi's own compaction keeps a complete one.
      if (response.stopReason === "length") throw new Error("the summary hit its output cap");
      if (response.stopReason === "error") throw new Error(response.errorMessage || "the summarizer request failed");
      const summary = response.content
        .filter((block) => block.type === "text")
        .map((block) => (block.type === "text" ? block.text : ""))
        .join("\n")
        .trim();
      if (!summary) throw new Error("the summarizer returned no text");

      const files = fileLists(preparation.fileOps);
      const seconds = Math.round((Date.now() - started) / 1000);
      ctx.ui.notify(
        `compact-delegate: summary after ${seconds}s (~${response.usage.output} tok out, cap ${cap} chars)`,
        "info",
      );
      return {
        compaction: {
          summary: summary + formatFileLists(files.readFiles, files.modifiedFiles),
          firstKeptEntryId: preparation.firstKeptEntryId,
          tokensBefore: preparation.tokensBefore,
          usage: response.usage,
          details: files,
        },
      };
    } catch (err) {
      if (signal.aborted) return { cancel: true };
      ctx.ui.notify(
        `compact-delegate: ${(err as Error).message}; falling back to pi's compaction`,
        "warning",
      );
      return;
    }
  });
}
