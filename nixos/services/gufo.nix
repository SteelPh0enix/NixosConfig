# Gufo serves Qwen3.8-Flash-Next on loopback; gufo-auth owns `llmPort` and checks the Bearer
# key. Gufo starts by hand, and the units conflict with the other engines.
{
  pkgs,
  lib,
  settings,
  ...
}:
let
  gufoServe = pkgs.writeShellScript "gufo-serve" ''
    set -euo pipefail
    exec ${lib.getExe pkgs.gufo} serve \
      --host 127.0.0.1 \
      --port ${toString settings.gufoUpstreamPort} \
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

  # The key stays off the command line: systemd passes it as a credential and the Caddyfile
  # expands it at load time.
  gufoAuthServe = pkgs.writeShellScript "gufo-auth-serve" ''
    set -euo pipefail
    LLM_API_KEY="$(cat "$CREDENTIALS_DIRECTORY/api-key")"
    export LLM_API_KEY
    exec ${lib.getExe pkgs.caddy} run --config ${caddyfile} --adapter caddyfile
  '';

  caddyfile = pkgs.writeText "gufo-auth-Caddyfile" ''
    {
      admin off
      auto_https off
    }

    :${toString settings.llmPort} {
      # Browsers send credentials only after the CORS preflight, which gufo answers itself.
      @preflight method OPTIONS
      @authed header Authorization "Bearer {$LLM_API_KEY}"

      handle @preflight {
        reverse_proxy 127.0.0.1:${toString settings.gufoUpstreamPort}
      }
      handle @authed {
        reverse_proxy 127.0.0.1:${toString settings.gufoUpstreamPort}
      }
      # Same body as the llama.cpp engines.
      handle {
        respond `{"error":{"message":"Invalid API key","type":"authorization"}}` 401
      }
    }
  '';
in
{
  systemd.services.gufo = {
    description = "Gufo engine, Qwen3.8-Flash-Next (127.0.0.1:${toString settings.gufoUpstreamPort}, behind gufo-auth on :${toString settings.llmPort})";
    documentation = [ "https://github.com/gufo-org/gufo" ];
    # Starts by hand; crucible is the boot engine.
    wantedBy = [ ];
    # One engine at a time: a start stops the others first and orders that stop ahead of the
    # start, so the port is free and the memory released before the weights load.
    after = [
      "crucible.service"
      "llama-server-rocm.service"
      "llama-server-vulkan.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    conflicts = [
      "crucible.service"
      "llama-server-rocm.service"
      "llama-server-vulkan.service"
    ];

    serviceConfig = {
      ExecStart = gufoServe;

      # gufo keeps its GGUF fingerprint cache under $XDG_CACHE_HOME/gufo, so point that at a
      # writable directory rather than a read-only home.
      CacheDirectory = "gufo";
      Environment = [ "XDG_CACHE_HOME=%C" ];

      # Shared with the Vulkan llama.cpp server.
      User = "llm";
      Group = "llm";
      SupplementaryGroups = [
        "video"
        "render"
      ];
      # HIP locks model pages; the non-privileged default is 8 KiB.
      LimitMEMLOCK = "infinity";

      # Only the host-side half of the footprint is in the cgroup: the weights are amdgpu GTT
      # charged to no unit and reclaimable by nobody. These bound session state and the cache.
      MemoryHigh = "14G";
      MemoryMax = "16G";
      # The cache and session state are what swap-in stalls decode; gufo gets a contained memcg
      # kill instead of minutes of zram churn.
      MemorySwapMax = "0";

      # A reload reads ~100 GiB, so do not start one into an OOM's leftovers. Stop gets 120s so
      # device memory is released before SIGKILL.
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

  # gufo-auth owns llmPort when gufo was started by hand and conflicts with the other engines;
  # gufo itself stays reachable only from loopback. A key rotation restarts this unit and leaves
  # the weights loaded.
  systemd.services.gufo-auth = {
    description = "Authenticating caddy front door for gufo (${settings.llmHost}:${toString settings.llmPort})";
    documentation = [ "https://caddyserver.com/docs/caddyfile" ];
    # Trips with gufo, by hand.
    wantedBy = [ ];
    after = [
      "crucible.service"
      "llama-server-rocm.service"
      "llama-server-vulkan.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    conflicts = [
      "crucible.service"
      "llama-server-rocm.service"
      "llama-server-vulkan.service"
    ];

    serviceConfig = {
      ExecStart = gufoAuthServe;
      LoadCredential = "api-key:${settings.llmApiKeyFile}";

      # caddy with `admin off` writes nothing; keep its XDG dirs inside the private /tmp anyway.
      User = "llm";
      Group = "llm";
      Environment = [
        "XDG_DATA_HOME=/tmp"
        "XDG_CACHE_HOME=/tmp"
      ];
      Restart = "on-failure";
      RestartSec = 5;

      ProtectSystem = "strict";
      ProtectHome = "read-only";
      PrivateTmp = true;
      PrivateIPC = true;
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
      AmbientCapabilities = "";
      # AF_NETLINK stays: libc getifaddrs() while opening the listener, same as gufo.
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
      # Nothing JITs here: caddy is Go, so deny write+execute outright.
      MemoryDenyWriteExecute = true;
      UMask = "0077";
    };
  };
}
