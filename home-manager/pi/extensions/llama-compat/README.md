# llama-compat

Reads `GET /props` (and `GET /models` for routers) from every llama.cpp server pi talks to, and compares
what the served chat template can actually do with what `~/.pi/agent/models.json` claims about it.
pi never looks at these caps itself, so a model whose template cannot call tools silently answers without
tool calls, and a context window that drifted after a re-fit is only noticed mid-session.

A server is checked when its **provider is named after llama** (`llama.cpp` built-in, `llama-b`, …) or when
`LLAMA_COMPAT_URLS` lists its root. Detection always runs and the list only ever adds, so nothing else is
contacted; model ids are not matched, because llama models on a hosted provider are not a local llama.cpp
server. Once a server is checked, every model pointing at it is compared whatever its provider is called,
and a listed server with no models at all still reports its instances. Instance props are read with
`autoload=false`, so sleeping and unloaded instances stay exactly as they are.

| Environment | Effect |
|---|---|
| `LLAMA_COMPAT_URLS` | extra server roots, comma-separated (`http://host:port`, a trailing `/v1` is fine) |
| `PI_LLAMA_CHECK=1` | check at session start, show the panel only on errors |
| `LLAMA_COMPAT_DEBUG=1` | list servers that were skipped, and why |

## Use

| Command | Result |
|---|---|
| `/llama-check` | panel above the editor: instance state plus findings (`error`/`warn`/`info`) |
| `/llama-check framework` | only servers or models whose name contains `framework` |
| `/llama-check block` | paste-ready `models.json` entry per server, from the served `n_ctx` and ftype |
| `/llama-check off` | hide the panel |

The same check is a codemode tool, `llama_compat({ filter, format })`, which returns text: `summary`
(default), `json` (caps per instance) or `block`. `PI_LLAMA_CHECK=1` runs it at session start and shows
the panel only when there are errors.

## Findings

| Code | Means |
|---|---|
| `not-offered` | models.json id is not a preset name/alias on the server → requests 400 |
| `caps-unknown` | instance is not loaded, so caps cannot be read |
| `no-tools`, `no-tool-calls` | template takes tools but cannot use/emit them |
| `object-arguments` | template wants string tool arguments, pi sends JSON objects |
| `context-overflow`, `max-tokens` | declared window above the served `n_ctx` |
| `context-undersized` | served `n_ctx` is much larger than what pi uses |
| `vision-declared`, `vision-unused` | `input` disagrees with the instance's modalities |
| `thinking-unsupported`, `thinking-ignored`, `thinking-not-sent` | pi's thinking level cannot reach this template |
| `effort-unused`, `preserve-thinking` | the template offers more than the current `compat` sends |
| `single-slot` | `parallel = 1`: simultaneous requests queue |
| `lru-eviction`, `instance-failed` | router-wide state worth knowing |

Tool findings are `error` for the model the session is using and `warn` for the others.
