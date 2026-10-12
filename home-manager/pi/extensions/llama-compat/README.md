# llama-compat

Keeps pi's model catalog honest about a llama.cpp server.

A `models.json` entry for a llama.cpp router is hand-written, so it drifts: `contextWindow` after a re-fit (`--fit`),
`reasoning` and `thinkingFormat` when a preset's chat template changes, `input` when a vision projector appears or
goes away. At startup this extension asks the servers behind your configured providers what they actually serve, and
re-registers them with the server's own answers: context window, vision, whether the model reasons, which thinking
format and which effort levels pi should send.

## What it adds

Nothing you interact with — no command, no tool, no panel, and no model is ever loaded or unloaded. A catalog refresh
is enough to re-read a server, so a `--fit` or a new chat template needs no restart of pi.

## Configuration

None of its own. It reads the llama.cpp providers in `~/.pi/agent/models.json`, and both shapes work:

```jsonc
// a provider you pin models on ...
"llama-main":        { "baseUrl": "http://host:33333/v1", "api": "openai-completions", "apiKey": "none",
                       "models": [{ "id": "Qwen 3.8 Flash Next", "name": "qwen-next" }] },
// ... and one that takes whatever the router advertises
"llama-fwpc-vulkan": { "baseUrl": "http://host:51536/v1", "api": "openai-completions", "apiKey": "none",
                       "models": [] }
```

With `"models": []` the presets the router advertises become the model list, so adding a preset server-side needs no
config change.

`apiKey` may be a literal, `$NAME`, or a leading `!` whose trimmed output is the key — which is how a secret stays out
of git. Anything you write under a model's `modelOverrides` is applied on top of everything the server said, so a
model can always be pinned by hand.

## Setup gotchas

- Only providers **you** put in `models.json` are touched. The built-in `llama.cpp` provider is left alone: its own
  code already reads the server.
- A server started with `--api-key` answers 401 to every question, so a provider without a key stays exactly as
  `models.json` describes it.
- A preset the router has not loaded cannot describe itself: it starts from its `--ctx-size` arg and without thinking.
  Load it, refresh the catalog once, and both fill in.
- A provider is registered whole. If the server does not offer one of the models you configured, the provider is left
  untouched rather than rewritten around the gap.
- Servers are probed at startup with a 2s budget each, in parallel; an unreachable one leaves the configuration as
  written.
- `LLAMA_COMPAT_DEBUG=1` writes one stderr line per provider: what was filled in, or why nothing was.

How the answers are read and applied: [AGENTS.md](AGENTS.md).
