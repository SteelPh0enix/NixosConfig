{
  config,
  lib,
  hostId,
  ...
}:
let
  inherit (config.my) nixosConfigRepoPath;

  say = color: msg: "echo (set_color ${color})\"${msg}\"(set_color normal)";

  nhOs =
    operation: flags:
    lib.concatStringsSep " " [
      "nh"
      "os"
      operation
      nixosConfigRepoPath
      "--hostname"
      hostId
      flags
    ];

  guardHost = "__os-host-guard; or return 1";

  dockerRun =
    flags:
    lib.concatStringsSep " " (
      [
        "docker"
        "run"
        "--rm"
      ]
      ++ flags
      ++ [
        "-v"
        "$PWD:$PWD"
        "-w"
        "$PWD"
      ]
    );

  gpuFlags = [
    "--device"
    "/dev/kfd"
    "--device"
    "/dev/dri"
    "--security-opt"
    "seccomp=unconfined"
  ];

  rsyncFlags = "--archive --recursive --mkpath --verbose --progress --human-readable";

  piholeComposeDir = "${nixosConfigRepoPath}/nixos/services/pihole";
in
{
  # ~/.local/bin comes from xdg.binHome (needs xdg.enable); ~/.npm/bin is the global npm
  # prefix bin - `programs.npm` sets the prefix but never touches PATH.
  xdg.enable = true;
  xdg.localBinInPath = true;
  home.sessionPath = [ "$HOME/.npm/bin" ];

  home.sessionVariables = {
    LLAMA_CPP_REPO_PATH = config.my.llamaCppRepoPath;
    LLAMA_CPP_VENV_PATH = "${config.my.llamaCppRepoPath}/.venv";
    LLAMA_BASE_URL = "http://steelph0enix.framework:51536/v1";
    LLAMA_API_KEY = "dummy";
  };

  programs.fish = {
    enable = true;

    shellAliases = {
      # `lg` comes from programs.lazygit's own shell wrapper, eza from nixos/packages/system.nix.
      ls = "eza --icons=always -gM --git";
      l = "ls -lh";
      la = "ls -alh";
      e = "$EDITOR";
      eh = "$EDITOR .";
      cpr = "cp -r";
      rbt = "sudo systemctl reboot";
      cfge = "$EDITOR ${nixosConfigRepoPath}";
      jrn = "sudo journalctl -u";
      sts = "sudo systemctl status";
      str = "sudo systemctl restart";

      # Run a container in $PWD, mounted at the same path. `-shell*` keeps a TTY,
      # `-gpu*` passes the GPU nodes through.
      #
      # Deliberately no `-u $(id -u):$(id -g)`: on rootless docker container root *is* our host
      # uid, so files written into $PWD stay ours. Forcing our uid instead maps to an unmapped
      # subuid: $PWD turns unwritable, there is no passwd entry, and HOME falls back to /.
      docker-here = dockerRun [ ];
      docker-here-shell = dockerRun [ "-it" ];
      docker-here-gpu = dockerRun gpuFlags;
      docker-here-shell-gpu = dockerRun (gpuFlags ++ [ "-it" ]);

      rcp = "rsync ${rsyncFlags}";
      rcpc = "rsync ${rsyncFlags} --compress";
    };

    functions = {
      llama-cpp-update = {
        description = "Pull the latest llama.cpp checkout";
        body = ''
          ${say "green" "Directory: $LLAMA_CPP_REPO_PATH"}
          ${say "blue" "Pulling updates..."}
          git -C $LLAMA_CPP_REPO_PATH pull; or return 1
        '';
      };

      llama-cpp-venv-create = {
        description = "Create the llama.cpp ROCm venv (torch with the rocm backend)";
        body = ''
          ${say "green" "Creating venv for llama.cpp in $LLAMA_CPP_VENV_PATH..."}
          uv venv -c -p 3.14 --color auto --no-config $LLAMA_CPP_VENV_PATH
          llama-cpp-venv-activate

          ${say "blue" "Installing/updating packages..."}
          uv pip install --upgrade pip wheel setuptools transformers numpy torch sentencepiece \
              --prerelease=allow \
              --index-strategy unsafe-best-match \
              --torch-backend=rocm7.2

          pushd $LLAMA_CPP_REPO_PATH/gguf-py
          uv pip install --upgrade .
          popd

          ${say "blue" "Done!"}
        '';
      };

      llama-cpp-venv-activate = {
        description = "Activate the llama.cpp venv";
        body = ''
          ${say "green" "Activating llama.cpp venv..."}
          source "$LLAMA_CPP_VENV_PATH/bin/activate.fish"
          ${say "blue" "Done!"}
        '';
      };

      llama-cpp-hf-to-gguf = {
        description = "Convert a HuggingFace model to GGUF: llama-cpp-hf-to-gguf <model_path> <gguf_path>";
        body = ''
          llama-cpp-venv-activate
          python $LLAMA_CPP_REPO_PATH/convert_hf_to_gguf.py --outfile $argv[1] --outtype auto $argv[2]
        '';
      };

      # Rebuilds the local `llama-rocm` image (llama.cpp master, ROCm, gfx1151) from
      # kyuz0/amd-strix-halo-toolboxes. The build goes through `sudo docker`, i.e. the SYSTEM
      # daemon - the same one llm-router-rocm runs on; the rootless daemon is invisible to it.
      update-llama-cpp-rocm = {
        description = "Rebuild the local llama.cpp ROCm image from amd-strix-halo-toolboxes";
        body = ''
          set -l repo_dir /home/LLMs/amd-strix-halo-toolboxes
          set -l image llama-rocm

          if not test -d $repo_dir/.git
              ${say "green" "Cloning amd-strix-halo-toolboxes into $repo_dir..."}
              git clone https://github.com/kyuz0/amd-strix-halo-toolboxes.git $repo_dir; or return 1
          end

          ${say "green" "Pulling latest amd-strix-halo-toolboxes..."}
          git -C $repo_dir pull --ff-only; or return 1

          # --no-cache is mandatory: the `git clone llama.cpp master` step has no changing
          # inputs, so a cached build would keep the old llama.cpp forever.
          ${say "green" "Building $image:latest (llama.cpp master, ROCm, gfx1151)..."}
          sudo docker build --no-cache -t $image:latest \
              -f $repo_dir/toolboxes/Dockerfile.rocm-10.0 \
              $repo_dir/toolboxes; or return 1
        '';
      };

      update-services = {
        description = "Update the container-based services (llama.cpp ROCm image, PiHole)";
        body = ''
          ${say "green" "Updating PiHole"}
          env -C ${piholeComposeDir} sudo docker compose pull --policy always
          sudo systemctl restart pihole

          # grace period for DNS restart
          ${say "blue" "Waiting for PiHole restart..."}
          sleep 5
          ${say "green" "Updating PiHole lists"}
          sudo docker exec pihole pihole -g
        '';
      };

      __os-host-guard = {
        description = "Abort host-specific helpers unless running on ${hostId}";
        body = ''
          if test (hostname) != ${hostId}
              ${say "red" "Refusing: this configuration is for ${hostId}, this host is $(hostname)."}
              return 1
          end
        '';
      };

      os-rebuild = {
        description = "Build the NixOS system configuration";
        body = ''
          ${guardHost}
          ${say "yellow" "Rebuilding NixOS for ${hostId}..."}
          ${nhOs "boot" "--keep-going"}
          ${say "green" "System rebuild complete."}
        '';
      };

      os-rebuild-switch = {
        description = "Build and switch to a new NixOS system configuration";
        body = ''
          ${guardHost}
          ${say "yellow" "Rebuilding NixOS for ${hostId} and switching to new build..."}
          ${nhOs "switch" "--keep-going"}
          ${say "green" "System rebuild complete, switched to new build."}
        '';
      };

      os-update = {
        description = "Update llama.cpp, services and the flake inputs, rebuild, commit flake.lock";
        body = ''
          ${guardHost}
          ${say "magenta" "=== Starting OS Update Sequence ==="}

          llama-cpp-update; or return 1

          ${say "blue" "Updating services..."}
          update-services; or return 1

          ${say "yellow" "Rebuilding NixOS for ${hostId}..."}
          ${nhOs "boot" "--update --keep-going"}
          ${say "green" "System rebuild complete."}

          ${say "blue" "Committing flake.lock..."}
          git -C ${nixosConfigRepoPath} add flake.lock
          if git -C ${nixosConfigRepoPath} diff --cached --quiet
              ${say "yellow" "flake.lock unchanged - nothing to commit."}
          else
              git -C ${nixosConfigRepoPath} commit -m 'os update'
          end
          ${say "green" "=== OS Update done! ==="}
        '';
      };

      os-clean = {
        description = "Garbage-collect and optimise the Nix store";
        body = ''
          ${say "yellow" "Running NixOS cleanup..."}
          nh clean all --optimise
          ${say "green" "System Clean Complete."}
        '';
      };

      os-check = {
        description = "Verify and repair the Nix store";
        body = ''
          ${say "yellow" "Running NixOS store check/fix..."}
          sudo nix-store --verify --check-contents --repair
          ${say "green" "NixOS store check/fix complete!"}
        '';
      };
    };
  };
}
