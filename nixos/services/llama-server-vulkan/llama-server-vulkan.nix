# llama.cpp router: presets from settings.llamaPresetsPath, models swapped in on request.
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
    # /slots, /props, /metrics expose n_ctx, template caps and the loaded preset.
    "--slots"
    "--props"
    "--metrics"
    # Autoload stays on: off, the router answers 400 "model is not loaded" until a /load.
    "--models-max"
    (toString settings.llamaModelsMax)
    "--models-preset"
    settings.llamaPresetsPath
    "--webui"
    "--perf"
  ];
in
{
  systemd.services.llama-server-vulkan = {
    description = "llama.cpp router server, Vulkan (${settings.llmHost}:${toString settings.llmPort})";
    documentation = [ "https://github.com/ggml-org/llama.cpp/tree/master/tools/server" ];
    # Starts by hand; gufo is the boot engine. A start stops the other engines first.
    wantedBy = [ ];
    after = [
      "gufo-auth.service"
      "gufo.service"
      "llama-server-rocm.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    conflicts = [
      "gufo-auth.service"
      "gufo.service"
      "llama-server-rocm.service"
    ];

    # Pin the real GPU: llvmpipe is enumerated as a second Vulkan device.
    environment = {
      GGML_VK_ALLOW_GRAPHICS_QUEUE = "1";
      GGML_VK_VISIBLE_DEVICES = "0";
    };

    serviceConfig = {
      # The credential is expanded in a shell wrapper: systemd's own `$CREDENTIALS_DIRECTORY`
      # expansion in ExecStart ate it as empty. The key stays off the command line.
      ExecStart = pkgs.writeShellScript "llama-server-vulkan-serve" ''
        exec ${lib.getExe' pkgs.llama-cpp "llama-server"} ${lib.escapeShellArgs args} \
          --api-key-file "$CREDENTIALS_DIRECTORY/api-key"
      '';
      LoadCredential = "api-key:${settings.llmApiKeyFile}";

      User = "llm";
      Group = "llm";
      # Vulkan wants renderD128; the DRM card node sits in video.
      SupplementaryGroups = [
        "video"
        "render"
      ];
      # A mmap+mlock preset needs far more than the non-privileged 8 KiB.
      LimitMEMLOCK = "infinity";

      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStopSec = 30;

      # Weights and preset live under /home, so home is read-only rather than masked.
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      ReadOnlyPaths = [
        settings.llamaModelsPath
        settings.llamaPresetsPath
      ];
      # PrivateDevices would hide /dev/dri.
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
