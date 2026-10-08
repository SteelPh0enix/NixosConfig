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
  "groups": { "gpu": 1 }
}
```

- `provider`, `model` — **required**. The subagent is hard-bound to that model of that provider. The pair is resolved
  when the task spawns, so a wrong one is a spawn error naming it.
- `description` — optional, shown in the spawn tool so the main agent knows what each subagent is for.
- `tools` — optional. Which tools the subagent gets, chosen from the main agent's active set read at spawn
  (`pi.getActiveTools()`); the five `subagent_*` tools are **always** excluded. Three shapes:
  - **omitted** — the main agent's tools as it stands, so `--tools`, the `defaultTools` setting and tools registered by
    extensions all carry over.
  - **a list** — exactly that allowlist and nothing else. pi treats an explicit allowlist strictly: MCP tools only
    survive if an entry starts with `mcp__`.
  - **`{ "enable": [...] }`** — the same as a list. **`{ "disable": [...] }`** — the main agent's tools minus those.
    The two keys are mutually exclusive.
- A named tool has to exist in the subagent's session or pi drops it without a word. That session is an SDK session and
  loads none of the CLI's built-in extensions, so the task supplies `codemode` itself; `tool_search` and MCP tools are
  not loaded, and naming them does nothing.
- `groups` — names of the concurrency groups below; the top-level `groups` map holds their limits.

The file is validated against a TypeBox schema at load. A bad entry is dropped with a message naming it
(`[subagents] user subagent "x" skipped: /tools must be a non-empty list, or { enable } / { disable }`) and the rest
of the config stays usable. One bad limit skips the whole `groups` map. A subagent that names a group nobody gave a
limit to is reported at load *and* refused at spawn — a concurrency limit is never silently not enforced.

## Group concurrency

A subagent holding a slot in every group it names; the limit is how many may run at once, enforced **across all pi
instances and all working directories** through the shared SQLite store at `~/.pi/agent/subagents/leases.db`:

- **Reject, don't queue** — a spawn into a full group returns an error result (`isError`, `details.blocked`) naming the
  full group(s). Nothing is created: no task record, no session, no session directory.
- **Atomic across groups** — several groups are taken together or not at all.
- **Crash-safe** — a lease is a claim, not a counter: it expires 90 s after the last heartbeat (renewed every 20 s) and
  any instance may reap it, so a dead process cannot deadlock a group. `/subagents leases purge` recovers at once.
- **Clean exit** — `session_shutdown` aborts running tasks and releases this instance's leases.
- The store opens lazily on the first grouped spawn, so an untracked subagent (no `groups`) costs nothing. A lease that
  cannot be written throws with the database's own message, rather than looking like a full group.

## Tools

| Tool | Args | Behavior |
|---|---|---|
| `subagent_spawn` | `name`, `task`, `session?`, `save_session?`, `workdir?` | Starts the task in the background and returns its `id` at once. |
| `subagent_status` | `id?` | One task or all: state, elapsed, how long it has been silent, turns, tokens, last activity, retry, error. Errors on an unknown id. |
| `subagent_wait` | `ids?`, `timeout_s?` (default 300) | Returns finished-but-undelivered tasks immediately, otherwise blocks until one arrives. Delivers each task once; with `ids`, tasks it was not asked for stay queued for the next call. Reports progress through `onUpdate` while blocked, and **ends when the request is aborted** rather than sitting out the timeout; a timed-out wait keeps naming what still runs. A timeout is a normal result, not an error. |
| `subagent_result` | `id` | The full report (over 20 000 chars is truncated, with the whole thing written to a temp file). |
| `subagent_kill` | `id` | Aborts a running task; it ends `killed` holding whatever output it has. |

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
- A toast fires when a task reaches `done`/`failed`/`killed`, from the task itself — it arrives whether or not anyone
  is waiting on it.
- `pi.events` gets a snapshot of the running tasks on `subagents:status`, `{ tasks: [{ id, name, model, state, elapsed,
  idle, turns, tokens, lastActivity, retry, error, recentOutput }] }`, whenever their state changes. Nothing in this
  setup subscribes to it yet; it is the seam a footer segment would attach to. Emitting into a session pi has replaced
  throws, so the snapshot swallows that rather than outliving its session.

Token and cost totals of the subagent models are folded into the `usage` of `subagent_wait` and `subagent_result`. That
`Usage` is synthetic — total tokens and total cost, no input/output/cache split.

## Implementation layout

```
subagents/
  index.ts            # config load, five tools, /subagents, lifecycle
  task.ts             # SubagentTask: createAgentSession, progress events, outcome, lease release
  state.ts            # task registry + completion queue, TaskSummary for details and events
  store.ts            # LeaseStore: cross-instance per-group concurrency over a shared SQLite file
  ui.ts               # event emission, renderCall/renderResult, completion toast
  test-utils/check.mjs
```

## Testing

```
node test-utils/check.mjs        # ~2 s, no pi running, no model called; exits non-zero on failure
```

`state.ts` and `store.ts` import nothing outside node, so their assertions run directly. `config.ts` (`typebox`) and
`ui.ts` (`pi-tui`) need pi's `node_modules`: the script locates it through the `pi` on `PATH`, or takes
`PI_NODE_MODULES=/nix/store/<hash>-pi/lib/pi/node_modules`. If neither works the two sections are reported as SKIP and
the run still fails, so a missing dependency is never mistaken for a passing suite.

What it pins down, mostly with the bugs it was written against:

- **registry** — a claim filtered by `ids` leaves the other finished tasks claimable instead of throwing them away;
  every task is delivered exactly once; a wait for `task-b` is not woken by `task-a`; abort ends the wait; `elapsed`
  measures startedAt to finishedAt and stops there; `details` carry a bounded output.
- **leases** — the limit rejects, a multi-group claim fills all groups or none, `list()` returns the column names the
  code reads (`expiresAt`, not `expires_at`), `close()` empties the instance's leases and refuses further claims.
- **config** — `enable` with `disable`, a non-list `enable`, a misspelled tool key and a missing provider/model are all
  refused with a message naming the entry; project overrides user; one bad group limit skips the map; no list inherits
  the main agent's tools, `disable` subtracts from them, and a tool the main agent lacks never leaks in.
- **renderers** — the state paints as text (once it was `[object Object]`), an abort never overwrites the activity line
  with a model error, a blocked spawn says which group, elapsed
  formats as `41s` / `3m12s` / `1h05m`, a live wait shows the subagent's last lines and says it is still running, and a
  timed-out wait says so.
- **entry point** — `index.ts` loaded against a fake pi: the five tools and the command register, and every way into a
  spawn fails with a message before a session could be created (unconfigured name, unknown model, `save_session`/
  `workdir` without a `session`, a name that is not kebab-case, a group with no limit — and no lease taken for that
  one). Also the wait/kill messages for ids that do not exist, the aborted wait, and the `/subagents` subcommands.
  The fixture gives no subagent a resolvable model, so the run cannot reach a server.

Not covered: `task.ts` and `index.ts` end to end, which need a live model — do that in a real pi session with a
`subagents.json` naming a small local model, and follow the rule in `../llama-dx/TESTING.md`: a test that reaches a
server never takes one from pi's default model.
