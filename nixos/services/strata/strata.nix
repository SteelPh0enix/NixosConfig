# Strata: Qwen3.8-Flash-Next in its own engine, here the Coder (IQ1_M: 256 of the 512 experts per
# layer, kept for code) - the size that fits this box's 31 GB of RAM. Unlike llama.cpp it is not a
# router: one model, loaded at start, OpenAI- and Anthropic-compatible API plus a browser UI.
#
# It runs in a container because its engine wants AMD's ROCm 7 userland, which this system does
# not ship: the image (Dockerfile next to this file) carries Strata, its .venv and the engine
# compiled for gfx1100. Build it by hand, same as the ROCm llama.cpp toolbox:
#   cd ~/nixos-config
#   docker build -t strata-hip-gfx1100:latest -f nixos/services/strata/Dockerfile nixos/services/strata
# ExecStartPre fails with a readable error while the image is missing.
#
# Rootless Docker, like llama-server-rocm: the unit drives the user daemon over
# /run/user/<uid>/docker.sock, so the container runs in the user's namespace and needs lingering
# (nixos/users.nix) to be up at boot. Published ports, not host networking - under rootless Docker
# host networking hides /sys/class/kfd and ROCr then reports no device.
#
# NOT wanted by multi-user.target: the model wants the card, and the llama.cpp router is what the
# subagent fleet uses, so starting this is a deliberate
#   systemctl start strata      (stops llama-server-vulkan; see Conflicts)
#   systemctl stop strata
# The first start downloads ~65 GB to settings.strataDataPath and is resumable, then writes a 23 GB
# expert pack next to it; loading the model takes a minute or two, during which the machine is slow.
#
# No API key: the server binds 0.0.0.0 and the firewall (nixos/services.nix) decides who reaches
# it, exactly like llama-server-vulkan. Add one (strataApiKey in settings, passed as API_KEY)
# before ever routing that port beyond the LAN.
#
# How little of the machine it leaves used is three settings: the context and the container's RAM
# ceiling, the mapped expert variant in the env below, and strataVramReserveMiB. The last one is an
# argument of the engine and the image's entry point has no variable for it, so it is written into
# Strata's own config on the data volume before every start - the file is otherwise Strata's, and a
# reinstall (REINSTALL=1) rewrites it without the argument. On a data volume with nothing installed
# yet the patch has no file to touch, so the very first start runs with the engine's default and the
# one after it is sized as configured.
#
# Measured with all of that on this box (RX 7900 XT, 31 GB): 1.1 GiB of VRAM and 27 GB of RAM free
# while serving, 33-59 tokens/s out, and llama-server-vulkan's presets swap the card in when it is
# started again.
{
  pkgs,
  lib,
  settings,
  ...
}:
let
  uid = toString settings.userUid;
  socket = "unix:///run/user/${uid}/docker.sock";

  # The container keeps its own 8080; -p maps the host port onto it.
  containerPort = 8080;

  # Read by the image's docker-entrypoint.sh: on a data dir with no config for this family and
  # size it runs Strata's setup (download + pack) and then starts the server.
  #
  # LOW_RAM=mmap: the mapped variant of the low-RAM mode, so the experts the card does not hold are
  # read through the OS file cache instead of copied into locked RAM (`--mmap-experts`); setup's own
  # `auto` picks the resident variant here, and that one left this 31 GB box with nothing free.
  # STRATA_ARENA_MMAP=1 goes with it: without it ROCclr pins every page of experts.bin it copies to
  # the card and never gives them back - the engine's own comment for this describes "a 32 GB PC ran
  # with ~0.3 GB free: the kernel swapped" (src/program/generate.cpp).
  environment = {
    STRATA_DATA = settings.strataDataPath;
    FAMILY = "coder";
    MODEL = "IQ1_M";
    CONTEXT = toString settings.strataContext;
    LOW_RAM = "mmap";
    STRATA_ARENA_MMAP = "1";
    HOST = "0.0.0.0";
    PORT = toString containerPort;
  };

  # --vram-reserve-mib into Strata's model config, and nowhere else: the entry point only forwards
  # the settings it knows, and a setup pass would write the argument out.
  reserveConfig = pkgs.writeText "strata-vram-reserve.py" ''
    import json, pathlib

    cfg = pathlib.Path("${settings.strataDataPath}/config/strata-coder-iq1_m.json")
    tail = ["--vram-reserve-mib", "${toString settings.strataVramReserveMiB}"]
    if cfg.exists():
        d = json.loads(cfg.read_text(encoding="utf-8"))
        args, drop_one = [], False
        for a in d.get("args", []):
            if a == "--vram-reserve-mib":
                drop_one = True
                continue
            if drop_one:
                drop_one = False
                continue
            args.append(a)
        if d["args"][-2:] != tail:
            d["args"] = args + tail
            cfg.write_text(json.dumps(d, indent=1), encoding="utf-8")
            print("strata: --vram-reserve-mib ${toString settings.strataVramReserveMiB}")
  '';

  patchReserve = "${pkgs.python3}/bin/python ${reserveConfig}";

  runArgs = [
    "run"
    "--rm"
    "--name"
    "strata"
    # ROCm needs the KFD node and the DRM render node; HSA wants an unfiltered syscall set.
    # No --group-add video/render (the ROCm units carry it): rootless Docker cannot resolve those
    # names, and it could not grant the host's 26/303 anyway, since only the subgid range is mapped
    # into the user namespace. It works without them - /dev/kfd and renderD128 are 0666 on this box.
    "--device"
    "/dev/kfd"
    "--device"
    "/dev/dri"
    "--security-opt"
    "seccomp=unconfined"
    "--shm-size"
    "8g"
    "--ulimit"
    "memlock=-1:-1"
    # The two guards that keep a loaded model from taking the desktop down with it: the RAM ceiling
    # (Strata reads 31 GB from /proc/meminfo, the container's real limit is this) and a high OOM
    # score, so the kernel stops the model first and never the compositor.
    "--memory"
    settings.strataMemoryLimit
    "--oom-score-adj"
    "500"
    # The pack lives at its real host path, so the paths saved in the model config stay valid.
    "--volume"
    "${settings.strataDataPath}:${settings.strataDataPath}"
    "--publish"
    "${toString settings.strataPort}:${toString containerPort}"
  ]
  ++ lib.concatMap (n: [
    "-e"
    "${n}=${environment.${n}}"
  ]) (builtins.attrNames environment)
  ++ [ settings.strataImage ];
