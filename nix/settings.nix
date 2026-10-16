# Single source of truth for host/user identity and well-known paths.
# Consumed by the system config, home-manager (via extraSpecialArgs) and the flake inputs.
# `rec` so a path can be spelled out of another one below.
rec {
  userName = "steelph0enix";
  # The rootless Docker socket lives under /run/user/<uid>; llama-server-rocm needs the
  # number spelled out, and it is 1000 here (first normal user, never reassigned).
  userUid = 1000;
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
  # ROCm counterpart of the preset (dev = ROCm0) and the toolbox image it runs in. The
  # image is built by hand from ${llamaModelsPath}/Dockerfile.rocm-10.1-gfx1100, not by Nix.
  llamaRocmPresetsPath = "${llamaModelsPath}/llama-server-rocm.ini";
  llamaRocmImage = "llama-rocm-10.1-gfx1100:latest";
  # Models kept resident at once (20 GB of VRAM here).
  llamaModelsMax = 1;
  # Services bind every interface and the firewall decides who gets in; the LAN names are only ever
  # used to reach the machine. The ports live here so the firewall rules cannot drift apart.
  llamaRouterHost = "0.0.0.0";
  llamaRouterPort = 51536;
  # Which engine owns the router port: "rocm" (the gfx1100 toolbox container) or
  # "vulkan" (the llama-cpp package). Both units stay configured; the other one is off.
  # ROCm is on hold - the gfx1100 toolbox container kept crashing the router.
  llamaBackend = "vulkan";
  # Unit that owns the router port; the log viewer tails it.
  llamaRouterService = "llama-server-${llamaBackend}";
  llamaLogsPort = 51580;

  # Strata (nixos/services/strata): Qwen3.8-Flash-Next Coder on Strata's own HIP engine, next to
  # the llama.cpp router on its own port. Only one engine can hold the card, so the units conflict
  # and Strata is not started at boot.
  strataRev = "v0.1.44.1";
  strataImage = "strata-hip-gfx1100:latest";
  # The model pack (~65 GB) and Strata's config, kept outside the container.
  strataDataPath = "${llamaModelsPath}/strata";
  # Slim by intent. 32K rather than setup's 131072 for a 20 GB card: in the low-RAM mode the KV cache
  # lives in VRAM, so every 32K of context costs ~1.4 GB that the experts would otherwise get.
  strataContext = 32768;
  # The VRAM the engine leaves for the desktop. The engine's own default is 700 MiB and it holds that
  # back only from the expert cache, so what it allocates afterwards (the KV cache, the verify windows)
  # spends it again: measured on this card, 700 left 131 MiB free and 2048 left 843 MiB.
  strataVramReserveMiB = 2304;
  # Hard ceiling for the container, and the reason it exists: without one, Strata filling the last of
  # the RAM takes the desktop with it (it did). 31 GB of RAM here, so ~7 GB stay outside the box.
  strataMemoryLimit = "24g";
  strataPort = 51537;
}
