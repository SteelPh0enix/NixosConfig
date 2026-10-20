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

  # GGUF weights and the router's preset file (see nixos/services/llama-server-vulkan). Both sit
  # under /home/LLMs rather than in the checkout: the unit runs as `llama`, and home is 0700, so it
  # cannot traverse anything below it - the preset read fails with EACCES. The checkout keeps a
  # symlink to the preset, so editing it and restarting the unit still needs no rebuild.
  llamaModelsPath = "/home/LLMs";
  llamaPresetsPath = "${llamaModelsPath}/llama-server.ini";
  # Models kept resident at once (see nixos/services/llama-server-vulkan).
  llamaModelsMax = 4;
  # Services bind every interface and the firewall decides who gets in; the LAN names are only ever
  # used to reach the machine. The ports live here so the firewall rules cannot drift apart.
  llamaRouterHost = "0.0.0.0";
  llamaRouterPort = 51536;
  llamaLogsPort = 51580;

  # Gufo engine (nixos/services/gufo.nix) on the port the retired rootless-Docker llama.cpp router
  # used. The LAN uses this port, the internet gets https://clanker.steelph0enix.dev/ through the
  # Cloudflare Tunnel, and the API key is the one external clients already hold.
  llamaStrixPort = 33333;

  # The Qwen3.8-Flash-Next target and the shared MTP sidecar it speculates with. Both stay under
  # llamaModelsPath so the service user can read them (see the note above). UD-Q4_K_XL is gufo's
  # qualified target; the AtomicChat AP-Q4_K_XL was rejected by the loader (IQ4_NL tensors it does
  # not implement), so it cannot be used here.
  gufoModelPath = "${llamaModelsPath}/models/qwen/3.8-Flash-Next/UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf";
  gufoMtpPath = "${llamaModelsPath}/models/qwen/3.8-Flash-Next/UD-Q4_K_XL/MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf";
  # Vision is not used: the Qwen projector files live in ../vision/, outside the directory gufo
  # auto-discovers. Do not move them back unless image requests are wanted.
  gufoServedModelName = "Qwen 3.8 Flash Next";
  gufoContext = 262144;
  # ~6.3 GB of KV/recurrent/indexer/MTP state per session at this context (gufo's measured figure).
  # Two sessions: the main agent holds one at 262k, the second lets a -smart subagent run alongside.
  # The weights plus both sessions measure ~100 GiB of the 124 GiB unified pool (gufo logs
  # gpu_device_used_mib); the rest is shared with the desktop and the CLI agents.
  gufoSessions = 2;
  # The Flash-Next continuation cache pins host pages on top of model and session state, and gufo sizes
  # it once from the free RAM at startup without ever re-checking it (gufo-org/gufo#387). Two sessions
  # leave ~15 GiB host-available at load; snapshots measured 0.5 GiB at 9k tokens and 0.8 GiB at 116k,
  # so 2 GiB retains the latest long checkpoint (the next turn restores it) and evicts older branches.
  # A larger cap left too little for the desktop and pushed two long prompts into zram swap;
  # MemoryMax fences whatever the budget does not cover.
  gufoCacheRamBytes = 4 * 1024 * 1024 * 1024;
  # A generation that makes no progress for this long exits as device_lost, so systemd restarts the
  # engine rather than the request hanging forever.
  gufoStallTimeoutMs = 120000;
  # Same key the Docker router served; external clients must not have to change it.
  gufoApiKeyFile = "${repoPath}/secrets/llama-strix-api-key";

  # The CI runner's token, handed to the runner as a systemd credential. The runner's uuid is
  # an identifier rather than a credential, so it lives in nixos/services/ci-runner.nix.
  ciRunnerTokenFile = "${repoPath}/secrets/ci-runner-token";
}
