# llama.cpp router server: one process, presets from settings.llamaPresetsPath, models swapped in
# on request. It serves the LAN (pi runs on the other box), so it stays a sandboxed system service
# on its own user instead of something started from a terminal session.
{
  pkgs,
  lib,
  settings,
  ...
}:
let
  args = [
    "--host"
    settings.llamaRouterHost
    "--port"
    (toString settings.llamaRouterPort)
    # /slots, /props, /metrics: how n_ctx, the chat-template caps and the loaded preset get inspected.
    "--slots"
    "--props"
    "--metrics"
    # 20 GB VRAM: one model resident, and llama.cpp's autoload (on by default) loads a preset when
    # a request names it - not at boot. Switching it off would make the router answer 400 "model is
    # not loaded" until something POSTs /load.
    "--models-max"
    "1"
    "--models-preset"
    settings.llamaPresetsPath
  ];
in
{
  users.groups.llama = { };
  users.users.llama = {
    group = "llama";
    isSystemUser = true;
  };

  systemd.services.llama-server = {
    description = "llama.cpp router server (${settings.llamaRouterHost}:${toString settings.llamaRouterPort})";
    documentation = [ "https://github.com/ggml-org/llama.cpp/tree/master/tools/server" ];
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      ExecStart = "${lib.getExe' pkgs.llama-cpp "llama-server"} ${lib.escapeShellArgs args}";
      User = "llama";
      Group = "llama";
      # Vulkan wants renderD128, ROCm compute wants kfd.
      SupplementaryGroups = [
        "video"
        "render"
      ];
      # `load-mode = mmap+mlock` in the presets needs far more than the non-privileged 8 KiB.
      LimitMEMLOCK = "infinity";

      # A crash should not wedge the port.
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStopSec = 30;

      # The weights are world-readable and live outside $HOME, so nothing here needs a user's files.
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadOnlyPaths = [ settings.llamaModelsPath ];
      # PrivateDevices stays off: it would need the GPU nodes whitelisted one by one, and they are
      # group-writable anyway.
      PrivateTmp = true;
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
      AmbientCapabilities = "";
      # AF_NETLINK stays: getaddrinfo(AI_ADDRCONFIG) needs it to resolve the bind address.
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
      SystemCallArchitectures = "native";
      MemoryDenyWriteExecute = false; # the Vulkan driver JITs
      UMask = "0077";
    };
  };
}
