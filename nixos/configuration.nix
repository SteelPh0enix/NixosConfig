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
    ./nix.nix
    ./packages.nix
    ./services.nix
    ./services/samba.nix
    ./services/wireguard.nix
    ./shell.nix
    ./timers.nix
    ./users.nix
    ./virtualization.nix
  ];
}
