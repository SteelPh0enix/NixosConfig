# One service per file; a service that needs extra files (the llama-server preset, the log
# viewer) gets its own directory.
{
  imports = [
    ./coverage.nix
    ./docs.nix
    ./ci-runner.nix
    ./minecraft.nix
    ./llama-server-vulkan/llama-server-vulkan.nix
    ./llama-server-rocm/llama-server-rocm.nix
    ./llama-logs/llama-logs.nix
    ./gufo.nix
    ./adguardhome.nix
    ./cloudflared.nix
    ./searxng.nix
    ./samba.nix
    ./tailscale.nix
  ];
}
