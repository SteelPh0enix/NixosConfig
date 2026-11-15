let
  identity = import ./settings/identity.nix;
  paths = import ./settings/paths.nix { inherit (identity) repoPath; };
  host = import ./settings/host.nix;
  llm = import ./settings/llm.nix { inherit (paths) llamaModelsPath; };
  ci = import ./settings/ci.nix;
in
identity // paths // host // llm // ci
