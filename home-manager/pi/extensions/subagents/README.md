# subagents extension

Spawns background subagents: the main agent delegates a task to a named subagent (bound to one provider + model),
keeps working, watches progress, manages the task, and reads the result. Only subagents in the config exist — the
spawn tool's `name` parameter is built from the config, so anything unconfigured is invisible to the model.

## Configuration

User-level `~/.pi/agent/subagents.json` · project-level `.pi/subagents.json`. Both are read once at startup, from the
directory pi was started in, so edits need a restart. The files merge: project entries append, and on a name clash the
project entry wins.

```json
{
  "subagents": {
    "repo-researcher": {
      "provider": "llama.cpp",
      "model": "llama-3.3-70b-instruct",
      "description": "Reads the repo and reports findings. Read-only by convention.",
      "tools": ["read", "bash", "web_search", "web_fetch"]
    },
    "code-reviewer": {
      "provider": "openrouter",
      "model": "anthropic/claude-sonnet-4.5",
      "tools": { "disable": ["write", "edit"] }
    },
    "gpu-batch": {
      "provider": "llama.cpp",
      "model": "llama-3.1-8x22b",
      "description": "Runs GPU-bound inference; limited by the 'gpu' group.",
      "groups": ["gpu"]
    }
  },
  "groups": { "gpu": 1 },
  "slots": { "llama-pc/lfm": 4, "openrouter/anthropic/claude-sonnet-4.5": 4 }
}
```

- `provider`, `model` — **required**. The subagent is hard-bound to that model of that provider. The provider is
  refreshed and the pair resolved when the task spawns, so a wrong one is a spawn error naming it and a llama.cpp
  model whose context was re-fit since pi started is handed its live window; a server that is not answering just
  leaves the catalog pi already has.
- `description` — optional, shown in the spawn tool so the main agent knows what each subagent is for.
- `tools` — optional. Which tools the subagent gets, chosen from the main agent's active set read at spawn
  (`pi.getActiveTools()`); the five `subagent_*` tools are **always** excluded. Three shapes:
  - **omitted** — the main agent's tools as it stands, so `--tools`, the `defaultTools` setting and tools registered by
    extensions all carry over.
  - **a list** — exactly that allowlist and nothing else, and it is absolute rather than a narrowing of what the main
    agent has: pi registers only the listed built-ins in the subagent's session, so it can hand out a tool the main
    agent is sitting without. MCP tools only survive if an entry starts with `mcp__`, and a name pi does not know is
    dropped silently — a typo just leaves the subagent short of tools.
  - **`{ "enable": [...] }`** — the same as a list. **`{ "disable": [...] }`** — the main agent's tools minus those.
    The two keys are mutually exclusive.
- A named tool has to exist in the subagent's session or pi drops it without a word. That session is an SDK session and
  loads none of the CLI's built-in extensions, so the task supplies `codemode` itself; `tool_search` and MCP tools are
  not loaded, and naming them does nothing.
- `groups` — names of the concurrency groups below. The top-level `groups` map holds their limits, and a limit counts
  how many *distinct models* may hold the group at once (see "Group concurrency"). Naming one group twice is a mistake,
  so it is reported and collapsed to one.
- `slots` — optional `"provider/model": N`, stating a model's slot count where the server does not report one — a cloud
  provider, or a server that is not answering. See "Group concurrency".
The entries are validated against a TypeBox schema at load. A bad entry is dropped with a message naming it
(`[subagents] user subagent "x" skipped: /tools must be a non-empty list, or { enable } / { disable }`) and the rest
of the config stays usable. One bad limit skips the whole `groups` map. A subagent that names a group nobody gave a
limit to is reported at load *and* refused at spawn — a concurrency limit is never silently not enforced. Those
messages go to stderr at startup and are repeated as a warning toast when the session opens, so they are not lost in
the noise of a start. A file that cannot be read or parsed is not a configuration worth loading: the extension throws
and pi reports it as a failed extension, rather than starting with no subagents and no explanation.

## Group concurrency

