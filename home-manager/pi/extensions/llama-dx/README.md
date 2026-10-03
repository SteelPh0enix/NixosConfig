# llama-dx

llama.cpp's diagnostics for the request pi is making right now, in pi's footer. Two lines:

```
pp  622 tg   58 t/s  │  fp 15.2k  ev 6.6k  re 8.6k  out  340  │  #3  ↑25k  ↓600  R13k  │  q 0  fl 1/1  bd 1.00  │  sc 61%  13/21  st 63%  │  tt   8.1s  │  @pc:51536  # 1/1  max  16k  3.9c/t  exact
~/src/steel-pi (master)  24,300 9.4%  █████████▍▓░░░░░░…░░░░░░░  262,144  qwen3-coder-27b • high
```

The bottom line is the one that matters: where you are, what you are on, and between them the **context bar** —
tokens held, the percent they are of the instance's `n_ctx`, and the bar itself taking every column the two names
leave. `█` is what the context already holds, `▓` what is landing in it this second (prefill evaluating, generation
producing), `░` the room left; both edges round to 1/8 of a cell, so prefill creeps instead of jumping whole cells.
A third line appears above these only when another extension has set a status text.

The top line holds the rest, grouped and separated by `│`. **What is dropped is decided by width alone, never by
the state of the request**: groups disappear from the right as the terminal narrows, in the order
throughput → this request → session → server → speculation → latency → detail. Cells keep their columns, so nothing
dances when a number changes.

| group | cells |
|---|---|
| throughput | `pp` `tg` t/s — prompt processing and generation, from `timings` once llama.cpp has measured enough of them (200 prompt tokens, 16 generated); until then `~` values |
| this request | `fp` full prompt, `ev` tokens that had to be evaluated, `re` taken from the KV cache, `out` generated |
| session | `#` requests llama.cpp served, `↑` in, `↓` out, `R` read from cache — pi's own totals, never a parallel bookkeeping |
| server | `q` deferred requests, `fl` processing over slots, `bd` busy slots per decode (above 1.00 several requests drag each other) |
| speculation | `sc` accepted/drafted this request, `st` over the instance's lifetime |
| latency | `tt` time to the first content token, measured client-side: prefill, queueing and model loading in one number |
| detail | `@` host, `#` slot over slots, `max` `n_tokens_max`, characters per token, and whether the speeds are `exact` or `fitted` |

A `~` means "not llama.cpp's own number", never "roughly": the live rate from `/slots` (held while its counter
stalls, since prefill advances in whole batch steps), or the mean of the last ten measurements for this server and
model — `pp` fitted against context, since it declines as the context grows. A new request opens at the speeds
already measured on that server and glides from there, and its counters keep the previous request's numbers until it
has measured its own. `—` means there is nothing to hold.

Two sources, because neither is enough alone: the response stream (`timings`, `usage` — exact, but the first chunk
only arrives once prefill is over, so the extension asks for `timings_per_token`), and `GET /slots?model=X` polled
while the request runs, which is the only way to watch prefill and the only per-instance `n_ctx`. The prompt size is
not available from the server, so it is estimated from the outgoing body and recalibrated against the previous
request's exact `usage.prompt_tokens`. The used zone is pi's own context figure, taken the moment the request went
out — what is arriving since then belongs to the flight zone.

`/metrics` is scraped at the start of a request and then once a second while it runs, always with `autoload=false`:
on a router a plain read would load the instance. Its two throughput gauges are deliberately not read, since every
scrape resets the buckets behind them. `--metrics` answers `501`, which is the only answer that turns those cells
off; a scrape that times out keeps the last one that answered.

Colours are theme tokens: `accent` for what is held (`warning` past 70%, `error` past 90%, pi's own compaction
thresholds), `success` for what is landing, `borderMuted` for the room left and the separators, `dim` for labels and
session totals, and the bright `accent` for the phase that is live right now.

`/llama-dx` prints what the footer currently thinks; `/llama-dx reset` zeroes the request counter and the speed
history; `LLAMA_DX_DEBUG=1` writes one stderr line per poll and per finished request. State is per session and per
model: starting a session or switching model drops the counters, so nothing measured on another machine survives.

Requirements: `--slots` per instance (llama.cpp default, off only with `--no-slots`), the router reachable at
`baseUrl` minus `/v1`, and `?model=` accepting what pi sends (preset name or alias). `--metrics` is optional and
only the server/spec-lifetime cells need it. A model that is not served by llama.cpp — checked once per server with
`/props` — hands the footer back to pi.

Limits: bar granularity is `--chunk-size`/`--batch-size`, so a 2048-batched instance has few real steps per cell.
With `--parallel > 1` the slot is picked as "the processing one" and the flight zone can describe someone else's
request. Nothing is written to the session: pi records token counts only, never `timings`, so these numbers exist
while the request runs and, dimmed, after it.

## Files

| file | what it holds |
|---|---|
| `index.ts` | wiring to pi's events, and `/llama-dx` |
| `layout.ts` | both lines as coloured segments of measured width; imports nothing at runtime |
| `server.ts` | the llama.cpp endpoints: `/props`, `/slots`, `/metrics` |
| `state.ts` | the polled request, the measured speeds, and the numbers the footer shows |
| `footer.ts` | the component pi renders, and taking pi's footer back when the server is not llama.cpp |

pi is handed the **directory**, not `index.ts`, because these import each other. `test-utils/` holds the dev-only
scripts, all of them plain node importing the `.ts` files: `preview.mjs` renders the layout at chosen widths
(`--check` asserts the bar fills its width at any width from 40 to 280), `harness.mjs` runs one real request against
a real instance (`--root http://steelph0enix.pc:51536 --model qwen-27B`, model load included) so the polling and the
flight zone can be watched, and `check.mjs` runs the whole extension against a fake instance and asserts what must
be visible in the footer — run it after any change to the layout or the request tracking.
