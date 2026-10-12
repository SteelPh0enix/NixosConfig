# subagents

Spawns background subagents: the main agent delegates a task to a named subagent — each bound to one provider and
model — keeps working, watches progress, manages the task, and reads the result. Only subagents in the config exist:
the spawn tool's `name` parameter is built from the config, so anything unconfigured is invisible to the model.

## What it adds

| Tool | Args | Behavior |
|---|---|---|
| `subagent_spawn` | `name`, `task`, `session?`, `save_session?`, `workdir?` | Starts the task in the background and returns its `id` at once. |
| `subagent_status` | `id?` | One task or all: state, elapsed, how long it has been silent, turns, tokens, what its model produced and how full its context is, last activity, retry, error. Errors on an unknown id. |
| `subagent_wait` | `ids?`, `timeout_s?` (default 300) | Blocks until a task finishes and returns it. Each task is delivered once, and reading a report with `subagent_result` counts as that delivery. A timeout is a normal result, not an error. |
| `subagent_result` | `id` | The full report (over 20 000 chars is truncated, with the whole thing written to a temp file), followed by what the task cost. A task that ended with nothing to show says so, with its error where it has one. |
| `subagent_kill` | `id`, `timeout_s?` (default 10) | Aborts a running task; it ends `killed` holding whatever output it has. |

Workflow: spawn several in one turn → keep working → `subagent_wait` (loop; each finished subagent is delivered by
exactly one call) → `subagent_status` for the laggards, `subagent_kill` for a stuck one, `subagent_result` to re-read
a report. A toast fires when a task reaches `done`/`failed`/`killed`, whether or not anyone is waiting on it.

`session` names a directory under `.pi/subagents/sessions/` and both remaining switches need it: `save_session` keeps
the task's transcript there, `workdir` runs the task inside it as an isolated scratchpad. Those directories are kept
deliberately — a transcript or scratchpad is an artifact worth having after the task ends.

## Configuration

User-level `~/.pi/agent/subagents.json` · project-level `.pi/subagents.json`. Both are read once at startup, from the
directory pi was started in, so **edits need a restart**. The files merge: project entries append, and on a name clash
the project entry wins.

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
  "slots": { "llama-pc/lfm": 4, "llama-pc/cyber-tiel-coder": 2 }
}
```

- `provider`, `model` — **required**. The subagent is hard-bound to that model of that provider. The provider is
  refreshed and the pair resolved when the task spawns, so a wrong one is a spawn error naming it, a llama.cpp model
  whose context was re-fit since pi started is handed its live window, and a server that is not answering just leaves
  the catalog pi already has.
- `description` — optional, listed as one `name: description` line on the `name` parameter of `subagent_spawn`, which
  is the only place the main agent reads it. Worth naming what the subagent is for and how many slots its model has,
  since a spawn for a model another task already holds is refused.
- `tools` — optional. Which tools the subagent gets, chosen from the main agent's active set at spawn. Omitted: the
  main agent's tools as it stands, so `--tools`, the `defaultTools` setting and tools registered by extensions all
  carry over. A list (or `{ "enable": [...] }`): exactly that allowlist and nothing else. `{ "disable": [...] }`: the
  main agent's tools minus those. The two keys are mutually exclusive, and the five `subagent_*` tools are **always**
  excluded.
- `groups` — names of the concurrency groups whose limits the entry obeys.
- `slots` — top-level map of `"provider/model": N`, how many of that model may run at once. It is stated by hand, and
  a model left out of it has one slot. Take the number for a llama.cpp preset from the router's `--parallel`, which
  costs no load:

  ```bash
  curl -s http://<router>:51536/v1/models | jq -r '.data[] | "\(.id): \(.status.args | index("--parallel") as $i | if $i then .[$i + 1] else 1 end)"'
  ```

A subagent has to name tools that exist where it runs: its session is an SDK session, so `codemode` has to be
supplied by the task, and `tool_search` and MCP tools are not loaded whatever you name.

## Commands

- `/subagents` — every live and finished task: id, name, model, state, elapsed, last activity and, once it has been
  quiet 15s, how long it has been quiet. Silence and `retrying N/M` are what a server that is not answering looks
  like; `starting…` with nothing after it means the model was never reached.
- `/subagents <id>` — the same line, plus turns and tokens, plus a preview of the task's recent output.
- `/subagents kill <id>` — the user's own abort (tab-completion offers the running ids).
- `/subagents leases` · `purge` · `drop <group>` · `drop-all` — the cross-instance concurrency accounting.

## Setup gotchas

- A config file that cannot be read or parsed is not a configuration worth loading: the extension throws and pi
  reports a failed extension, rather than starting with no subagents and no explanation. One bad *entry* is dropped
  with a message naming it and the rest stays usable; one bad limit skips the whole `groups` map. Those messages go to
  stderr at startup and are repeated as a warning toast when the session opens.
- Keys are checked, so a typo is caught rather than loaded as something weaker: an entry carrying `group` instead of
  `groups` is refused, and a subagent naming a group nobody gave a limit to is reported at load *and* refused at
  spawn. A concurrency limit is never silently not enforced.
- Refusals are refusals, not queues. A spawn is refused when this model's slots are gone, or when it would put a
  second, *different* preset on a card that keeps one resident — the error names the model and the group, and nothing
  is created: no task record, no session, no session directory. Retry once something else finishes.
- Concurrency is enforced across every pi instance and working directory through `~/.pi/agent/subagents/leases.db`. A
  lease expires 90 s after its last heartbeat and any instance may reap it, so a dead process cannot deadlock a group;
  `/subagents leases purge` recovers at once.
- Nothing here knows which model the main session is on. If the main agent shares the card, its own requests can swap
  away the model a subagent holds — only subagents are accounted for.
- A subagent shares the main working directory, and `edit`/`write` are reachable unless the config's `tools` says
  otherwise; a subagent with `bash` can reach everything the main agent can. Use an allowlist for a strict setup. A
  subagent cannot spawn or manage subagents.
- Each task is its own SDK session, which reloads the whole extension stack — most of a spawn's cost, not the model.

Internals — concurrency mechanics, isolation, the system prompt section, the layout and the test suite:
[AGENTS.md](AGENTS.md).
