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
  llmHost = "0.0.0.0";
  # The router endpoint: whichever backend settings.llamaBackend picks listens here, and only one of
  # them is ever enabled. Strata is the other engine on the card and has its own port below.
  llmPort = 51536;
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
  # 131072, which is what setup picks. The KV cache normally lives in VRAM in the low-RAM mode and
  # costs ~1.4 GB per 32K of it, so the full context is only affordable with the streaming in
  # strataEngineArgs below, which keeps it in RAM and only its 32K window on the card.
  strataContext = 131072;
  # Engine arguments, kept in one list because the image's entry point forwards only the settings it
  # knows (see strata.nix, which writes these into Strata's own config before every start).
  #   --kv-resident      stream the KV cache: 32K of it on the card, the rest in RAM (~1.7 GB at this
  #                      context). Reads the same values; measured here 55 -> 64 tokens/s at 22K.
  #   --resident-cpu-experts  copy the experts the card does not hold into ordinary RAM - pageable,
  #                      so unlike --resident-experts it never locks the desktop's memory. The bigger
  #                      win: 64 -> 72 tokens/s, and no reading the pack mid-request.
  #   --pool-workers     parallel SSD reads for the experts that still come from the file.
  #   --adapt-every 0    no expert swaps while serving: the profile is fixed, so adapting is churn.
  #   --pcie-frac 0      goes with STRATA_ARENA_MMAP: nothing is staged over the bus in the background.
  strataEngineArgs = [
    "--kv-resident"
    "32768"
    "--resident-cpu-experts"
    "--pool-workers"
    "15"
    "--adapt-every"
    "0"
    "--pcie-frac"
    "0"
  ];
  # The VRAM the engine leaves for the desktop. The engine's own default is 700 MiB and it holds that
  # back only from the expert cache, so what it allocates afterwards (the KV cache, the verify windows)
  # spends it again: measured on this card, 700 left 131 MiB free and 2048 left 843 MiB.
  strataVramReserveMiB = 2304;
  # Hard ceiling for the container, and the reason it exists: without one, Strata filling the last of
  # the RAM takes the desktop with it (it did). 31 GB of RAM here, so ~7 GB stay outside the box.
  strataMemoryLimit = "24g";
  strataPort = 51537;
}
