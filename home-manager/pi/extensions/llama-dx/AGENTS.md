# llama-dx internals

For whoever changes the extension. [README.md](README.md) explains what the footer shows; this is how those numbers
are produced, and [TESTING.md](TESTING.md) is what to run afterwards. `preview.mjs --demo` paints every combination of
the bar in the palette in use, without pi.

## Layout

Two lines can sit above the two llama.cpp ones, in this order: pi's own status text when another extension sets one,
and the row of running subagents.

**What is dropped is decided by width alone, never by the state of the request**: groups disappear from the right as
the terminal narrows, compaction → throughput → this request → session → server → speculation → latency → detail.
Cells keep their columns, so nothing dances when a number changes.

Identity gives way before the bar does — the thinking level, then the ends of both names, then the percent, then the
model, and last the path, the one field whose length says nothing. From ~16 columns up the line is always exactly the
terminal's width, and `preview.mjs --check` holds it to that.

A band claims every cell it touches, so one block stands for `n_ctx / cells` tokens and the bar moves in whole cells.
Where bands share a cell the topmost one is the foreground and the one it lands on the background, drawn as `▒` so
both show through — a block can be held *and* generating at once, but never pending, which is a forecast rather than
something the context holds. Over capacity held gives way and the moving bands keep the right edge.

## Sources

Two sources, because neither is enough alone: the response stream, which the extension asks llama.cpp to fill with
`timings_per_token` and `return_progress`, and `GET /slots?model=X`, polled once a second while the request runs for
what only it knows — `n_ctx`, whether the slot is busy, and the counters that move the bar.

`pf` and the pending band are llama.cpp's own arithmetic, not a guess: `prompt_progress` names `total`, `cache` and
`processed`, and the progress is `(processed - cache) / (total - cache)`, exactly as its README defines it. An old
server without progress chunks leaves both blank until it reports the prompt size in a stream `usage` or in the
`timings` of the *finished* task (`prompt_n + cache_n` — while a task runs they are repeated after every token and
count only what has been evaluated *so far*, so taking them for the whole prompt is what made `pf` hit 100% halfway
through prefill). `/slots` cannot help: its `n_prompt_tokens` is the size of the slot's whole KV — cached prefix,
what it has batched and what it has generated — not the size of this prompt.

The held band is llama.cpp's reused prefix of this prompt (`re`), so held + evaluating + pending is the whole
prompt; what prefill and generation are adding are the moving bands. Until the server has reported a prefix, pi's own
context figure stands in — except on the first request of a session, where pi can only estimate the whole prompt and
would otherwise count it as held as well as processed, so the band stays empty.

`/slots` is polled slowly on purpose: it posts a task to the server queue and answers with the whole prompt and
answer detokenized, which at a 57k context costs about 2 ms and 1.8 MB per answer, so a fast poll is load on the
machine the footer is watching. The bands do not miss it: they move on the stream's own chunks.

`/metrics` is scraped at the start of a request and then every two seconds while it runs, always with `autoload=false`:
on a router a plain read would load the instance. Its two throughput gauges are deliberately not read, since every
scrape resets the buckets behind them; a scrape that times out keeps the last one that answered.

Compaction is not a request of ours: pi summarizes with a direct model call (`compact()` hands `agent.streamFunction`
to the summarizer), and `compact-delegate` calls the model registry the same way, so neither goes through
`before_provider_request` or the stream hooks and there are no timings to show. `session_before_compact` puts the
line into a `compact` phase that holds the bar at `preparation.tokensBefore` and counts up a second at a time;
`session_compact` drops the request that led to it, so the bar reads pi's rebuilt context instead of adding the
summary to the context that was replaced; `session_compact_failed` only clears the phase. This is the one cell that
shows elapsed time rather than a rate, because the pipeline never sees the work.

Speeds are only llama.cpp's own: `pp` appears once 200 prompt tokens have been evaluated, `tg` once 16 have been
generated, and in the gap before either — and between requests — the last value it reported stands. Nothing is
fitted, smoothed or borrowed from another server or model, so a new request opens on the previous one's `pp`/`tg`
rather than on an estimate. It keeps that request's token counters too until it knows its own prompt, when it drops
them.

