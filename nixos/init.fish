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
