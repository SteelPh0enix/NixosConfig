if status is-interactive
    # Commands to run in interactive sessions can go here
end

alias ls "eza --icons=always -gM --git"
alias l "ls -lh"
alias la "ls -alh"
alias lg lazygit
alias e "$EDITOR"
alias eh "$EDITOR ."
alias cpr "cp -r"
alias rbt "sudo systemctl reboot"
alias cfge "code ~/nixos-config"
alias docker-here "docker run --rm -v $PWD:$PWD -w $PWD -u $(id -u):$(id -g)"
alias docker-here-shell "docker run --rm -it -v $PWD:$PWD -w $PWD -u $(id -u):$(id -g)"
alias docker-here-rocm "docker run --device /dev/kfd --device /dev/dri --security-opt seccomp=unconfined --rm"
alias docker-here-shell-rocm "docker run --device /dev/kfd --device /dev/dri --security-opt seccomp=unconfined --rm -it"
alias rcp "rsync --archive --recursive --mkpath --verbose --progress --human-readable"
alias rcpc "rsync --archive --recursive --mkpath --compress --verbose --progress --human-readable"

function os-rebuild
    echo (set_color green)"Directory: ~/nixos-config"(set_color normal)
    cd ~/nixos-config; or return 1

    echo (set_color yellow)"Rebuilding NixOS (boot) for main PC..."(set_color normal)
    # sudo will likely prompt for password here
    sudo nixos-rebuild boot --flake .#steelph0enix-pc --upgrade-all --print-build-logs --show-trace --refresh
end

function os-update
    echo (set_color magenta)"=== Starting OS Update Sequence ==="(set_color normal)

    # 1. Update llama.cpp
    llama-cpp-update; or return 1

    # 2. Update Flake inputs
    echo (set_color green)"Directory: ~/nixos-config"(set_color normal)
    cd ~/nixos-config; or return 1

    echo (set_color blue)"Updating flake inputs..."(set_color normal)
    nix flake update; or return 1

    # 3. Rebuild System
    os-rebuild; or return 1

    # 4. Commit changes
    echo (set_color blue)"Committing flake.lock..."(set_color normal)
    git add flake.lock && git commit -m 'os update'

    echo (set_color magenta)"=== OS Update Complete ==="(set_color normal)
end

function os-clean
    echo (set_color yellow)"Running Store Garbage Collection (Root)..."(set_color normal)
    sudo nix-store --gc; or return 1

    echo (set_color yellow)"Optimizing Nix Store..."(set_color normal)
    sudo nix-store --optimise; or return 1

    echo (set_color yellow)"Deleting old generations (Root)..."(set_color normal)
    sudo nix-collect-garbage -d; or return 1

    echo (set_color yellow)"Deleting old generations (User)..."(set_color normal)
    nix-collect-garbage -d

    echo (set_color green)"System Clean Complete."(set_color normal)
end
