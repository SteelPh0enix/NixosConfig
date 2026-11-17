# One service per file; a service that needs extra files (the llama-server preset, the log
# viewer) gets its own directory.
{ settings, ... }:
{
  assertions = [
    {
      assertion = builtins.elem settings.defaultLlmEngine (builtins.attrNames settings.llmEngineUnits);
      message = "settings.defaultLlmEngine must name one of settings.llmEngineUnits.";
    }
  ];
  imports = [
    ./static-sites.nix
    ./ci-runner.nix
    ./ci-network.nix
    ./ci-gateway.nix
    ./llama-server-vulkan/llama-server-vulkan.nix
    ./llama-server-rocm/llama-server-rocm.nix
    ./llama-logs/llama-logs.nix
    ./gufo.nix
    ./crucible.nix
    ./adguardhome.nix
    ./cloudflared.nix
    ./searxng.nix
    ./samba.nix
    ./tailscale.nix
  ];
}
