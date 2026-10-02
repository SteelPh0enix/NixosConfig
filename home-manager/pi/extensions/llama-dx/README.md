# llama-dx

Live llama.cpp diagnostics for the request pi is making right now, rendered below the input box:

```
 prefill qwen-27B ▰▰▰▱▱▱▱▱▱▱ 8.2k/~12k prompt tok · ~6s left
           650 tok/s · reuse ≥4.1k
 decode qwen-27B 472 tok out @ 148/s
           508 tok prefill @ 611/s · 4.1k tok reused · speculative 259/465 accepted
```

Two sources, because neither is enough alone: the response stream (`timings`/`usage`, exact, but the
first chunk only arrives once prefill is over — the extension adds `timings_per_token: true` to the
request so they repeat with every chunk) and `GET /slots?model=X` on the server behind the model's
`baseUrl`, polled while the request runs. `/slots` is what makes prefill progress visible:
`n_prompt_tokens_processed` advances while the prompt is being read. The total prompt size is not
available from the server, so it is estimated from the outgoing body and re-calibrated against the
previous request's exact `usage.prompt_tokens` (~3.6-4.1 characters per token with pi's prompt); the
tilde in `~12k` marks an estimate. Idle servers and non-llama.cpp providers cost nothing: a server that
does not answer `/slots` is dropped after three polls and the bar falls back to stream timings.

* `/llama-dx` keeps the last request's numbers on screen after it finishes.
* `/llama-dx detail` adds context used, server host and slot count.
* `LLAMA_DX_DEBUG=1` writes one stderr line per poll and a summary per request.

Requirements: `--slots` per instance (llama.cpp default, off only with `--no-slots`), the router
reachable at `baseUrl` minus `/v1`, and `?model=` accepting what pi sends as the model (preset name or
alias, the same matching `llama-compat` uses). Progress granularity is `--chunk-size`/`--batch-size`, so
a 2048-batched instance has few real steps per bar; a warm KV cache usually means no prefill at all,
which the bar states instead of printing a meaningless speed.

Nothing is written to the session; pi records only token counts today, never `timings`, so these numbers
exist only while the request runs. With `--parallel > 1` on one server (subagents) the bar can describe someone else's request — the
slot is picked as "the processing one".
