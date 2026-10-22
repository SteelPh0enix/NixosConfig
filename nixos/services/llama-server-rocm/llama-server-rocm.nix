# llama.cpp router server on ROCm 10.1, from the gfx1100 toolbox container
# (RX 7900 XT). Same port and same router behaviour as llama-server-vulkan; only the
# engine differs: upstream llama.cpp compiled against AMD's ROCm 10.1 Core SDK.
#
# The image is NOT built here. Build it by hand on this box:
#   cd /mnt/NVMe/LLMs
#   docker build --no-cache -t llama-rocm-10.1-gfx1100 -f Dockerfile.rocm-10.1-gfx1100 .
# which is the rootless daemon (it is the default context here), the same one this unit
# talks to. ExecStartPre fails with a readable error if the image is missing.
#
# Rootless Docker: the unit is a system service that drives the user daemon over
# /run/user/<uid>/docker.sock, so the container runs in the user's namespace and needs
# lingering (see nixos/users.nix) to be up at boot. Keep published ports - host
# networking under rootless Docker hides /sys/class/kfd and ROCr then reports no device.
#
# Flags mirror /mnt/NVMe/LLMs/llm-router-rocm-docker-compose.yml, which is the manual
# A/B path. Change one, change the other.
#
# Only one engine may hold the router port, so this unit is gated on settings.llamaBackend; the
# Vulkan module in nixos/services/llama-server-vulkan is gated the same way.
#
# Do NOT disable a unit from another module with `wantedBy = lib.mkForce [ ]`. The unit still gets
# linked, empty, and pid1 then logs "Service has no ExecStart=, ExecStop=, or SuccessAction.
# Refusing." on every activation. Reach for `enable` or drop the import.
{
  pkgs,
  lib,
  settings,
  ...
}:
let
  uid = toString settings.userUid;
  socket = "unix:///run/user/${uid}/docker.sock";

  # The container listens on the router port itself, so -p maps it one to one.
  serverArgs = [
    "--models-preset"
    settings.llamaRocmPresetsPath
    "--host"
    settings.llmHost
    "--port"
    (toString settings.llmPort)
    "--models-max"
    (toString settings.llamaModelsMax)
    # /slots, /props, /metrics: how n_ctx, the chat-template caps and the loaded preset get inspected.
    "--slots"
    "--props"
    "--metrics"
    # The browser chat and the t/s + pp/tg breakdown the log viewer follows.
    "--webui"
    "--perf"
  ];

  runArgs = [
    "run"
    "--rm"
    "--name"
    "llama-server-rocm"
    # ROCm needs the KFD node and the DRM render node.
    "--device"
    "/dev/kfd"
    "--device"
    "/dev/dri"
    "--group-add"
    "video"
    "--group-add"
    "render"
    # HSA wants an unfiltered syscall set inside the container.
    "--security-opt"
    "seccomp=unconfined"
    "--shm-size"
    "8g"
    "--ulimit"
    "memlock=-1:-1"
    # Weights and preset resolve at their real host paths, so the preset file needs no rewrites.
    "--volume"
    "${settings.llamaModelsPath}:${settings.llamaModelsPath}:ro"
    "--publish"
    "${toString settings.llmPort}:${toString settings.llmPort}"
    settings.llamaRocmImage
    "/usr/local/bin/llama-server"
  ]
  ++ serverArgs;
in
{
  systemd.services.llama-server-rocm = {
    enable = settings.llamaBackend == "rocm";
    description = "llama.cpp router server, ROCm container (${settings.llmHost}:${toString settings.llmPort})";
    documentation = [ "https://github.com/kyuz0/amd-strix-halo-toolboxes/blob/main/docs/rocm-10.1-gfx1100.md" ];
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "user@${uid}.service"
    ];
    wants = [ "network-online.target" ];
    requires = [ "user@${uid}.service" ];

    serviceConfig = {
      Environment = [
        "DOCKER_HOST=${socket}"
        "XDG_RUNTIME_DIR=/run/user/${uid}"
      ];

      ExecStartPre = [
        # The user daemon is a user service; being after user@.service is not the same as
        # its docker-rootless socket existing.
        "${pkgs.bash}/bin/bash -c 'for i in {1..30}; do [ -S /run/user/${uid}/docker.sock ] && exit 0; sleep 2; done; echo \"rootless docker socket missing: /run/user/${uid}/docker.sock\" >&2; exit 1'"
        # Fail loudly here rather than having Docker try to pull a tag that has no registry.
        "${pkgs.docker}/bin/docker image inspect ${settings.llamaRocmImage} --format=image-present"
      ];

      ExecStart = "${pkgs.docker}/bin/docker ${lib.escapeShellArgs runArgs}";

      # docker run forwards SIGTERM to llama-server, which unloads and exits; --rm cleans up.
      TimeoutStopSec = 60;
      Restart = "on-failure";
      RestartSec = 10;

      # Deliberately little hardening: access to the Docker socket is already the whole
      # machine, and the container is where isolation happens.
      User = settings.userName;
      PrivateTmp = true;
      NoNewPrivileges = true;
      UMask = "0077";
    };
  };
}

