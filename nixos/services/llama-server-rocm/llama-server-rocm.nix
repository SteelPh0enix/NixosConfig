# llama-server-vulkan's router, on upstream llama.cpp in an AMD ROCm 10.1 container for the
# gfx1100 card. The image is built by hand, not by Nix:
#   cd /mnt/NVMe/LLMs && docker build --no-cache -t llama-rocm-10.1-gfx1100 -f Dockerfile.rocm-10.1-gfx1100 .
# It drives the rootless daemon over /run/user/<uid>/docker.sock, so it needs lingering
# (nixos/users.nix) at boot, and keeps its published port: host networking hides /sys/class/kfd
# and ROCr then reports no device. Flags mirror llm-router-rocm-docker-compose.yml in /mnt/NVMe/LLMs.
# Only one engine holds the port, so this unit is gated on settings.llamaBackend. Do NOT disable a
# unit with `wantedBy = lib.mkForce [ ]`: it gets linked empty and pid1 refuses every activation.
{
  pkgs,
  lib,
  settings,
  ...
}:
let
  uid = toString settings.userUid;
  socket = "unix:///run/user/${uid}/docker.sock";

  serverArgs = [
    "--models-preset"
    settings.llamaRocmPresetsPath
    "--host"
    settings.llmHost
    "--port"
    (toString settings.llmPort)
    "--models-max"
    (toString settings.llamaModelsMax)
    # The endpoints n_ctx, the chat-template caps and the loaded preset get inspected through.
    "--slots"
    "--props"
    "--metrics"
    "--webui"
    "--perf"
  ];

  runArgs = [
    "run"
    "--rm"
    "--name"
    "llama-server-rocm"
    "--device"
    "/dev/kfd"
    "--device"
    "/dev/dri"
    "--group-add"
    "video"
    "--group-add"
    "render"
    "--security-opt"
    "seccomp=unconfined"
    "--shm-size"
    "8g"
    "--ulimit"
    "memlock=-1:-1"
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
    documentation = [
      "https://github.com/kyuz0/amd-strix-halo-toolboxes/blob/main/docs/rocm-10.1-gfx1100.md"
    ];
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
        # Being after user@.service is not the same as its rootless socket existing.
        "${pkgs.bash}/bin/bash -c 'for i in {1..30}; do [ -S /run/user/${uid}/docker.sock ] && exit 0; sleep 2; done; echo \"rootless docker socket missing: /run/user/${uid}/docker.sock\" >&2; exit 1'"
        # Fail loudly rather than have Docker pull a tag that has no registry.
        "${pkgs.docker}/bin/docker image inspect ${settings.llamaRocmImage} --format=image-present"
      ];

      ExecStart = "${pkgs.docker}/bin/docker ${lib.escapeShellArgs runArgs}";

      TimeoutStopSec = 60;
      Restart = "on-failure";
      RestartSec = 10;

      # Little hardening on purpose: the Docker socket is already the whole machine.
      User = settings.userName;
      PrivateTmp = true;
      NoNewPrivileges = true;
      UMask = "0077";
    };
  };
}
