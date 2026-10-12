# webfetch

Gives pi `web_fetch` and `web_interact`: reading a page and driving one, with a real Chromium running on your own
machine. No third-party fetch API sits in between — the only traffic is your browser talking to the site — and the
AI Gateway variables that a hosted-fetch tool would pick up from the environment are stripped from every child process.

Both tools talk to [agent-browser](https://github.com/vercel-labs/agent-browser), which owns the browser.

## What it adds

| Tool | Args | Behavior |
|---|---|---|
| `web_fetch` | `url`, `format?` (`text`/`html`/`outline`), `mode?` (`auto`/`http`/`browser`), `filter?`, `wait_for?`, `max_chars?`, `save_to?` | One page as text. `auto` asks the HTTP path first and re-reads through Chromium when the answer is a bot challenge or an empty shell. |
| `web_interact` | `action` (`goto`, `snapshot`, `click`, `fill`, `press`, `scroll`, `text`, `screenshot`, `close`), plus `url`/`target`/`value`/… | Drives the rendered page. `snapshot -i` produces `@e12`-style refs, which is what `target` takes. |

`filter=` keeps only the sections matching some text, `outline=` maps a long page cheaply, and `save_to=` writes the
body to a file and returns a preview — that is how a page bigger than the 20 000-char default gets read in chunks
rather than truncated. Truncation is always announced, never silent.

## Installing agent-browser

Two things are needed: the CLI, and a Chromium-family browser for it to automate.

```bash
npm install -g agent-browser   # or: brew install agent-browser / cargo install agent-browser
agent-browser install          # first time only: downloads Chrome from Chrome for Testing
agent-browser install --with-deps   # Linux: also pull the system libraries a browser needs
```

An existing Chrome, Chromium, Brave, or a Playwright/Puppeteer download is detected on its own, so `agent-browser
install` can be skipped when you already have one — which is what happens on this machine (see below). Check the
result with `agent-browser doctor`, and sanity-check the whole path from the shell before blaming the extension:

```bash
agent-browser --session smoke open https://example.com
agent-browser --session smoke read --json | head -c 300
agent-browser --session smoke close
```

NixOS needs no npm: the packaged agent-browser is installed with home-manager here, `PI_WEBFETCH_BIN` points at it, and
the browser is the Chromium already on `PATH` — so `agent-browser install` stays unrun, since its whole job is to
download a Chrome the machine has. Its `--with-deps` variant wants a system package manager and has none on NixOS; the
libraries come from the package instead.

## Configuration

All optional, all read from pi's environment.

| Variable | Meaning |
|---|---|
| `PI_WEBFETCH_BIN` | the agent-browser executable. Otherwise `~/.npm-global/bin/agent-browser`, `/usr/local/bin/agent-browser`, `/run/current-system/sw/bin/agent-browser`, or `agent-browser` from `PATH` |
| `PI_WEBFETCH_BROWSER` | which browser to launch. Otherwise `AGENT_BROWSER_EXECUTABLE_PATH`, or the first `chromium`, `chromium-browser`, `google-chrome`, `google-chrome-stable` on `PATH` |
| `PI_WEBFETCH_PROFILE` | profile directory, default `~/.pi/agent/data/webfetch-profile` |

`AGENT_BROWSER_USER_AGENT` and `AGENT_BROWSER_IDLE_TIMEOUT_MS` are honoured; if unset, the extension sets them (see
[AGENTS.md](AGENTS.md)).

## Setup gotchas

- Missing CLI is reported as `agent-browser not found. Install: npm install -g agent-browser (or set
  PI_WEBFETCH_BIN)` — the error you get when the browser is fine but the CLI is not on pi's `PATH`.
- A browser whose name pi cannot guess in `PATH` means agent-browser picks the engine itself, or fails. Set
  `PI_WEBFETCH_BROWSER` then.
- The profile directory persists between calls, so a login done through `web_interact` is still there tomorrow, in a
  plain directory under your home. Delete it to start clean; point `PI_WEBFETCH_PROFILE` somewhere else for a second,
  throwaway identity.
- Both tools share one browser session (`pi-webfetch`), so a page left open is the page `web_interact` acts on, and
  `close` releases it. That is also why both are marked sequential: two fetches at once would fight over the tab.
- The rendered path is slow (90s budget, versus 20s for plain HTTP) and is only reached when it pays: `mode=http`
  never launches a browser.
- `screenshot` writes a PNG to the temp dir, returns it as an image, and deletes the file.
- The user agent is rewritten from `HeadlessChrome/…` to the browser's real version, because bot-walls reject the
  headless one outright.

How the two paths and the CLI are used: [AGENTS.md](AGENTS.md).
