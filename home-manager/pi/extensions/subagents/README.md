# subagents extension

Spawns background subagents: the main agent delegates a task to a named subagent (bound to a
specific provider + model), keeps working, then watches progress, manages the task, and reads
the result. Only subagents listed in the config exist — the main agent sees and can spawn
exactly those.

## Configuration

User-level: `~/.pi/agent/subagents.json` · Project-level: `.pi/subagents.json`. Project entries **append** to user entries (the maps are merged); on a name clash the project entry wins for that subagent.

```json
{
  "subagents": {
    "repo-researcher": {
      "provider": "llama.cpp",
      "model": "llama-3.3-70b-instruct",
      "description": "Reads the repo and reports findings. Read-only by convention.",
      "tools": ["read", "bash", "web_search", "web_fetch"]
    },
    "security-reviewer": {
      "provider": "openrouter",
      "model": "anthropic/claude-sonnet-4.5"
    },
    "code-reviewer": {
      "provider": "openrouter",
      "model": "anthropic/claude-sonnet-4.5",
      "tools": {
        "enable": ["read", "grep", "edit"],
        "disable": ["write"]
      }
    },
    "gpu-batch": {
      "provider": "llama.cpp",
      "model": "llama-3.1-8x22b",
      "description": "Runs GPU-bound inference. Limited to the number of concurrent runs allowed in the 'gpu' group."
    }
  },
  "groups": {
    "gpu": 1
  }
}
```

- `provider`, `model` — **required**. The subagent is hard-bound to this model of this provider.
- `description` — optional. Shown in `subagent_spawn` so the main agent knows what each subagent is for.
- `tools` — optional. Controls which of the **main agent's** tools the subagent gets (the five
  `subagents` tools are **always** excluded, so a subagent can never spawn or manage other
  subagents). It is one of three forms:
  - **omitted** — the subagent gets everything the main agent gets (the resolved `defaultTools`
    setting, so things like `+codemode` are inherited) **minus** the `subagents` tools.
  - **a list** — that exact, only allowlist; the `subagents` tools are dropped if listed.
  - **a dict** `{ enable?: string[], disable?: string[] }` — layered on top of the default set
    (the omitted-tools case). `enable` and `disable` are **mutually exclusive** (error if both set).

Validation at load: unknown provider/model, malformed entries, or `tools` with both `enable` and
`disable` are reported as extension errors; that subagent simply does not exist.

### Group concurrency (limits)

Two optional pieces, both merged across user + project configs like everything else:

- **`groups` on a subagent** — an array of group names, e.g. `"groups": ["gpu"]`. A subagent may
  name more than one group; it holds a slot in *each*.
- **top-level `groups`** — a `{ "<name>": <maxConcurrent> }` map (limits are positive integers ≥ 1).

Each subagent's `groups[]` names must appear in the map; a name that isn't declared anywhere is a
load error (reported, subagent kept, that group simply unenforced). A subagent with no `groups` is
**untracked** — it runs without any concurrency limit. Config is otherwise validated the same way.

## Group concurrency

When a subagent names one or more groups, spawning it must first **hold a slot in every group** it
names. This is enforced **across all pi instances** (and all working directories) via a shared
SQLite lease store at `~/.pi/agent/subagents/leases.db`:

- **Reject instantly when full** — if any of the subagent's groups is at capacity, the spawn returns
  an error result (`isError`, `details.blocked: true`) with a message naming the full group(s); no
  task record is created and no session is started. (It is *not* queued.)
- **Atomic multi-group** — a subagent naming several groups acquires all of them together, or none
  (if any single group is full, none are taken).
- **Crash-safe** — leases expire after 90 s and are reaped by any instance; active leases heartbeat
  every 20 s before expiry. If an instance dies, its leases self-expire and are reclaimed within
  ~2 minutes. The store is opened lazily on first spawn (not at startup) so it costs nothing unless
  a grouped subagent is used.
