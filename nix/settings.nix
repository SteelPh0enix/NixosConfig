# Single source of truth for host/user identity and well-known paths.
# Consumed by the system config, home-manager (via extraSpecialArgs) and the flake inputs.
# `rec` so a path can be spelled out of another one below.
rec {
  userName = "steelph0enix";
  hostId = "RX-78-FPC";

  # Working checkout, not `self`: this flake is a local *git* input, so `self` is the
  # committed store copy rather than the dirty worktree `nh` should build.
  repoPath = "/home/steelph0enix/nixos-config";

  # Externally managed checkout outside this repo; the `llama-cpp` flake input repeats it
  # because flake input URLs have to be literals.
  llamaCppPath = "/home/steelph0enix/llama.cpp";

  # GGUF weights and the router's preset file (see nixos/llama-server.nix). Per-host: point them
  # wherever the weights live on that machine.
  llamaModelsPath = "/mnt/NVMe/LLMs";
  llamaPresetsPath = "${llamaModelsPath}/llama-server.ini";
  # The router binds this name and the other box connects to it; kept next to `llamaPresetsPath`
  # so the firewall rule and the service cannot drift apart.
  llamaRouterHost = "steelph0enix.pc";
  llamaRouterPort = 51536;
}
