{ config, lib, ... }:
let
  inherit (config.my) nixosHostId nixosConfigRepoPath;

  say = color: msg: "echo (set_color ${color})\"${msg}\"(set_color normal)";

  nhOs =
    operation: flags:
    lib.concatStringsSep " " [
      "nh"
      "os"
      operation
      nixosConfigRepoPath
      "--hostname"
      nixosHostId
      flags
    ];

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
in
{
  # ~/.local/bin comes from xdg.binHome (needs xdg.enable); ~/.npm/bin is the global npm
  # prefix bin - `programs.npm` sets the prefix but never touches PATH.
  xdg.enable = true;
  xdg.localBinInPath = true;
  home.sessionPath = [ "$HOME/.npm/bin" ];

  home.sessionVariables.LLAMA_CPP_REPO_PATH = config.my.llamaCppRepoPath;

  programs.fish = {
    enable = true;

    shellAliases = {
      l = "ls -lh";
      la = "ls -alh";
      # `lg` comes from programs.lazygit's own fish integration.
      e = "$EDITOR";
      eh = "$EDITOR .";
      cpr = "cp -r";
      rbt = "sudo systemctl reboot";
      cfge = "$EDITOR ${nixosConfigRepoPath}";

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

      os-rebuild = {
        description = "Build the NixOS system configuration";
        body = ''
          ${say "yellow" "Rebuilding NixOS for ${nixosHostId}..."}
          ${nhOs "boot" "--keep-going"}
          ${say "green" "System rebuild complete."}
        '';
      };

      os-rebuild-switch = {
        description = "Build and switch to a new NixOS system configuration";
        body = ''
          ${say "yellow" "Rebuilding NixOS for ${nixosHostId} and switching to new build..."}
          ${nhOs "switch" "--keep-going"}
          ${say "green" "System rebuild complete, switched to new build."}
        '';
      };

      os-update = {
        description = "Update llama.cpp and the flake inputs, rebuild, commit flake.lock";
        body = ''
          ${say "magenta" "=== Starting OS Update Sequence ==="}

          llama-cpp-update; or return 1

          ${say "yellow" "Rebuilding NixOS for ${nixosHostId}..."}
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
