# compact-delegate

pi's own compaction asks the model you are talking to for a summary of the conversation it is about to drop, and it
clips every tool result to 2000 characters, because that request still has to fit the window that model just ran out
of. This extension asks a different model instead - the **summarizer** subagent's model, which has a far larger
window - and gives it roomy tool results, so details survive into the summary instead of being clipped away before
anyone reads them.

Nothing else changes. The trigger, what gets cut, the structured summary format and what pi stores are still pi's, and
the summary is what your session model reads back.

## configuration

Optional: `~/.pi/agent/compact-delegate.json`, or `.pi/compact-delegate.json` in the project, which wins. With no
file at all the provider and model of the `summarizer` subagent are used, so there is one place that says what the
summarizer is.

```json
{
  "enabled": true,
  "provider": "llama-pc",
  "model": "sharp-spark",
  "toolResultMaxChars": 16000,
  "maxSummaryTokens": 16384,
  "reasoning": "off"
}
```

| key | default | meaning |
|---|---|---|
| `enabled` | `true` | `false` leaves pi's compaction alone, no questions asked |
| `provider` / `model` | the `summarizer` subagent | where the summary is written |
| `toolResultMaxChars` | `16000` | how much of each tool result and thinking block the summarizer reads (pi: 2000) |
| `maxSummaryTokens` | `16384` | output cap for the summary itself |
| `reasoning` | `off` | thinking level for the summary request; `off` sends nothing and leaves it to the server |

A key that is misspelled or a value that cannot be used is reported at session start; whatever is still usable
applies. A model that is not available means pi compacts the ordinary way.

`/compact-delegate` shows the model in use, its window, and the caps.

## reading the room

The summarizer gets as much as it can hold: when the conversation would not fit its window, tool results are clipped
harder (16000 → 4000 → 1000 → … down to 200 characters) rather than dropping whole messages, so the summary never
silently forgets the beginning.

Since the summary is no longer bounded by the session model's patience, the other knob is worth a look:
`compaction.keepRecentTokens` in pi's settings decides how much of the conversation survives unsummarized, and a
lower number frees more context per compaction.

A big window is not free. A summarization request is a full prefill of everything being summarized, so on a busy
server a compaction of a long session can take a minute or two, with pi waiting. Notifications say what went where
and how long it took.

Branch summaries (`/tree`) are still pi's own.

## verifying it

Nothing to set up. `/compact` in a session that has something to summarize, then watch for
`compact-delegate: ~Nk tok to llama-pc/sharp-spark …` and the summary that follows. A warning naming a fallback means
the delegation did not happen and pi handled it instead.