- **Manual cleanup** — see `/subagents leases` below. A `session_shutdown` does not force-release
  leases (an interrupted task's lease expires on its own); use `leases purge` for immediate recovery
  after a hard crash.

## Provided tools

## Provided tools

Namespace: `subagents`. All visible to the main agent only; never to subagents.

| Tool | Args | Behavior |
|---|---|---|
| `subagent_spawn` | `name` (enum of configured subagents), `task`, `session?`, `save_session?`, `workdir?` | Starts the task in the background, returns `{ id }` immediately. The main agent's turn continues. `session`/`save_session`/`workdir` see Task session directory. |
| `subagent_status` | `id?` | State of one task or all tasks: `running` / `done` / `failed` / `killed`, elapsed, last activity. |
| `subagent_wait` | `ids?`, `timeout_s?` (default 300) | Returns already-finished unclaimed tasks immediately; otherwise blocks until one or more finish. **Aggregates every task that finished during the wait into this single result** (one section per task: status + output). On timeout with no completion, returns partial status (not an error). |
| `subagent_result` | `id` | Full output of a finished task (truncated for the model, full copy saved to a temp file). |
| `subagent_kill` | `id` | Aborts a running task; it becomes `killed` with whatever output it produced. |

## Workflow

1. **Config** — extension loads config, validates entries, registers the five tools. The spawn tool's `name` enum is built from the config, so unconfigured subagents are invisible and unspawnable.
2. **Spawn** — main agent calls `subagent_spawn` (several, in one turn if independent). Each task runs in its own SDK agent session with the configured provider/model. Subagent sessions are **in-memory by default** (`SessionManager.inMemory()`) — important because `createAgentSession()` defaults to a persistent file-backed session, which would litter the session dir with one file per subagent task. Nothing is written to the main transcript or session files (unless `save_session` is used, see below).
3. **Work in parallel** — the main agent does its own work (research, tests, edits) while subagents run.
4. **Collect** — loop `subagent_wait`: every finished subagent that arrived during the wait is delivered together in one result; the main agent analyzes them and calls `subagent_wait` again for the rest. Each subagent gets a turn; simultaneous completions are aggregated, never lost.
5. **Manage** — `subagent_status` to check laggards, `subagent_kill` to cut a stuck task, `subagent_result` to re-read a full output later.
6. **Cleanup** — `session_shutdown` aborts any still-running subagents.

## Task session directory (optional)

Two independent switches on `subagent_spawn`, sharing one directory and one name:

- `session` — a short kebab-case identifier. With the creation date and time it determines the directory,
  under the main working directory: `.pi/subagents/sessions/<session>-<YYYY-MM-DD>-<HHMMSS>/`
  (e.g. `repo-scan-2025-07-10-153005`). Same name spawned twice in the same second gets `-2`, `-3`, … appended.
- `save_session` (bool, default `false`) — persist the task's session as JSONL inside that directory
  (the SDK's `SessionManager.create(cwd, sessionDir)` pointed at it). Written live per entry like any pi
  session; standard format, so it can be opened and reviewed with pi afterward.
- `workdir` (bool, default `false`) — run the subagent with that directory as its working directory instead of
  inheriting the main cwd. All of its tools (read/write/edit/bash/web…) resolve paths there, so it operates
  in an isolated scratchpad and leaves the project tree untouched.

Validation: either switch requires `session`; a `session` with both switches off is rejected. All four
combinations are valid: directory as workdir, as session store, both, or neither (plain in-memory task in
the inherited cwd).

Unlike the in-memory fallback dump (deleted with the task), directories under `.pi/subagents/sessions/` are
**kept deliberately** — a saved session or scratchpad is an artifact the user may want after the task ends.

## Isolation rules

- A subagent **cannot spawn subagents**: its session is created with all `subagents` tools excluded,
  regardless of the `tools` setting (a list, an `enable`/`disable` dict, or omitted — the
  `subagents` tools are always re-added to the exclude list).
- A subagent **cannot touch other subagents**: it has no reference to the task registry and no management tools.
- Subagents share the main working directory and see the main session **read-only**: the spawn system prompt gives them the main session file path (see below). They can read and grep it but are instructed not to modify it (their `tools` allowlist may include `edit`/`write`; the instruction, not a hard block, keeps them from it — a `read`-only allowlist is available via config for strict setups).

### Main session visibility (read-only)

Pi appends every finalized entry to the session JSONL synchronously (`appendFileSync` in `SessionManager`), so the main session file on disk is always current while the session runs — no periodic flush to wait for. Therefore:

- **Primary**: at spawn, the subagent's system prompt carries the live main session path from `ctx.sessionManager.getSessionFile()`, with the note that it is an append-only JSONL tree — to read the current conversation, follow the `parentId` chain from the leaf. Concurrent reads are safe: the file only grows, and each line is a self-contained entry.
- **Fallback**: if `getSessionFile()` is undefined (in-memory main session), the extension dumps `ctx.sessionManager.getBranch()` as JSONL into a temp file at spawn time and hands out that path instead. Temp files are cleaned up with the task.
- Model call `usage` of each subagent is folded into its `subagent_wait`/`subagent_result` result so session token totals stay accurate.

## Example usage

### 1. Parallel research while running tests

Main agent: "Find every caller of `parseConfig` in the repo" →
`subagent_spawn(repo-researcher, "Find all call sites of parseConfig, note which pass legacy-format args. Report file:line list.")` → gets `id: task-1`.
Continues its own turn: runs the test suite, fixes a failing test.
Then `subagent_wait(ids: ["task-1"])` → gets the call-site report, folds it into the change plan.

### 2. Multiple reviewers, sequential analysis

Three configured subagents: `style-reviewer`, `security-reviewer` (different provider), `perf-reviewer`.
Main agent spawns all three in one turn, each with the same diff but a different brief.
Then loops:
- `subagent_wait()` → `security-reviewer` finished first → analyze its findings, fix the CVE-style issue it found.
- `subagent_wait()` → `style-reviewer` and `perf-reviewer` both finished meanwhile → single aggregated result → analyze both in the same turn.
- `subagent_wait()` returns nothing new after timeout only if a task is stuck → `subagent_kill` it.

## UI/UX

### Footer bar: live subagent status (llama-dx integration)

The subagents extension owns the truth; llama-dx only renders it.

- **Channel**: `pi.events` — subagents emits a structured snapshot on every state change:
  `pi.events.emit("subagents:status", { tasks: [{ id, name, model, state, elapsed, lastActivity }] })`.
- **Placement**: llama-dx subscribes on load and renders it as an extra group in the **top bar** (the metrics line),
  inserted after the "this request" group and before the server (q/fl/bd) group — i.e. in the middle of that line;
  the bottom line (pi context stats + context bar) is untouched:
  `pp 14.2 tg 88 t/s │ fp 1.2k ev … │ ⚙ researcher 3m12s · sec-review 41s │ q 0 fl 1/2 bd 0.12`
  At most two tasks shown, then `+n`. Group disappears when nothing is running; `kill`/completion repaint
  immediately. It participates in the line's width-priority trimming like any group, so on narrow terminals it
  drops before the q/fl/bd group rather than squeezing it.
- **Fallback without llama-dx**: subagents also calls `ctx.ui.setStatus("subagents", …)`, which pi's
  footer (and llama-dx's status line) already render. When llama-dx draws the middle segment, it
  filters the `subagents` entry out of the status line so it is not shown twice.

### `/subagents` command

- `/subagents` — table of all live and recently finished tasks: id, name, model, state, elapsed, last activity.
- `/subagents <id>` — the same plus the task's recent output: its last assistant message and last tool call, truncated.
- `/subagents kill <id>` — manually abort a running task (same effect as the agent's `subagent_kill` tool, for user-driven cleanup).
- `/subagents leases` (or `leases list`) — list active group leases: group, subagent, owning pid, and time until expiry.
- `/subagents leases purge` — reap expired leases and remove leases whose owning process is gone (fast recovery after a crash; never frees a live slot).
- `/subagents leases drop <group>` — drop all leases for one group.
- `/subagents leases drop-all` — drop every lease.

Leases are hidden from the normal task views and the footer bar (they are cross-instance accounting,
not tasks); use the `/subagents leases ...` commands to inspect or force them.
- Shown as a transient dialog in the TUI (`ctx.hasUI` guard; in non-interactive modes it prints to the transcript).

### Tool rendering and live progress

- `renderCall`/`renderResult` for all five tools: spawn shows `id ← name (model)`; wait/status render one
  compact block per task (state, elapsed, output preview); result renders the full output with a dim header.
- `subagent_wait` streams `onUpdate` progress while blocked: the waited-on subagent's current activity
  (last tool call, text preview, elapsed) so the user can watch it without calling `subagent_status`.

### Notifications

- `ctx.ui.notify()` toast when a subagent finishes (done/failed/killed) — most useful when the main agent is
  idle or mid-wait. The toast carries the task name and id; details stay in the transcript tools.

### Other niceties

- Above-editor widget (`ctx.ui.setWidget`, `aboveEditor`) listing running tasks with live elapsed time —
  optional; useful in narrow terminals where the footer segment is truncated. Off by default.
- Consistent id color so `task-3` in a toast, the command output, and the bar are visually linkable.
- Elapsed time formatting matches llama-dx conventions (`41s`, `3m12s`) so the bar reads as one surface.

## Implementation layout

```
subagents/
  index.ts    # config load/validate, tool registration, /subagents command (+leases), session_shutdown cleanup
  task.ts     # SubagentTask: wraps createAgentSession, tracks state, captures result; releases group leases on finish
  state.ts    # in-memory task registry (id → task), completion queue for subagent_wait
  store.ts    # LeaseStore: cross-instance per-group concurrency via a shared SQLite file (acquire/heartbeat/reap/release)
  ui.ts       # pi.events emission, ctx.ui.setStatus, renderCall/renderResult, notifications
```
