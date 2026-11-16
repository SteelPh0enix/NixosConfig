# llama.cpp router server: one process, models swapped in from the presets on request.
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
    "--slots"
    "--props"
    "--metrics"
    # Autoload (on by default) loads a named preset on request, not at boot; switching it off would
    # make the router answer 400 until something POSTs /load.
    "--models-max"
    (toString settings.llamaModelsMax)
    "--models-preset"
    settings.llamaPresetsPath
    "--webui"
    "--perf"
  ];
in
{
  users.groups.llama = { };
  users.users.llama = {
    group = "llama";
    isSystemUser = true;
  };

  systemd.services.llama-server-vulkan = {
    # Kept configured, but only one backend may own the port: settings.llamaBackend picks it.
    enable = settings.llamaBackend == "vulkan";
    description = "llama.cpp router server, Vulkan (${settings.llmHost}:${toString settings.llmPort})";
    documentation = [ "https://github.com/ggml-org/llama.cpp/tree/master/tools/server" ];
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    # Pin the real GPU: llvmpipe is enumerated as a second Vulkan device.
    environment = {
      GGML_VK_ALLOW_GRAPHICS_QUEUE = "1";
      GGML_VK_VISIBLE_DEVICES = "0";
    };

    serviceConfig = {
      ExecStart = "${lib.getExe' pkgs.llama-cpp "llama-server"} ${lib.escapeShellArgs args}";
      User = "llama";
      Group = "llama";
      SupplementaryGroups = [
        "video"
        "render"
      ];
      # `load-mode = mmap+mlock` in the presets needs far more than the non-privileged 8 KiB.
      LimitMEMLOCK = "infinity";

      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStopSec = 30;

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
      ProtectProc = "invisible";
      SystemCallArchitectures = "native";
      MemoryDenyWriteExecute = false; # the Vulkan driver JITs
      UMask = "0077";
    };
  };
}
