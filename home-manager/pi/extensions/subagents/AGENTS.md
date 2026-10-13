# subagents internals

For whoever changes the extension. [README.md](README.md) covers the config, the tools and the commands; this is how
they are enforced, what is hidden from a subagent, and what the test suite pins down.

## Group concurrency

A subagent holds a slot in every group it names, and a group's limit means **how many distinct models may hold it at
once** — the router here keeps one preset resident (`--models-max 1`), so a second, *different* model only swaps the
card. Within one model the capacity is its own **slot count**, taken from the `slots` map and defaulting to 1 for a
model nobody listed.

Two `cyber-tiel-coder` tasks (2 slots) run together; a `qwen-27B` task beside them is refused as a residency clash.
Capacity counts per model across every group, so a model reached through two groups still runs only its slots, and a
task shows where it sits as `(slot 2/2)`.

Enforced **across every pi instance and working directory** through `~/.pi/agent/subagents/leases.db`:

- **Reject, don't queue** — a spawn refused by residency (the card is on another model) or capacity (this model's
  slots are gone) returns `isError` + `details.blocked` naming the model. Nothing is created: no task record, no
  session, no session directory.
- **Atomic across groups** — several groups are taken together or not at all.
- **Crash-safe** — a lease is a claim, not a counter: it expires 90 s after the last heartbeat (renewed every 20 s)
  and any instance may reap it. `/subagents leases` lists only leases that still count — an expired one is a slot
  somebody may already be standing in — and names the model (`provider/model`) each is on.
- **Timers stay quiet** — the reap and heartbeat ticks swallow database errors and wait for the next tick. pi turns an
  uncaught exception in a callback into a crash record and `exit(1)`, so a locked database is never allowed to be
  fatal.
- **Clean exit** — `session_shutdown` aborts running tasks and releases this instance's leases. pi fires it on quit
  and on `/new`, `/fork`, `/resume`, `/import` and `/reload`, so any of those stops the tasks this instance started.
- The store opens lazily on the first grouped spawn, so an untracked subagent (no `groups`) costs nothing. A lease
  that cannot be written throws with the database's own message, rather than looking like a full group.

Validation happens at load, keys included, through a TypeBox schema: `enable` together with `disable`, a non-list
`enable`, a misspelled tool key, a key an entry should not have and a missing provider/model are all refused with a
message naming the entry. A group named twice is a mistake, so it is reported and collapsed to one.

## Isolation

- A subagent cannot spawn or manage subagents: all five tools are excluded whatever `tools` says.
- A subagent has no reference to the task registry, so it cannot touch other tasks.
- A subagent shares the main working directory and is *told* the main transcript path
  (`ctx.sessionManager.getSessionFile()`) as a read-only reference — an append-only JSONL log to be read with the
  `read` tool. That is an instruction, not a sandbox. With an in-memory main session (no file) there is no path to
  hand out and the subagent simply gets no reference.
- A named tool has to exist in the subagent's session or pi drops it without a word. That session is an SDK session
  and loads none of the CLI's built-in extensions, so the task supplies `codemode` itself; `tool_search` and MCP tools
  are not loaded. MCP tools only survive an allowlist if an entry starts with `mcp__`, and a name pi does not know is
  dropped silently — a typo just leaves the subagent short of tools.
- Each task is its own SDK session, which means the whole extension stack in `~/.pi/agent/extensions` is loaded again
  per task. That reload, not the model, is where most of a spawn's cost goes.

## System prompt

The extension introduces itself. `before_agent_start` fills `systemPromptOptions.sections.subagents` with what the
extension is for, how the five calls differ, and the group and slot limits *read out of the config* — the same
numbers `store.ts` enforces, so what the model is told cannot drift from what it gets. Built once at load and never
rewritten mid-session, so the prompt cache stays warm.

It reaches only a session that holds `subagent_spawn`. A subagent's own session has all five tools stripped (see
[Isolation](#isolation)), so it never gets the section and is never invited to recurse. Nothing about subagents
belongs in `APPEND_SYSTEM.md`.

### The subagent's own prompt

`config.ts` turns an entry's `prompt` into text while loading — a value naming a file (one line, absolute or
path-like, which means it contains `/` or ends in `.md`) is read there and trimmed, resolved against the directory of
the config that declared it; anything else is the text. That test is the whole rule, so a one-line instruction written
with a path or a `.md` in it is looked for on disk. A file that is missing or empty is an entry error, so a subagent
never ends up prompted with its own filename. A new prompt file needs a link of its own in `home-manager/pi/default.nix` - `${agentDir}/subagents` is a
real directory, the lease database lives there, so a directory-wide link is not possible - which is what the suite
asserts, since a file that is missing only from the installed config is otherwise invisible until activation.

`task.ts` hands the task's resource loader one more extension (`subagentPromptExtension`, hidden from the startup
list), and its `before_agent_start` calls `applySubagentPrompt` from `prompt.ts`:

- **append** (the default) puts the text at the end of `appendSystemPrompt`, where pi collects `APPEND_SYSTEM.md`;
  everything else pi builds stays.
