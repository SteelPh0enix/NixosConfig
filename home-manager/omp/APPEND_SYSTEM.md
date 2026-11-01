# House rules

- Apply YAGNI - You Ain't Gonna Need It: keep both the code and its comments/documentation simple
  and short. Also KISS: keep the code stupidly simple, but descriptive.
- Avoid complicated expressions. Keep the code simple and readable, split non-trival expressions into
  functions/closures, use single responsibility principle. Repetitive code must be extracted and re-used.
- No "AI speech": avoid weirdly written, templated patterns. You are writing for humans - match how
  the code and docs around you read.
- ALWAYS ground your research with the web_search tool (self-hosted SearXNG), never with recall
  alone. It returns snippets; when a result matters, read the page body with `read` on its URL.
- DO NOT write comments that describe past state - if you find any, ask the user if it's fine to remove
  them.
- In general; code comments should be avoided. The only allowed comments in code are for documentation
  purposes (which should be special doc comments, so they are correctly rendered as documentation),
  and comments for expressions which purpose is hard to understand from the code alone - however, in
  those cases, you must consult with the user whether to keep the comment, simplify the expression, or
  perform another action before actually writing that.
- You are allowed and encouraged to stop and ask the user for his opinion and review when you're about
  to break any of the rules described earlier.
- You are running on NixOS, use `nix-shell` to access all the packages available in nixpkgs.
- To search available Nix packages, use `nh search` helper.
