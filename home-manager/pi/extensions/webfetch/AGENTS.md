# webfetch internals

For whoever changes how the CLI is driven. [README.md](README.md) stops at what a user has to install and set; this is
how both tools turn into agent-browser calls.

## One wrapper

Every call is

```
agent-browser --session pi-webfetch --profile <profile dir> <args> [--json]
```

as a spawned child with its own stdout/stderr. `callCli` resolves the exit code — a non-zero one becomes an error from
the JSON payload's `error` field, falling back to stderr + stdout. `callJson` adds `--json`, rejects on
`success: false`, and hands back `data`. Both take a timeout and the caller's abort signal; either one `SIGKILL`s the
child, which is what actually stops a hung browser (20s for the HTTP path, 90s everywhere else).

The daemon behind the CLI is not managed here: it starts on the first command and is left to its idle timeout.

## The environment children get

Built once per pi process and memoized, then reused by every call:

- `AI_GATEWAY_API_KEY`, `AI_GATEWAY_URL`, `AI_GATEWAY_MODEL` are deleted — that is what keeps a stray gateway
  configuration from turning "local browser" into a hosted one.
- `AGENT_BROWSER_EXECUTABLE_PATH` ← the first `chromium`/`chromium-browser`/`google-chrome`/`google-chrome-stable` on
  `PATH`, through `realpathSync` so a Nix symlink resolves to the binary the version probe can read.
- `AGENT_BROWSER_USER_AGENT` ← a UA carrying the browser's own major version (from `--version`, memoized) and a
  platform string, because the default headless UA reports `HeadlessChrome/…` and gets a challenge page for its
  trouble.
- `AGENT_BROWSER_IDLE_TIMEOUT_MS` ← `120000` when unset, so a browser nobody used for two minutes goes away instead of
  sitting until the daemon's own hour.

## Getting a page

`read <url>` with the format flags: `html` → `--raw`, `outline` → `--outline`, nothing for `text`, plus
`--filter <text>` when a filter was given. Omitting the URL reads the active tab, which is how the rendered path works:
`open <url>`, optionally `wait --text <wait_for>`, then `read` with no URL.

| mode | path |
|---|---|
| `http` | `read <url>` only |
| `browser` | `open` → `read` |
| `auto` | `http`, then `browser` when the body looks like a challenge, or when the plain request failed |

`needsRender` is the decision: an empty body, or a match against `BOT_WALL` — a list of phrases the walls actually
print ("just a moment", "verify you are human", a 12-hex-character Cloudflare error code). A wording nobody has seen
before is not caught, and only `text` is checked: `--raw` and `--outline` of a wall are already honest answers. When
both paths fail, the error names both, since the HTTP reason is usually the interesting one.

Note what `read` itself does before the extension sees it: it prefers markdown (`Accept: text/markdown`, then the same
URL with `.md`), looks for a nearest-ancestor `llms.txt`, and only then extracts readable text from the HTML. So
`format=text` is often not the page's own prose, and `format=html` is the answer to that.

## Output shaping

`clip` cuts at `max_chars` (default 20 000, capped at 200 000) and appends where the rest went and what to do about it
— a silent cut reads to a model as the whole page. `save_to` writes the body (`mkdir -p` first) and returns a 800-char
preview; if the write fails, the body comes back in the result with the reason, because throwing away a page that was
already fetched is the worse outcome.

## web_interact

| action | CLI |
|---|---|
| `goto` | `open <url>` then `read` (with no URL: the active tab) |
| `snapshot` | `snapshot -i`, plus `-u` for hrefs; the raw stdout, not a JSON payload |
| `click` / `fill` / `press` / `scroll` | `click <target>`, `fill <target> <value>`, `press <value>`, `scroll <direction> <pixels>`; each returns a one-line ack |
| `screenshot` | `screenshot [--full] [target] <tmp.png>`, read back as base64, file removed in a `finally` |
| `close` | `close` (30s budget) |
| `text` | falls through to `read` with no URL |

Refs come from `snapshot -i` and are only valid for the page that produced them, which is why the prompt guidelines
say to re-snapshot after navigation rather than reuse a `@ref`.

## Things that bite

- The browser path, version and UA are computed once per pi process; swapping browsers or updating Chromium needs pi
  restarted.
- `PI_WEBFETCH_BIN`'s fallback list is npm/macOS/NixOS-specific, which is why the packaged case is worth pinning.
- Both tools pass the same `--session` and `--profile`, so cookies and the open page carry from one to the other;
  `close` releases the browser but leaves the profile on disk.
- A timeout or a cancel kills the CLI child, never the daemon — the browser it was driving stays up until the idle
  timeout, or until the next command reuses it.
- Both tools are `executionMode: "sequential"`.

## Files

| file | what it holds |
|---|---|
| `index.ts` | everything: the CLI wrapper, both tools, and their render functions |