A subagent holds a slot in every group it names, and a group's limit means **how many distinct models may hold it at
once** — the router here keeps one preset resident (`--models-max 1`), so a second, *different* model only swaps the
card. Within one model the capacity is its own **slot count**: `slots` if configured, else the preset's `--parallel`
read from `/v1/models` at spawn (which never loads a model), else 1. Two `cyber-tiel-coder` tasks (2 slots) run
together; a `qwen-27B` task beside them is refused as a residency clash. Capacity counts per model across every group,
so a model reached through two groups still runs only its slots, and a task shows where it sits as `(slot 2/2)`.
Enforced **across every pi instance and working directory** through `~/.pi/agent/subagents/leases.db`:

- **Reject, don't queue** — a spawn refused by residency (the card is on another model) or capacity (this model's slots
  are gone) returns `isError` + `details.blocked` naming the model. Nothing is created: no task record, no session,
  no session directory.
- **Atomic across groups** — several groups are taken together or not at all.
- **Crash-safe** — a lease is a claim, not a counter: it expires 90 s after the last heartbeat (renewed every 20 s) and
  any instance may reap it, so a dead process cannot deadlock a group, and `/subagents leases purge` recovers at once.
  `/subagents leases` lists only leases that still count — an expired one is a slot somebody may already be standing
  in — and names the model (`provider/model`) each is on.
- **Timers stay quiet** — the reap and heartbeat ticks swallow database errors and wait for the next tick. pi turns an
  uncaught exception in a callback into a crash record and `exit(1)`, so a locked database is never allowed to be fatal.
- **Clean exit** — `session_shutdown` aborts running tasks and releases this instance's leases. pi fires it on quit and
  on `/new`, `/fork`, `/resume`, `/import` and `/reload`, so any of those stops the tasks this instance started.
- **The main session is not leased** — nothing here knows which model the main agent itself is using. If it shares this
  card, its own requests can swap away the model a subagent holds; only subagents are accounted for.
- The store opens lazily on the first grouped spawn, so an untracked subagent (no `groups`) costs nothing. A lease that
  cannot be written throws with the database's own message, rather than looking like a full group.

## Tools

| Tool | Args | Behavior |
|---|---|---|
| `subagent_spawn` | `name`, `task`, `session?`, `save_session?`, `workdir?` | Starts the task in the background and returns its `id` at once. |
| `subagent_status` | `id?` | One task or all: state, elapsed, how long it has been silent, turns, tokens, what its model produced and how full its context is, last activity, retry, error. Errors on an unknown id. |
| `subagent_wait` | `ids?`, `timeout_s?` (default 300) | Returns finished-but-undelivered tasks immediately, otherwise blocks until one arrives. Delivers each task once — reading a report with `subagent_result` counts as that delivery; with `ids`, tasks it was not asked for stay queued for the next call, and ids whose task already reported are named as *nothing new* rather than as missing. Reports progress through `onUpdate` while blocked, and **ends when the request is aborted** rather than sitting out the timeout; a timed-out wait keeps naming what still runs, and a wait with nothing running and nothing queued answers at once rather than standing still for `timeout_s`. A timeout is a normal result, not an error. |
| `subagent_result` | `id` | The full report (over 20 000 chars is truncated, with the whole thing written to a temp file), followed by what the task cost. A task that ended with nothing to show says so, with its error where it has one. |
| `subagent_kill` | `id`, `timeout_s?` (default 10) | Aborts a running task; it ends `killed` holding whatever output it has. Nothing here waits longer than `timeout_s`: a task still stuck inside a session that is being created is marked killed anyway and its group slots are freed, and the abandoned runner finishes by itself. |

Workflow: spawn several in one turn → keep working → `subagent_wait` (loop; each finished subagent is delivered by
exactly one call) → `subagent_status` for the laggards, `subagent_kill` for a stuck one, `subagent_result` to re-read a
report.

## Task session directory

`session` is a short kebab-case name that decides the directory:
`.pi/subagents/sessions/<session>-<YYYY-MM-DD>-<HHMMSS>/` under the main working directory (`-2`, `-3` on a clash
within the same second). Both switches need it, and at least one of them must be set — a bare `session` asks for
nothing, so it creates no directory:

