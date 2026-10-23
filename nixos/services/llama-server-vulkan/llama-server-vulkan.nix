# llama.cpp router server: one process, presets from settings.llamaPresetsPath, models swapped in
# on request. It serves the LAN (pi runs on the other box), so it stays a sandboxed system service
# instead of something started from a terminal session, on the `llm` account gufo also runs as.
{
  pkgs,
  lib,
  settings,
  ...
}:
let
  args = [
    "--host"
    settings.llmHost
    "--port"
    (toString settings.llmPort)
    # /slots, /props, /metrics: how n_ctx, the chat-template caps and the loaded preset get inspected.
    "--slots"
    "--props"
    "--metrics"
    # How many models stay resident is per host; llama.cpp's autoload (on by default) then loads a
    # preset when a request names it - not at boot. Switching autoload off would make the router
    # answer 400 "model is not loaded" until something POSTs /load.
    "--models-max"
    (toString settings.llamaModelsMax)
    "--models-preset"
    settings.llamaPresetsPath
    # The browser chat and the t/s + pp/tg breakdown the log viewer follows.
    "--webui"
    "--perf"
  ];
in
{
  systemd.services.llama-server-vulkan = {
    description = "llama.cpp router server, Vulkan (${settings.llmHost}:${toString settings.llmPort})";
    documentation = [ "https://github.com/ggml-org/llama.cpp/tree/master/tools/server" ];
    # The boot engine: autoload reads a preset only when a request names one, so it comes up with
    # nothing loaded and an idle server holds none of the unified memory pool. A start still stops
    # gufo first (Conflicts=/After= below), so a model loaded here does not land on top of it.
    wantedBy = [ "multi-user.target" ];
    after = [
      "gufo.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    conflicts = [ "gufo.service" ];

    # Pin the real GPU: llvmpipe is enumerated as a second Vulkan device.
    environment = {
      GGML_VK_ALLOW_GRAPHICS_QUEUE = "1";
      GGML_VK_VISIBLE_DEVICES = "0";
    };

    serviceConfig = {
      # The rotation script writes one key per line and --api-key-file reads exactly that shape.
      # The credential path stays outside the quoted args so systemd expands
      # $CREDENTIALS_DIRECTORY at exec time; LoadCredential below is required, so a missing secret
      # fails the unit at start instead of booting an unauthenticated engine.
      ExecStart = "${lib.getExe' pkgs.llama-cpp "llama-server"} ${lib.escapeShellArgs args} --api-key-file $CREDENTIALS_DIRECTORY/api-key";
      LoadCredential = "api-key:${settings.llmApiKeyFile}";

      # Shared account declared in nixos/users.nix; gufo runs as the same user.
      User = "llm";
      Group = "llm";
      # Vulkan wants renderD128, the DRM card node sits in video.
      SupplementaryGroups = [
        "video"
        "render"
      ];
      # The presets live outside the repo and a `load-mode = mmap+mlock` one needs far more than the
      # non-privileged 8 KiB, so the limit stays raised even though the current presets do not use it.
      LimitMEMLOCK = "infinity";

      # A crash should not wedge the port.
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStopSec = 30;

      # Weights and preset both live under /home, so home is exposed read-only rather than masked;
      # everything else the service could touch is world-readable and outside any user's files.
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      ReadOnlyPaths = [
        settings.llamaModelsPath
        settings.llamaPresetsPath
      ];
      # PrivateDevices stays off: it would hide /dev/dri, and the GPU nodes are group-writable anyway.
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
      # The server only ever reads its own /proc entries.
      ProtectProc = "invisible";
      SystemCallArchitectures = "native";
      MemoryDenyWriteExecute = false; # the Vulkan driver JITs
      UMask = "0077";
    };
  };
}
