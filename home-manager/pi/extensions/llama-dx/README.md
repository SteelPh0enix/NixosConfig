# llama-dx

llama.cpp's diagnostics for the request pi is making right now, in pi's footer. Two lines:

```
pp ~712 tg   — t/s  │  fp ~15.2k  ev 2.7k  pf  41.3%  re 8.6k  out    0  │  #3  ↑25k  ↓260  R13k  │  q 0  fl 1/1  bd 1.00  │  sc 63%  22/35  st 86%  │  tt    —  │  @pc:51536  # 1/1  max  16k  3.9c/t  fitted
~/src/steel-pi (master)  24,300 9.4%  █████████▒███░░░░░░░░…░░░░░░░  262,144  qwen3-coder-27b • high
```

The bottom line is the one that matters: where you are, what you are on, and between them the **context bar** —
tokens held, the percent they are of the instance's `n_ctx`, and the bar itself taking every column the two names
leave. Four bands over one row of full blocks: what the context **holds**, what prefill is **evaluating** into it
this second, the prompt it has **yet to evaluate**, what generation is **producing** this second, and the room left.
A band claims every cell it touches, so one block stands for `n_ctx / cells` tokens and the bar moves in whole
cells. What is still to come is the quiet track *in the colour it is about to turn into*: the green `█` of evaluating
eats into the green `░` of the incoming prompt, and you can see where the request is going to leave the context
before it has evaluated a single token. Where bands share a cell the topmost one is the foreground and the one it
lands on the background, drawn as `▒` so both show through — a block can be held *and* generating at once, but never
pending, which is a forecast rather than something the context holds. Over capacity held gives way and the moving
bands keep the right edge. `node test-utils/preview.mjs --demo` prints every combination in your own palette. A third
line appears above these only when another extension has set a status text.

The top line holds the rest, grouped and separated by `│`. **What is dropped is decided by width alone, never by
the state of the request**: groups disappear from the right as the terminal narrows, in the order
throughput → this request → session → server → speculation → latency → detail. Cells keep their columns, so nothing
dances when a number changes.

| group | cells |
|---|---|
| throughput | `pp` `tg` t/s — prompt processing and generation, from `timings` once llama.cpp has measured enough of them (200 prompt tokens, 16 generated); until then `~` values |
| this request | `fp` full prompt, `ev` tokens that had to be evaluated, `pf` how far that evaluation has got (`ev` over what has to be evaluated; `—` when the whole prompt came from the cache), `re` taken from the KV cache, `out` generated |
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
out — what is arriving since then belongs to the moving bands. What a request still has to evaluate is no estimate
either: while it runs, `/slots` gives the whole prompt and the cached part of it, so the pending band and `pf` are
the server's own numbers (`input_tokens = n_prompt_tokens - n_prompt_tokens_cache`); only before the first `/slots`
answer of a request is that total the same body-size estimate as `fp`.

`/metrics` is scraped at the start of a request and then once a second while it runs, always with `autoload=false`:
on a router a plain read would load the instance. Its two throughput gauges are deliberately not read, since every
scrape resets the buckets behind them. `--metrics` answers `501`, which is the only answer that turns those cells
off; a scrape that times out keeps the last one that answered.

Colours are theme tokens: `accent` for what is held (`warning` past 70%, `error` past 90%, pi's own compaction
thresholds, and the frontier behind it follows), `success` for what prefill is evaluating **and** for the prompt
still to come — the same green, one density quieter, so `░` becoming `█` is the progress of prefill — `text` for what
is generating (the live edge is the brightest block on the line), `borderMuted` for the room left and the separators,
`dim` for labels and session totals, and the bright `accent` for the phase running right now on the metrics line. A
cell where two real bands meet asks the theme for both colours, so it is the one place the footer sets a background.

`/llama-dx` prints what the footer currently thinks; `/llama-dx info` lists every indicator of the metrics line and
what it means (the table above, cell by cell); `/llama-dx reset` zeroes the request counter and the speed history;
`LLAMA_DX_DEBUG=1` writes one stderr line per poll and per finished request. State is per session and per
model: starting a session or switching model drops the counters, so nothing measured on another machine survives.

Requirements: `--slots` per instance (llama.cpp default, off only with `--no-slots`), the router reachable at
`baseUrl` minus `/v1`, and `?model=` accepting what pi sends (preset name or alias). `--metrics` is optional and
only the server/spec-lifetime cells need it. A model that is not served by llama.cpp — checked once per server with
`/props` — hands the footer back to pi.

Limits: bar granularity is `--chunk-size`/`--batch-size`, so a 2048-batched instance has few real steps per cell.
With `--parallel > 1` the slot is picked as "the processing one" and the moving bands can describe someone else's
request. Nothing is written to the session: pi records token counts only, never `timings`, so these numbers exist
while the request runs and, dimmed, after it. Once it ends, what it evaluated and produced joins the held band —
otherwise the bar would shrink by exactly those tokens until the next request re-measured the context.

## Files

| file | what it holds |
|---|---|
| `index.ts` | wiring to pi's events, and `/llama-dx` |
| `layout.ts` | both lines as coloured segments of measured width; imports nothing at runtime |
| `server.ts` | the llama.cpp endpoints: `/props`, `/slots`, `/metrics` |
| `state.ts` | the polled request, the measured speeds, and the numbers the footer shows |
| `footer.ts` | the component pi renders, and taking pi's footer back when the server is not llama.cpp |
| `legend.ts` | what each indicator of the metrics line means, which `/llama-dx info` prints |

pi is handed the **directory**, not `index.ts`, because these import each other.

**[TESTING.md](TESTING.md)** is what to run after a change: `preview.mjs` for the look at any width, `check.mjs`
for the whole extension against a fake llama.cpp (no server, no pi, a few seconds), `harness.mjs` for one real
request against the instance on `steelph0enix.pc` — never pi's default model, whose cache the testing agent is
living in — plus the `tsc` command and the way to load the extension in pi without rebuilding the system.
