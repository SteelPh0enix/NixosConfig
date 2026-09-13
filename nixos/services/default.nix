# One service per file; a service that needs extra files (docker-compose.yml, the llama-server
# preset, the log viewer) gets its own directory.
{
  imports = [
    ./coverage.nix
    ./docs.nix
    ./llm-logs-web.nix
    ./llm-router/llm-router.nix
    ./llm-router-rocm/llm-router-rocm.nix
    ./pihole/pihole.nix
    ./samba.nix
  ];
}
