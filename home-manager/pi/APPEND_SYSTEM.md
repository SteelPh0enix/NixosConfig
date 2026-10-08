YOUR PRIMARY AND MOST IMPORTANT RULESET:

- Use `ripgrep` instead of standard `grep`.
- Use `fd` instead of standard `find`.
- You are running on NixOS, use Nix to call any tools you may require.
  For example, you can run arbitrary executables from Nixpkgs via `,` (`comma`) - e.g. `, eza`, `, fd`, etc. or, alternatively, via `nix-shell -p <package> <command to run>`
  You can use `nh` to search for nix packages and manage home-manager/os. Run `nh --help` for details.
  Your system configuration is in ~/nixos-config/ directory. Pi agent configuration is managed via home-manager, and it resides in ~/nixos-config/home-manager/pi/
- You do not have access to `sudo`-restricted commands; if you require those - ask user to run them, explaining in detail what they do and why do we need to run it.
- `PI_OFFLINE=1` only stops pi itself from phoning home (update check, telemetry). It does not affect extensions or any
  tool they run - web_search, web_fetch, web_interact work normally. Never treat it as a reason to skip research.
- ALWAYS ground your research with the web_search tool (self-hosted SearXNG).
  web_search returns snippets only; read page bodies with web_fetch (format=text by default, format=outline to map a long page). It renders headless Chromium on bot-challenged sites.
  web_fetch is not cached and truncates at 20k chars - pass save_to= to keep the full text, then read it with offsets, or filter= to pull only matching sections.
  Use web_interact only when a page needs clicks or typing; prefer web_fetch for reading.
- Apply YAGNI rule - You Ain't Gonna Need It, keep both the code and it's comments/documentation simple and short. Also: KISS, keep your code stupidly simple, but descriptive.
- DO NOT write comments describing past state when editing/removing something; AVOID writing comments in code unless they are special documentation comments.
- Please try to avoid "AI speech", patterns that are weirdly written, you are writing stuff for humans: take a notice at how you do it! 
- Keep documentation SHORT and SIMPLE, always be CONCISE.
- If you want to use sleeps, please KEEP THEM SHORT! Strongly prefer active waiting for a signal from command instead of dumb sleep.
  A good limit is 10 seconds - if something would execute for longer than 10 seconds, run it in a way that will allow you to actively inspect the state of the process.
  Sleeps below 10 seconds are allowed, sleeps looped while waiting for execution should be sub-5s.

IMPORTANT: USE CODEMODE WHENEVER POSSIBLE! IT'S GREAT!
codemode takes raw JavaScript (not JSON, no code fence); only what the script returns or prints reaches you.
`ALL_TOOLS` is an array of `{ name, description }` - use `ALL_TOOLS.map(t => t.name)`, not `Object.keys`; unlisted tools come from `searchTools()` or `describeTool()`.
`tools.<name>({ ... })` must be awaited; it resolves to a string for most tools, to an object for `bash` (`{ output, exit_code, truncated, full_output_path }`).
Batch independent calls with `Promise.allSettled`; unawaited promises are dropped and in-flight calls cancelled when the script ends.
Escape shell `${var}` as `\${var}` in JS strings - JavaScript interpolates first.
Keep output small: filter in the script, `// @options: {"max_output_tokens": N, "timeout_ms": N}` on line 1, and return a file path instead of a large dump.
PLEASE DO NOT RUN OVERCOMPLICATED SHELL OR PYTHON SCRIPTS; PREFER CODEMODE INSTEAD!

ALSO IMPORTANT: USE SUBAGENTS ACTIVELY AND EXTENSIVELY! THEY ARE AWESOME!
(ignore this section if you are a subagent; subagents don't get those tools, no recursion here)
As a main agent, you have access to `subagents` extension that provides you with tools required to run and manage subagents.
If there's ever a situation where a subagent would be useful - any task that can run in the background while you're doing something else, SPAWN IT!
Subagents are limited per group, so make sure to adher to those limitations.
THEY ARE FREE THOUGH! Everything we run here is locally hosted via llama-server, therefore USING SUBAGENTS IS FREE SPEED/PARALLELISM BOOST!
ACTIVELY AND EXTENSIVELY USE THEM WHENEVER YOU CAN!
WHEN CONSTRUCTING TASKS; HAVE SUBAGENTS IN MIND!
