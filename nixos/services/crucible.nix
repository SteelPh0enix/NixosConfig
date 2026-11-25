# Crucible serves Qwen3.8-Flash-Next on `llmPort` and checks the Bearer key itself; it boots when
# `settings.defaultLlmEngine` names it, and the other engines start by hand and conflict with it.
{
  pkgs,
  lib,
  settings,
  ...
}:
let
  prepare = pkgs.writeShellScript "crucible-prepare" ''
    set -euo pipefail
    ${pkgs.coreutils}/bin/install -m 600 "$CREDENTIALS_DIRECTORY/api-key" "$STATE_DIRECTORY/api-key"
  '';

  serve = pkgs.writeShellScript "crucible-serve" ''
    set -euo pipefail
    exec ${pkgs.crucible}/bin/crucible-server \
      ${lib.escapeShellArg settings.crucibleModelPath} \
      --engine ${pkgs.crucible}/share/crucible/engine \
      --host ${settings.llmHost} \
      --port ${toString settings.llmPort} \
      --model-id ${lib.escapeShellArg settings.crucibleServedModelName} \
      --api-key-file "$STATE_DIRECTORY/api-key" \
      --streams ${toString settings.crucibleStreams} \
      --ctx 262144 \
      --prefill 4096 \
      --conversation-cache-mib 9700 \
      --host-reserve-mib 11264 \
      --state-dir ${lib.escapeShellArg settings.crucibleStatePath} \
      --state-disk-gib 200 \
      --vision \
      --clamp-max-tokens \
      --default-thinking on \
      --max-body-mib 16 \
      --systemd \
      --no-update-check
  '';
in
{
  # The engine's own home and the cache that spills into it, both llm-owned: crucible 0.38 refuses
  # a state folder whose parent chain another user can change, which rules out /home/LLMs.
  # ReadWritePaths below also needs the state folder to exist before the /home mount.
  systemd.tmpfiles.rules = [
    "d ${settings.crucibleHomePath} 0700 llm llm - -"
    "d ${settings.crucibleStatePath} 0700 llm llm - -"
  ];

  systemd.services.crucible = {
    description = "Crucible engine, Qwen3.8-Flash-Next EXL3 (${settings.llmHost}:${toString settings.llmPort})";
    documentation = [ "https://github.com/jaedync/crucible-strix-halo" ];
    wantedBy = lib.optionals (settings.defaultLlmEngine == "crucible") [ "multi-user.target" ];
    after = [
      "gufo.service"
      "gufo-auth.service"
      "llama-server-rocm.service"
      "llama-server-vulkan.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    conflicts = [
      "gufo.service"
      "gufo-auth.service"
      "llama-server-rocm.service"
      "llama-server-vulkan.service"
    ];

    # The measured run of docs/QUICKSTART.md, step 6, plus py unbuffering for the journal.
    environment = {
      # HOME moves with the state folder: llm's real home is on the root filesystem, which has no
      # room for the 200 GiB cache, and 0.38 wants the state folder changeable by `llm` or root
      # only, which the engine's own home satisfies.
      HOME = settings.crucibleHomePath;
      CRUCIBLE_PLE_HOST = "1";
      CRUCIBLE_COMPACT_STATE = "1";
      CRUCIBLE_PLE_FETCH = "1";
      CRUCIBLE_DRAFT_HEAD = "q2";
      CRUCIBLE_DRAFT_CHAIN = "hc8,lead";
      CRUCIBLE_PF_LAUNCH_ROWS = "16384+128";
      PYTHONUNBUFFERED = "1";
    };

    serviceConfig = {
      Type = "notify";
      NotifyAccess = "main";
      ExecStartPre = prepare;
      ExecStart = serve;
      # systemd reads the secret as root; the copy is the file --api-key-file needs (0600, llm-owned).
      LoadCredential = "api-key:${settings.llmApiKeyFile}";
      StateDirectory = "crucible";
      StateDirectoryMode = "0700";

      User = "llm";
      Group = "llm";
      SupplementaryGroups = [
        "video"
        "render"
      ];
      LimitMEMLOCK = "infinity";
      LimitNOFILE = 65536;
      LimitCORE = 0;

      # Only the host half is in the cgroup: weights and sessions are GTT charged to no unit. 24G
      # covers the 9.7 GiB conversation cache plus page cache for the n-gram table.
      MemoryHigh = "20G";
      MemoryMax = "24G";
      MemorySwapMax = "0";

      WatchdogSec = 30;
      TimeoutStartSec = 1200;
      TimeoutStopSec = 120;
      Restart = "on-failure";
      RestartSec = 60;
      # 2 = bad config or bind, 78 = bad key file: a restart cannot fix either.
      RestartPreventExitStatus = [
        2
        78
      ];
      OOMPolicy = "stop";
      SyslogIdentifier = "crucible";

      ProtectSystem = "strict";
      ProtectHome = "read-only";
      ReadWritePaths = [ settings.crucibleStatePath ];
      PrivateTmp = true;
      PrivateIPC = true;
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
      AmbientCapabilities = "";
      # AF_NETLINK stays: libc getifaddrs() while opening the listener.
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
