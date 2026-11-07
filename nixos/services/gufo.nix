# Gufo engine serving Qwen3.8-Flash-Next with its shared MTP sidecar. It is the Strix Halo native
# engine, built from its flake input for gfx1151 (nix/overlays.nix). Gufo 0.31 dropped its own
# API-key auth entirely (gufo-org/gufo#957): the server answers every route without credentials, so
# it binds loopback-only (settings.gufoUpstreamPort) behind gufo-auth, the caddy front door below
# that owns the shared endpoint (settings.llmPort) and checks the same Bearer key the other two
# engines take. The units conflict the same way (llama-server-vulkan, llama-server-rocm), so only
# one listener is ever bound; the LAN and the Cloudflare Tunnel (https://clanker.steelph0enix.dev/)
# reach it with the same API key as those two.
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

  # The key must not land in the store: systemd hands it over as a credential, and this wrapper
  # exports it as the environment variable the Caddyfile's {$LLM_API_KEY} placeholder expands at
  # load time — unlike gufo's old `--api-key`, the value stays off the process command line.
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
      # Browsers send credentials only after the CORS preflight, and a preflight exposes nothing;
      # gufo answers those itself with its wildcard CORS policy. Everything else needs the key.
      @preflight method OPTIONS
      @authed header Authorization "Bearer {$LLM_API_KEY}"

      handle @preflight {
        reverse_proxy 127.0.0.1:${toString settings.gufoUpstreamPort}
      }
      handle @authed {
        reverse_proxy 127.0.0.1:${toString settings.gufoUpstreamPort}
      }
      # The body matches what the llama.cpp engines answer, so a bad key reads the same whichever
      # engine is up.
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
    # The boot engine. It loads its weights and the 262144-token sessions at boot and fills the
    # unified pool from then on — the accepted trade against the router engines, which idle with
    # no weights loaded. The after/conflicts lines below govern a manual `systemctl start gufo`
    # too: they stop the other engines first so the weights load into a free pool.
    wantedBy = [ "multi-user.target" ];
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
      ExecStart = gufoServe;

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

  # Gufo's front door: it owns the shared endpoint while gufo is up and conflicts with the other
  # two engines exactly like gufo does, so an engine start still frees the port (and the pool)
  # first, while gufo itself is unreachable from outside loopback. A key rotation is a
  # `systemctl restart gufo-auth`: only the front door re-reads the key, and gufo keeps its
  # weights loaded.
  systemd.services.gufo-auth = {
    description = "Authenticating caddy front door for gufo (${settings.llmHost}:${toString settings.llmPort})";
    documentation = [ "https://caddyserver.com/docs/caddyfile" ];
    # Boots with gufo, the boot engine. A start stops the router engines first, same as gufo.
    wantedBy = [ "multi-user.target" ];
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
      ExecStart = gufoAuthServe;
      LoadCredential = "api-key:${settings.llmApiKeyFile}";

      # caddy with `admin off` and no certificates writes nothing; point its XDG dirs at the
      # unit's private /tmp anyway so a stray write cannot touch a home.
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
