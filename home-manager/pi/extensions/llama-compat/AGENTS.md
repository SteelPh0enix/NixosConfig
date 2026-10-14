# llama-compat internals

For whoever changes the probing and the re-registration. [README.md](README.md) stops at what a user has to set up;
this is how the server's answers become pi catalog entries.

## What is read

| Read | Used for |
|---|---|
| `GET /props` | whether the endpoint is a llama.cpp server at all; anything else is left alone |
| `GET /models` | `contextWindow` from `meta.n_ctx` or the preset's `--ctx-size` arg, `input` from `architecture.input_modalities`, instance ids, aliases, `status.value`, and the `--parallel` / `--kv-unified` launch args |
| `GET /props?model=X&autoload=false`, loaded or sleeping instances only | served `n_ctx`, `total_slots`, vision, the thinking switch and the effort variable the template declares, the effort values it accepts, `chat_template_caps.supports_reasoning_effort` and `supports_preserve_reasoning` |

The per-model read carries `autoload=false`: a probe must never load a model on a router that keeps one preset
resident. The two server-level reads (`/props`, `/models`) answer about the server and need no such marking.

## What is applied

| Server says | Applied |
|---|---|
| served `n_ctx`, else the preset's `--ctx-size`, else pi's 128K default; with `--kv-unified` and more than one slot, divided by the slot count | `contextWindow`, and `maxTokens` clamped down to it |
| `--kv-unified` with more than one slot | `llamaShared: { pool, slots }` on the registered model, so a concurrent-session extension can re-divide the pool by the tasks actually running |
| vision projector present / absent | `input` `["text", "image"]` / `["text"]` |
| any thinking switch, effort, or thinking tags of its own | `reasoning: true`, otherwise `false` |
| template emits thinking tags but reads no variable about it (LFM2.5) | `reasoning: true`, no thinking format, `thinkingLevelMap` left as `models.json` gave it - only `off` means anything to it |
| template declares its own variables (a switch such as `enable_thinking` or `thinking`, or a `*_reasoning_effort`) | `compat.thinkingFormat: "chat-template"` with `chatTemplateKwargs` carrying the switch and, when the template names the values it accepts, the effort too; `preserve_thinking` only when the template declares it |
| template only reads OpenAI's `reasoning_effort` | `supportsReasoningEffort: true` and a `thinkingLevelMap` over the efforts the template names, others marked null |
| always | `supportsStore`/`supportsDeveloperRole`/`supportsStrictMode` false, `supportsUsageInStreaming` true, `maxTokensField: "max_tokens"` |

## Providers with no models

Only presets pi can actually route are registered: a loaded or sleeping instance, or a cold one when the router
reports `models_autoload` (llama.cpp's own rule). Presets that can only answer with vectors (`--embeddings` or
`--pooling` in their launch args) are left out.

A `--kv-unified` preset gives all its slots one shared KV pool, so `-c` is the pool, not a per-request window: the
window is divided by the slot count or two parallel requests would each claim the whole pool and together overrun
it. `--no-kv-unified` keeps one cache per slot, so the window is left whole. The slot count comes from `total_slots`
when the instance answers, and from `--parallel` when it is still cold.

A cold preset cannot report its template or its served context, so it starts from its `--ctx-size` arg (pi's 128K
default when the preset passes none) and without thinking.

## Things that bite

- Effort levels are only claimed when the template can take them: a template that validates its effort (most Qwen
  ones: `xhigh`/`medium`/`low`) 500s on `high`, and pi sends `thinkingLevelMap[level] ?? level`.
- Switch and effort names come out of the template's own jinja expressions, ignoring its comments and strings. A
  template that switches thinking under a name never seen before still works; one that only mentions thinking in
  prose is read as having no switch.
- Registering a provider replaces its whole model list, which is why one configured model missing from the server
  means the provider is left alone entirely rather than partially rebuilt.
- The built-in `llama.cpp` provider is skipped so its classifier models survive.
- `modelOverrides` is applied last, so a hand-written value always beats what was probed.

## Files

| file | what it holds |
|---|---|
| `index.ts` | everything: probe the three endpoints, apply the answers, register the provider, `refreshModels` |

`LLAMA_COMPAT_DEBUG=1` writes one stderr line per provider: what was filled in, or why nothing was.
