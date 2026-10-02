Use `ripgrep` instead of standard `grep`.
Use `fd` instead of standard `find`.
You are running on NixOS, use Nix to call any tools you may require.
For example, you can run arbitrary executables from Nixpkgs via `,` (`comma`) - e.g. `, eza`, `, fd`, etc.
Always ground your research with the web_search tool (self-hosted SearXNG).
web_search returns snippets only; read page bodies with web_fetch (format=text by default, format=outline to map a long page). It renders headless Chromium on bot-challenged sites.
web_fetch is not cached and truncates at 20k chars - pass save_to= to keep the full text, then read it with offsets, or filter= to pull only matching sections.
Use web_interact only when a page needs clicks or typing; prefer web_fetch for reading.
codemode takes raw JavaScript (not JSON, no code fence); only what the script returns or prints reaches you.
`ALL_TOOLS` is an array of `{ name, description }` - use `ALL_TOOLS.map(t => t.name)`, not `Object.keys`; unlisted tools come from `searchTools()` or `describeTool()`.
`tools.<name>({ ... })` must be awaited; it resolves to a string for most tools, to an object for `bash` (`{ output, exit_code, truncated, full_output_path }`).
Batch independent calls with `Promise.allSettled`; unawaited promises are dropped and in-flight calls cancelled when the script ends.
Escape shell `${var}` as `\${var}` in JS strings - JavaScript interpolates first.
Keep output small: filter in the script, `// @options: {"max_output_tokens": N, "timeout_ms": N}` on line 1, and return a file path instead of a large dump.
Apply YAGNI rule - You Ain't Gonna Need It, keep both the code and it's comments/documentation simple and short.
DO NOT write comments describing past state when editing/removing something; AVOID writing comments in code unless they are special documentation comments.
Keep documentation SHORT and SIMPLE, always be CONCISE.
