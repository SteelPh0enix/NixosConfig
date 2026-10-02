# llama-dx

Live llama.cpp diagnostics for the request pi is making right now, in three fixed rows below the editor:

```
 qwen-27B       pp   658 t/s  tg     59 t/s  spec  61%     13/21  ttft  10.1s
 prompt    8.4k  eval   6.6k  reuse   1.8k  out     21  ctx   8.4k/  150k   5%
 ▰▰▰▰▰▰▰▰▰▰▰▰    8.4k/   8.4k     done  session   2 req    10k in     80 out   3.5k reused
```

Row 1 is speed, row 2 the current request's tokens, row 3 prompt progress plus session totals. **Cells never
move, never shrink and never disappear**: they keep their column, and a value that is finished stays on screen
dimmed instead of vanishing when the phase ends.

| | |
|---|---|
| `pp` / `tg` | prompt-processing and generation throughput. Exact (`timings.prompt_per_second`, `predicted_per_second`) once llama.cpp has measured enough of this request — 200 prompt tokens, 16 generated ones — otherwise a `~` value: the live rate from `/slots`, or the mean of the last ≤10 measurements for this server+model, the `pp` one fitted against context since it declines as the context grows |
| `spec` | speculative-decode acceptance, `draft_n_accepted/draft_n`, the only clue when a `--spec-type` preset stops helping |
| `ttft` | client-measured time to the first content token: prefill, queueing and model loading in one number |
| `prompt` / `eval` / `reuse` | prompt size, tokens that had to be evaluated, tokens that came back from the KV cache |
| `out` | tokens generated |
| `ctx` | used over the instance's served `n_ctx`, from `/slots` |
| progress bar | prompt processing: evaluated + reused over the prompt. Full and dim once the request is over; `cached` when there was nothing to evaluate, `~4s` while there is |
| `session` | requests, input, output and reused tokens accumulated in this session |

A `~` in front of a number means "not llama.cpp's own number", never "roughly".

Two sources, because neither is enough alone: the response stream (`timings`/`usage`, exact, but the first
chunk only arrives once prefill is over — the extension adds `timings_per_token: true` to get them repeated),
and `GET /slots?model=X` polled while the request runs, which is the only way to watch prefill. The prompt size
is not available from the server, so it is estimated from the outgoing body and re-calibrated against the
previous request's exact `usage.prompt_tokens` (~3.6-4.1 characters per token with pi's prompt).

* `/llama-dx` — keep (default) or clear the panel once a request finishes
* `/llama-dx detail` — host, slot, characters-per-token, whether the speeds are measured or fitted
* `/llama-dx reset` — zero the session counters and the speed history
* `LLAMA_DX_DEBUG=1` — one stderr line per poll and per finished request

State is per session and per model: starting a session or selecting a model drops the counters and the speed
history, so nothing measured on another machine shows up under a new model.

Requirements: `--slots` per instance (llama.cpp default, off only with `--no-slots`), the router reachable at
`baseUrl` minus `/v1`, and `?model=` accepting what pi sends as the model (preset name or alias, the same
matching `llama-compat` does). A server that does not answer `/slots` is dropped after three polls and the
panel falls back to stream timings.

Limits: progress granularity is `--chunk-size`/`--batch-size`, so a 2048-batched instance has few real steps
per bar. With `--parallel > 1` on one server (subagents) the slot is picked as "the processing one" and the bar
can describe someone else's request. Nothing is written to the session: pi records token counts only, never
`timings`, so these numbers exist while the request runs and, dimmed, after it.
