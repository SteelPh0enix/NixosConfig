# llama-dx

Live llama.cpp diagnostics for the request pi is making right now. It takes over pi's footer, so the numbers sit
in the two lines pi already used rather than in rows of their own:

```
 ~/Projects/steel-pi (master)  qwen3-coder-27b • high  pp 658 t/s  tg 59 t/s  spec 61% 13/21  ttft 10.1s  prompt 8.4k  eval 6.6k
 out 21  ▰▰▰▰▰▰▰▰▰▰▰▰ 8.4k/8.4k done  ctx 8.4k/150k 6%  req 2 ↑10k ↓80 R3.5k  queue 0  in flight 1/1  busy/dec 1.00
```

Cells fill the lines in a fixed order and the last line is right-aligned, so a wide terminal gets everything on
two lines and a narrow one gets more of them with the ragged edge inside the block instead of at its right side.
`/llama-dx compact` shortens the labels and the padding, which is usually what fits it all on two lines.

Where llama.cpp and pi measure the same thing, pi's number is the one shown: the token totals (`↑` in, `↓` out,
`R` read from cache, `$` cost) are what the session recorded, and `ctx` is what the slot holds over what the
server serves — pi's own estimate while there is no server number. `req` counts the requests llama.cpp served.
Of pi's footer only the provider prefix, the subscription marker, the routed-model arrow and the `xp` marker are
gone; everything else is above, and texts other extensions set with `setStatus()` keep their own line.

**Cells never move, never shrink and never disappear**: they keep their column, only the terminal's width changes
which line one lands on, and a value that is finished stays on screen dimmed instead of vanishing when the phase ends.

Nor does anything fall back to `0`, which is the loudest thing a panel of fixed columns can do. A speed is held
while its phase has nothing new — prefill advances in whole `--batch-size` steps, so the live rate is a staircase
of stalls — and is taken towards the fresh measurement each poll instead of snapping to it; a new request opens at
the speeds already measured on this server and glides from there; and its counters keep the previous request's
numbers until it has measured its own — they describe the slot's KV, which survives between requests anyway. The
footer is redrawn a few times a second rather than once per generated token.

| | |
|---|---|
| `pp` / `tg` | prompt-processing and generation throughput. Exact (`timings.prompt_per_second`, `predicted_per_second`) once llama.cpp has measured enough of this request — 200 prompt tokens, 16 generated ones — otherwise a `~` value: the live rate from `/slots` (smoothed, and held while its counter stalls), or the mean of the last ≤10 measurements for this server+model, the `pp` one fitted against context since it declines as the context grows |
| `spec` | speculative-decode acceptance, `draft_n_accepted/draft_n`, the only clue when a `--spec-type` preset stops helping |
| `ttft` | client-measured time to the first content token: prefill, queueing and model loading in one number |
| `prompt` / `eval` / `reuse` | prompt size, tokens that had to be evaluated, tokens that came back from the KV cache |
| `out` | tokens generated |
| `ctx` | used over the instance's served `n_ctx`, from `/slots`; coloured at pi's own compaction thresholds |
| progress bar | prompt processing: evaluated + reused over the prompt. Full and dim once the request is over; `cached` when there was nothing to evaluate, `~4s` while there is |
| `↑ ↓ R $` | the session's tokens and cost as pi recorded them |
| `queue` | `llamacpp:requests_deferred`: requests waiting for a slot, i.e. "slow" meaning "queued behind someone" |
| `in flight` | `requests_processing` over the instance's slot count |
| `busy/dec` | `n_busy_slots_per_decode`: above 1.00 several requests share each decode step, so their speeds are mutually dragged down |
| `spec life` | acceptance over the instance's whole lifetime (`spec_decode_num_*_total`), unlike the single-request `spec` |
| `n_tokens_max` | in `/llama-dx detail`: largest sequence the instance has ever held |

A `~` in front of a number means "not llama.cpp's own number", never "roughly".

Compact mode keeps the short keys and drops the words, the units and some padding — same order, same columns:
`pp tg` unchanged, `sp` spec, `tt` ttft, `pr` prompt, `ev` eval, `rs` reuse, `cx` ctx, `q` queue, `fl` in flight,
`bd` busy/dec, `sl` spec life, `@` host, `#` slot, `max` n_tokens_max, `exact`/`fitted` timings.

Two sources, because neither is enough alone: the response stream (`timings`/`usage`, exact, but the first
chunk only arrives once prefill is over — the extension adds `timings_per_token: true` to get them repeated),
and `GET /slots?model=X` polled while the request runs, which is the only way to watch prefill. The prompt size
is not available from the server, so it is estimated from the outgoing body and re-calibrated against the
previous request's exact `usage.prompt_tokens` (~3.6-4.1 characters per token with pi's prompt).

* `/llama-dx` — keep (default) or clear the diagnostics once a request finishes
* `/llama-dx compact` — short keys, no labels, tighter padding
* `/llama-dx detail` — host, slot, characters-per-token, whether the speeds are measured or fitted
* `/llama-dx reset` — zero the request counter and the speed history
* `LLAMA_DX_DEBUG=1` — one stderr line per poll and per finished request

State is per session and per model: starting a session or selecting a model drops the counters and the speed
history, so nothing measured on another machine shows up under a new model.

`/metrics` is scraped once at the start of a request and then once a second while it runs, always with
`autoload=false` — on a router `/metrics` is proxied per model and a plain read would load the instance
(`server.cpp:220` → `proxy_get` → `ensure_model_ready`). Its two throughput gauges are deliberately not read:
every scrape resets the buckets behind them (`server-context.cpp:4807`), so they are only valid for one scraper
and reading them would spoil them for anyone else. `--metrics` answers `501 … Start it with --metrics`, which
is the only answer that turns those cells off; a scrape that times out leaves them on the last one that answered.

Requirements: `--slots` per instance (llama.cpp default, off only with `--no-slots`), the router reachable at
`baseUrl` minus `/v1`, and `?model=` accepting what pi sends as the model (preset name or alias, the same
matching `llama-compat` does). A server that never answers `/slots` is given up on after ~10s of silence and the
diagnostics fall back to stream timings; one that is merely slow, or still loading, is not. With a model that is
not served by llama.cpp at all the footer shows only pi's own numbers.

Limits: progress granularity is `--chunk-size`/`--batch-size`, so a 2048-batched instance has few real steps
per bar. With `--parallel > 1` on one server (subagents) the slot is picked as "the processing one" and the bar
can describe someone else's request. Nothing is written to the session: pi records token counts only, never
`timings`, so these numbers exist while the request runs and, dimmed, after it.
