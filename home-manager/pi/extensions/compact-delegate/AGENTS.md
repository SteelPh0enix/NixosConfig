# compact-delegate internals

For whoever changes the extension. [README.md](README.md) covers the config and the command; this is the contract with
pi, the invariants, and what the check covers.

## the contract

One handler, `session_before_compact`, returning `{ compaction }`. pi writes the `CompactionEntry` and rebuilds the
context from it, so the three fields have to be pi's own values and only the text is ours:

- `firstKeptEntryId` and `tokensBefore` come straight from `preparation`. Changing them moves the cut, which is pi's
  job (it also owns split user-message spans, which this extension does not compute).
- `summary` is ours, plus the `<read-files>` / `<modified-files>` tags appended.
- `usage` is the summarizer request's usage, so session totals include the work.
- `details` is `{ readFiles, modifiedFiles }`, the same shape pi's own compaction stores.

**Any path that does not produce a complete summary returns `undefined`.** Returning nothing makes pi run its own
compaction: unavailable model, request error, `stopReason` `error` or `length`, empty text. A `length` summary is a
partial checkpoint and must never be persisted, which is also what pi's own code refuses. `cancel: true` is returned
only when the abort signal already fired, so a user pressing Esc does not start a second, slower compaction.

## standing aside for a running task

A llama.cpp provider keeps one preset resident, so summarizing on another model while a subagent runs would swap that
model out and reload it for the task's next turn. `index.ts` therefore subscribes to `subagents:status` and keeps the
running tasks' `{ provider, model }`, and `session_before_compact` asks `conflictingModel()` (in `config.ts`, pure and
tested) whether the summarizer's provider is held by a different model. On a conflict it notes which model and returns
`undefined`, so pi compacts itself. The same provider with the summarizer's own model is not a conflict, and neither is
a task on another provider.

## why the caps are the way they are

pi clips each tool result to `TOOL_RESULT_MAX_CHARS = 2000` in `serializeConversation()`, because the summarization
request has to fit the window the session model just exhausted. That clip is the whole reason to delegate: the
summarizer has a window an order of magnitude larger, so `summarize.ts` has its own serializer (pi's is not exported
with a cap parameter) using `toolResultMaxChars` for tool results *and* thinking blocks.

`fitConversation()` shrinks the cap by quarters until the serialized text plus the previous summary fits
`charBudget()` (85% of the summarizer's window minus the output reserve and a margin). It shrinks the cap rather than
dropping old messages: a thin description of the beginning is better than a summary that never saw it. The floor is
200 characters and a request still too big is sent anyway - the error lands in the fallback above.

`reasoning: "off"` means the `reasoning` option is not sent at all, which leaves it to the llama.cpp preset. Only pass
a level the model's `thinkingLevelMap` does not null out.

## file lists survive here, not through pi

`prepareCompaction()` carries file lists out of the previous compaction only when that entry was *not* written by an
extension (`fromHook`), so a second compaction of a session this extension already summarized would lose the lists.
`carryFileOps()` merges `getLatestCompactionEntry(branchEntries).details` into `preparation.fileOps` before the lists
are computed. Keep it: it is the only reason the cumulative tracking still works after the first delegated compaction.

## module boundaries

`config.ts` and `summarize.ts` must not import pi at runtime (`summarize.ts` has one `import type`), so
`test-utils/check.mjs` loads them with plain node. The pi-specific parts - the event, the registry call,
`convertToLlm()`, `getLatestCompactionEntry()` - stay in `index.ts`.

`FileOperations`, `SUMMARIZATION_SYSTEM_PROMPT` and the section format are re-declared locally because pi does not
export them. **The section format is what the session model reads back**; pi documents it, and drifting from it
changes what every post-compaction context looks like.

## tests

```sh
node test-utils/check.mjs     # offline: serialization, budget fit, prompt, file lists, config loading
```

Types, the same way the other pi extensions here do it (copy next to a `node_modules` symlink pointing at pi's):

```sh
TSC="$(nix build --no-link --print-out-paths nixpkgs#typescript)/bin/tsc"
pi_root=$(dirname "$(dirname "$(readlink -f "$(command -v pi)")")")
rm -rf /tmp/cd-typecheck && mkdir -p /tmp/cd-typecheck && ln -s "$pi_root/lib/pi/node_modules" /tmp/cd-typecheck/node_modules
cp ./*.ts /tmp/cd-typecheck/ && cd /tmp/cd-typecheck
"$TSC" --noEmit --strict --noUnusedLocals --noImplicitOverride --skipLibCheck --target es2023 \
  --module esnext --moduleResolution bundler --allowImportingTsExtensions --types node index.ts
```

## forcing a real compaction

`/compact` in a session that matters spends that session's context. The isolated recipe uses `sharp-spark` on both
sides (4 slots, so a second instance is free) and `PI_CODING_AGENT_DIR` so the live agent dir, its settings and its
sessions are never touched:

```sh
mkdir -p /tmp/cd-agent /tmp/cd-test
ln -sf ~/.pi/agent/models.json ~/.pi/agent/subagents.json /tmp/cd-agent/
echo '{"compaction":{"modelOverrides":{"llama-pc/sharp-spark":{"reserveTokens":747000,"keepRecentTokens":1}}}}' > /tmp/cd-agent/settings.json
cd /tmp/cd-test
PI_CODING_AGENT_DIR=/tmp/cd-agent pi -e <this dir> --provider llama-pc --model sharp-spark -p "Remember: ZEBRA-42."
PI_CODING_AGENT_DIR=/tmp/cd-agent pi -e <this dir> --provider llama-pc --model sharp-spark --continue -p "<40k chars of filler>
What serial did I ask you to remember?"
```

The override makes every turn compact and `keepRecentTokens: 1` leaves nothing but the newest message kept, so the
second turn summarizes for real. Check `/tmp/cd-agent/sessions/*/*.jsonl` for the `compaction` entry - `fromHook:
true`, a `usage` with the summarizer's tokens, `details.readFiles`/`modifiedFiles`, pi's section format - and that the
answer after the compaction still names ZEBRA-42, which is the point of the whole exercise.
