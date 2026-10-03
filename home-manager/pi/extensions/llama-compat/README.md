# llama-compat

Feeds what a llama.cpp server actually serves into pi's model catalog. Nothing else: no command, no tool, no
panel, and no model is ever loaded or unloaded (capabilities are read with `autoload=false`).

A `models.json` entry for a llama.cpp router is hand-written, so it drifts: `contextWindow` after a re-fit
(`--fit`), `reasoning` and `thinkingFormat` when a preset's chat template changes, `input` when a vision
projector appears or goes away. At startup this extension reads the servers behind the configured providers
and re-registers them with the server's own answers. `refreshModels` is registered too, so a model-catalog
refresh re-reads the server without restarting pi.

```jsonc
// both shapes work: a provider you pin models on, and one that takes whatever the router advertises
"llama-main":        { "baseUrl": "http://host:33333/v1", "api": "openai-completions", "apiKey": "none",
                       "models": [{ "id": "Qwen 3.8 Flash Next", "name": "qwen-next" }] },
"llama-fwpc-vulkan": { "baseUrl": "http://host:51536/v1", "api": "openai-completions", "apiKey": "none",
                       "models": [] }
```

| Read | Used for |
|---|---|
| `GET /props` | whether the endpoint is a llama.cpp server at all; anything else is left alone |
| `GET /models` | `contextWindow` from `meta.n_ctx` or the preset's `--ctx-size` arg, `input` from `architecture.input_modalities`, instance ids, aliases, `status.value` |
| `GET /props?model=X&autoload=false`, loaded or sleeping instances only | served `n_ctx`, vision, the thinking switch and the effort variable the template declares, the effort values it accepts, `chat_template_caps.supports_reasoning_effort` and `supports_preserve_reasoning` |

| Server says | Applied |
|---|---|
| served `n_ctx` | `contextWindow`, and `maxTokens` clamped down to it |
| vision projector present / absent | `input` `["text", "image"]` / `["text"]` |
| any thinking switch or effort at all | `reasoning: true`, otherwise `false` |
| template declares its own variables (a switch such as `enable_thinking` or `thinking`, or a `*_reasoning_effort`) | `compat.thinkingFormat: "chat-template"` with `chatTemplateKwargs` carrying the switch and, when the template names the values it accepts, the effort too; `preserve_thinking` only when the template declares it |
| template only reads OpenAI's `reasoning_effort` | `supportsReasoningEffort: true` and a `thinkingLevelMap` over the efforts the template names, others marked null |
| always | `supportsStore`/`supportsDeveloperRole`/`supportsStrictMode` false, `supportsUsageInStreaming` true, `maxTokensField: "max_tokens"` |

## Providers with no models

A provider that declares `"models": []` is filled from the presets the router advertises, so adding a preset
server-side needs no config change. Only presets pi can actually route are registered: a loaded or sleeping
instance, or a cold one when the router reports `models_autoload` (llama.cpp's own rule). Presets that can
only answer with vectors (`--embeddings` or `--pooling` in their launch args) are left out.

A cold preset cannot report its template or its served context, so it starts from its `--ctx-size` arg (pi's
128K default when the preset passes none) and without thinking. Open `/model` once the preset has been loaded
and the catalog refresh fills both in.

## Limits

- The built-in `llama.cpp` provider is skipped: its own code already reads the server, and re-registering it
  would drop its classifier models. Only providers you put in `models.json` are touched.
- Effort levels are only claimed when the template can take them: a template that validates its effort (most
  Qwen ones: `xhigh`/`medium`/`low`) 500s on `high`, and pi sends `thinkingLevelMap[level] ?? level`.
- Switch and effort names come out of the template's own jinja expressions, ignoring its comments and strings.
  A template that switches thinking under a name never seen before still works; one that only mentions
  thinking in prose is read as having no switch.
- What `models.json` writes under `modelOverrides` is applied on top of all of this, so a model can always be
  pinned by hand.
- A cold preset answers nothing about itself, so it keeps its configured values rather than guessing.
- Registering a provider replaces its whole model list, so if the server does not offer one of the configured
  models, the provider is left exactly as `models.json` describes it.
- The server is probed at startup with a 2s budget per provider, in parallel; an unreachable server leaves the
  configuration untouched.

`LLAMA_COMPAT_DEBUG=1` writes one stderr line per provider: what was filled in, or why nothing was.
