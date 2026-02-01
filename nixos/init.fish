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

function llm-router
    llama-server \
        --models-dir /home/LLMs/llama-models/ \
        --models-preset /home/LLMs/llama-models.ini \
        --mlock \
        --direct-io \
        --fit on \
        --log-colors on \
        --offline \
        --warmup \
        --host 0.0.0.0 \
        --port 51536 \
        --webui \
        --metrics \
        --props \
        --slots \
        --flash-attn on \
        --gpu-layers all
end

function update-services
    echo (set_color green)"Updating OpenWebUI..."(set_color normal)
    cd ~/nixos-config/nixos/services/open-webui
    sudo docker compose pull --policy always
    sudo systemctl restart open-webui

    echo (set_color green)"Updating Lancache"(set_color normal)
    cd /mnt/NAS2/lancache
    sudo docker compose pull --policy always
    sudo systemctl restart lancache

    echo (set_color green)"Updating PiHole"(set_color normal)
    cd ~/nixos-config/nixos/services/pihole
    sudo docker compose pull --policy always
    sudo systemctl restart pihole

    # grace period for DNS restart
    echo (set_color -d blue)"Waiting for PiHole restart..."(set_color normal)
    sleep 5
    echo (set_color green)"Updating PiHole lists"(set_color normal)
    sudo docker exec pihole pihole -g
end
