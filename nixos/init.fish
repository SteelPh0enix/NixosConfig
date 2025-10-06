# General utils

function remote-cp --description "Compresses, sends, and decompresses a directory to a remote server via scp."
    # --- Check for required commands ---
    if not command -v 7z >/dev/null
        echo "Error: 7z (p7zip) is not installed. Please install it to continue." >&2
        return 1
    end
    if not command -v scp >/dev/null
        echo "Error: scp is not installed." >&2
        return 1
    end
    if not command -v ssh >/dev/null
        echo "Error: ssh is not installed." >&2
        return 1
    end

    # --- Argument validation ---
    if test (count $argv) -ne 2
        echo "Usage: remote-cp <local_directory> <user@host:remote_path>" >&2
        return 1
    end

    set local_path $argv[1]
    set remote_target $argv[2]

    if not test -d $local_path
        echo "Error: Local path '$local_path' is not a directory." >&2
        return 1
    end

    # --- Parse remote target ---
    set remote_parts (string split ":" -- $remote_target)
    if test (count $remote_parts) -ne 2
        echo "Error: Invalid remote target format. Expected <user@host:remote_path>." >&2
        return 1
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
        return 1
    end

    # --- Secure Copy ---
    echo "Copying '$archive_name' to '$remote_host:$remote_archive_path'..."
    scp "$archive_name" "$remote_host:$remote_archive_path"
    if test $status -ne 0
        echo "Error: scp failed." >&2
        rm -f "$archive_name"
        return 1
    end

    # --- Remote Deletion and Decompression ---
    echo "Removing existing directory and uncompressing on remote host..."
    ssh $remote_host "if test -d \"$remote_path\"; rm -rf \"$remote_path\"; end; and 7z x \"$remote_archive_path\" -o\"$target_dir\"; and rm \"$remote_archive_path\""
    if test $status -ne 0
        echo "Error: Remote command execution failed." >&2
        rm -f "$archive_name"
        return 1
    end

    # --- Cleanup ---
    rm -f "$archive_name"
    echo "Done."
end

# LLM functions

function serve-llm
    set model_gguf_path $argv[1]
    set model_name (basename $argv[1] .gguf)

    if test -z "$model_gguf_path"
        echo "Error: Model path not provided" >&2
        echo "Usage: serve-llm <path-to-model.gguf> <context-length> [additional arguments for llama-server]" >&2
        return 1
    end

    if not test -f "$model_gguf_path"
        echo "Error: Model file not found at: $model_gguf_path" >&2
        return 2
    end

    set context_length $argv[2]

    if test -z "$context_length"
        echo "Error: Context length not provided" >&2
        return 3
    end

    if test "$context_length" -lt 0
        echo "Error: Context length must be >= 0" >&2
        return 4
    end

    if test "$context_length" -gt 0
        echo "Serving $model_name with $context_length tokens context, additional flags: $argv[3..-1]"
    else
        echo "Serving $model_name with maximum available context, additional flags: $argv[3..-1]"
    end

    llama-server \
        --ctx-size $context_length \
        --model $model_gguf_path \
        --alias $model_name \
        $argv[3..-1]
end

function serve-llm-jinja
    serve-llm $argv[1] $argv[2] \
        --jinja \
        $argv[3..-1]
end

function serve-llm-jinja-ext
    set template_path $argv[3]

    if test -z "$template_path"
        echo "Error: Chat template path not provided" >&2
        echo "Usage: serve-llm-jinja-ext <path-to-model.gguf> <context-length> <chat-template.jinja> [additional arguments for llama-server]" >&2
        return 1
    end

    if not test -f "$template_path"
        echo "Error: Chat template file not found at: $template_path" >&2
        return 10
    end

    serve-llm-jinja $argv[1] $argv[2] \
        --chat-template-file $template_path \
        $argv[4..-1]
end
