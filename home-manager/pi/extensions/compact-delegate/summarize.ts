// The text the summarizer reads, and what it is asked to do with it.
//
// No pi imports in this file on purpose: test-utils/check.mjs exercises it with
// plain node. The section format is pi's documented one, since it is the *main*
// model that reads the summary back - changing it here changes what that model
// finds after a compaction.

import type { Message } from "@earendil-works/pi-ai";

export const SUMMARIZATION_SYSTEM_PROMPT =
  "You are a context summarization assistant. Your task is to read a conversation between a user and an AI assistant, then produce a structured summary following the exact format specified.\n\nDo NOT continue the conversation. Do NOT respond to any questions in the conversation. ONLY output the structured summary.";

const SECTIONS = `## Goal
[What is the user trying to accomplish? Can be multiple items if the session covers different tasks.]

## Constraints & Preferences
- [Any constraints, preferences, or requirements mentioned by user]
- [Or "(none)" if none were mentioned]

## Progress
### Done
- [x] [Completed tasks/changes]

### In Progress
- [ ] [Current work]

### Blocked
- [Issues preventing progress, if any]

## Key Decisions
- **[Decision]**: [Brief rationale]

## Next Steps
1. [Ordered list of what should happen next]

## Critical Context
- [Any data, examples, or references needed to continue]
- [Or "(none)" if not applicable]

Keep each section concise. Preserve exact file paths, function names, and error messages.`;

const SUMMARIZE = `The messages above are a conversation to summarize. Create a structured context checkpoint summary that another LLM will use to continue the work.

Use this EXACT format:

${SECTIONS}`;

const UPDATE = `The messages above are NEW conversation messages to incorporate into the existing summary provided in <previous-summary> tags.

RULES:
- PRESERVE all existing information from the previous summary
- ADD new progress, decisions, and context from the new messages
- UPDATE the Progress section: move items from "In Progress" to "Done" when completed
- UPDATE "Next Steps" based on what was accomplished
- PRESERVE exact file paths, function names, and error messages
- If something is no longer relevant, you may remove it

Use this EXACT format:

${SECTIONS}`;

/** Same shape as pi's FileOperations, kept local so this file does not import pi. */
export interface FileOperations {
  read: Set<string>;
  written: Set<string>;
  edited: Set<string>;
}

interface LooseBlock {
  type?: string;
  text?: string;
  thinking?: string;
  name?: string;
  arguments?: Record<string, unknown>;
}
interface LooseMessage {
  role?: string;
  content?: string | LooseBlock[];
}

function textOf(content: string | LooseBlock[] | undefined): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .filter((block) => block?.type === "text")
    .map((block) => block.text ?? "")
    .join("");
}

function clip(text: string, maxChars: number): string {
  if (text.length <= maxChars) return text;
  return `${text.slice(0, maxChars)}\n\n[... ${text.length - maxChars} more characters truncated]`;
}

/**
 * Flatten messages to text, the way pi does, so the summarizer reads a record
 * rather than a conversation to continue. pi caps each tool result at 2000
 * characters because the request has to fit the window it just ran out of; here
 * the cap is a parameter, and that is the whole point of asking a bigger model.
 */
export function serializeConversation(messages: readonly Message[], blockMaxChars: number): string {
  const parts: string[] = [];
  for (const raw of messages as unknown as LooseMessage[]) {
    if (raw.role === "user") {
      const content = textOf(raw.content);
      if (content) parts.push(`[User]: ${content}`);
      continue;
    }
    if (raw.role === "assistant") {
      const blocks = Array.isArray(raw.content) ? raw.content : [];
      const thinking = blocks.filter((block) => block?.type === "thinking").map((block) => clip(block.thinking ?? "", blockMaxChars));
      const toolCalls = blocks
        .filter((block) => block?.type === "toolCall")
        .map((block) => `${block.name}(${Object.entries(block.arguments ?? {}).map(([k, v]) => `${k}=${JSON.stringify(v)}`).join(", ")})`);
      if (thinking.length > 0) parts.push(`[Assistant thinking]: ${thinking.join("\n")}`);
      const speech = textOf(blocks);
      if (speech) parts.push(`[Assistant]: ${speech}`);
      if (toolCalls.length > 0) parts.push(`[Assistant tool calls]: ${toolCalls.join("; ")}`);
      continue;
    }
    if (raw.role === "toolResult") {
      const content = textOf(raw.content);
      if (content) parts.push(`[Tool result]: ${clip(content, blockMaxChars)}`);
    }
  }
  return parts.join("\n\n");
}

/** Characters of conversation text that still leave the summarizer room to answer. */
export function charBudget(contextWindow: number, maxSummaryTokens: number): number {
  return Math.max(32_000, Math.floor((contextWindow - maxSummaryTokens - 4096) * 4 * 0.85));
}

/**
 * Serialize under a character budget, shrinking the per-block cap until it fits.
 * A request the summarizer cannot even be sent is worse than one where old tool
 * output is thin, so the cap goes down rather than the conversation getting cut.
 */
export function fitConversation(
  messages: readonly Message[],
  budgetChars: number,
  cap: number,
  previousSummary = "",
): { conversation: string; cap: number } {
  let current = Math.max(200, cap);
  for (;;) {
    const conversation = serializeConversation(messages, current);
    if (conversation.length + previousSummary.length <= budgetChars || current <= 200) return { conversation, cap: current };
    current = Math.max(200, Math.floor(current / 4));
  }
}

export function buildSummaryRequest(options: {
  conversation: string;
  previousSummary?: string;
  customInstructions?: string;
  cap: number;
}): string {
  let prompt = `<conversation>\n${options.conversation}\n</conversation>\n\n`;
  if (options.previousSummary) prompt += `<previous-summary>\n${options.previousSummary}\n</previous-summary>\n\n`;
  prompt += options.previousSummary ? UPDATE : SUMMARIZE;
  prompt += `\n\nTool results and thinking blocks above are clipped at ${options.cap} characters each, with the clipped amount marked in place.`;
  if (options.customInstructions) prompt += `\n\nAdditional focus: ${options.customInstructions}`;
  return prompt;
}

/** Carry the file lists a previous summary recorded, so they survive another compaction. */
export function carryFileOps(target: FileOperations, details: unknown): void {
  if (typeof details !== "object" || details === null) return;
  const { readFiles, modifiedFiles } = details as { readFiles?: unknown; modifiedFiles?: unknown };
  if (Array.isArray(readFiles)) for (const file of readFiles) if (typeof file === "string") target.read.add(file);
  if (Array.isArray(modifiedFiles)) for (const file of modifiedFiles) if (typeof file === "string") target.edited.add(file);
}

export function fileLists(fileOps: FileOperations): { readFiles: string[]; modifiedFiles: string[] } {
  const modified = new Set([...fileOps.edited, ...fileOps.written]);
  return {
    readFiles: [...fileOps.read].filter((file) => !modified.has(file)).sort(),
    modifiedFiles: [...modified].sort(),
  };
}

/** The same tags pi appends, so a summary written here reads like one written by pi. */
export function formatFileLists(readFiles: string[], modifiedFiles: string[]): string {
  const sections: string[] = [];
  if (readFiles.length > 0) sections.push(`<read-files>\n${readFiles.join("\n")}\n</read-files>`);
  if (modifiedFiles.length > 0) sections.push(`<modified-files>\n${modifiedFiles.join("\n")}\n</modified-files>`);
  return sections.length > 0 ? `\n\n${sections.join("\n\n")}` : "";
}