- `save_session` — persist the task's transcript there with the SDK's `SessionManager.create(cwd, dir)`. Standard
  format, openable in pi afterwards.
- `workdir` — run the subagent with that directory as its working directory, so its tools resolve paths there: an
  isolated scratchpad that leaves the project tree alone.

Directories under `.pi/subagents/sessions/` are **kept deliberately**: a saved transcript or a scratchpad is an
artifact worth having after the task ends.

## Isolation

- A subagent cannot spawn or manage subagents: all five tools are excluded whatever `tools` says.
- A subagent has no reference to the task registry, so it cannot touch other tasks.
- A subagent shares the main working directory and is *told* the main transcript path (`ctx.sessionManager.getSessionFile()`)
  as a read-only reference — an append-only JSONL log to be read with the `read` tool. That is an instruction, not a
  sandbox: `edit`/`write` are reachable unless the config's `tools` says otherwise, and a subagent with `bash` can reach
  everything the main agent can. Use an allowlist for strict setups. With an in-memory main session (no file) there is
  no path to hand out and the subagent simply gets no reference.
- Each task is its own SDK session, which means the whole extension stack in `~/.pi/agent/extensions` is loaded again
  per task. That reload, not the model, is where most of a spawn's cost goes.

## UI

- `/subagents` — every live and finished task: id, name, model, state, elapsed, last activity, and — once it has been
  quiet 15s — how long it has been quiet. Silence and `retrying N/M` are what a server that is not answering looks
  like; `starting…` with nothing after it means the model was never reached.
- `/subagents <id>` — the same line, plus turns and tokens (and the retry, mid-backoff), plus a preview of the task's
  recent assistant text.
- `/subagents kill <id>` — the user's own abort (tab-completion offers the running ids).
- `/subagents leases` · `purge` · `drop <group>` · `drop-all` — the cross-instance accounting, which stays out of the
  task views.
- `renderCall`/`renderResult` on all five tools. Expanded views show state, elapsed, error, last activity and the tail
  of the output; `details` carry a bounded summary rather than the whole report, because they are persisted into the
  session file.
- While `subagent_wait` blocks, its widget shows per running task what it is doing and the last three lines of its own
  text. That tail is handed to the renderer by the wait's progress updates only, so it never reaches `details` or a
  finished task's report.
- A settled task reports no last activity — `DONE 12s — writing…` would read as still going. An aborted one keeps the
  line it stopped on, which is the case where it says something.
- Every report line ends with what the task's model is doing with its context: `… · out 1.2k · ctx 41.2k/262k (16%)`.
  `out` is the tokens its own model produced; while a turn is still decoding it is counted off the stream and shown as
  `out ~1.2k`, replaced by the model's figure the moment the turn ends. `ctx` is pi's context estimate for the
  subagent's session against its window, refreshed with every status emit, so the blocked `subagent_wait` widget shows
  it climbing while the task works.
- A task's tokens and cost reach the main session's totals **once**, from whichever tool collects it first — `pi`
  adds up the `usage` of every tool result it is handed, so reporting twice would count the same calls twice.
- A toast fires when a task reaches `done`/`failed`/`killed`, from the task itself — it arrives whether or not anyone
  is waiting on it, and only once, not again when the report is read.
- `pi.events` gets a snapshot of the running tasks on `subagents:status`, `{ tasks: [{ id, name, model, state, elapsed,
  idle, turns, tokens, lastActivity, retry, error, recentOutput }] }`, whenever their state changes. Nothing in this
  setup subscribes to it yet; it is the seam a footer segment would attach to. Emitting into a session pi has replaced
  throws, so the snapshot swallows that rather than outliving its session.

The `Usage` those two tools report is synthetic — total tokens and total cost, no input/output/cache split.

## Implementation layout

```
subagents/
  index.ts            # config load, five tools, /subagents, lifecycle
  config.ts           # subagents.json schema, merging and tool resolution
  slots.ts            # SlotResolver: a model's slot count — config, then the server's --parallel, then 1
  task.ts             # SubagentTask: createAgentSession, progress events, outcome, lease release
  state.ts            # task registry + completion queue, TaskSummary for details and events, kill with a deadline
  store.ts            # LeaseStore: cross-instance concurrency over a shared SQLite file — a group counts models, a model counts slots
  ui.ts               # event emission, renderCall/renderResult, completion toast
  test-utils/check.mjs
```