- **replace** (`replace_system_prompt`) sets `customPrompt` — that is what makes pi drop its preamble, rules and docs —
  and empties `appendSystemPrompt`, `contextFiles` and `skills`, so neither `APPEND_SYSTEM.md`, nor the repo's
  `AGENTS.md`, nor the skills list reaches a subagent running on its own prompt. pi renders no `<tools>` section for a
  custom prompt, so the tool index is rendered from `selectedTools` and `toolSnippets` the way pi renders it and put
  into `sections.tools`; a section by that name is allowed (`preamble` is the one name that is not).

`forceSystemPrompt` is deliberately unused: it replaces the whole prompt opaquely, with no sections for pi to diff on
later. Tool names, descriptions and schemas travel with the request whatever the mode, so replacing the prompt hides
no tool — the `<tools>` index is only the one-line list. pi normalizes the prompt options once per
`before_agent_start` emit and hands that one object to every handler, so these mutations never reach the session's own
base options, but a handler registered after this one does see them - including the emptied `appendSystemPrompt` of a
replaced prompt.

The fixed "you are a background subagent…" framing lives in `prompt.ts` (`SUBAGENT_FRAMING`) and is part of the system
prompt in both modes; the user message is only the read-only transcript reference, the report rule and the task.

## Task session directory

`session` is required: a short kebab-case name that names the task and decides the directory
`.pi/subagents/sessions/<session>-<YYYY-MM-DD>-<HHMMSS>/` under the main working directory (`-2`, `-3` on a clash
within the same second). Every task's transcript is persisted there with the SDK's `SessionManager.create(cwd, dir)`
— standard format, openable in pi afterwards.

- `workdir` — run the subagent with that directory as its working directory, so its tools resolve paths there.

## UI

- `renderCall`/`renderResult` on all five tools. Expanded views show state, elapsed, error, last activity and the
  tail of the output; `details` carry a bounded summary rather than the whole report, because they are persisted into
  the session file.
- While `subagent_wait` blocks, its widget shows per running task what it is doing and the last three lines of its own
  text. That tail is handed to the renderer by the wait's progress updates only, so it never reaches `details` or a
  finished task's report. `subagent_wait` reports progress through `onUpdate` while blocked and **ends when the
  request is aborted** rather than sitting out the timeout; a timed-out wait keeps naming what still runs, and a wait
  with nothing running and nothing queued answers at once rather than standing still for `timeout_s`. With `ids`,
  tasks it was not asked for stay queued for the next call, and ids whose task already reported are named as *nothing
  new* rather than as missing.
- A settled task reports no last activity — `DONE 12s — writing…` would read as still going. An aborted one keeps the
  line it stopped on, which is the case where it says something.
- The activity line names the step, not just "writing": while a tool runs it carries the tool, its argument summary
  and a live timer (`bash: sleep 60 (4.2s)`), and a finished call leaves its outcome and duration behind. The
  expanded view adds the last few calls as `read 0.3s · ✗bash 4.2s`, bounded to `RECENT_TOOLS_LIMIT`.
- Every report line ends with what the task's model is doing with its context: `… · out 1.2k · ctx 41.2k/262k (16%)`.
  `out` is the tokens its own model produced; while a turn is still decoding it is counted off the stream and shown as
  `out ~1.2k` — thinking counted, not only the answer text — replaced by the model's figure the moment the turn ends.
  `ctx` is pi's context estimate for the subagent's session against its window, refreshed with every status emit, so
  the blocked `subagent_wait` widget shows it climbing while the task works.
- A task's tokens and cost reach the main session's totals **once**, from whichever tool collects it first — `pi`
  adds up the `usage` of every tool result it is handed, so reporting twice would count the same calls twice. The
  `Usage` those two tools report is synthetic: what the task's model produced comes back as `output` and the rest of
  its tokens as `input`, with no cache split and every cost but the total at zero.
- A toast fires when a task reaches `done`/`failed`/`killed`, from the task itself — it arrives whether or not anyone
  is waiting on it, and only once, not again when the report is read.
- `pi.events` gets a snapshot of the running tasks on `subagents:status`,
  `{ tasks: [{ id, name, model, state, elapsed, idle, turns, tokens, lastActivity, tool, recentTools, retry, error, recentOutput }] }`,
  whenever their state changes. `../llama-dx` subscribes to it and paints a row of its own above the two llama.cpp
  lines, so nothing here is drawn from it. Emitting into a session pi has replaced throws, so the snapshot swallows
  that rather than outliving its session.

## Implementation layout

