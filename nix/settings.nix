let
  identity = import ./settings/identity.nix;
  paths = import ./settings/paths.nix;
  host = import ./settings/host.nix;
  llm = import ./settings/llm.nix;
in
identity // paths // host // llm