A `/props` that gets no reply is not an answer: the footer stays and the question is asked again up to five times, so
a stalled lookup or a router still loading costs the moving cells rather than the whole line. Nothing is polled or
scraped until that check has said yes. gufo is not llama.cpp but serves the same `/slots`, `/metrics` and
`prompt_progress`; its `/props` is a stub that demands a `?model=`, so when `/props` does not answer the probe falls
back to `/v1/models` and accepts it when a model there is `owned_by: gufo`.

## The row of subagents

```
subagents 3  │  task-1 researcher  12s  bash: nix flake check (4.2s)  out ~1.2k  ctx 41k/262k  │  task-2 coder 2/2  3m12s idle 1m30s  edit home-manager/pi/subagents/ui…  out 18k  ctx 190k/262k
```

The subagents extension reports its running tasks on pi's event bus (`subagents:status`) and this extension turns
them into this row — the only thing that reads that channel. A task names itself, its slot when its model has more
than one, how long it has run, and what it is busy with: while a tool runs that is the tool, its argument summary and
a live timer, cut to 34 columns, otherwise the task's last activity. What its own model produced (`out`, `~` while the
turn is still decoding) and how full its own context is (`ctx 41k/262k`, `warning` past 70%, `error` past 90%, the
same thresholds as the bar below) follow. The count in front never leaves, since tasks drop from the right as the
terminal narrows and what has been dropped must not look like the whole set. Silence of 15 s and a retried model call
go to `warning`, an error to `error`. A snapshot arrives only when something moved, so the ages keep counting from the
moment it was taken, and the row goes away with the last task. Switching pi's model keeps it — those tasks run on
their own models — but a new session starts without the row of the tasks the session before it ran. `preview.mjs
--agents` shows it, `check.mjs` asserts it.

## Colours

Theme tokens throughout: `accent` for what is held (`warning` past 70%, `error` past 90%, pi's own compaction
thresholds, and the frontier behind it follows), `success` for what prefill is evaluating **and** for the prompt
still to come — the same green, one density quieter, so `░` becoming `█` is the progress of prefill — `text` for what
is generating (the live edge is the brightest block on the line), `borderMuted` for the room left and the separators,
`dim` for labels and session totals, and the bright `accent` for the phase running right now on the metrics line. A
cell where two real bands meet asks the theme for both colours, so it is the one place the footer sets a background.

## Scope and what never happens

Only the interactive pi is watched: pi loads extensions into every session it makes, including the in-memory ones
another extension runs a subagent in, and those share this module — one footer measuring two servers is unreadable,
and a subagent's context is thrown away long before the footer stops rendering.

Nothing is written to the session: pi records token counts only, never `timings`, so these numbers exist while the
request runs and, dimmed, after it. The committed tokens join the held band at the end for a reason: otherwise the bar
would shrink by exactly those tokens until the next request re-measured the context — the held band is the reused
prefix plus what this request evaluated and produced.

## Files

| file | what it holds |
|---|---|
| `index.ts` | wiring to pi's events, and `/llama-dx` |
| `layout.ts` | both lines as coloured segments of measured width; imports nothing at runtime |
| `agents.ts` | the row of running subagents, out of the snapshot the subagents extension broadcasts |
| `server.ts` | the server's endpoints: `/props`, `/slots`, `/metrics`, and `/v1/models` for gufo |
| `state.ts` | the polled request, the last speeds llama.cpp reported, the compaction phase, and the numbers the footer shows |
| `footer.ts` | the component pi renders, and taking pi's footer back when the server is not llama.cpp |
| `debug.ts` | `LLAMA_DX_DEBUG=1`: one stderr line per poll, per scrape and per finished request |
| `legend.ts` | what each indicator of the metrics line means, which `/llama-dx info` prints |

pi is handed the **directory**, not `index.ts`, because these import each other.
