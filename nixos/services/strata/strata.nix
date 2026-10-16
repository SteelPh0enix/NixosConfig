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
# The context, the VRAM reserve and strataEngineArgs are arguments of the engine, and the image's
# entry point has no variable for them, so they are written into Strata's own config on the data
# volume before every start - the file is otherwise Strata's, and a reinstall (REINSTALL=1) rewrites
# it without them. On a volume with nothing installed yet the patch has no file to touch, so the very
# first start runs on the engine's defaults and the one after it is as configured.
#
# Measured here (RX 7900 XT 20 GB, 31 GB RAM), same harness every time: a 22.6K-token prompt, then
# 256 tokens out cold - each line is the one above plus one change:
#   32K context                     49 out,  963 prompt t/s   865 MiB VRAM free   27 GB RAM free
#   131K, KV in VRAM                48       1110                               27
#   + KV streaming                  52       1032                               25
#   + experts copied to RAM         55       1112     1.1 GiB VRAM free          10
# 262144 is the model's native length but it does not fit beside the RAM copy - the engine's own
# guard refuses the start - and forcing it in with a smaller copy served at 5 tokens/s.
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

  # What the engine is started with. These go into Strata's own model config and nowhere else: the
  # entry point forwards only the settings it has a variable for, and a setup pass rewrites the file.
  engineArgs = [
    "--max-context"
    (toString settings.strataContext)
    "--vram-reserve-mib"
    (toString settings.strataVramReserveMiB)
  ]
  ++ settings.strataEngineArgs;

  # Ensure those arguments in the pack config: whatever is there of them is dropped, the list is
  # appended, and a file that already matches is left alone.
  engineConfig = pkgs.writeText "strata-engine-args.py" ''
    import json, pathlib

    cfg = pathlib.Path("${settings.strataDataPath}/config/strata-coder-iq1_m.json")
    wanted = ${builtins.toJSON engineArgs}
    # The pinned variants: they take the RAM and do not give it back, which is what put this box on
    # its back the first time Strata ran. Stripped even though nothing asks for them.
    forbidden = ["--resident-experts", "--resident-budget-gib"]
    if cfg.exists():
        d = json.loads(cfg.read_text(encoding="utf-8"))
        owned = {a for a in wanted if a.startswith("--")} | set(forbidden)
        args, have, i = [], d.get("args", []), 0
        while i < len(have):
            if have[i] in owned:
                i += 1
                if i < len(have) and not have[i].startswith("--"):
                    i += 1
                continue
            args.append(have[i])
            i += 1
        if args + wanted != have:
            d["args"] = args + wanted
            cfg.write_text(json.dumps(d, indent=1), encoding="utf-8")
            print("strata: " + " ".join(wanted))
  '';

  patchArgs = "${pkgs.python3}/bin/python ${engineConfig}";

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
        # The engine arguments, re-applied on every start.
        patchArgs
      ];

      ExecStart = "${pkgs.docker}/bin/docker ${lib.escapeShellArgs runArgs}";

      # The first start downloads the model; do not cut it off, and do not treat the download as
      # a slow start worth retrying.
      TimeoutStartSec = "infinity";
      # Stopping is SIGTERM all the way down, and it has to be: the server turns it into a QUIT for
      # the engine, which releases the ROCm context. Kill it instead and the driver keeps the model's
      # GTT mappings - measured here as 15 GB of system RAM that nothing gets back but a GPU reset.
      TimeoutStopSec = 150;
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
