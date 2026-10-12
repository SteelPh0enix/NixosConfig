# searxng internals

For whoever changes the request or the output. [README.md](README.md) stops at what a user has to set up; this is how
a query becomes the text the model reads.

## The request

One `GET` to `<base>/search` with `q`, `format=json`, `pageno`, `categories` (`general` when the caller passed
none), plus `language` and `time_range` only when they were given. `Accept: application/json`.

The signal handed to `fetch` is the caller's own abort signal linked with a 20s timer, so a cancelled tool call and a
timeout both end the request; the timer and the listener are removed in a `finally`.

`base` is `SEARXNG_URL` trimmed of trailing slashes, validated to start with `http://` or `https://` — a base with a
typo would otherwise surface as a confusing `fetch failed`.

## The answer

`results` is passed through `collectResults`: entries with neither URL nor title are dropped, the rest are keyed by
`host + pathname (no trailing slash) + search`, lowercased — a result with no usable URL is keyed by its title
instead — and the first 10 kept. Deduplicating matters because the same page arrives from several engines with
different tracking parameters, and 10 slots is all there is.

Each result prints as: title (or URL when there is no title, or "Untitled result"), the URL, the snippet at 400
chars, and a meta line joining `via <engines>` and `published <date>` — the engine list comes from `engines`, falling
back to `engine`, and the date is the first 10 characters of `publishedDate`. Whitespace is collapsed everywhere and
anything over its limit gets an ellipsis.

Two notes go after the list: the page-full hint (only when exactly 10 came out, naming `page+1`), and
`unresponsive_engines` verbatim.

## Errors

| Seen as | Reported as |
|---|---|
| 403 | told to add `"json"` to `search.formats`, with the base URL named |
| body that is not JSON | the same hint, as a question about `search.formats` |
| `AbortError` / `TimeoutError` | the 20s budget and the base URL |
| anything else, incl. connection refused | `Could not reach SearXNG at <base>` + the original message + "Set SEARXNG_URL" |
| aborted while an error is on its way | `Search cancelled.` with `cancelled: true`, not an error |

## Files

| file | what it holds |
|---|---|
| `index.ts` | everything: parameters, the request, dedup and formatting, both render functions |

`details` (`query`, `page`, `returned`, `possiblyMore`, `url`) is what `renderResult` prints: the count and the page.
`possiblyMore` is the same "exactly 10" test that produced the page-full hint.