in
{
  # The pack and Strata's config outlive the container; tmpfiles owns the empty directory.
  systemd.tmpfiles.rules = [ "d ${settings.strataDataPath} 0755 ${settings.userName} users -" ];

  systemd.services.strata = {
    description = "Strata (Qwen3.8-Flash-Next Coder, HIP container) on :${toString settings.strataPort}";
    documentation = [ "https://github.com/Niko1221/Strata/blob/main/docs/AMD_HIP.md" ];
    after = [
      "network-online.target"
      "user@${uid}.service"
    ];
    wants = [ "network-online.target" ];
    requires = [ "user@${uid}.service" ];

    # One card, one engine: whichever of them starts stops the others.
    conflicts = [
      "llama-server-vulkan.service"
      "llama-server-rocm.service"
    ];

    serviceConfig = {
      Environment = [
        "DOCKER_HOST=${socket}"
        "XDG_RUNTIME_DIR=/run/user/${uid}"
      ];

      ExecStartPre = [
        # The user daemon is a user service; being after user@.service is not the same as its
        # docker-rootless socket existing.
        "${pkgs.bash}/bin/bash -c 'for i in {1..30}; do [ -S /run/user/${uid}/docker.sock ] && exit 0; sleep 2; done; echo \"rootless docker socket missing: /run/user/${uid}/docker.sock\" >&2; exit 1'"
        # Fail loudly here rather than having Docker try to pull a tag that has no registry.
        "${pkgs.docker}/bin/docker image inspect ${settings.strataImage} --format=image-present"
        # The VRAM reserve, re-applied on every start.
        patchReserve
      ];

      ExecStart = "${pkgs.docker}/bin/docker ${lib.escapeShellArgs runArgs}";

      # The first start downloads the model; do not cut it off, and do not treat the download as
      # a slow start worth retrying.
      TimeoutStartSec = "infinity";
      TimeoutStopSec = 60;
      Restart = "on-failure";
      RestartSec = 10;
      StartLimitBurst = 2;

      # Deliberately little hardening: access to the Docker socket is already the whole machine,
      # and the container is where the isolation happens.
      User = settings.userName;
      PrivateTmp = true;
      NoNewPrivileges = true;
      UMask = "0077";
    };
  };
}
