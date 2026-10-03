// pi's footer, with llama.cpp in it: the metrics line, and below it path, context bar and model.

import type { ExtensionContext, ReadonlyFooterDataProvider, Theme, ThemeColor } from "@earendil-works/pi-coding-agent";
import type { Component, TUI } from "@earendil-works/pi-tui";
import { baseLine, cols, cut, flatten, metricGroups, metricsLine, type Segment, type Tone } from "./layout.ts";
import { isLlama } from "./server.ts";
import { paint, runtime, view } from "./state.ts";

const TONE: Record<Tone, ThemeColor | undefined> = {
  label: "dim",
  value: "text",
  live: "accent",
  dim: "dim",
  warn: "warning",
  error: "error",
  separator: "borderMuted",
  ident: "dim",
  model: "muted",
  number: "text",
  percent: "text",
  held: "accent",
  evaluating: "success",
  pending: "success",
  generating: "text",
  free: "borderMuted",
  none: undefined,
};

/** A segment with a `bg` is a cell where two layers meet: the one on top in the foreground, the one under it in the background. */
const styleSegments = (segments: Segment[], theme: Theme): string => {
  const colors = theme.colors;
  return segments
    .map((s) => {
      const fg = TONE[s.tone];
      if (fg === undefined) return s.text;
      return s.bg === undefined ? theme.fg(fg, s.text) : theme.style(s.text, { fg, bg: colors[TONE[s.bg]!] });
    })
    .join("");
};

const colorize = (segments: Segment[], theme: Theme, to?: number): string => {
  const text = styleSegments(segments, theme);
  const room = to === undefined ? 0 : to - cols(flatten(segments));
  return room > 0 ? `${text}${" ".repeat(room)}` : text;
};

/** What other extensions set with ctx.ui.setStatus(), on a line of its own above the rest. */
function statusLine(footerData: ReadonlyFooterDataProvider, width: number, theme: Theme): string | undefined {
  const texts = [...footerData.getExtensionStatuses().values()];
  if (texts.length === 0) return undefined;
  const text = texts.join(" ").replace(/[\r\n\t]/g, " ").replace(/ +/g, " ").trim();
  return theme.fg("dim", cut(text, width));
}

const cwdOf = (): string => {
  const path = runtime.ctx?.sessionManager.getCwd() ?? process.cwd();
  const home = process.env.HOME ?? process.env.USERPROFILE;
  return home && (path === home || path.startsWith(`${home}/`)) ? `~${path.slice(home.length)}` : path;
};

const thinkingOf = (): string | null => {
  const ctx = runtime.ctx;
  if (!ctx?.model?.reasoning) return null;
  return !ctx.thinkingLevel || ctx.thinkingLevel === "off" ? "thinking off" : ctx.thinkingLevel;
};

// Plain fields rather than constructor parameter properties: this file is loaded by preview.mjs and harness.mjs
// under plain node, which strips types but does not transform them.
class DxFooter implements Component {
  private theme: Theme;
  private footerData: ReadonlyFooterDataProvider;
  private stopBranchChange: () => void;

  constructor(theme: Theme, footerData: ReadonlyFooterDataProvider) {
    this.theme = theme;
    this.footerData = footerData;
    this.stopBranchChange = footerData.onBranchChange(() => paint(false));
  }

  render(width: number): string[] {
    runtime.width = width;
    const lines: string[] = [];
    const status = statusLine(this.footerData, width, this.theme);
    if (status !== undefined) lines.push(status);
    const v = view();
    if (v === undefined) return [...lines, colorize(baseLine({ width, cwd: cwdOf(), branch: this.footerData.getGitBranch(), model: runtime.ctx?.model?.id, thinking: thinkingOf(), used: null, total: runtime.model.nCtx }), this.theme, width)];
    lines.push(colorize(metricsLine(metricGroups(v.facts), width), this.theme));
    lines.push(
      colorize(
        baseLine({ width, cwd: cwdOf(), branch: this.footerData.getGitBranch(), model: runtime.ctx?.model?.id, thinking: thinkingOf(), used: v.used, evaluating: v.evaluating, pending: v.pending, generating: v.generating, total: v.total }),
        this.theme,
        width,
      ),
    );
    return lines;
  }

  dispose(): void {
    this.stopBranchChange();
  }

  invalidate(): void {}
}

/** Take pi's footer while the model's server answers like llama.cpp, hand it back when it does not. */
export function syncFooter(ctx: ExtensionContext): void {
  runtime.ctx = ctx;
  if (ctx.mode !== "tui") return;
  if (isLlama(runtime.model.root)) ctx.ui.setFooter((_tui: TUI, theme: Theme, footerData: ReadonlyFooterDataProvider) => ((runtime.tui = _tui), new DxFooter(theme, footerData)));
  else ctx.ui.setFooter(undefined);
}
