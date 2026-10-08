# One service per file; a service that needs extra files (the llama-server preset, the log
# viewer) gets its own directory.
{
  imports = [
    ./coverage.nix
    ./docs.nix
    ./minecraft.nix
    ./llama-server-vulkan/llama-server-vulkan.nix
    ./llama-vulkan-logs/llama-vulkan-logs.nix
    ./adguardhome.nix
    ./searxng.nix
    ./samba.nix
    ./tailscale.nix
  ];
}
