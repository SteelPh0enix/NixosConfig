{
  system.stateVersion = "25.11";
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
    ./shell.nix
    ./users.nix
    ./virtualisation.nix
  ];
}
