# Gufo engine serving Qwen3.8-Flash-Next with its shared MTP sidecar. It is the Strix Halo native
# engine, built from its flake input for gfx1151 (nix/overlays.nix). It listens on the shared
# endpoint (settings.llmPort) and conflicts with the other two engines (llama-server-vulkan,
# llama-server-rocm), so only one engine is bound at a time; the LAN and the Cloudflare Tunnel
# (https://clanker.steelph0enix.dev/) reach it with the same API key.
{
  pkgs,
  lib,
  settings,
  ...
}:
let
  # gufo has no env alias for the key (unlike llama.cpp's LLAMA_API_KEY) and the value must not land
  # in the store: systemd reads the secret as root, exposes it under $CREDENTIALS_DIRECTORY, and this
  # wrapper expands it at exec time.
  serve = pkgs.writeShellScript "gufo-serve" ''
    set -euo pipefail
    exec ${lib.getExe pkgs.gufo} serve \
      --host ${settings.llmHost} \
      --port ${toString settings.llmPort} \
      --api-key "$(cat "$CREDENTIALS_DIRECTORY/api-key")" \
      llm \
      --model ${settings.gufoModelPath} \
      --speculative mtp \
      --mtp-model ${settings.gufoMtpPath} \
      --context ${toString settings.gufoContext} \
      --sessions ${toString settings.gufoSessions} \
      --cache-ram-bytes ${toString settings.gufoCacheRamBytes} \
      --stall-timeout-ms ${toString settings.gufoStallTimeoutMs} \
      --served-model-name ${lib.escapeShellArg settings.gufoServedModelName}
  '';
in
{
  systemd.services.gufo = {
    description = "Gufo engine, Qwen3.8-Flash-Next (${settings.llmHost}:${toString settings.llmPort})";
    documentation = [ "https://github.com/gufo-org/gufo" ];
    # Starts by hand: its 262144-token session permanently fills the unified memory pool, so the
    # boot engine is the one that idles empty (llama-server-rocm). The after/conflicts lines
    # below govern the manual `systemctl start gufo`: they stop the other engines first so the
    # weights load into a free pool.
    wantedBy = [ ];
    # One engine at a time: a start of gufo stops the other engines first, and the ordering keeps
    # that stop ahead of the start so the port is free and the memory is released before the
    # weights load.
    after = [
      "llama-server-rocm.service"
      "llama-server-vulkan.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    conflicts = [
      "llama-server-rocm.service"
      "llama-server-vulkan.service"
    ];

    serviceConfig = {
      ExecStart = serve;
      LoadCredential = "api-key:${settings.llmApiKeyFile}";

      # gufo keeps its GGUF fingerprint cache under $XDG_CACHE_HOME/gufo, so point that at a
      # writable directory rather than a read-only home.
      CacheDirectory = "gufo";
      Environment = [ "XDG_CACHE_HOME=%C" ];

      # Shared account declared in nixos/users.nix; the Vulkan llama.cpp server runs as the same
      # user.
      User = "llm";
      Group = "llm";
      SupplementaryGroups = [
        "video"
        "render"
      ];
      # HIP locks model pages; the non-privileged default is 8 KiB.
      LimitMEMLOCK = "infinity";

      # Only the host-side half of the footprint is visible to the cgroup: the weights live in amdgpu GTT
      # buffer objects, allocated in the kernel, charged to no unit and reclaimable by nobody (measured
      # 89 GiB in mem_info_gtt_used against 6 GiB of process RSS). These bound the half that does grow -
      # session state plus the continuation cache, ~6 GiB measured - so a runaway cache costs gufo a cgroup
      # kill instead of taking the machine down with a global OOM.
      MemoryHigh = "14G";
      MemoryMax = "16G";
      # The cache and session state are the pages whose swap-in stalls decode. The kernel may still
      # swap the desktop and agents, which do not hold a GPU session; gufo itself gets a contained
      # memcg kill instead of minutes of zram churn.
      MemorySwapMax = "0";

      # A reload reads ~100 GiB from disk, so do not start one into the pressure an OOM just left behind.
      # Stop gets 120s rather than 30: a shutdown that exceeded the old timeout was SIGKILLed with device
      # memory still attached, and the next load had to work around the leftovers.
      OOMPolicy = "stop";
      Restart = "on-failure";
      RestartSec = 60;
      TimeoutStopSec = 120;

      # Weights live under /home, so home is exposed read-only rather than masked.
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      ReadOnlyPaths = [ settings.llamaModelsPath ];
      PrivateTmp = true;
      PrivateIPC = true;
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
      AmbientCapabilities = "";
      # AF_NETLINK stays: libc getifaddrs() uses it while setting up the listening socket.
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_NETLINK"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
      RestrictSUIDSGID = true;
      RestrictRealtime = true;
      LockPersonality = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      ProtectProc = "invisible";
      SystemCallArchitectures = "native";
      MemoryDenyWriteExecute = false; # HIP JITs device code at runtime
      UMask = "0077";
    };
  };
}
