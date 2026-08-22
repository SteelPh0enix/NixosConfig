# General utils

function remote-cp --description "Compresses, sends, and decompresses a directory to a remote server via scp."
    # --- Check for required commands ---
    if not command -v 7z >/dev/null
        echo "Error: 7z (p7zip) is not installed. Please install it to continue." >&2
        return 1
    end
    if not command -v scp >/dev/null
        echo "Error: scp is not installed." >&2
        return 2
    end
    if not command -v ssh >/dev/null
        echo "Error: ssh is not installed." >&2
        return 3
    end

    # --- Argument validation ---
    if test (count $argv) -ne 2
        echo "Usage: remote-cp <local_directory> <user@host:remote_path>" >&2
        return 4
    end

    set local_path $argv[1]
    set remote_target $argv[2]

    if not test -d $local_path
        echo "Error: Local path '$local_path' is not a directory." >&2
        return 5
    end

    # --- Parse remote target ---
    set remote_parts (string split ":" -- $remote_target)
    if test (count $remote_parts) -ne 2
        echo "Error: Invalid remote target format. Expected <user@host:remote_path>." >&2
        return 6
    end

    set remote_host $remote_parts[1]
    set remote_path $remote_parts[2]
    set local_dir_name (basename "$local_path")
    set archive_name "$local_dir_name.7z"
    set remote_archive_path "/tmp/$archive_name"
    set target_dir (dirname "$remote_path")

    # --- Compression ---
    echo "Compressing '$local_path' to '$archive_name'..."
    7z a -r "$archive_name" "$local_path" >/dev/null
    if test $status -ne 0
        echo "Error: Compression failed." >&2
        rm -f "$archive_name"
        return 7
    end

    # --- Secure Copy ---
    echo "Copying '$archive_name' to '$remote_host:$remote_archive_path'..."
    scp "$archive_name" "$remote_host:$remote_archive_path"
    if test $status -ne 0
        echo "Error: scp failed." >&2
        rm -f "$archive_name"
        return 8
    end

    # --- Remote Deletion and Decompression ---
    echo "Removing existing directory and uncompressing on remote host..."
    ssh $remote_host "if test -d \"$remote_path\"; rm -rf \"$remote_path\"; end; and 7z x \"$remote_archive_path\" -o\"$target_dir\"; and rm \"$remote_archive_path\""
    if test $status -ne 0
        echo "Error: Remote command execution failed." >&2
        rm -f "$archive_name"
        return 9
    end

    # --- Cleanup ---
    rm -f "$archive_name"
    echo "Done."
end

# LLM functions

function serve-llm
    set -l llama_port 51536
    set -l context_length 0
    argparse h/help 'm/model=' 'p/port=' 'c/context=' -- $argv
    or return 1

    if set -q _flag_help
        echo "Usage: serve-llm -m/--model=<path to GGUF file> -p/--port=<port, optional, $llama_port by default> -c/--context=<context length, optional, 0 (max context) by default>"
        return 2
    end

    if not set -q _flag_model
        echo "Error: model path is required!" >&2
        return 3
    end

    set -l model_path $_flag_model
    set -l model_name (basename $model_path .gguf)

    if not test -e "$model_path"
        echo "Error: Model $model_path does not exist!" >&2
        return 4
    end

    if set -q _flag_port
        set llama_port $_flag_port
    end

    if set -q _flag_context
        set context_length $_flag_context
    end

    if test "$context_length" -lt 0
        echo "Error: context length must be >= 0!" >&2
        return 5
    end

    if test "$context_length" -gt 0
        echo "Serving $model_name with $context_length tokens of context on port $llama_port, additional flags: $argv"
    else
        echo "Serving $model_name with maximum available context on port $llama_port, additional flags: $argv"
    end

    llama-server \
        --ctx-size $context_length \
        --model $model_path \
        --alias $model_name \
        --mlock \
        --fit on \
        --log-colors on \
        --offline \
        --warmup \
        --host 0.0.0.0 \
        --port $llama_port \
        --webui \
        --metrics \
        --props \
        --slots \
        --models-max 1 \
        --parallel 1 \
        --flash-attn on \
        --gpu-layers all \
        --direct-io \
        $argv
end

function update-llama-cpp-rocm --description "Rebuild the local llama.cpp ROCm 7.14 image from the latest amd-strix-halo-toolboxes"
    # Builds against the SYSTEM docker daemon (sudo -> /run/docker.sock), the
    # same daemon the llm-router-rocm systemd service runs on. The user's
    # rootless daemon (DOCKER_HOST=unix:///run/user/1000/docker.sock) is NOT
    # visible to the service, so the build must go through sudo.
    set -l repo_dir /home/LLMs/amd-strix-halo-toolboxes
    set -l image llama-rocm-7.14

    if not test -d $repo_dir/.git
        echo (set_color green)"Cloning amd-strix-halo-toolboxes into $repo_dir..."(set_color normal)
        git clone https://github.com/kyuz0/amd-strix-halo-toolboxes.git $repo_dir; or return 1
    end

    echo (set_color green)"Pulling latest amd-strix-halo-toolboxes..."(set_color normal)
    git -C $repo_dir pull --ff-only; or return 1

    # --no-cache is mandatory: the `git clone llama.cpp master` step has no
    # changing inputs, so a cached build would keep the old llama.cpp forever.
    echo (set_color green)"Building $image:latest (llama.cpp master, ROCm 7.14, gfx1151)..."(set_color normal)
    sudo docker build --no-cache -t $image:latest \
        -f $repo_dir/toolboxes/Dockerfile.rocm-7.14 \
        $repo_dir/toolboxes; or return 1

    echo (set_color green)"Built: "(set_color normal)(sudo docker image inspect --format '{{.Id}}' $image:latest)
end

function update-services
    echo (set_color green)"Updating AnythingLLM..."(set_color normal)
    env -C ~/nixos-config/nixos/services/anything-llm sudo docker compose pull --policy always
    sudo systemctl restart anything-llm

    echo (set_color green)"Updating Hindsight"(set_color normal)
    env -C ~/nixos-config/nixos/services/hindsight sudo docker compose pull --policy always
    sudo systemctl restart hindsight

    echo (set_color green)"Updating TEI (embeddings + reranker)"(set_color normal)
    env -C ~/nixos-config/nixos/services/tei sudo docker compose pull --policy always
    sudo systemctl restart tei

    echo (set_color green)"Updating llama.cpp (ROCm)"(set_color normal)
    update-llama-cpp-rocm; or return 1
    sudo systemctl restart llm-router-rocm

    echo (set_color green)"Updating PiHole"(set_color normal)
    env -C ~/nixos-config/nixos/services/pihole sudo docker compose pull --policy always
    sudo systemctl restart pihole

    # grace period for DNS restart
    echo (set_color -d blue)"Waiting for PiHole restart..."(set_color normal)
    sleep 5
    echo (set_color green)"Updating PiHole lists"(set_color normal)
    sudo docker exec pihole pihole -g
end
