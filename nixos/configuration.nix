{
  system.stateVersion = "25.05";
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  imports = [
    ./boot.nix
    ./desktop.nix
    ./fonts.nix
    ./hardware-configuration.nix
    ./hardware.nix
    ./locale.nix
    ./mounts.nix
    ./networking.nix
    ./nix.nix
    ./packages/default.nix
    ./services.nix
    ./services/open-webui/open-webui.nix
    ./services/anything-llm/anything-llm.nix
    ./services/pihole/pihole.nix
    ./services/samba.nix
    ./services/wireguard.nix
    ./services/llm-logs-web.nix
    ./services/llm-router.nix
    ./services/llm-router-rocm/llm-router-rocm.nix
    ./services/minecraft-server.nix
    ./services/hindsight/hindsight.nix
    ./services/tei/tei.nix
    ./services/web-extract/web-extract.nix
    ./shell.nix
    ./timers.nix
    ./users.nix
    ./virtualization.nix
  ];
}
