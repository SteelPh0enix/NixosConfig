# One service per file; a service that needs extra files (the llama-server preset, the log
# viewer) gets its own directory.
{
  imports = [
    ./llama-server-vulkan/llama-server-vulkan.nix
    ./llama-vulkan-logs/llama-vulkan-logs.nix
  ];
}
