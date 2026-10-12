# searxng

Gives pi `web_search`, backed by a SearXNG instance you run yourself rather than by a hosted search API.

The instance does the aggregating: pi asks it one query and gets its results back as text — title, URL, snippet,
which engines produced each one. Nothing is sent anywhere else, and no key is needed.

## What it adds

| Tool | Args | Behavior |
|---|---|---|
| `web_search` | `query`, `page?` (1–10), `categories?`, `language?`, `time_range?` | One page of up to 10 results per call, each with URL and snippet. A page of exactly 10 says so and names the next page to ask for. |

`categories` is comma-separated SearXNG categories (`general`, `news`, `it`, `images`, …), `general` by default.
`time_range` is `day`, `week`, `month` or `year`.

Paging is the point: 10 results per call, then `page=2` for the next ten, rather than the same query phrased four
different ways.

## Configuration

One environment variable: `SEARXNG_URL`, the base URL of the instance, `http://127.0.0.1:7777` when unset. On this
machine home-manager sets it to `http://search.framework:7777` — the SearXNG this box runs, reached by name through
the local DNS rewrite rather than by localhost.

## Setup gotchas

- The instance must accept JSON. Without `"json"` in SearXNG's `search.formats` the API answers 403, and the error
  says exactly that instead of looking like a broken extension.
- A request that cannot connect is reported with the base URL in the message, and suggests `SEARXNG_URL` —
  `fetch failed` alone never says which host was tried.
- 20s per request; that is the whole budget, engines included.
- Results are deduplicated by URL (host + path + query), and only the first 10 survive: SearXNG's own ordering
  decides which they are, duplicates are dropped rather than padded out.
- No caching. Every call is a live search on the instance.

How the request is built and its answer formatted: [AGENTS.md](AGENTS.md).
