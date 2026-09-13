{
  pkgs,
  lib,
  settings,
  ...
}:
let
  inherit (settings) repoPath llamaCppPath;

  # ANSI status lines: `printf` instead of fish's `set_color`, so any shell renders them.
  # `'' ''` strings keep backslashes literal, which is exactly what printf needs here.
  say = sgr: message: ''printf '\033[1;${sgr}m%s\033[0m\n' ${lib.escapeShellArg message}'';
  error = say "31";
  warning = say "38;5;208"; # orange
  info = say "34";
  success = say "32";

  # POSIX-sh scripts instead of fish functions: they also work from `nvim :!`, systemd-run,
  # a non-interactive ssh session and any other shell.
  script =
    name: description: text:
    pkgs.writeShellApplication {
      inherit name text;
      runtimeInputs = [
        pkgs.nh
        pkgs.git
      ];
      meta.description = description;
    };

  rsyncFlags = "--archive --recursive --mkpath --verbose --progress --human-readable";
in
{
  # Fish stays the login shell; nothing below depends on it. This option is what makes
  # `home.shellAliases` reach fish at all.
  programs.fish.enable = true;

  # ~/.npm/bin: programs.npm sets the global prefix to ~/.npm but never adds its bin to PATH.
  # ~/.local/bin itself goes into PATH system-wide (environment.localBinInPath).
  home.sessionPath = [ "$HOME/.npm/bin" ];

  home.sessionVariables = {
    LLAMA_CPP_REPO_PATH = llamaCppPath;
    LLAMA_CPP_VENV_PATH = "${llamaCppPath}/.venv";
    LLAMA_BASE_URL = "http://steelph0enix.framework:51536/v1";
    LLAMA_API_KEY = "dummy";
  };

  # Simple, shell-independent aliases. eza's own integration already provides
  # ls/ll/la/lt/lla, so only `l` is added here - on purpose through `ls`, so it keeps eza's
  # icons/--git/extraOptions.
  home.shellAliases = {
    l = "ls -lh";
    e = "$EDITOR";
    eh = "$EDITOR .";
    cpr = "cp -r";
    rbt = "sudo systemctl reboot";
    cfge = "$EDITOR ${repoPath}";
    jrn = "sudo journalctl -u";
    sts = "sudo systemctl status";
    str = "sudo systemctl restart";
    rcp = "rsync ${rsyncFlags}";
    rcpc = "rsync ${rsyncFlags} --compress";
  };

  programs.fish.functions = {
    # Sourcing activate.fish only works in fish, so this one stays a fish function - every
    # script below uses $LLAMA_CPP_VENV_PATH/bin directly instead.
    llama-cpp-venv-activate = {
      description = "Activate the llama.cpp venv";
      body = ''
        ${info "Activating llama.cpp venv..."}
        source "$LLAMA_CPP_VENV_PATH/bin/activate.fish"
      '';
    };
  };

  home.packages =
    let
      dockerHere = pkgs.writeShellApplication {
        name = "docker-here";
        runtimeInputs = [ pkgs.docker ];
        meta.description = "Run a container with $PWD mounted at the same path";
        text = ''
          usage() {
            cat <<'EOF'
          docker-here - run a container against the current directory

          Usage: docker-here [OPTIONS] IMAGE [ARG...]

            -s, --shell   interactive run (-it), image command defaults to the image's shell
            -g, --gpu     pass through the AMD GPU nodes and disable the seccomp profile
            -h, --help    show this help

          $PWD is mounted at the same path inside the container and used as the workdir.

          Examples:
            docker-here alpine ls -l
            docker-here --shell python:3.14
            docker-here --shell --gpu ollama/ollama
          EOF
          }

          tty=( )
          gpu=( )

          while [ "$#" -gt 0 ]; do
            case "$1" in
              -s | --shell) tty=( -it ) ;;
              -g | --gpu) gpu=( --device /dev/kfd --device /dev/dri --security-opt seccomp=unconfined ) ;;
              -h | --help) usage; exit 0 ;;
              --) shift; break ;;
              -*)
                printf 'docker-here: unknown option: %s\n' "$1" >&2
                usage >&2
                exit 2
                ;;
              *) break ;;
            esac
            shift
          done

          if [ "$#" -eq 0 ]; then
            usage >&2
            exit 2
          fi

          # Deliberately no `-u $(id -u):$(id -g)`: on rootless docker, container root *is* our
          # host uid, so files written into $PWD stay ours. Forcing our uid instead maps to an
          # unmapped subuid: $PWD turns unwritable and HOME falls back to /.
          exec docker run --rm "''${tty[@]}" "''${gpu[@]}" -v "$PWD:$PWD" -w "$PWD" "$@"
        '';
      };

      llamaCppUpdate = script "llama-cpp-update" "Pull the latest llama.cpp checkout" ''
        dir="''${LLAMA_CPP_REPO_PATH:-${llamaCppPath}}"
        if [ ! -d "$dir/.git" ]; then
          ${error "No llama.cpp checkout found"}
          exit 1
        fi
        if ! git -C "$dir" diff --quiet; then
          ${warning "Uncommitted changes in the llama.cpp checkout - the pull may conflict."}
        fi
        ${info "Pulling llama.cpp updates..."}
        git -C "$dir" pull
        ${success "llama.cpp updated."}
      '';
    in
    [
      dockerHere
      llamaCppUpdate

      (script "os-rebuild" "Build the NixOS system configuration" ''
        ${info "Rebuilding NixOS..."}
        nh os boot --keep-going
        ${success "System rebuild complete."}
      '')

      (script "os-rebuild-switch" "Build and switch to a new NixOS system configuration" ''
        ${info "Rebuilding NixOS and switching to the new build..."}
        nh os switch --keep-going
        ${success "System rebuild complete, switched to new build."}
      '')

      # `--commit-lock-file` is handled by `nix flake update` itself and no-ops when the
      # lock file did not change.
      # Restarting AdGuard refreshes the filter lists: the unit's preStart merge replaces the
      # top-level `filters`, wiping the `last_updated` stamps AdGuard would otherwise honour. The API
      # equivalent (/control/refresh) would need the web password, which we don't keep here.
      (script "os-update" "Update llama.cpp and the AdGuard filter lists, rebuild, commit flake.lock" ''
        ${info "=== Starting OS Update Sequence ==="}
        llama-cpp-update

        ${info "Refreshing AdGuard Home filter lists..."}
        sudo systemctl restart adguardhome
        # grace period for DNS restart
        sleep 5
        ${info "Rebuilding NixOS with updated inputs..."}
        nh os boot --keep-going --show-trace --refresh --commit-lock-file --update
        ${success "=== OS Update done! ==="}
      '')

      # Generations are already reaped daily by `programs.nh.clean`; this is the on-demand
      # variant, which also drops gcroots. No --optimise: auto-optimise-store covers it.
      (script "os-clean" "Garbage-collect the Nix store and prune gcroots" ''
        ${info "Running NixOS cleanup..."}
        nh clean all
        ${success "System clean complete."}
      '')

      # `nix store verify` has no --repair yet, so this one stays on the old CLI.
      (script "os-check" "Verify and repair the Nix store" ''
        ${info "Running NixOS store check/fix..."}
        sudo nix-store --verify --check-contents --repair
        ${success "NixOS store check/fix complete!"}
      '')

      (script "os-repair" "Rebuild the whole OS, repair nix store and install bootloader." ''
        ${info "=== Starting OS Update Sequence ==="}
        llama-cpp-update
        ${info "Rebuilding NixOS with updated inputs..."}
        nh os boot --keep-going --repair --show-trace --install-bootloader
        ${success "=== OS Update done! ==="}
      '')

      # ROCm venv for the conversion scripts; `llama-cpp-venv-activate` (fish) for interactive use.
      (pkgs.writeShellApplication {
        name = "llama-cpp-venv-create";
        runtimeInputs = [ pkgs.uv ];
        meta.description = "Create the llama.cpp ROCm venv (torch with the rocm backend)";
        text = ''
          venv="''${LLAMA_CPP_VENV_PATH:-${llamaCppPath}/.venv}"
          printf '\033[1;34mCreating venv in %s...\033[0m\n' "$venv"
          uv venv -c -p 3.14 --color auto --no-config "$venv"

          ${info "Installing/updating packages..."}
          VIRTUAL_ENV="$venv" uv pip install --upgrade pip wheel setuptools transformers numpy torch sentencepiece \
              --prerelease=allow \
              --index-strategy unsafe-best-match \
              --torch-backend=rocm7.2

          VIRTUAL_ENV="$venv" uv pip install --upgrade "${llamaCppPath}/gguf-py"
          ${success "Done! Activate it with 'llama-cpp-venv-activate' (fish)."}
        '';
      })

      (pkgs.writeShellApplication {
        name = "llama-cpp-hf-to-gguf";
        meta.description = "Convert a HuggingFace model to GGUF: llama-cpp-hf-to-gguf <out.gguf> <model_dir_or_repo>";
        text = ''
          if [ "$#" -ne 2 ]; then
            printf 'usage: llama-cpp-hf-to-gguf <out.gguf> <model_dir_or_repo>\n' >&2
            exit 2
          fi
          exec "''${LLAMA_CPP_VENV_PATH:-${llamaCppPath}/.venv}"/bin/python \
            "''${LLAMA_CPP_REPO_PATH:-${llamaCppPath}}"/convert_hf_to_gguf.py \
            --outfile "$1" --outtype auto "$2"
        '';
      })

      # Rebuilds the local `llama-rocm` image (llama.cpp master, ROCm, gfx1151) from
      # kyuz0/amd-strix-halo-toolboxes. The build goes through `sudo docker`, i.e. the SYSTEM
      # daemon - the same one llm-router-rocm runs on; the rootless daemon is invisible to it.
      (pkgs.writeShellApplication {
        name = "update-llama-cpp-rocm";
        runtimeInputs = [
          pkgs.git
          pkgs.docker
        ];
        meta.description = "Rebuild the local llama.cpp ROCm image from amd-strix-halo-toolboxes";
        text = ''
          repo_dir=/home/LLMs/amd-strix-halo-toolboxes
          image=llama-rocm

          if [ ! -d "$repo_dir/.git" ]; then
            printf '\033[1;34mCloning amd-strix-halo-toolboxes into %s...\033[0m\n' "$repo_dir"
            git clone https://github.com/kyuz0/amd-strix-halo-toolboxes.git "$repo_dir"
          fi

          ${info "Pulling latest amd-strix-halo-toolboxes..."}
          git -C "$repo_dir" pull --ff-only

          # --no-cache is mandatory: the `git clone llama.cpp master` step has no changing
          # inputs, so a cached build would keep the old llama.cpp forever.
          printf '\033[1;34mBuilding %s:latest (llama.cpp master, ROCm, gfx1151)...\033[0m\n' "$image"
          sudo docker build --no-cache -t "$image:latest" \
              -f "$repo_dir/toolboxes/Dockerfile.rocm-10.0" \
              "$repo_dir/toolboxes"
        '';
      })
    ];
}
