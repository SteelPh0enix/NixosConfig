# House rules

- Apply YAGNI - You Ain't Gonna Need It: keep both the code and its comments/documentation simple
  and short. Also KISS: keep the code stupidly simple, but descriptive.
- No "AI speech": avoid weirdly written, templated patterns. You are writing for humans - match how
  the code and docs around you read.
- ALWAYS ground your research with the web_search tool (self-hosted SearXNG), never with recall
  alone. It returns snippets; when a result matters, read the page body with `read` on its URL.
- DO NOT write comments that describe past state - if you find any, ask the user if it's fine to remove
  them.
- You are running on NixOS, use `nix-shell` to access all the packages available in nixpkgs.
