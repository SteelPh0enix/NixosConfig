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
alias cfge "$EDITOR ~/nixos-config"
alias docker-here "docker run --rm -v $PWD:$PWD -w $PWD -u $(id -u):$(id -g)"
alias docker-here-shell "docker run --rm -it -v $PWD:$PWD -w $PWD -u $(id -u):$(id -g)"
alias docker-here-rocm "docker run --device /dev/kfd --device /dev/dri --security-opt seccomp=unconfined --rm"
alias docker-here-shell-rocm "docker run --device /dev/kfd --device /dev/dri --security-opt seccomp=unconfined --rm -it"
alias rcp "rsync --archive --recursive --mkpath --verbose --progress --human-readable"
alias rcpc "rsync --archive --recursive --mkpath --compress --verbose --progress --human-readable"
alias jrn "sudo journalctl -u"
alias sts "sudo systemctl status"
alias str "sudo systemctl restart"

set -Ux llama_cpp_repo_path "/home/steelph0enix/llama.cpp"
set -Ux llama_cpp_venv_path "$llama_cpp_repo_path/.venv"
set -gx PATH "/home/steelph0enix/.npm/bin:/home/steelph0enix/.local/bin:$PATH"

function llama-cpp-update
    echo (set_color green)"Directory: $llama_cpp_repo_path"(set_color normal)
    cd $llama_cpp_repo_path; or return 1

    echo (set_color blue)"Switching to master and pulling updates..."(set_color normal)
    git switch master && git pull; or return 1
end

function llama-cpp-venv-create
    echo (set_color green)"Creating venv for llama.cpp in $llama_cpp_venv_path..."
    uv venv -c -p 3.14 --color auto --no-config $llama_cpp_venv_path
    llama-cpp-venv-activate

    echo (set_color blue)"Installing/updating packages..."
    uv pip install --upgrade pip wheel setuptools transformers numpy torch --prerelease=allow --index-strategy unsafe-best-match

    pushd $llama_cpp_repo_path/gguf-py
    uv pip install --upgrade .
    popd

    echo (set_color blue)"Done!"
end

function llama-cpp-venv-activate
    echo (set_color green)"Activating llama.cpp venv..."
    source "$llama_cpp_venv_path/bin/activate.fish"
    echo (set_color blue)"Done!"
end

function llama-cpp-hf-to-gguf -a model_path gguf_path
    set -l script_path "$llama_cpp_repo_path/convert_hf_to_gguf.py"

    llama-cpp-venv-activate
    python $script_path --outfile $gguf_path --outtype auto $model_path
end

function os-rebuild
    echo (set_color yellow)"Rebuilding NixOS for main PC..."(set_color normal)
    nh os boot ~/nixos-config --hostname RX-78-FPC --update --keep-going
    echo (set_color green)"System rebuild complete."(set_color normal)
end

function os-rebuild-switch
    echo (set_color yellow)"Rebuilding NixOS for main PC and switching to new build..."(set_color normal)
    nh os switch ~/nixos-config --hostname RX-78-FPC --update --keep-going
    echo (set_color green)"System rebuild complete, switched to new build."(set_color normal)
end

function os-update
    echo (set_color magenta)"=== Starting OS Update Sequence ==="(set_color normal)

    # 1. Update llama.cpp
    llama-cpp-update; or return 1

    # 2. Update external services
    echo (set_color blue)"Updating services..."(set_color normal)
    update-services; or return 1

    # 2. Rebuild System
    os-rebuild; or return 1

    # 3. Commit changes
    echo (set_color blue)"Committing flake.lock..."(set_color normal)
    git add flake.lock && git commit -m 'os update'
    echo (set_color green)"=== OS Update done! ==="(set_color normal)
end

function os-clean
    echo (set_color yellow)"Running NixOS cleanup..."(set_color normal)
    nh clean all --optimise
    echo (set_color green)"System Clean Complete."(set_color normal)
end

function os-check
    echo (set_color yellow)"Running NixOS store check/fix..."(set_color normal)
    sudo nix-store --verify --check-contents --repair
    echo (set_color green)"NixOS store check/fix complete!"(set_color normal)
end
