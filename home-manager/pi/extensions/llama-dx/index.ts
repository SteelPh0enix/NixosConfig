// llama.cpp's diagnostics as pi's footer. Two lines: the metrics line on top, and below it the working directory,
// the model, and between them a context bar filling whatever room is left — KV held, tokens landing right now,
// room left. Groups on the metrics line drop from the right as the terminal narrows, so nothing is ever
// compressed; only the width decides what is there, never the state of the request.
//
// layout.ts composes the two lines, server.ts talks to llama.cpp, state.ts turns what comes back into numbers,
// footer.ts colours them and mounts the result; this file only wires them to pi's events.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { syncFooter } from "./footer.ts";
import { full, percent } from "./layout.ts";
import { dropRequest, finishRequest, observeStream, onServerAnswer, paint, resetAll, runtime, sess, startRequest, stopPolling, trackModel, view } from "./state.ts";

export default function llamaDx(pi: ExtensionAPI) {
  // A server that turns out not to be llama.cpp gets pi's footer back.
  onServerAnswer(() => (runtime.ctx ? syncFooter(runtime.ctx) : paint(false)));

  pi.on("session_start", (_event, ctx) => {
    resetAll();
    trackModel(ctx);
    syncFooter(ctx);
  });

  // A new model is a different machine: nothing measured on the old one may leak into these cells.
  pi.on("model_select", (_event, ctx) => {
    resetAll();
    trackModel(ctx);
    syncFooter(ctx);
    paint(false);
  });

  pi.on("before_provider_request", async (event, ctx) => startRequest(event.payload as Record<string, unknown>, ctx));

  pi.on("provider_stream_event", async (event) => observeStream(event.data));

  pi.on("agent_end", async () => {
    stopPolling();
    finishRequest();
    paint(false);
  });

  pi.on("session_shutdown", (_event, ctx) => {
    stopPolling();
    dropRequest();
    ctx.ui.setFooter(undefined);
  });

  pi.registerCommand("llama-dx", {
    description: "llama.cpp footer: /llama-dx prints its state, /llama-dx reset zeroes the counters",
    handler: async (args, ctx) => {
      if (args.trim() === "reset") {
        resetAll();
        ctx.ui.notify("llama-dx: request counter and speed history cleared", "info");
      } else {
        const v = view();
        ctx.ui.notify(
          v === undefined
            ? "llama-dx: not on a llama.cpp model, pi's footer is back"
            : `llama-dx: ${sess.reqs} requests, ${v.facts.ppEstimated ? "~" : ""}${Math.round(v.facts.pp ?? 0)} pp, ${v.facts.tgEstimated ? "~" : ""}${Math.round(v.facts.tg ?? 0)} tg t/s, host ${v.facts.host}, bar ${percent(v.used ?? 0, v.total)} of ${full(v.total)}`,
          "info",
        );
      }
      runtime.tui?.requestRender();
    },
  });
}
