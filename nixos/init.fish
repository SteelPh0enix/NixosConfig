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

function os-rebuild
    echo (set_color green)"Directory: ~/nixos-config"(set_color normal)
    cd ~/nixos-config; or return 1

    echo (set_color yellow)"Rebuilding NixOS (boot) for WorkVM..."(set_color normal)
    # sudo will likely prompt for password here
    sudo nixos-rebuild boot --flake .#steelph0enix-work-vm --upgrade-all --print-build-logs --show-trace --refresh
end

function os-update
    echo (set_color magenta)"=== Starting OS Update Sequence ==="(set_color normal)

    # 1. Update Flake inputs
    echo (set_color green)"Directory: ~/nixos-config"(set_color normal)
    cd ~/nixos-config; or return 1

    echo (set_color blue)"Updating flake inputs..."(set_color normal)
    nix flake update; or return 1

    # 2. Rebuild System
    os-rebuild; or return 1

    # 3. Commit changes
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

function decode-id
    set -l int_val $argv[1]

    # Extract bytes using bitwise operations
    # Byte 3 (Most Significant Byte)
    set -l b3 (math "bitand($int_val >> 24, 0xFF)")
    # Byte 2
    set -l b2 (math "bitand($int_val >> 16, 0xFF)")
    # Byte 1
    set -l b1 (math "bitand($int_val >> 8, 0xFF)")
    # Byte 0 (Least Significant Byte - the number at the end)
    set -l b0 (math "bitand($int_val, 0xFF)")

    # Construct a string of Hex escapes (e.g., \x4d\x45\x4d)
    set -l ascii_str (printf "\\x%x\\x%x\\x%x" $b3 $b2 $b1)

    # Print the result, interpreting the hex escapes as characters
    printf "$ascii_str-$b0\n"
end
