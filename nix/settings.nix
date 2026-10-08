# Single source of truth for host/user identity and well-known paths.
# Consumed by the system config, home-manager (via extraSpecialArgs) and the flake inputs.
# `rec` so a path can be spelled out of another one below.
rec {
  userName = "steelph0enix";
  hostId = "steelph0enix-pc";

  # Working checkout, not `self`: this flake is a local *git* input, so `self` is the
  # committed store copy rather than the dirty worktree `nh` should build.
  repoPath = "/home/steelph0enix/nixos-config";

  # Externally managed checkout outside this repo; the `llama-cpp` flake input repeats it
  # because flake input URLs have to be literals.
  llamaCppPath = "/home/steelph0enix/llama.cpp";

  # GGUF weights and the router's preset file (see nixos/services/llama-server-vulkan): point them
  # wherever the weights live on that machine; the preset is edited in place and the unit restarted.
  llamaModelsPath = "/mnt/NVMe/LLMs";
  llamaPresetsPath = "${llamaModelsPath}/llama-server.ini";
  # Models kept resident at once (20 GB of VRAM here).
  llamaModelsMax = 1;
  # Services bind every interface and the firewall decides who gets in; the LAN names are only ever
  # used to reach the machine. The ports live here so the firewall rules cannot drift apart.
  llamaRouterHost = "0.0.0.0";
  llamaRouterPort = 51536;
  llamaLogsPort = 51580;
}