## Testing

```
node test-utils/check.mjs        # ~1 s, no pi running, no model called; exits non-zero on failure
```

`state.ts` and `store.ts` import nothing outside node, so their assertions run directly. `config.ts` (`typebox`) and
`ui.ts` (`pi-tui`) need pi's `node_modules`: the script locates it through the `pi` on `PATH`, or takes
`PI_NODE_MODULES=/nix/store/<hash>-pi/lib/pi/node_modules`. If neither works the two sections are reported as SKIP and
the run still fails, so a missing dependency is never mistaken for a passing suite.

What it pins down, mostly with the bugs it was written against:

- **registry** — a claim filtered by `ids` leaves the other finished tasks claimable instead of throwing them away;
  every task is delivered exactly once; a wait for `task-b` survives `task-a` finishing and is still woken when `task-b`
  does (a waiter dropped by an unasked-for finish used to sit out the whole timeout); abort ends the wait; `elapsed`
  measures startedAt to finishedAt and stops there; `details` carry a bounded output.
- **kill** — a task that never settles is killed anyway, inside the deadline, with its group slots handed back; one
  that stops cleanly says so; killing a finished task is not a second kill; a task stopped between turns keeps what it
  had already said as its report.
- **tokens** — a running task counts what it is still writing and marks it live, a finished one reports the model's own
  figure, and `out …/ctx …/%` formats as `out 1.2k · ctx 41.2k/262k (16%)`, or `ctx ?/262k` when pi cannot estimate.
- **leases** — a limit rejects a *different* model and admits several of the same one up to its slots (2 and 4 are
  exercised), a multi-group claim fills all groups or none and counts once toward capacity, the slot label counts
  spawns rather than lease rows, `list()` returns the column names the code reads (`expiresAt`, not `expires_at`) and
  the model each lease is on, and hides a lease whose slot already expired; `close()` empties the instance's leases and
  refuses further claims.
- **slots** — `--parallel` comes out of a preset's launch args (absent or malformed means 1), a configured override
  wins, and a server that is not answering means one slot rather than a failed spawn.
- **config** — `enable` with `disable`, a non-list `enable`, a misspelled tool key and a missing provider/model are all
  refused with a message naming the entry; a file that cannot be parsed throws; a group named twice is collapsed and
  reported; project overrides user; one bad group limit skips the map; no list inherits the main agent's tools,
  `disable` subtracts from them, and a tool the main agent lacks never leaks in.
- **renderers** — the state paints as text (once it was `[object Object]`), all five survive a result whose `details`
  are missing (pi then shows a plain-text fallback and logs nothing, so this is easy to lose), a completion toasts once
  rather than again when the report is read, an abort never overwrites the activity line with a model error — not even
  the turn pi opens while aborting — a blocked spawn says which group, elapsed formats as `41s` / `3m12s` / `1h05m`, a
  live wait shows the subagent's last lines and says it is still running, and a timed-out wait says so.
- **entry point** — `index.ts` loaded against a fake pi: the five tools and the command register, and every way into a
  spawn fails with a message before a session could be created (unconfigured name, unknown model, `save_session`/
  `workdir` without a `session`, a name that is not kebab-case, a group with no limit — and no lease taken for that
  one). Also the wait/kill messages for ids that do not exist, the aborted wait, and the `/subagents` subcommands.
  The fixture gives no subagent a resolvable model, so the run cannot reach a server.

Not covered: `task.ts` and `index.ts` end to end, which need a live model — do that in a real pi session with a
`subagents.json` naming a small local model, and follow the rule in `../llama-dx/TESTING.md`: a test that reaches a
server never takes one from pi's default model. The fake-pi fixture deliberately gives no subagent a resolvable model,
so it cannot create a task record; the wording of `subagent_wait` for ids already delivered, and of a `subagent_kill`
that ran out of time, is therefore checked only at the `killRecord` level.
