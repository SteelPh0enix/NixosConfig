# llama-dx

llama.cpp's diagnostics for the request pi is making right now, in pi's footer. Two lines — and one above them while
subagents run:

```
pp  712 tg   — t/s  │  fp 15.2k  ev 2.7k  pf 41.3%  re 8.6k  out    0  │  #3  ↑25k  ↓260  R13k  │  q 0  fl 1/1  bd 1.00  │  sc 63%  22/35  st 86%  │  tt    —  │  @pc:51536  # 1/1  max  16k
~/src/steel-pi (master)  24,300 9.4%  █████████▒███░░░░░░░░…░░░░░░░  262,144  qwen3-coder-27b • high
```

The bottom line is the one that matters: where you are, what you are on, and between them the **context bar** —
tokens held, the percent they are of the instance's `n_ctx`, and the bar itself taking every column the two names
leave. Read left to right it holds what the context **holds**, what prefill is **evaluating** into it this second, the
prompt it has **yet to evaluate**, what generation is **producing** this second, and the room left. What is still to
come is the quiet track *in the colour it is about to turn into*, so you can see where the request is going to leave
the context before prefill has evaluated a single token. When a request ends, what it evaluated and produced joins
the held band.

The top line holds the rest, grouped and separated by `│`. Narrow the terminal and groups disappear from the right in
the order below; the identity on the bottom line gives way before the bar does.

| group | cells |
|---|---|
| compaction | `compact` the reason, `before` the tokens being rewritten, elapsed — only while pi is compacting |
| throughput | `pp` `tg` t/s — prompt processing and generation, llama.cpp's own `timings` once it has measured enough of them (200 prompt tokens, 16 generated); between measurements the last value it reported is held |
| this request | `fp` full prompt, `ev` tokens that had to be evaluated, `pf` how far that evaluation has got (`ev` over what has to be evaluated; `—` when the whole prompt came from the cache), `re` taken from the KV cache, `out` generated |
| session | `#` requests llama.cpp served, `↑` in, `↓` out, `R` read from cache — pi's own totals, never a parallel bookkeeping |
| server | `q` deferred requests, `fl` processing over slots, `bd` busy slots per decode (above 1.00 several requests drag each other) |
| speculation | `sc` accepted/drafted this request, `st` over the instance's lifetime |
| latency | `tt` time to the first content token, measured client-side: prefill, queueing and model loading in one number |
| detail | `@` host, `#` slot over slots, `max` `n_tokens_max` |

There are no approximate values: a speed, a prompt size or a prefill percentage is shown only when llama.cpp has
reported it. Between reports the last value stands, and `—` means there is nothing to hold — never a zero and never a
number of ours. Compaction is the exception the pipeline forces: its summarizer runs outside the request hooks, so
the line leads with `compact <reason> before <tokens> <elapsed>` while the bar holds at the context being rewritten,
and a finished compaction drops the request that led to it so the bar reads the rebuilt context.

## Configuration

None. The extension takes the llama.cpp providers from `~/.pi/agent/models.json` and works out per server what it can
be asked. Nothing is remembered between sessions: starting one, or switching model, drops the counters, so no speed
measured on another machine survives.

## Commands

- `/llama-dx` — what the footer currently thinks.
- `/llama-dx info` — every indicator of the metrics line and what it means.
- `/llama-dx reset` — zero the request counter and the speed history.

## Setup gotchas

- Each instance needs `--slots` (a llama.cpp default, off only with `--no-slots`), the router reachable at `baseUrl`
  minus `/v1`, and `?model=` accepting what pi sends (a preset name or an alias). Without those the moving cells go
  quiet.
- `--metrics` is optional; only the server cells and the lifetime speculation cell need it, and a `501` there turns
  exactly those off.
- All three reads carry the provider's `apiKey` from `models.json`. A server started with `--api-key` answers 401,
  and an unauthenticated probe would read as "not llama.cpp" rather than as no answer.
- A model that is not served by llama.cpp hands the footer back to pi and is never polled or scraped again — a
  request to some third-party API never goes out looking for slots and metrics.
- Gufo is treated as llama.cpp compatible, recognised through `/v1/models` (its `/props` is a stub). It serves
  `/slots` and `/metrics` and answers `return_progress` with live `prompt_progress`, but sends `timings` only on the
  terminal chunk, so prefill moves while `pp`/`tg` land when the request ends.
- Bar granularity is `--batch-size`, so a 2048-batched instance has few real steps per cell.
- `LLAMA_DX_DEBUG=1` writes one stderr line per poll, per scrape and per finished request.

How the numbers are produced — the two sources and their arithmetic, the layout, the colours, the files:
[AGENTS.md](AGENTS.md). What to run after a change: [TESTING.md](TESTING.md).
