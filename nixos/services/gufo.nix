# Gufo engine serving Qwen3.8-Flash-Next with its shared MTP sidecar. This replaced the rootless
# Docker llama.cpp router on this port: gufo is the Strix Halo native engine, built from its flake
# input for gfx1151 (nix/overlays.nix). The LAN and the Cloudflare Tunnel reach it through the same
# port and the same API key, so external clients did not change.
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
      --host ${settings.llamaRouterHost} \
      --port ${toString settings.llamaStrixPort} \
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
    description = "Gufo engine, Qwen3.8-Flash-Next (${settings.llamaRouterHost}:${toString settings.llamaStrixPort})";
    documentation = [ "https://github.com/gufo-org/gufo" ];
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      ExecStart = serve;
      LoadCredential = "api-key:${settings.gufoApiKeyFile}";

      # gufo keeps its GGUF fingerprint cache under $XDG_CACHE_HOME/gufo, so point that at a
      # writable directory rather than a read-only home.
      CacheDirectory = "gufo";
      Environment = [ "XDG_CACHE_HOME=%C" ];

      # `llama` is declared by the Vulkan llama.cpp service; both are GPU services on one user.
      User = "llama";
      Group = "llama";
      SupplementaryGroups = [
        "video"
        "render"
      ];
      # HIP locks model pages; the non-privileged default is 8 KiB.
      LimitMEMLOCK = "infinity";

      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStopSec = 30;

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
