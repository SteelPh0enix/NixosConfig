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
alias os-rebuild "cd ~/nixos-config && sudo nixos-rebuild switch --flake .#RX-78-FPC --upgrade-all --print-build-logs --show-trace --refresh"
alias os-update "cd ~/nixos-config && nix flake update && os-rebuild && git add flake.lock && git commit -m 'os update'"
alias os-clean "sudo nix-store --gc && sudo nix-store --optimise && sudo nix-collect-garbage -d && nix-collect-garbage -d"
alias rbt "sudo systemctl reboot"
alias cfge "$EDITOR ~/nixos-config"
alias docker-here "docker run --rm -v $PWD:$PWD -w $PWD -u $(id -u):$(id -g)"
alias docker-here-shell "docker run --rm -it -v $PWD:$PWD -w $PWD -u $(id -u):$(id -g)"
alias docker-here-rocm "docker run --device /dev/kfd --device /dev/dri --security-opt seccomp=unconfined --rm"
alias docker-here-shell-rocm "docker run --device /dev/kfd --device /dev/dri --security-opt seccomp=unconfined --rm -it"
alias rcp "rsync --archive --recursive --mkpath --verbose --progress --human-readable"
alias rcpc "rsync --archive --recursive --mkpath --compress --verbose --progress --human-readable"