```
subagents/
  index.ts            # config load, five tools, /subagents, system prompt section, lifecycle
  config.ts           # subagents.json schema, merging, prompt files and tool resolution
  prompt.ts           # the section a spawning session is given, and how a subagent's own prompt is applied
  task.ts             # SubagentTask: createAgentSession, the prompt extension, progress events, outcome, lease release
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
  every task is delivered exactly once; a wait for `task-b` survives `task-a` finishing and is still woken when
  `task-b` does (a waiter dropped by an unasked-for finish used to sit out the whole timeout); abort ends the wait;
  `elapsed` measures startedAt to finishedAt and stops there; `details` carry a bounded output.
- **kill** — a task that never settles is killed anyway, inside the deadline, with its group slots handed back; one
  that stops cleanly says so; killing a finished task is not a second kill; a task with no runner is killed rather than
  left running; a kill that ran out of time queues the task so a wait can still deliver it; a task stopped between
  turns keeps what it had already said as its report, and the tail it keeps is as bounded as any other.
- **tools** — a running tool is kept with its start time and shows a live timer; finishing it records the duration and
  the error flag, and the breadcrumb stays bounded; `formatDuration` reads `0.3s` / `4.2s` / `1m02s`.
- **tokens** — a running task counts what it is still writing (thinking included) and marks it live, a finished one
  reports the model's own figure, and `out …/ctx …/%` formats as `out 1.2k · ctx 41.2k/262k (16%)`, or `ctx ?/262k`
  when pi cannot estimate; `oneLine` collapses, trims and cuts to its limit, and `formatTokens` reads `999`, `1.2k`,
  `147k`.
- **leases** — a limit rejects a *different* model and admits several of the same one up to its slots (2 and 4 are
  exercised), a multi-group claim fills all groups or none and counts once toward capacity, the slot label counts
  spawns rather than lease rows, `list()` returns the column names the code reads (`expiresAt`, not `expires_at`) and
  the model each lease is on, and hides a lease whose slot already expired; `close()` empties the instance's leases and
  refuses further claims.
- **slots** — a configured `slots` map loads and refuses a non-integer or a limit below 1; an unlisted model is one
  slot. Nothing is probed at spawn.
- **config** — `enable` with `disable`, a non-list `enable`, a misspelled tool key, a key an entry should not have and
  a missing provider/model are all refused with a message naming the entry; a file that cannot be parsed throws; a
  group named twice is collapsed and reported; project overrides user; one bad group limit skips the map; no list
  inherits the main agent's tools, `disable` subtracts from them, and a tool the main agent lacks never leaks in.
- **prompt files** — a `prompt` that names a file is read from the declaring config's own directory (user config and
  project config each get their own), trimmed, and kept as text when it is not path-like; a missing or empty file drops
  the entry naming it, `replace_system_prompt` without a `prompt` is refused, and the `subagents.json` this repo ships
  is loaded for real — the repo checkout, or `~/.pi/agent` when the suite runs from the installed copy — so every
  prompt it names has to exist; run from the repo it also requires each of them to be linked by
  `home-manager/pi/default.nix`.
- **subagent prompt** — the framing alone when an entry has no `prompt`; appending joins it after what pi had and
  touches nothing else; replacing sets `customPrompt`, empties the global append, the context files and the skills,
  and rebuilds the tool index from the snippets (tools without one are left out, and an empty index still says
  `(none)`); the extension `task.ts` registers asks for `before_agent_start` and stays hidden.
- **system prompt** — the section names all five tools, quotes the group limit and each model's slot count straight
  from the config, lists each subagent under the model it runs on with the roomiest model first, explains a refusal as
  a refusal rather than a queue, and is empty when nothing is configured.
- **renderers** — the state paints as text (once it was `[object Object]`), all five survive a result whose `details`
  are missing (pi then shows a plain-text fallback and logs nothing, so this is easy to lose), a completion toasts once
  rather than again when the report is read, an abort never overwrites the activity line with a model error — not even
  the turn pi opens while aborting — a blocked spawn says which group, elapsed formats as `41s` / `3m12s` / `1h05m`, a
  live wait shows the subagent's last lines and says it is still running, and a timed-out wait says so.
- **entry point** — `index.ts` loaded against a fake pi: the five tools and the command register, the spawn tool's
  `name` carrying every configured subagent with its description, and every way into a spawn fails with a message
  before a session could be created (unconfigured name, unknown model, a missing or non-kebab-case `session`, a group
  with no limit — and no lease taken for that one). Also the wait/kill messages for ids that do not exist, the aborted
  wait, the `/subagents` subcommands (including `leases drop <group>`), and `before_agent_start` adding the prompt
  section only when `subagent_spawn` is active. The fixture gives no subagent a resolvable model, so the run cannot
  reach a server.

Not covered: `task.ts` and `index.ts` end to end, which need a live model — do that in a real pi session with a
`subagents.json` naming a small local model, and follow the rule in `../llama-dx/TESTING.md`: a test that reaches a
server never takes one from pi's default model. The prompt pipeline is the part that can be checked without pi: build
a `DefaultResourceLoader` with `extensionFactories: [createCodemodeExtension(), subagentPromptExtension(text, replace)]`,
prompt a small model, and read the `sections` of the system message — appending leaves `preamble`, `tools`, `rules`,
`docs`, `addendum`, `cwd` and puts the role text at the end of `addendum`; replacing leaves `preamble` (the role text),
`tools` (rendered here) and `cwd` and nothing else. The fake-pi fixture deliberately gives no subagent a resolvable model,
so it cannot create a task record; the wording of `subagent_wait` for ids already delivered, and of a `subagent_kill`
that ran out of time, is therefore checked only at the `killRecord` level.
