// What every indicator on the metrics line means: the list `/llama-dx info` prints.
// Text and width only, so test-utils/preview.mjs renders it under plain node.

import type { Theme, ThemeColor } from "@earendil-works/pi-coding-agent";
import { cols, cut } from "./layout.ts";

type Row = { cell: string; meaning: string };

/** In the order the groups sit on the line, which is the order they drop from it as the terminal narrows. */
const SECTIONS: { name: string; rows: Row[] }[] = [
  {
    name: "throughput",
    rows: [
      { cell: "pp", meaning: "prompt processing: prompt tokens evaluated per second" },
      { cell: "tg", meaning: "generation: tokens produced per second" },
      { cell: "t/s", meaning: "the unit of both" },
    ],
  },
  {
    name: "this request",
    rows: [
      { cell: "fp", meaning: "the whole prompt: reused tokens and evaluated ones together" },
      { cell: "ev", meaning: "of it, the tokens that had to be computed now" },
      { cell: "re", meaning: "of it, the tokens taken from the KV cache" },
      { cell: "out", meaning: "tokens this request generated" },
    ],
  },
  {
    name: "session",
    rows: [
      { cell: "#", meaning: "requests llama.cpp served since pi got on this model" },
      { cell: "↑", meaning: "tokens in, pi's own total for this session" },
      { cell: "↓", meaning: "tokens out, pi's own total" },
      { cell: "R", meaning: "tokens read from the prompt cache" },
    ],
  },
  {
    name: "server, needs --metrics",
    rows: [
      { cell: "q", meaning: "requests deferred by the server's queue" },
      { cell: "fl", meaning: "requests processing, over slots filled" },
      { cell: "bd", meaning: "busy slots per decode; over 1.00 requests drag each other" },
    ],
  },
  {
    name: "speculation",
    rows: [
      { cell: "sc", meaning: "speculative tokens accepted over drafted, this request" },
      { cell: "st", meaning: "the same over the instance's whole lifetime" },
    ],
  },
  {
    name: "latency",
    rows: [{ cell: "tt", meaning: "time to the first content token: prefill, queue and load in one" }],
  },
  {
    name: "detail",
    rows: [
      { cell: "@", meaning: "the machine serving this model, host:port" },
      { cell: "#", meaning: "the watched slot, over the number of slots" },
      { cell: "max", meaning: "n_tokens_max, the largest context the instance has held" },
      { cell: "c/t", meaning: "characters per token, from the last exact prompt size" },
      { cell: "exact", meaning: "speeds are llama.cpp's own timings; fitted means they are ours" },
    ],
  },
  {
    name: "context bar, on the bottom line",
    rows: [
      { cell: "held", meaning: "█ what the context already holds; warning past 70%, error past 90%" },
      { cell: "eval", meaning: "█ prompt tokens prefill is putting into the KV right now" },
      { cell: "gen", meaning: "█ tokens being produced right now, the brightest block on the line" },
      { cell: "▒", meaning: "two layers in one cell: the newer colour in front of the one it lands on" },
      { cell: "free", meaning: "░ the room left in n_ctx" },
    ],
  },
  {
    name: "markers",
    rows: [
      { cell: "~", meaning: "not llama.cpp's own number: the live rate, or the estimate from history" },
      { cell: "—", meaning: "nothing to show and nothing to hold, never a zero" },
      { cell: "bright", meaning: "the phase running right now: pp in prefill, tg in generation" },
    ],
  },
];

const ROLE: Record<"head" | "cell" | "meaning" | "note", ThemeColor> = { head: "muted", cell: "accent", meaning: "text", note: "dim" };

/** Each line fits `width`: meanings are cut rather than wrapped, so the cells keep their column. */
export function legend(theme: Pick<Theme, "fg">, width: number): string {
  const cells = Math.max(...SECTIONS.flatMap((s) => s.rows.map((r) => cols(r.cell))));
  const run = (role: keyof typeof ROLE, text: string) => (text ? theme.fg(ROLE[role], text) : text);
  const out = [run("head", cut("the footer, group by group", width)), ""];
  for (const s of SECTIONS) {
    out.push(run("head", s.name));
    for (const r of s.rows) {
      const cell = `  ${r.cell}${" ".repeat(Math.max(0, cells - cols(r.cell)))}  `;
      out.push(`${run("cell", cell)}${run("meaning", cut(r.meaning, Math.max(0, width - cols(cell))))}`);
    }
  }
  out.push("", run("note", cut("what is shown is decided by width alone, never by the state of the request", width)));
  return out.join("\n");
}
