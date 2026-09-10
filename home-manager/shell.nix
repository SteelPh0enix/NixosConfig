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

  # Exports the XDG_* session variables; ~/.local/bin itself goes into PATH system-wide
  # (environment.localBinInPath), which also covers shells home-manager does not configure.
  xdg.enable = true;

  # ~/.npm/bin: programs.npm sets the global prefix to ~/.npm but never adds its bin to PATH.
  home.sessionPath = [ "$HOME/.npm/bin" ];

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
    rcp = "rsync ${rsyncFlags}";
    rcpc = "rsync ${rsyncFlags} --compress";
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
      (script "os-update" "Update llama.cpp and the flake inputs, rebuild, commit flake.lock" ''
        ${info "=== Starting OS Update Sequence ==="}
        llama-cpp-update
        ${info "Rebuilding NixOS with updated inputs..."}
        nh os boot --update --commit-lock-file --keep-going
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
    ];
}
